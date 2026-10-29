-- M0 · 09 — storage — SPEC §7.5, D25
-- Buckets are created by migration, not by hand, so a fresh project rebuilds
-- identically. Media is private; avatars are public.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', true,
  2 * 1024 * 1024,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'media', 'media', false,
  10 * 1024 * 1024,
  array['image/png', 'image/jpeg', 'image/webp', 'image/gif']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- The same gate as space_head / space_enter, applied to an object path.
-- Path shape is `{space_id}/{uuid}.{ext}`.
--
-- A gated Space's media is past the door, so it needs a session. This is the
-- coarse but honest rule from §7.3: you cannot reach gated bytes by guessing
-- an image URL.
-- ---------------------------------------------------------------------------

create or replace function private.can_read_media_path(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_space_id uuid;
  v_space    public.spaces;
  v_uid      uuid := auth.uid();
begin
  begin
    v_space_id := split_part(p_name, '/', 1)::uuid;
  exception when others then
    return false;
  end;

  select * into v_space from public.spaces where id = v_space_id;
  if v_space.id is null then
    return false;
  end if;

  if v_space.owner_id = v_uid then
    return true;
  end if;

  if not private.is_publicly_readable(v_space.visibility, v_space.published_at, v_space.deleted_at) then
    return false;
  end if;

  if v_space.published_gated_blocks is not null then
    return v_uid is not null;
  end if;

  return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- avatars — public bucket, own folder only for writes
-- ---------------------------------------------------------------------------

create policy avatars_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'avatars');

create policy avatars_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy avatars_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- media — private bucket, gated read, own-Space write
-- ---------------------------------------------------------------------------

create policy media_read_gated on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'media' and private.can_read_media_path(name));

create policy media_insert_own_space on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'media'
    and exists (
      select 1 from public.spaces s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = auth.uid()
    )
  );

create policy media_update_own_space on storage.objects
  for update to authenticated
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.spaces s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = auth.uid()
    )
  );

create policy media_delete_own_space on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'media'
    and exists (
      select 1 from public.spaces s
      where s.id::text = (storage.foldername(name))[1]
        and s.owner_id = auth.uid()
    )
  );
