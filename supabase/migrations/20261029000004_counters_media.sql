-- M0 · 04 — counters and media — SPEC §6.4, §6.5, §6.6

-- Readers: one row per (Space, person), forever. A refresh cannot move it.
create table public.space_visits (
  space_id   uuid not null references public.spaces (id) on delete cascade,
  reader_id  uuid not null references public.users (id) on delete cascade,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now(),

  primary key (space_id, reader_id)
);

create index space_visits_reader_idx on public.space_visits (reader_id);

-- Likes: one per reader per Space. "The owner cannot like their own Space" is
-- enforced in the RPC, not here — the owner check needs auth.uid().
create table public.space_likes (
  space_id   uuid not null references public.spaces (id) on delete cascade,
  reader_id  uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),

  primary key (space_id, reader_id)
);

create index space_likes_reader_idx on public.space_likes (reader_id);

-- Media rows. The bytes live in a private bucket; this table is the index and
-- the quota ledger.
create table public.media (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.users (id) on delete cascade,
  -- null = avatar
  space_id   uuid references public.spaces (id) on delete cascade,
  path       text not null unique,
  mime       text not null,
  bytes      integer not null,
  width      integer,
  height     integer,
  created_at timestamptz not null default now(),

  constraint media_mime_allowed check (
    mime in ('image/png', 'image/jpeg', 'image/webp', 'image/gif')
  ),
  constraint media_bytes_positive check (bytes > 0),
  constraint media_bytes_max check (bytes <= 10 * 1024 * 1024),
  -- Avatars get their own, smaller ceiling.
  constraint media_avatar_bytes_max check (space_id is not null or bytes <= 2 * 1024 * 1024)
);

create index media_owner_idx on public.media (owner_id);
create index media_space_idx on public.media (space_id);

-- 200 MB per user, enforced on insert.
create or replace function public.enforce_media_quota()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if coalesce((select sum(m.bytes) from public.media m where m.owner_id = new.owner_id), 0)
     + new.bytes > 200 * 1024 * 1024 then
    raise exception 'media_quota_exceeded';
  end if;
  return new;
end;
$$;

create trigger media_enforce_quota
  before insert on public.media
  for each row execute function public.enforce_media_quota();
