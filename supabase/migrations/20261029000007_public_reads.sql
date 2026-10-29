-- M0 · 07 — the public read surface — SPEC §7.1, §7.2, §7.3 (D24)
-- Clients never read `spaces` directly. Anonymous callers reach the product
-- only through these functions, and the gated slice never crosses the wire.

-- ---------------------------------------------------------------------------
-- space_head — the public page. Callable by anon.
-- Returns the slice above the first door. Nothing below it, ever.
-- ---------------------------------------------------------------------------

create or replace function public.space_head(p_handle citext, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space  public.spaces;
  v_author public.users;
  v_email  text;
  v_door   boolean;
begin
  v_space := private.resolve_published(p_handle, p_slug);

  if v_space.id is null then
    return jsonb_build_object('found', false);
  end if;

  v_door := v_space.published_gated_blocks is not null;

  select * into v_author from public.users where id = v_space.owner_id;

  if v_author.email_public then
    select email into v_email from auth.users where id = v_author.id;
  end if;

  return jsonb_build_object(
    'found', true,
    'id', v_space.id,
    'title', v_space.published_title,
    'slug', v_space.published_slug,
    'published_at', v_space.published_at,
    'blocks', coalesce(v_space.published_public_blocks, '[]'::jsonb),
    'has_door', v_door,
    -- Counters need a door (D23). Without one they are suppressed, not faked.
    'readers', case when v_door then (select count(*) from public.space_visits v where v.space_id = v_space.id) else 0 end,
    'likes',   case when v_door then (select count(*) from public.space_likes  l where l.space_id = v_space.id) else 0 end,
    'author', jsonb_build_object(
      'username', v_author.username,
      'name', v_author.name,
      'avatar_path', v_author.avatar_path,
      'social', v_author.social,
      'email', v_email
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- space_enter — past the door. Requires a session.
-- Returns the full published document and records the visit.
-- ---------------------------------------------------------------------------

create or replace function public.space_enter(p_handle citext, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid    uuid := auth.uid();
  v_space  public.spaces;
  v_author public.users;
  v_email  text;
  v_door   boolean;
  v_liked  boolean;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  v_space := private.resolve_published(p_handle, p_slug);

  if v_space.id is null then
    return jsonb_build_object('found', false);
  end if;

  v_door := v_space.published_gated_blocks is not null;

  insert into public.space_visits (space_id, reader_id)
  values (v_space.id, v_uid)
  on conflict (space_id, reader_id) do update set last_seen = now();

  select * into v_author from public.users where id = v_space.owner_id;

  if v_author.email_public then
    select email into v_email from auth.users where id = v_author.id;
  end if;

  select exists (
    select 1 from public.space_likes l
    where l.space_id = v_space.id and l.reader_id = v_uid
  ) into v_liked;

  return jsonb_build_object(
    'found', true,
    'id', v_space.id,
    'title', v_space.published_title,
    'slug', v_space.published_slug,
    'published_at', v_space.published_at,
    'blocks', coalesce(v_space.published_blocks, '[]'::jsonb),
    'has_door', v_door,
    'readers', case when v_door then (select count(*) from public.space_visits v where v.space_id = v_space.id) else 0 end,
    'likes',   case when v_door then (select count(*) from public.space_likes  l where l.space_id = v_space.id) else 0 end,
    'liked_by_me', v_liked,
    'author', jsonb_build_object(
      'username', v_author.username,
      'name', v_author.name,
      'avatar_path', v_author.avatar_path,
      'social', v_author.social,
      'email', v_email
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- profile_public — the visitor lens at @username (D14, D17).
-- Published Spaces only. No chips, no controls, no trace of drafts.
-- ---------------------------------------------------------------------------

create or replace function public.profile_public(p_handle citext)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_author public.users;
  v_email  text;
  v_spaces jsonb;
begin
  select * into v_author from public.users where username = p_handle;

  if v_author.id is null then
    return jsonb_build_object('found', false);
  end if;

  if v_author.email_public then
    select email into v_email from auth.users where id = v_author.id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'title', s.published_title,
           'slug', s.published_slug,
           'published_at', s.published_at
         ) order by s.published_at desc), '[]'::jsonb)
  into v_spaces
  from public.spaces s
  where s.owner_id = v_author.id
    and private.is_publicly_readable(s.visibility, s.published_at, s.deleted_at);

  return jsonb_build_object(
    'found', true,
    'username', v_author.username,
    'name', v_author.name,
    'avatar_path', v_author.avatar_path,
    'social', v_author.social,
    'email', v_email,
    'spaces', v_spaces
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- space_counts — the two numbers, to the owner or to anyone the Space is
-- already readable by. Nothing else.
-- ---------------------------------------------------------------------------

create or replace function public.space_counts(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces;
begin
  select * into v_space from public.spaces where id = p_space_id;

  if v_space.id is null then
    return jsonb_build_object('found', false);
  end if;

  if v_space.owner_id is distinct from auth.uid()
     and not private.is_publicly_readable(v_space.visibility, v_space.published_at, v_space.deleted_at) then
    return jsonb_build_object('found', false);
  end if;

  return jsonb_build_object(
    'found', true,
    'readers', (select count(*) from public.space_visits v where v.space_id = v_space.id),
    'likes',   (select count(*) from public.space_likes  l where l.space_id = v_space.id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- username_available — public by design (SPEC §7.3, "username enumeration:
-- accepted, profiles are public").
-- ---------------------------------------------------------------------------

create or replace function public.username_available(p_username citext)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_username is null
     or p_username::text !~ '^[a-z0-9](?:[a-z0-9-]{1,28}[a-z0-9])$'
     or p_username::text ~ '--' then
    return false;
  end if;

  return not exists (select 1 from public.users u where u.username = p_username);
end;
$$;

-- ---------------------------------------------------------------------------
-- toggle_like — one per reader, never from the author, never without a door.
-- ---------------------------------------------------------------------------

create or replace function public.toggle_like(p_handle citext, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_space public.spaces;
  v_liked boolean;
begin
  if v_uid is null then
    raise exception 'auth_required';
  end if;

  v_space := private.resolve_published(p_handle, p_slug);

  if v_space.id is null then
    return jsonb_build_object('found', false);
  end if;

  if v_space.owner_id = v_uid then
    raise exception 'cannot_like_own';
  end if;

  -- No door, no counters: the like is not recorded, and says so quietly.
  if v_space.published_gated_blocks is null then
    return jsonb_build_object('found', true, 'liked', false, 'likes', 0);
  end if;

  delete from public.space_likes l
  where l.space_id = v_space.id and l.reader_id = v_uid;

  if found then
    v_liked := false;
  else
    insert into public.space_likes (space_id, reader_id) values (v_space.id, v_uid);
    v_liked := true;
  end if;

  return jsonb_build_object(
    'found', true,
    'liked', v_liked,
    'likes', (select count(*) from public.space_likes l where l.space_id = v_space.id)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Execution grants. Functions default to PUBLIC in PostgreSQL, so everything
-- is revoked first and opened deliberately.
-- ---------------------------------------------------------------------------

revoke execute on all functions in schema public from public, anon, authenticated;

grant execute on function public.space_head(citext, text)          to anon, authenticated;
grant execute on function public.profile_public(citext)            to anon, authenticated;
grant execute on function public.space_counts(uuid)                to anon, authenticated;
grant execute on function public.username_available(citext)        to anon, authenticated;
grant execute on function public.space_enter(citext, text)         to authenticated;
grant execute on function public.toggle_like(citext, text)         to authenticated;
