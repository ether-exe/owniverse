import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../blocks/block.dart';

/// What a reader is allowed to see (D22, D24).
///
/// One object for both halves of the gate: before entering, `blocks` is the
/// public slice and `space_head` provided it; after entering, `blocks` is the
/// whole frozen document and `space_enter` provided it. The page renders the same
/// widget either way, which is what makes "lands on the same block" true rather
/// than approximated.
class PublicSpace {
  const PublicSpace({
    required this.id,
    required this.title,
    required this.slug,
    required this.blocks,
    required this.hasDoor,
    required this.readers,
    required this.likes,
    this.likedByMe = false,
    this.authorName,
    this.authorHandle,
    this.authorEmail,
    this.authorAvatar,
    this.publishedAt,
  });

  final String id;
  final String title;
  final String slug;
  final List<Block> blocks;
  final bool hasDoor;

  /// Counted readers. Suppressed to zero by the database when there is no door —
  /// a counter that cannot count anybody is not shown a number (D23).
  final int readers;
  final int likes;
  final bool likedByMe;

  final String? authorName;
  final String? authorHandle;
  final String? authorEmail;

  /// DoD 4. A profile picture is public by design — the gate is on the Space,
  /// not on somebody's face.
  final String? authorAvatar;

  /// DoD 4. A profile picture is public by design — the gate is on the Space.
  final DateTime? publishedAt;

  factory PublicSpace.fromMap(Map<String, Object?> json) {
    final author = json['author'];
    final authorMap = author is Map ? Map<String, Object?>.from(author) : const <String, Object?>{};

    return PublicSpace(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      slug: (json['slug'] as String?) ?? '',
      blocks: blocksFromJson(json['blocks']),
      hasDoor: json['has_door'] == true,
      readers: _int(json['readers']),
      likes: _int(json['likes']),
      likedByMe: json['liked_by_me'] == true,
      authorName: authorMap['name'] as String?,
      authorHandle: authorMap['username'] as String?,
      authorEmail: authorMap['email'] as String?,
      authorAvatar: authorMap['avatar_path'] as String?,
      publishedAt: switch (json['published_at']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      },
    );
  }

  /// The reader's own view is the fuller one.
  PublicSpace withLiked({required bool liked, required int likes}) =>
      PublicSpace(
        id: id,
        title: title,
        slug: slug,
        blocks: blocks,
        hasDoor: hasDoor,
        readers: readers,
        likes: likes,
        likedByMe: liked,
        authorName: authorName,
        authorHandle: authorHandle,
        authorEmail: authorEmail,
        authorAvatar: authorAvatar,
        publishedAt: publishedAt,
      );

  static int _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    _ => 0,
  };
}

/// `(handle without @, slug)` — the two segments of a public address.
typedef SpaceAddress = (String handle, String slug);

/// The public read (D24: the public surface is functions, never table reads).
///
/// `space_head` returns the **public slice only**. The gated blocks are absent
/// from this payload, not hidden by the page — assertion 19 of the security suite
/// proves that on the wire.
final publicSpaceProvider = FutureProvider.family<PublicSpace?, SpaceAddress>(
  (ref, address) async {
    final result = await ref
        .watch(supabaseProvider)
        .rpc(
          'space_head',
          params: {'p_handle': address.$1, 'p_slug': address.$2},
        );

    if (result is! Map) return null;
    final map = Map<String, Object?>.from(result);
    return map['found'] == true ? PublicSpace.fromMap(map) : null;
  },
);
