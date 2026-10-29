-- M0 · 01 — extensions and shared helpers
-- citext gives case-insensitive usernames. Installed in `public` on purpose:
-- every SECURITY DEFINER function pins `search_path = public, pg_temp`, so the
-- type and its operators must be reachable from there. Installing it in
-- `extensions` would make `username = $1` fail to resolve an operator.

create extension if not exists citext with schema public;

-- One trigger function for every `updated_at` column. Replaces moddatetime so
-- the schema has no dependency beyond what PostgreSQL ships with.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
