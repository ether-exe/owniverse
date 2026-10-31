-- v0.1 · 13 — resolving a block's media to a path
--
-- Found while building the media pipeline, by running it rather than by reading
-- it: a `cover` or `image` block carries a `media_id`, and NOTHING outside the
-- owner can turn that id into a storage path. `media_select_own` scopes reads to
-- `owner_id = auth.uid()`, which is right for a table and wrong for a page: the
-- reader of a published Space is not the owner, so every image would resolve to
-- nothing.
--
-- Two things were considered and rejected:
--
--   * Putting `path` in the block's `data`. It works, and it is one line of
--     client code — but it makes the public address of a file part of a JSON
--     document the author can edit, and SPEC §8 defines the block as
--     `{ media_id, alt, caption? }`. The spec is not edited to match a shortcut.
--
--   * Broadening `media_select_own`. That policy is the table's boundary; the
--     page needs a *constructed* answer, which is what D24 says the public
--     surface is for.
--
-- What this returns is not the bytes — storage policies still decide those (D25).
-- It is the mapping, and only for a Space that is publicly readable at all. On a
-- Space with a door the paths still come back, because a signed-in reader may
-- fetch them and an anonymous one is refused by the bucket, not by this list.

create or replace function public.space_media(p_space_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'path', m.path,
        'mime', m.mime,
        'width', m.width,
        'height', m.height
      )
      order by m.created_at
    ),
    '[]'::jsonb
  )
  from public.media m
  join public.spaces s on s.id = m.space_id
  where m.space_id = p_space_id
    and private.is_publicly_readable(s.visibility, s.published_at, s.deleted_at);
$$;

revoke execute on function public.space_media(uuid) from public, anon, authenticated;
grant execute on function public.space_media(uuid) to anon, authenticated;
