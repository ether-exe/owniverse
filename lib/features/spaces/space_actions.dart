import 'package:supabase_flutter/supabase_flutter.dart';

import '../blocks/block.dart';
import '../blocks/save_outcome.dart';
import 'slug.dart';
import 'space.dart';

/// A write that did not happen, and the sentence to say about it.
///
/// The database raises bare identifiers (`slug_taken`, `space_trashed`) because
/// a Postgres function is not the place for product copy. This is the place:
/// one mapping, so the same condition reads the same on every screen.
class SpaceFailure implements Exception {
  const SpaceFailure(this.code, this.message);

  /// The database's identifier, or `network` / `unknown` when there was none.
  final String code;

  /// A sentence a person can read. Never a stack trace, never "Oops".
  final String message;

  @override
  String toString() => message;
}

/// Maps anything a write can throw onto a [SpaceFailure].
///
/// Pure, so it is unit-tested without a client: the identifiers below are
/// copied from the migrations and the security suite, not guessed.
SpaceFailure spaceFailureFrom(Object error) {
  if (error is SpaceFailure) return error;

  if (error is PostgrestException) {
    return switch (error.message) {
      'slug_taken' => const SpaceFailure(
        'slug_taken',
        'One of your Spaces already uses that title.',
      ),
      'profile_incomplete' => const SpaceFailure(
        'profile_incomplete',
        'Finish your profile before making a Space.',
      ),
      'auth_required' => const SpaceFailure(
        'auth_required',
        'You are signed out. Sign in and try again.',
      ),
      'space_trashed' => const SpaceFailure(
        'space_trashed',
        'That Space is in the Trash. Restore it first.',
      ),
      'not_found' => const SpaceFailure(
        'not_found',
        'That Space is gone.',
      ),
      'invalid_visibility' => const SpaceFailure(
        'invalid_visibility',
        'Only private and public exist.',
      ),
      _ => const SpaceFailure('unknown', 'That did not save. Try again.'),
    };
  }

  if (error is AuthException) {
    return const SpaceFailure(
      'auth_required',
      'You are signed out. Sign in and try again.',
    );
  }

  return const SpaceFailure('network', 'Could not reach the server. Try again.');
}

/// Every write the profile and Trash screens perform.
///
/// An interface rather than a concrete class so the screens can be tested
/// without a backend: the dialog's whole job is to decide *which* call to make
/// and what to say when it fails, and neither question needs a network.
///
/// Every implementation goes through a `security definer` function, never
/// through a table (D35). The client cannot insert, update or delete a row even
/// if it wanted to: the policy matrix is the boundary, and these are the only
/// doors in it.
abstract interface class SpaceActions {
  /// New Space (DoD 5). The address is derived from the title — the author
  /// typed a title, not a slug (D18), and the database answers `slug_taken` if
  /// that title is already theirs.
  Future<Space> create({required String title});

  /// Rename (DoD 11). Moves the working slug and leaves `published_slug`
  /// alone, so the live address keeps answering until the next publish (D9).
  Future<Space> rename(String id, {required String title});

  /// D17's switch between `published` and `unlisted`. Only meaningful once a
  /// Space has a snapshot; on a draft it is a no-op the database accepts.
  Future<void> setVisibility(String id, {required bool isPublic});

  /// D3. Claims survive Trash — the title stays taken until purge (D19).
  Future<void> trash(String id);

  /// Reclaims the title and puts the Space back on the profile.
  Future<void> restore(String id);

  /// Releases the title immediately; there is no undo.
  Future<void> deleteForever(String id);

  /// D19's build-time polish: when a title collides, find out whether the
  /// holder is in the Trash, so the dialog can offer *Restore* instead of a
  /// dead end.
  Future<Space?> trashedBySlug(String slug);

  /// The editor's only write (SPEC §11). Sends the whole document and the
  /// version it was read from; a stale version comes back as a [Conflict]
  /// rather than overwriting what the other tab wrote.
  Future<SaveOutcome> saveBlocks(
    String id,
    List<Block> blocks, {
    required int version,
  });

