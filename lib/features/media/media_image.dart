import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme.dart';
import 'media.dart';

/// One image, fetched through the caller's session.
///
/// The three states are the three honest answers: bytes (you may see this), the
/// hairline (waiting), and nothing at all — because a gated Space's media is
/// refused by the bucket to an anonymous reader and a broken rectangle would be
/// a lie about why.
class MediaImage extends ConsumerWidget {
  const MediaImage({
    super.key,
    required this.path,
    this.maxHeight = 420,
    this.fit = BoxFit.cover,
  });

  final String path;
  final double maxHeight;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(mediaBytesProvider(path));

    if (bytes.hasError) return const SizedBox.shrink();
    if (bytes.isLoading) {
      return Container(
        height: 80,
        decoration: BoxDecoration(border: Border.all(color: Palette.hairline)),
      );
    }

    final data = bytes.value;
    if (data == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Image.memory(
        data,
        fit: fit,
        width: double.infinity,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Shown in place of an image whose bytes the reader may not fetch — the case
/// that only exists on a gated Space, and the one worth saying out loud rather
/// than leaving blank.
class MediaWithheld extends StatelessWidget {
  const MediaWithheld({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'An image here is held back with the rest of the page.',
      style: AppType.mono(size: 10, spacing: 1.2),
    );
  }
}

