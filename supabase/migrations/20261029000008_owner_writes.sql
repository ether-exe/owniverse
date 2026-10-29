-- M0 · 08 — owner write surface
-- Every mutation is a function. `spaces` and `global` get no write grants at
-- all, because a direct UPDATE could forge `published_*` and publish gated
-- content — exactly the hole §7.3 exists to close. Recorded as D35.

-- ---------------------------------------------------------------------------
-- Claim registry maintenance — SPEC §6.3
-- ---------------------------------------------------------------------------

create or replace function private.claim(p_user_id uuid, p_slug text, p_space_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.global (user_id, slug, space_id)
  values (p_user_id, p_slug, p_space_id);
exception when unique_violation then
  raise exception 'slug_taken';
end;
$$;

-- The single rule from §6.3: keep a claim while it is either the draft slug or
-- the published slug; release it otherwise.
create or replace function private.sync_claims(p_space_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.global g
  where g.space_id = p_space_id
    and g.slug is distinct from (select slug from public.spaces where id = p_space_id)
    and g.slug is distinct from (select published_slug from public.spaces where id = p_space_id);

  insert into public.global (user_id, slug, space_id)
  select s.owner_id, s.slug, s.id from public.spaces s where s.id = p_space_id
  on conflict (user_id, slug) do nothing;

  insert into public.global (user_id, slug, space_id)
  select s.owner_id, s.published_slug, s.id from public.spaces s
  where s.id = p_space_id and s.published_slug is not null
  on conflict (user_id, slug) do nothing;
end;
$$;

-- Load a Space that this caller may write to, or raise.
create or replace function private.owned_space(p_space_id uuid, p_allow_deleted boolean default false)
returns public.spaces
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces;
begin
  if auth.uid() is null then
    raise exception 'auth_required';
  end if;

  select * into v_space from public.spaces
  where id = p_space_id and owner_id = auth.uid();

  if v_space.id is null then
    raise exception 'not_found';
  end if;

  if not p_allow_deleted and v_space.deleted_at is not null then
    raise exception 'space_trashed';
  end if;

  return v_space;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_space / rename_space
-- ---------------------------------------------------------------------------

create or replace function public.create_space(p_title text, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_title  text := btrim(coalesce(p_title, ''));
  v_space  public.spaces;
begin
  perform public.assert_onboarded();

  insert into public.spaces (owner_id, title, slug)
  values (v_uid, v_title, p_slug)
  returning * into v_space;

  perform private.claim(v_uid, p_slug, v_space.id);

  return jsonb_build_object(
    'id', v_space.id, 'title', v_space.title, 'slug', v_space.slug,
    'visibility', v_space.visibility, 'blocks_version', v_space.blocks_version
  );
end;
$$;

create or replace function public.rename_space(p_space_id uuid, p_title text, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id);
begin
  update public.spaces
     set title = btrim(coalesce(p_title, '')), slug = p_slug
   where id = p_space_id
   returning * into v_space;

  perform private.claim(v_space.owner_id, p_slug, p_space_id);
  -- Releases the previous draft slug, unless it is the published one (D9).
  perform private.sync_claims(p_space_id);

  return jsonb_build_object(
    'id', v_space.id, 'title', v_space.title, 'slug', v_space.slug,
    'published_slug', v_space.published_slug
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- save_blocks — optimistic locking, validated on every write
-- ---------------------------------------------------------------------------

create or replace function public.save_blocks(p_space_id uuid, p_blocks jsonb, p_version integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id);
begin
  if v_space.blocks_version <> p_version then
    return jsonb_build_object('status', 'conflict', 'version', v_space.blocks_version);
  end if;

  perform private.validate_blocks(p_blocks, p_space_id);

  update public.spaces
     set blocks = p_blocks, blocks_version = v_space.blocks_version + 1
   where id = p_space_id;

  return jsonb_build_object('status', 'saved', 'version', v_space.blocks_version + 1);
end;
$$;

-- ---------------------------------------------------------------------------
-- publish_space — the split happens here (D33). The client sends nothing but
-- an id, so it cannot choose which blocks go public.
-- ---------------------------------------------------------------------------

create or replace function public.publish_space(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space   public.spaces := private.owned_space(p_space_id);
  v_public  jsonb;
  v_gated   jsonb;
  v_door    boolean;
begin
  perform private.validate_blocks(v_space.blocks, p_space_id);

  select s.public_blocks, s.gated_blocks
    into v_public, v_gated
    from private.split_at_door(v_space.blocks) s;

  v_door := v_gated is not null;

  -- Claim the slug being published *before* it becomes reachable. A conflict
  -- aborts the whole update, so an unpublished rename can never slip through.
  perform private.claim(v_space.owner_id, v_space.slug, p_space_id);

  update public.spaces
     set published_blocks        = v_space.blocks,
         published_public_blocks = v_public,
         published_gated_blocks  = v_gated,
         published_title         = v_space.title,
         published_slug          = v_space.slug,
         published_at            = now(),
         visibility              = 'public'
   where id = p_space_id;

  perform private.sync_claims(p_space_id);

  return jsonb_build_object(
    'status', 'published',
    'published_at', now(),
    'published_slug', v_space.slug,
    'has_door', v_door
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- set_visibility — private keeps the snapshot (§13 step 15)
-- ---------------------------------------------------------------------------

create or replace function public.set_visibility(p_space_id uuid, p_visibility text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id);
begin
  if p_visibility not in ('private', 'public') then
    raise exception 'invalid_visibility';
  end if;

  update public.spaces set visibility = p_visibility where id = p_space_id;

  return jsonb_build_object('id', p_space_id, 'visibility', p_visibility);
end;
$$;

-- ---------------------------------------------------------------------------
-- trash / restore / delete forever — D3
-- Claims survive Trash (D19): the title stays squatted until purge.
-- ---------------------------------------------------------------------------

create or replace function public.trash_space(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id);
  v_count integer;
begin
  with recursive subtree as (
    select id from public.spaces where id = p_space_id
    union all
    select c.id from public.spaces c join subtree t on c.parent_id = t.id
  )
  update public.spaces s
     set deleted_at = now()
    from subtree t
   where s.id = t.id and s.deleted_at is null;

  get diagnostics v_count = row_count;

  return jsonb_build_object('id', p_space_id, 'trashed', v_count);
end;
$$;

create or replace function public.restore_space(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id, true);
  v_count integer;
begin
  with recursive subtree as (
    select id from public.spaces where id = p_space_id
    union all
    select c.id from public.spaces c join subtree t on c.parent_id = t.id
  )
  update public.spaces s
     set deleted_at = null
    from subtree t
   where s.id = t.id and s.deleted_at is not null;

  get diagnostics v_count = row_count;

  perform private.sync_claims(p_space_id);

  return jsonb_build_object('id', p_space_id, 'restored', v_count);
end;
$$;

create or replace function public.delete_forever(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space   public.spaces := private.owned_space(p_space_id, true);
  v_total   integer := 0;
  v_deleted integer;
  v_pass    integer;
begin
  -- `parent_id` is ON DELETE RESTRICT, so leaves go first. Bounded so a
  -- corrupted cycle can never spin forever.
  for v_pass in 1..100 loop
    with recursive subtree as (
      select id from public.spaces where id = p_space_id
      union all
      select c.id from public.spaces c join subtree t on c.parent_id = t.id
    )
    delete from public.spaces s
     where s.id in (select t.id from subtree t)
       and not exists (select 1 from public.spaces c where c.parent_id = s.id);

    get diagnostics v_deleted = row_count;
    v_total := v_total + v_deleted;
    exit when v_deleted = 0;
  end loop;

  return jsonb_build_object('id', p_space_id, 'deleted', v_total, 'passes', v_pass);
end;
$$;

-- ---------------------------------------------------------------------------
-- update_profile — the one place a username is claimed
-- ---------------------------------------------------------------------------

create or replace function public.update_profile(
  p_name text,
  p_username text,
  p_avatar_path text,
  p_email_public boolean,
  p_social jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid  uuid := auth.uid();
  v_user public.users;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  begin
    update public.users
       set name         = nullif(btrim(coalesce(p_name, '')), ''),
           username     = nullif(btrim(coalesce(p_username, '')), '')::citext,
           avatar_path  = nullif(btrim(coalesce(p_avatar_path, '')), ''),
           email_public = coalesce(p_email_public, false),
           social       = coalesce(p_social, '{}'::jsonb)
     where id = v_uid
     returning * into v_user;
  exception when unique_violation then
    raise exception 'username_taken';
  end;

  if v_user.id is null then
    raise exception 'not_found';
  end if;

  return jsonb_build_object(
    'username', v_user.username,
    'name', v_user.name,
    'avatar_path', v_user.avatar_path,
    'email_public', v_user.email_public,
    'social', v_user.social
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants: the tables get no write path; the functions do.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.space_head(citext, text)   to anon, authenticated;
grant execute on function public.profile_public(citext)     to anon, authenticated;
grant execute on function public.space_counts(uuid)         to anon, authenticated;
grant execute on function public.username_available(citext) to anon, authenticated;

grant execute on function public.space_enter(citext, text)             to authenticated;
grant execute on function public.toggle_like(citext, text)             to authenticated;
grant execute on function public.create_space(text, text)              to authenticated;
grant execute on function public.rename_space(uuid, text, text)        to authenticated;
grant execute on function public.save_blocks(uuid, jsonb, integer)     to authenticated;
grant execute on function public.publish_space(uuid)                   to authenticated;
grant execute on function public.set_visibility(uuid, text)            to authenticated;
grant execute on function public.trash_space(uuid)                     to authenticated;
grant execute on function public.restore_space(uuid)                   to authenticated;
grant execute on function public.delete_forever(uuid)                  to authenticated;
grant execute on function public.update_profile(text, text, text, boolean, jsonb) to authenticated;

-- Writes on spaces and global are RPC-only. Reads stay table-level for the owner.
revoke insert, update, delete, truncate on public.spaces from anon, authenticated;
revoke insert, update, delete, truncate on public.global from anon, authenticated;
grant select on public.global to authenticated;

-- Counters and media: no TRUNCATE, ever (RLS does not apply to TRUNCATE).
revoke truncate on public.users, public.space_visits, public.space_likes, public.media
  from anon, authenticated;