  /// D5, D33: freeze the current document into a snapshot and make it public.
  /// The client sends nothing but an id — it cannot choose which blocks go
  /// public, and it cannot publish a document the server has not validated.
  ///
  /// Returns whether the snapshot has a door.
  Future<bool> publish(String id);

  /// Past the door (D22). Requires a session; records this reader once, so a
  /// refresh cannot inflate the count.
  Future<Map<String, Object?>?> enter(String handle, String slug);

  /// Adds or removes this reader's like. The author cannot like their own
  /// Space, and the database says so rather than the page pretending.
  Future<({bool liked, int likes})> toggleLike(String handle, String slug);
}

/// The real one: Supabase, over RPC.
class RpcSpaceActions implements SpaceActions {
  const RpcSpaceActions(this._client);

  final SupabaseClient _client;

  @override
  Future<Space> create({required String title}) => _guard(() async {
    final result = await _client.rpc(
      'create_space',
      params: {'p_title': title.trim(), 'p_slug': slugify(title)},
    );
    return Space.fromRpc(_asMap(result));
  });

  @override
  Future<Space> rename(String id, {required String title}) => _guard(() async {
    final result = await _client.rpc(
      'rename_space',
      params: {
        'p_space_id': id,
        'p_title': title.trim(),
        'p_slug': slugify(title),
      },
    );
    return Space.fromRpc(_asMap(result));
  });

  @override
  Future<void> setVisibility(String id, {required bool isPublic}) =>
      _guard(() async {
        await _client.rpc(
          'set_visibility',
          params: {
            'p_space_id': id,
            'p_visibility': isPublic ? Space.publicVisibility : 'private',
          },
        );
      });

  @override
  Future<void> trash(String id) => _guard(() async {
    await _client.rpc('trash_space', params: {'p_space_id': id});
  });

  @override
  Future<void> restore(String id) => _guard(() async {
    await _client.rpc('restore_space', params: {'p_space_id': id});
  });

  @override
  Future<void> deleteForever(String id) => _guard(() async {
    await _client.rpc('delete_forever', params: {'p_space_id': id});
  });

  /// Only `slug` is matched, not `published_slug`: a trashed Space holds its
  /// working title, and that is the one a new Space would collide with.
  @override
  Future<Space?> trashedBySlug(String slug) => _guard(() async {
    final row = await _client
        .from('spaces')
        .select(Space.columns)
        .not('deleted_at', 'is', null)
        .eq('slug', slug)
        .limit(1)
        .maybeSingle();

    return row == null ? null : Space.fromRow(row);
  });

  @override
  Future<SaveOutcome> saveBlocks(
    String id,
    List<Block> blocks, {
    required int version,
  }) => _guard(() async {
    final result = await _client.rpc(
      'save_blocks',
      params: {
        'p_space_id': id,
        'p_blocks': blocksToJson(blocks),
        'p_version': version,
      },
    );

    return SaveOutcome.fromRpc(_asMap(result));
  });

  @override
  Future<bool> publish(String id) => _guard(() async {
    final result = await _client.rpc(
      'publish_space',
      params: {'p_space_id': id},
    );
    return _asMap(result)['has_door'] == true;
  });

  @override
  Future<Map<String, Object?>?> enter(String handle, String slug) =>
      _guard(() async {
        final result = await _client.rpc(
          'space_enter',
          params: {'p_handle': handle, 'p_slug': slug},
        );
        if (result is! Map) return null;
        final map = Map<String, Object?>.from(result);
        return map['found'] == true ? map : null;
      });

  @override
  Future<({bool liked, int likes})> toggleLike(String handle, String slug) =>
      _guard(() async {
        final result = _asMap(
          await _client.rpc(
            'toggle_like',
            params: {'p_handle': handle, 'p_slug': slug},
          ),
        );
        return (
          liked: result['liked'] == true,
          likes: switch (result['likes']) {
            final int v => v,
            final num v => v.toInt(),
            _ => 0,
          },
        );
      });
}

Future<T> _guard<T>(Future<T> Function() run) async {
  try {
    return await run();
  } catch (error) {
    throw spaceFailureFrom(error);
  }
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
