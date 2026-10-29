-- M0 · 05 — row level security — SPEC §7.1, §7.4
-- Default deny: RLS on, and a table with no policy is unreachable.
-- There is no anon policy anywhere. The public reads tables never (D24).

alter table public.users        enable row level security;
alter table public.spaces       enable row level security;
alter table public.global       enable row level security;
alter table public.space_visits enable row level security;
alter table public.space_likes  enable row level security;
alter table public.media        enable row level security;

-- ---------------------------------------------------------------------------
-- Onboarding enforcement (§7.4). A direct PostgREST call cannot create content
-- from a half-built account.
-- ---------------------------------------------------------------------------

create or replace function public.assert_onboarded()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if (select username from public.users where id = auth.uid()) is null then
    raise exception 'profile_incomplete';
  end if;
end;
$$;

create or replace function public.require_onboarded()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_onboarded();
  return new;
end;
$$;

create trigger spaces_require_onboarded
  before insert on public.spaces
  for each row execute function public.require_onboarded();

create trigger media_require_onboarded
  before insert on public.media
  for each row execute function public.require_onboarded();

-- ---------------------------------------------------------------------------
-- users — owner may read and edit their own row. Nobody else, no anon.
-- ---------------------------------------------------------------------------

create policy users_select_own on public.users
  for select to authenticated
  using (id = auth.uid());

create policy users_update_own on public.users
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- spaces — the owner, and only the owner.
--
-- SPEC §7.1 writes this policy as "select own, where deleted_at is null".
-- That cannot ship as written: §13 step 18 requires Trash to list trashed
-- Spaces, and a policy is not a query filter. Trashed rows are not a security
-- boundary — they are the owner's own data — so access is scoped by owner and
-- the profile/Trash split is done in the query. Recorded as D34.
--
-- No DELETE policy: deleting is impossible over the API. Trash, restore and
-- purge are RPCs.
-- ---------------------------------------------------------------------------

create policy spaces_select_own on public.spaces
  for select to authenticated
  using (owner_id = auth.uid());

create policy spaces_insert_own on public.spaces
  for insert to authenticated
  with check (owner_id = auth.uid());

create policy spaces_update_own on public.spaces
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ---------------------------------------------------------------------------
-- global — the owner sees their own claims so availability can be checked.
-- ---------------------------------------------------------------------------

create policy global_select_own on public.global
  for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- counters — the owner reads the counts. Nobody writes them from the client;
-- space_enter and toggle_like do, as definer functions.
-- ---------------------------------------------------------------------------

create policy space_visits_select_own on public.space_visits
  for select to authenticated
  using (exists (
    select 1 from public.spaces s
    where s.id = space_visits.space_id and s.owner_id = auth.uid()
  ));

create policy space_likes_select_own on public.space_likes
  for select to authenticated
  using (exists (
    select 1 from public.spaces s
    where s.id = space_likes.space_id and s.owner_id = auth.uid()
  ));

-- ---------------------------------------------------------------------------
-- media — owner reads and inserts their own rows.
-- ---------------------------------------------------------------------------

create policy media_select_own on public.media
  for select to authenticated
  using (owner_id = auth.uid());

create policy media_insert_own on public.media
  for insert to authenticated
  with check (owner_id = auth.uid());
