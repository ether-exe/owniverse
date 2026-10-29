-- M0 · 10 — purge of trashed Spaces — D3, SPEC §6.2
-- Trash holds a Space for 30 days; then it is unrecoverable and its title
-- becomes claimable again (D19).

create extension if not exists pg_cron;

create or replace function public.purge_trashed()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_total   integer := 0;
  v_deleted integer;
  v_pass    integer;
begin
  for v_pass in 1..100 loop
    -- `parent_id` is ON DELETE RESTRICT: remove leaves first, then their parents.
    delete from public.spaces s
    where s.deleted_at is not null
      and s.purge_after < now()
      and not exists (
        select 1 from public.spaces c where c.parent_id = s.id
      );

    get diagnostics v_deleted = row_count;
    v_total := v_total + v_deleted;
    exit when v_deleted = 0;
  end loop;

  return v_total;
end;
$$;

revoke execute on function public.purge_trashed() from public, anon, authenticated;

-- Daily at 03:17 UTC. Times are UTC because that is what pg_cron runs in.
select cron.schedule(
  'owniverse-purge-trashed',
  '17 3 * * *',
  $$select public.purge_trashed();$$
);
