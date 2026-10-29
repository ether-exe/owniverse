-- M0 · 12 — one error for one condition
-- A duplicate slug could surface two ways: `slug_taken` from the registry, or
-- a raw 409 from `spaces_slug_unique_per_owner` when the backstop fires first.
-- The client should not have to know which. Normalise the backstop.

create or replace function public.create_space(p_title text, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_title text := btrim(coalesce(p_title, ''));
  v_space public.spaces;
begin
  perform public.assert_onboarded();

  begin
    insert into public.spaces (owner_id, title, slug)
    values (v_uid, v_title, p_slug)
    returning * into v_space;
  exception when unique_violation then
    raise exception 'slug_taken';
  end;

  perform private.claim(v_uid, p_slug, v_space.id);

  return jsonb_build_object(
    'id', v_space.id, 'title', v_space.title, 'slug', v_space.slug,
    'visibility', v_space.visibility, 'blocks_version', v_space.blocks_version
  );
end;
$$;

create or replace function public.rename_space(p_space_id uuid, p_title text, p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space public.spaces := private.owned_space(p_space_id);
begin
  begin
    update public.spaces
       set title = btrim(coalesce(p_title, '')), slug = p_slug
     where id = p_space_id
     returning * into v_space;
  exception when unique_violation then
    raise exception 'slug_taken';
  end;

  perform private.claim(v_space.owner_id, p_slug, p_space_id);
  perform private.sync_claims(p_space_id);

  return jsonb_build_object(
    'id', v_space.id, 'title', v_space.title, 'slug', v_space.slug,
    'published_slug', v_space.published_slug
  );
end;
$$;

revoke execute on function public.create_space(text, text) from public, anon, authenticated;
revoke execute on function public.rename_space(uuid, text, text) from public, anon, authenticated;
grant execute on function public.create_space(text, text) to authenticated;
grant execute on function public.rename_space(uuid, text, text) to authenticated;
