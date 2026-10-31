import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/blocks/save_outcome.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/space_actions.dart';
import 'package:owniverse/features/spaces/slug.dart';

/// A stand-in for the database, recording what was asked of it.
///
/// Every M2 screen's job is to decide *which* call to make, with which value,
/// and what to say when it fails. None of that needs a network — the real
/// boundary is proved by `scripts/db-test.mjs`, not here.
class FakeSpaceActions implements SpaceActions {
  FakeSpaceActions({this.trashedHolder, this.seeded = const []});

  /// Returned by [trashedBySlug], for D19's escape hatch.
  final Space? trashedHolder;

  /// Anything the screens should already believe exists.
  final List<Space> seeded;

  final List<String> created = [];
  final List<String> renamed = [];
  final List<String> trashed = [];
  final List<String> restored = [];
  final List<String> deleted = [];
  final List<String> visibilityChanges = [];
  final List<String> savedVersions = [];

  /// Set while `create` should answer `slug_taken`.
  bool slugTaken = false;

  /// The version the next [saveBlocks] will report as current, so a conflict
  /// can be staged.
  int nextVersion = 1;
  bool savesConflict = false;

  /// Set to make the next write fail with a specific failure.
  SpaceFailure? throwOnWrite;

  Future<T> _write<T>(T Function() answer) async {
    final failure = throwOnWrite;
    if (failure != null) {
      throwOnWrite = null;
      throw failure;
    }
    return answer();
  }

  @override
  Future<Space> create({required String title}) async {
    created.add(title);
    if (slugTaken) {
      throw const SpaceFailure(
        'slug_taken',
        'One of your Spaces already uses that title.',
      );
    }
    return _write(
      () => Space(
        id: 'new',
        title: title,
        slug: slugify(title),
        visibility: 'private',
      ),
    );
  }

  @override
  Future<Space> rename(String id, {required String title}) async {
    renamed.add('$id:$title');
    return _write(
      () => Space(
        id: id,
        title: title,
        slug: slugify(title),
        visibility: 'private',
      ),
    );
  }

  @override
  Future<void> setVisibility(String id, {required bool isPublic}) async {
    visibilityChanges.add('$id:${isPublic ? 'public' : 'private'}');
    await _write(() => null);
  }

  @override
  Future<void> trash(String id) async {
    trashed.add(id);
    await _write(() => null);
  }

  @override
  Future<void> restore(String id) async {
    restored.add(id);
    await _write(() => null);
  }

  @override
  Future<void> deleteForever(String id) async {
    deleted.add(id);
    await _write(() => null);
  }

  @override
  Future<Space?> trashedBySlug(String slug) async => trashedHolder;

  @override
  Future<SaveOutcome> saveBlocks(
    String id,
    List<Block> blocks, {
    required int version,
  }) async {
    savedVersions.add('$id@$version/${blocks.length}');
    return _write(
      () => savesConflict ? Conflict(nextVersion) : Saved(version + 1),
    );
  }

  /// Records that publish was asked for, and what it answered.
  final List<String> published = [];
  bool publishHasDoor = false;

  /// Set to make [enter] answer with a document instead of `null`.
  Map<String, Object?>? enterResult;
  final List<String> entered = [];

  bool likedByMe = false;
  int likeCount = 0;

  @override
  Future<bool> publish(String id) async {
    published.add(id);
    await _write(() => null);
    return publishHasDoor;
  }

  @override
  Future<Map<String, Object?>?> enter(String handle, String slug) async {
    entered.add('$handle/$slug');
    await _write(() => null);
    return enterResult;
  }

  @override
  Future<({bool liked, int likes})> toggleLike(
    String handle,
    String slug,
  ) async {
    likedByMe = !likedByMe;
    likeCount += likedByMe ? 1 : -1;
    await _write(() => null);
    return (liked: likedByMe, likes: likeCount);
  }
}
