-- M0 · 11 — fix publish_space (D33)
-- 08 claimed the draft slug before publishing, but create_space already holds
-- that claim, so every first publish raised slug_taken. The claim is not
-- needed: sync_claims already inserts both the draft and published slugs and
-- releases the previous published one (D9).

create or replace function public.publish_space(p_space_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_space  public.spaces := private.owned_space(p_space_id);
  v_public jsonb;
  v_gated  jsonb;
  v_door   boolean;
begin
  perform private.validate_blocks(v_space.blocks, p_space_id);

  select s.public_blocks, s.gated_blocks
    into v_public, v_gated
    from private.split_at_door(v_space.blocks) s;

  v_door := v_gated is not null;

  update public.spaces
     set published_blocks        = v_space.blocks,
         published_public_blocks = v_public,
         published_gated_blocks  = v_gated,
         published_title         = v_space.title,
         published_slug          = v_space.slug,
         published_at            = now(),
         visibility              = 'public'
   where id = p_space_id;

  -- Claims the new published slug; releases the previous one unless the draft
  -- still uses it (D9).
  perform private.sync_claims(p_space_id);

  return jsonb_build_object(
    'status', 'published',
    'published_slug', v_space.slug,
    'has_door', v_door,
    'public_blocks', jsonb_array_length(v_public),
    'gated_blocks', coalesce(jsonb_array_length(v_gated), 0)
  );
end;
$$;

revoke execute on function public.publish_space(uuid) from public, anon, authenticated;
grant execute on function public.publish_space(uuid) to authenticated;
