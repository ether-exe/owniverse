import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../blocks/block.dart';
import 'space.dart';
import 'space_actions.dart';

/// The one place writes are reached from. Screens call methods on it and then
/// invalidate a list; they never hold a `SupabaseClient` themselves.
final spaceActionsProvider = Provider<SpaceActions>(
  (ref) => RpcSpaceActions(ref.watch(supabaseProvider)),
);

/// The owner lens: every live Space the caller owns, drafts included.
///
/// Reads `spaces` directly rather than through a function because
/// `spaces_select_own` already scopes the rows to the caller (SPEC §7.1) and
/// there is no write path here — writes are RPC-only (D35).
///
/// Top-level only (D15): child Spaces are schema-supported and UI-parked (D2).
final ownerSpacesProvider = FutureProvider<List<Space>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];

  final rows = await ref
      .watch(supabaseProvider)
      .from('spaces')
      .select(Space.columns)
      .eq('owner_id', session.user.id)
      .isFilter('deleted_at', null)
      .isFilter('parent_id', null)
      .order('updated_at', ascending: false);

  return [
    for (final row in rows) Space.fromRow(row),
  ];
});

/// `/trash` — the same rows, seen through `deleted_at`.
///
/// A separate provider rather than a filter argument: the two lists never
/// appear together, and a policy is not a query filter (D34).
final trashedSpacesProvider = FutureProvider<List<Space>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];

  final rows = await ref
      .watch(supabaseProvider)
      .from('spaces')
      .select(Space.columns)
      .eq('owner_id', session.user.id)
      .not('deleted_at', 'is', null)
      .isFilter('parent_id', null)
      .order('deleted_at', ascending: false);

  return [
    for (final row in rows) Space.fromRow(row),
  ];
});

/// One Space **with its document**, for the editor only.
///
/// Kept apart from [Space] on purpose. `blocks` is the whole draft document — up
/// to 200 blocks and a quarter of a megabyte — and the profile lists every Space
/// at once. Putting the document in [Space.columns] would make the owner's own
/// profile fetch every word they have ever written to render a list of titles.
class SpaceDocument {
  const SpaceDocument({required this.space, required this.blocks});

  final Space space;
  final List<Block> blocks;

  /// The optimistic-lock version the document was read at (SPEC §11).
  int get version => space.blocksVersion;
}

/// The editor's read: one Space, its document, and the version to save against.
final spaceDocumentProvider = FutureProvider.family<SpaceDocument?, String>((
  ref,
  id,
) async {
  final row = await ref
      .watch(supabaseProvider)
      .from('spaces')
      .select('${Space.columns}, blocks')
      .eq('id', id)
      .maybeSingle();

  if (row == null) return null;
  return SpaceDocument(
    space: Space.fromRow(row),
    blocks: blocksFromJson(row['blocks']),
  );
});
