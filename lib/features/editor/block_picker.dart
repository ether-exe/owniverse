import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../blocks/block.dart';

/// The block picker: a real panel, not a slash menu (D28).
///
/// Nine types is small enough to show, so it shows them — grouped by what they
/// do rather than alphabetically. The six content types read; the three at the
/// bottom change what the page *does*, and the door is the only one that alters
/// who can read the rest.
class BlockPicker extends StatelessWidget {
  const BlockPicker({
    super.key,
    this.canAddDoor = true,
    this.unavailable = const {},
  });

  /// A document has at most one door. When it already has one, the door row is
  /// shown and refused rather than hidden — hiding it would make the author
  /// wonder where it went.
  final bool canAddDoor;

  /// Types this build cannot place yet. Shown with the reason instead of offered
  /// and broken: an image without an upload is a block that can never be saved.
  final Set<BlockType> unavailable;

  static Future<BlockType?> show(
    BuildContext context, {
    bool canAddDoor = true,
    Set<BlockType> unavailable = const {},
  }) {
    return showDialog<BlockType>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (_) =>
          BlockPicker(canAddDoor: canAddDoor, unavailable: unavailable),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = BlockType.values.where((type) => type.isContent);
    final structure = BlockType.values.where((type) => !type.isContent);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: Palette.canvas,
            border: Border.all(color: Palette.hairline),
          ),
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'ADD A BLOCK',
                    style: AppType.mono(size: 10, spacing: 2.4),
                  ),
                ),
                const SizedBox(height: 12),
                for (final type in content)
                  _PickerRow(
                    type: type,
                    disabled: unavailable.contains(type),
                    disabledNote: 'Arrives with the media pipeline.',
                  ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'BEHAVIOUR',
                    style: AppType.mono(size: 9, spacing: 2.2),
                  ),
                ),
                for (final type in structure)
                  _PickerRow(
                    type: type,
                    disabled:
                        (type == BlockType.door && !canAddDoor) ||
                        unavailable.contains(type),
                    disabledNote: type == BlockType.door
                        ? 'This page already has its door.'
                        : 'Arrives with the media pipeline.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.type,
    this.disabled = false,
    this.disabledNote,
  });

  final BlockType type;
  final bool disabled;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : () => Navigator.of(context).pop(type),
      hoverColor: Palette.hairline.withValues(alpha: 0.5),
      focusColor: Palette.hairline,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.label,
                    style: AppType.sans(
                      size: 15,
                      color: disabled ? Palette.muted : Palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    disabled ? (disabledNote ?? '') : type.hint,
                    style: AppType.sans(
                      size: 12,
                      color: Palette.muted,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
