import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../export/save_file.dart';
import '../export/space_export.dart';
import 'space.dart';
import 'space_actions.dart';
import 'space_feedback.dart';
import 'space_title_dialog.dart';
import 'spaces_providers.dart';

/// D15: the per-Space actions live on the Space's row, not inside it and not in
/// a sidebar. In M2 that is Rename and Move to Trash; Publish joins them in M4
/// and the editor stays the place where blocks are edited (D7).
enum SpaceMenuAction { open, rename, publish, visibility, export, trash }

class SpaceRowMenu extends ConsumerWidget {
  const SpaceRowMenu({
    super.key,
    required this.space,
    required this.handle,
    this.canPublish = true,
  });

  final Space space;
  final String handle;

  /// False for a Space with nothing in it — publishing an empty page is a
  /// decision the author should make deliberately, and the server will.
  final bool canPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<SpaceMenuAction>(
      tooltip: 'Actions',
      offset: const Offset(0, 32),
      color: Palette.canvas,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Palette.hairline),
      ),
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        _item(SpaceMenuAction.rename, 'Rename'),
        _item(
          SpaceMenuAction.publish,
          space.hasSnapshot ? 'Publish again' : 'Publish',
          enabled: canPublish,
        ),
        // D17, DoD 15: a published Space can be made private. The snapshot is
        // kept, so the address stops answering without the bytes being lost.
        if (space.hasSnapshot)
          _item(
            SpaceMenuAction.visibility,
            space.state == SpaceState.published ? 'Make private' : 'Make public',
          ),
        // DoD 19: the document leaves as one file, unchanged.
        _item(SpaceMenuAction.export, 'Export JSON'),
        _item(SpaceMenuAction.trash, 'Move to Trash'),
      ],
      child: Padding(
        // A 44 px target around a two-character glyph: the glyph is the mark,
        // the padding is the button.
        padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Text(
              '⋯',
              style: AppType.mono(size: 15, color: Palette.muted),
            ),
          ),
        ),
      ),
    );
  }

  static PopupMenuItem<SpaceMenuAction> _item(
    SpaceMenuAction action,
    String label, {
    bool enabled = true,
  }) {
    return PopupMenuItem<SpaceMenuAction>(
      value: action,
      enabled: enabled,
      height: 40,
      child: Text(
        label,
        style: AppType.sans(size: 14, color: enabled ? Palette.ink : Palette.muted),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    SpaceMenuAction action,
  ) async {
    switch (action) {
      case SpaceMenuAction.open:
        context.push('/space/${space.id}');

      case SpaceMenuAction.rename:
        await SpaceTitleDialog.show(context, handle: handle, space: space);

      case SpaceMenuAction.publish:
        try {
          await ref.read(spaceActionsProvider).publish(space.id);
          ref.invalidate(ownerSpacesProvider);
          ref.invalidate(spaceDocumentProvider(space.id));
          if (!context.mounted) return;
          // D8: the address only becomes live now, and it is worth saying which
          // one it is — the draft slug is not necessarily the published one.
          showSpaceNotice(context, 'Published at $handle/${space.slug}.');
        } on SpaceFailure catch (failure) {
          if (context.mounted) showSpaceFailure(context, failure);
        }

      case SpaceMenuAction.visibility:
        final makePublic = space.state != SpaceState.published;
        try {
          await ref
              .read(spaceActionsProvider)
              .setVisibility(space.id, isPublic: makePublic);
          ref.invalidate(ownerSpacesProvider);
          if (!context.mounted) return;
          showSpaceNotice(
            context,
            makePublic
                ? 'Public again at $handle/${space.addressSlug}.'
                : 'Private. The address stops answering; the snapshot is kept.',
          );
        } on SpaceFailure catch (failure) {
          if (context.mounted) showSpaceFailure(context, failure);
        }

      case SpaceMenuAction.export:
        try {
          // The list row does not carry the document — fetching it here is the
          // point of keeping `blocks` out of every list query.
          final document = await ref.read(
            spaceDocumentProvider(space.id).future,
          );
          if (!context.mounted) return;
          if (document == null) {
            showSpaceNotice(context, 'That Space is gone.', bad: true);
            return;
          }

          final saved = saveTextFile(
            exportFileName(document),
            exportDocument(document),
          );
          if (!context.mounted) return;
          showSpaceNotice(
            context,
            saved
                ? 'Exported ${exportFileName(document)}.'
                : 'This platform cannot save a file. No export was made.',
            bad: !saved,
          );
        } on SpaceFailure catch (failure) {
          if (context.mounted) showSpaceFailure(context, failure);
        }

      case SpaceMenuAction.trash:
        try {
          await ref.read(spaceActionsProvider).trash(space.id);
          ref.invalidate(ownerSpacesProvider);
          ref.invalidate(trashedSpacesProvider);
          // The row leaving is the confirmation, and the Trash count at the
          // bottom of the page goes up by one. A toast would only repeat that.
        } on SpaceFailure catch (failure) {
          if (context.mounted) showSpaceFailure(context, failure);
        }
    }
  }
}
