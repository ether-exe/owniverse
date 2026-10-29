-- M0 · 03 — spaces and the per-user slug registry — SPEC §6.2, §6.3

create table public.spaces (
  id                       uuid primary key default gen_random_uuid(),
  owner_id                 uuid not null references public.users (id) on delete cascade,
  -- Restrict, not cascade: deleting a parent must not silently bypass the
  -- 30-day Trash. The purge job deletes deepest-first (see 08).
  parent_id                uuid references public.spaces (id) on delete restrict,
  title                    text not null,
  slug                     text not null,
  description              text,
  blocks                   jsonb not null default '[]'::jsonb,
  blocks_version           integer not null default 1,
  visibility               text not null default 'private',

  -- Publish produces three snapshots: the full document (owner-only), the
  -- slice above the first door, and the slice from the door down.
  published_blocks         jsonb,
  published_public_blocks  jsonb,
  published_gated_blocks   jsonb,
  published_title          text,
  published_slug           text,
  published_at             timestamptz,

  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  deleted_at               timestamptz,
  -- Not a generated column: `timestamptz + interval` is STABLE, not IMMUTABLE,
  -- so PostgreSQL rejects it as a generation expression. Maintained by trigger.
  purge_after              timestamptz,

  constraint spaces_title_length check (char_length(btrim(title)) between 2 and 80),
  constraint spaces_slug_shape check (
    char_length(slug) between 2 and 60
    and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  ),
  constraint spaces_description_length check (
    description is null or char_length(description) <= 200
  ),
  constraint spaces_visibility_values check (visibility in ('private', 'public')),
  constraint spaces_blocks_is_array check (jsonb_typeof(blocks) = 'array'),
  constraint spaces_blocks_count check (jsonb_array_length(blocks) <= 200),
  constraint spaces_blocks_size check (pg_column_size(blocks) <= 262144),
  constraint spaces_blocks_version_positive check (blocks_version >= 1),

  -- Backstop only. The registry in `global` is authoritative.
  constraint spaces_slug_unique_per_owner unique (owner_id, slug)
);

create index spaces_owner_deleted_idx
  on public.spaces (owner_id, deleted_at);

create index spaces_owner_published_slug_idx
  on public.spaces (owner_id, published_slug)
  where deleted_at is null;

create index spaces_parent_idx on public.spaces (parent_id);

create trigger spaces_touch_updated_at
  before update on public.spaces
  for each row execute function public.touch_updated_at();

-- Trash holds a Space for 30 days, then it is eligible for purge (D3).
create or replace function public.set_spaces_purge_after()
returns trigger
language plpgsql
as $$
begin
  new.purge_after = case
    when new.deleted_at is null then null
    else new.deleted_at + interval '30 days'
  end;
  return new;
end;
$$;

create trigger spaces_set_purge_after
  before insert or update on public.spaces
  for each row execute function public.set_spaces_purge_after();

-- ---------------------------------------------------------------------------
-- global — the per-user claim registry (D20)
-- The composite primary key is the race fix: two clients claiming the same
-- slug in the same instant produce one row and one unique violation.
-- ---------------------------------------------------------------------------

create table public.global (
  user_id    uuid not null references public.users (id) on delete cascade,
  slug       text not null,
  space_id   uuid not null references public.spaces (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (user_id, slug),

  constraint global_slug_shape check (
    char_length(slug) between 2 and 60
    and slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
  )
);

create index global_space_idx on public.global (space_id);
