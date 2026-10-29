-- M0 · 02 — users (profile, 1:1 with auth.users) — SPEC §6.1
-- `username is null` IS "onboarding incomplete" (SPEC §7.4).

-- Social links are an allow-list of keys with http(s) values. A CHECK cannot
-- contain a subquery, so the rule lives in an immutable function.
create or replace function public.is_valid_social(j jsonb)
returns boolean
language plpgsql
immutable
as $$
begin
  if j is null or jsonb_typeof(j) <> 'object' then
    return false;
  end if;

  if exists (
    select 1 from jsonb_object_keys(j) as k
    where k not in ('x', 'github', 'instagram', 'youtube', 'website')
  ) then
    return false;
  end if;

  if exists (
    select 1 from jsonb_each_text(j) as e
    where char_length(e.value) > 300
       or e.value !~ '^https?://'
  ) then
    return false;
  end if;

  return true;
end;
$$;

create table public.users (
  id            uuid primary key references auth.users (id) on delete cascade,
  username      public.citext unique,
  name          text,
  avatar_path   text,
  email_public  boolean not null default false,
  social        jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  -- 3–30 chars, lowercase alphanumeric and hyphens, no edge hyphens, no `--`.
  constraint users_username_format check (
    username is null
    or username::text ~ '^[a-z0-9](?:[a-z0-9-]{1,28}[a-z0-9])$'
  ),
  constraint users_username_no_double_hyphen check (
    username is null or username::text !~ '--'
  ),
  constraint users_name_length check (
    name is null or char_length(btrim(name)) between 1 and 60
  ),
  constraint users_social_valid check (public.is_valid_social(social))
);

create trigger users_touch_updated_at
  before update on public.users
  for each row execute function public.touch_updated_at();

-- Every auth user gets a bare profile row. Run as definer so the auth schema
-- trigger can write into public regardless of who signed up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill any accounts that already exist.
insert into public.users (id)
select id from auth.users
on conflict (id) do nothing;
