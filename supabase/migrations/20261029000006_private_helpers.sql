-- M0 · 06 — private helpers and the shared block validator — SPEC §8
-- Functions in `private` are not exposed by PostgREST. They are reachable only
-- from the definer functions in `public`, and only as their owner.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- A Space is publicly readable when it is public, published, and not trashed.
-- This one predicate is the gate, and it is used by every public read.
create or replace function private.is_publicly_readable(
  p_visibility text,
  p_published_at timestamptz,
  p_deleted_at timestamptz
)
returns boolean
language sql
immutable
as $$
  select p_visibility = 'public'
     and p_published_at is not null
     and p_deleted_at is null;
$$;

-- Resolve @handle/slug to the Space that owns that public URL.
-- Only `published_slug` answers: the pre-publish placeholder died in D17.
create or replace function private.resolve_published(p_handle citext, p_slug text)
returns public.spaces
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select s.*
  from public.spaces s
  join public.users u on u.id = s.owner_id
  where u.username = p_handle
    and s.published_slug = p_slug
    and private.is_publicly_readable(s.visibility, s.published_at, s.deleted_at)
  limit 1;
$$;

-- ---------------------------------------------------------------------------
-- Block validation — one function, applied on save and again on publish.
-- Never trust the client's last state (SPEC §8).
--
-- Unknown `type` or `v > 1` is NOT an error: those render as a quiet
-- placeholder, so a document written by a newer client still opens.
-- ---------------------------------------------------------------------------

create or replace function private.validate_blocks(p_blocks jsonb, p_space_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if jsonb_typeof(p_blocks) <> 'array' then
    raise exception 'blocks_not_array';
  end if;

  if jsonb_array_length(p_blocks) > 200 then
    raise exception 'too_many_blocks';
  end if;

  -- Shape: every element is an object carrying id, type and an object `data`.
  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where jsonb_typeof(b) <> 'object'
       or not (b ? 'id')
       or not (b ? 'type')
       or jsonb_typeof(b -> 'data') is distinct from 'object'
  ) then
    raise exception 'block_shape_invalid';
  end if;

  -- At most one door per Space (SPEC §8).
  if (
    select count(*) from jsonb_array_elements(p_blocks) b
    where b ->> 'type' = 'door'
  ) > 1 then
    raise exception 'multiple_doors';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where b ->> 'type' = 'text'
      and char_length(coalesce(b -> 'data' ->> 'text', '')) > 20000
  ) then
    raise exception 'text_too_long';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where b ->> 'type' = 'longtext'
      and char_length(coalesce(b -> 'data' ->> 'text', '')) > 60000
  ) then
    raise exception 'longtext_too_long';
  end if;

  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where b ->> 'type' = 'heading'
      and (
        char_length(coalesce(b -> 'data' ->> 'text', '')) > 200
        or coalesce(b -> 'data' ->> 'level', '') not in ('1', '2', '3')
      )
  ) then
    raise exception 'heading_invalid';
  end if;

  -- alt is mandatory on images: the accessibility gate, not a suggestion.
  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where b ->> 'type' = 'image'
      and coalesce(btrim(b -> 'data' ->> 'alt'), '') = ''
  ) then
    raise exception 'image_alt_required';
  end if;

  -- Media must already belong to this Space.
  if exists (
    select 1 from jsonb_array_elements(p_blocks) b
    where b ->> 'type' in ('cover', 'image')
      and coalesce(b -> 'data' ->> 'media_id', '') <> ''
      and not exists (
        select 1 from public.media m
        where m.id::text = b -> 'data' ->> 'media_id'
          and m.space_id = p_space_id
      )
  ) then
    raise exception 'media_not_owned';
  end if;
end;
$$;

-- Split a document at the first door (D22, D33). The server does this, not the
-- client: the gated slice must never be written by the request that publishes.
create or replace function private.split_at_door(p_blocks jsonb)
returns table (public_blocks jsonb, gated_blocks jsonb)
language plpgsql
immutable
as $$
declare
  v_door_ord int;
begin
  select min(b.ord) into v_door_ord
  from jsonb_array_elements(p_blocks) with ordinality as b(value, ord)
  where b.value ->> 'type' = 'door';

  if v_door_ord is null then
    return query select p_blocks, null::jsonb;
    return;
  end if;

  return query
  select
    coalesce(
      (select jsonb_agg(b.value order by b.ord)
       from jsonb_array_elements(p_blocks) with ordinality as b(value, ord)
       where b.ord < v_door_ord),
      '[]'::jsonb
    ),
    (select jsonb_agg(b.value order by b.ord)
     from jsonb_array_elements(p_blocks) with ordinality as b(value, ord)
     where b.ord >= v_door_ord);
end;
$$;
