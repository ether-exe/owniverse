import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_providers.dart';
import '../blocks/block.dart';
import 'pick_file.dart';

/// A refusal the author can read, for the cases the client can judge before the
/// server has to.
class MediaFailure implements Exception {
  const MediaFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where a block's image actually lives.
///
/// The bytes are fetched with the caller's own session, so the bucket's policies
/// decide who gets them: the owner always, an anonymous reader only on a Space
/// with no door, a signed-in reader on a gated one. The client never invents a
/// rule of its own here (D25).
class MediaRef {
  const MediaRef({required this.id, required this.path});

  final String id;
  final String path;
}

/// The write side of media. Not on `SpaceActions`, and deliberately so: that
/// interface is the RPC surface (D35), and media is the one place the schema
/// grants a direct insert — `media_insert_own` exists for exactly this.
class MediaWriter {
  const MediaWriter(this._client);

  final SupabaseClient _client;

  /// Opens the file chooser. Returns null when there is no chooser on this
  /// platform, or the author cancelled.
  Future<PickedFile?> pick() => pickImageFile();

  /// Uploads one file into its Space's folder and records the row.
  ///
  /// The path is `{space_id}/{uuid}.{ext}` because the storage policies key on
  /// the first folder being a Space the caller owns (SPEC §6.6). The row's `id`
  /// is what the block references; the path stays out of the document.
  Future<MediaRef> upload({
    required String spaceId,
    required PickedFile file,
  }) async {
    if (file.bytes.isEmpty) {
      throw const MediaFailure('That file is empty.');
    }
    // The column's own limit is 10 MB (`enforce_media_quota`). Saying so here
    // means the author is told before spending the upload, not after.
    if (file.bytes.length > 10 * 1024 * 1024) {
      throw const MediaFailure('An image can be up to 10 MB.');
    }

    final extension = _extensionOf(file.name, file.mime);
    final path = '$spaceId/${_uuid()}.$extension';

    await _client.storage
        .from('media')
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: file.mime),
        );

    final row = await _client
        .from('media')
        .insert({
          'space_id': spaceId,
          'path': path,
          'mime': file.mime,
          'bytes': file.bytes.length,
        })
        .select('id')
        .single();

    return MediaRef(id: row['id'] as String, path: path);
  }

  static String _extensionOf(String name, String mime) {
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final ext = name.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) return ext;
    }
    return switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };
  }

  /// A v4 id for a storage path.
  ///
  /// **Not** derived from the clock: an earlier version built all sixteen bytes
  /// from `DateTime.now().microsecond`, which gives the same byte sixteen times
  /// and hands two uploads in the same tick the same path. `newBlockId` is the
  /// one generator in the app, and it uses `Random.secure`.
  static String _uuid() => newBlockId();
}

final mediaWriterProvider = Provider<MediaWriter>(
  (ref) => MediaWriter(ref.watch(supabaseProvider)),
);

/// One image's bytes, fetched through the caller's session.
///
/// `null` means "not available to you", which is the honest answer for a gated
/// Space's media seen by an anonymous reader — the bucket refuses, and the page
/// shows nothing rather than a broken rectangle.
final mediaBytesProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  path,
) async {
  try {
    return await ref.watch(supabaseProvider).storage.from('media').download(path);
  } catch (_) {
    return null;
  }
});

/// The owner's view: `media` rows are readable by their owner, so a draft can
/// resolve its own images.
final ownerMediaPathsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, spaceId) async {
      final rows = await ref
          .watch(supabaseProvider)
          .from('media')
          .select('id, path')
          .eq('space_id', spaceId);

      return {
        for (final row in rows) row['id'] as String: row['path'] as String,
      };
    });

/// The reader's view: `space_media` (migration 13) answers with the mapping, and
/// only for a Space that is publicly readable at all.
final publicMediaPathsProvider =
    FutureProvider.family<Map<String, String>, String>((ref, spaceId) async {
      final result = await ref
          .watch(supabaseProvider)
          .rpc('space_media', params: {'p_space_id': spaceId});

      if (result is! List) return const {};
      return {
        for (final item in result)
          if (item is Map && item['id'] is String && item['path'] is String)
            item['id'] as String: item['path'] as String,
      };
    });

/// The block data a placed image carries. Kept next to the writer so the two
/// cannot disagree about which keys mean what.
Map<String, Object?> imageData({required String mediaId, String alt = ''}) => {
  'media_id': mediaId,
  'alt': alt,
};

Map<String, Object?> coverData({required String mediaId, String caption = ''}) => {
  'media_id': mediaId,
  'caption': caption,
};

/// The `media_id` a block points at, if any.
String? mediaIdOf(Block block) => block.mediaId;

/// The same pipeline into the public `avatars` bucket (DoD 4).
///
/// Separate from [MediaWriter.upload] on purpose: avatars belong to a user, not
/// a Space, live in a bucket with no gate, and are addressed by `{user_id}/…`
/// because that is what `avatars_insert_own` checks.
Future<String> uploadAvatar({
  required SupabaseClient client,
  required String userId,
  required PickedFile file,
}) async {
  final extension = MediaWriter._extensionOf(file.name, file.mime);
  final path = '$userId/${MediaWriter._uuid()}.$extension';

  await client.storage
      .from('avatars')
      .uploadBinary(
        path,
        file.bytes,
        fileOptions: FileOptions(contentType: file.mime),
      );

  return path;
}

/// A URL for a stored avatar. The bucket is public, so this is not a signed
/// link — a profile picture is public by design, and D24's boundary is on the
/// Space content, not on somebody's face.
String? avatarUrl(SupabaseClient client, String? path) {
  if (path == null || path.isEmpty) return null;
  return client.storage.from('avatars').getPublicUrl(path);
}
