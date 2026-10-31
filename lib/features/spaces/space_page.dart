import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import '../../ui/not_found_page.dart';
import '../auth/auth_providers.dart';
import '../editor/block_editor.dart';
import 'spaces_providers.dart';

/// `/space/:id` — the owner's canvas (SPEC §10). Id-based on purpose: a Draft has
/// no public address to open, and it still needs a URL.
///
/// This widget does the reading — loading, failure, ownership — and hands the
/// document to [BlockEditor], which owns everything from there. Keeping the two
/// apart means the editor can be tested with a document rather than a database.
class SpacePage extends ConsumerWidget {
  const SpacePage({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(spaceDocumentProvider(id));
    final handle = ref.watch(profileProvider).value?.handle;

    // Same ordering as the profile: a retrying failure is still a failure, and
    // the reader should not be shown a spinner for it (see `_OwnerLens`).
    if (document.hasError) {
      return Canvas(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This Space could not be loaded.',
              style: AppType.sans(size: 15, color: Palette.muted),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => ref.invalidate(spaceDocumentProvider(id)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(
                'Try again',
                style: AppType.mono(size: 11, color: Palette.ink),
              ),
            ),
          ],
        ),
      );
    }

    if (document.isLoading) {
      return const Canvas(child: LinearProgressIndicator(minHeight: 1));
    }

    final value = document.value;
    // RLS is the ownership check: a Space that is not yours is not returned at
    // all, so "no row" and "not yours" are the same answer here.
    if (value == null || handle == null) {
      return NotFoundPage(lookedFor: '/space/$id');
    }

    return BlockEditor(
      // The key makes a different Space a different editor, rather than the
      // same one with someone else's text in it.
      key: ValueKey(value.space.id),
      document: value,
      handle: handle,
    );
  }
}
