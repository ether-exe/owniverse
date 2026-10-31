import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../ui/canvas.dart';
import '../auth/auth_providers.dart';
import '../spaces/space.dart';
import '../spaces/space_actions.dart';
import '../spaces/space_feedback.dart';
import '../spaces/spaces_providers.dart';

/// `/trash` — where a deleted Space waits (D3, D19, SPEC §10).
///
/// Trash is not a state of a Space; it is `deleted_at` on a row that still
/// exists. The title stays claimed for all thirty days, which is why the same
/// title cannot be reused until this page lets it go.
class TrashPage extends ConsumerWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trash = ref.watch(trashedSpacesProvider);
    final handle = ref.watch(profileProvider).value?.handle ?? '';

    final Widget body;
    // `hasError` before `isLoading`: a retrying failure is still a failure (see
    // `_OwnerLens` in profile_page.dart).
    if (trash.hasError) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The Trash could not be loaded.',
            style: AppType.sans(size: 15, color: Palette.muted),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => ref.invalidate(trashedSpacesProvider),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text(
              'Try again',
              style: AppType.mono(size: 11, color: Palette.ink),
            ),
          ),
        ],
      );
    } else if (trash.isLoading) {
      body = const LinearProgressIndicator(minHeight: 1);
    } else {
      body = _TrashList(spaces: trash.requireValue, handle: handle);
    }

    return Canvas(
      maxWidth: 560,
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRASH', style: AppType.mono(size: 11, spacing: 2.4)),
          const SizedBox(height: 20),
          Text('What you deleted.', style: AppType.serif(size: 30)),
          const SizedBox(height: 12),
          Text(
            'A Space sits here for thirty days with its title still held. '
            'After that it is gone, and the title is free again.',
            style: AppType.sans(size: 14, color: Palette.muted, height: 1.6),
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, color: Palette.hairline),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => context.go('/$handle'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: Text('← $handle', style: AppType.mono(size: 12)),
          ),
        ],
      ),
    );
  }
}

class _TrashList extends ConsumerWidget {
  const _TrashList({required this.spaces, required this.handle});

  final List<Space> spaces;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (spaces.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Nothing in the Trash.',
          style: AppType.sans(size: 15, color: Palette.muted, height: 1.6),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < spaces.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Palette.hairline),
          _TrashRow(space: spaces[i], handle: handle),
        ],
      ],
    );
  }
}

class _TrashRow extends ConsumerWidget {
  const _TrashRow({required this.space, required this.handle});

  final Space space;
  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = space.remainingDays(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(space.title, style: AppType.serif(size: 22)),
          const SizedBox(height: 2),
          Text('$handle/${space.addressSlug}', style: AppType.mono(size: 11)),
          const SizedBox(height: 8),
          Text(
            days <= 0 ? 'LAST DAY' : '$days DAYS LEFT',
            style: AppType.mono(size: 10, spacing: 1.4),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 20,
            runSpacing: 2,
            children: [
              TextButton(
                onPressed: () => _restore(context, ref),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text('Restore', style: AppType.sans(size: 13)),
              ),
              TextButton(
                onPressed: () => _deleteForever(context, ref),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: Palette.accent,
                ),
                child: Text(
                  'Delete forever',
                  style: AppType.sans(size: 13, color: Palette.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(spaceActionsProvider).restore(space.id);
      ref.invalidate(ownerSpacesProvider);
      ref.invalidate(trashedSpacesProvider);
      if (context.mounted) showSpaceNotice(context, 'Restored to $handle.');
    } on SpaceFailure catch (failure) {
      if (context.mounted) showSpaceFailure(context, failure);
    }
  }

  Future<void> _deleteForever(BuildContext context, WidgetRef ref) async {
    final confirmed = await _ConfirmDelete.show(context, title: space.title);
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(spaceActionsProvider).deleteForever(space.id);
      ref.invalidate(ownerSpacesProvider);
      ref.invalidate(trashedSpacesProvider);
      // DoD 18's last clause, said out loud: the title is claimable again.
      if (context.mounted) {
        showSpaceNotice(context, 'Gone. Its title is free to use again.');
      }
    } on SpaceFailure catch (failure) {
      if (context.mounted) showSpaceFailure(context, failure);
    }
  }
}

/// Irreversible, so it is asked. Restoring is not asked — that one is.
class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.title});

  final String title;

  static Future<bool?> show(BuildContext context, {required String title}) {
    return showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => _ConfirmDelete(title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            color: Palette.canvas,
            border: Border.all(color: Palette.hairline),
          ),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DELETE FOREVER', style: AppType.mono(size: 10, spacing: 2.4)),
              const SizedBox(height: 16),
              Text('This cannot be undone.', style: AppType.serif(size: 26)),
              const SizedBox(height: 10),
              Text(
                '“$title” is deleted now — its blocks, its snapshots and its '
                'place in your Trash. The title becomes free for you to use '
                'again.',
                style: AppType.sans(size: 13, color: Palette.muted, height: 1.6),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: AppType.sans(size: 14, color: Palette.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: Palette.accent,
                    ),
                    child: Text(
                      'Delete forever',
                      style: AppType.sans(size: 14, color: Palette.accent),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
