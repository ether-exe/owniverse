import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../media/media_image.dart';
import '../blocks/block.dart';

/// One block in the canvas.
///
/// Three of the nine types are typed into; the rest are placed and configured.
/// A placed block renders as an object — a door you can label, a table of
/// contents of what it hides — rather than a settings form dropped into the
/// middle of a page.
class BlockField extends StatelessWidget {
  const BlockField({
    super.key,
    required this.block,
    required this.controller,
    required this.onFieldChanged,
    this.focusNode,
    this.autofocus = false,
    this.doorAbove,
    this.doorBelow,
    this.mediaPath,
    this.counterActive = false,
    this.authorName,
    this.authorHandle,
  });

  final Block block;
  final TextEditingController controller;

  /// Which key of `data` this field edits — `text` for the typed blocks, `note`
  /// for a door.
  final void Function(String key, Object? value) onFieldChanged;

  /// Focus is how the editor learns a block is selected: a text field wins the
  /// tap for itself, so the row's own handler never sees a click in the words.
  final FocusNode? focusNode;

  final bool autofocus;

  /// For a door: how much it publishes and how much it withholds.
  final int? doorAbove;
  final int? doorBelow;

  /// Where this block's image lives, if it has one. `null` while a cover or
  /// image has no bytes yet.
  final String? mediaPath;

  /// For a counter: whether a door sits above it (SPEC §9).
  final bool counterActive;

  final String? authorName;
  final String? authorHandle;

  static const Map<BlockType, String> _hints = {
    BlockType.text: 'Write something.',
    BlockType.heading: 'Heading',
    BlockType.longtext: 'A longer passage.',
    BlockType.door: 'A line for whoever is about to enter.',
  };

  @override
  Widget build(BuildContext context) {
    if (!block.isRenderable) return const _UnknownBlock();

    return switch (block.kind) {
      BlockType.text || BlockType.heading || BlockType.longtext => _typed(),
      BlockType.door => _door(),
      BlockType.readers => _counter('READERS', 'How many people have entered.'),
      BlockType.likes => _counter('LIKES', 'A count, and a way to add to it.'),
      BlockType.profile => _profile(),
      BlockType.cover => _media(
        'COVER',
        captionKey: 'caption',
        captionHint: 'A caption, if it needs one.',
      ),
      BlockType.image => _media(
        'IMAGE',
        captionKey: 'alt',
        captionHint: 'Describe the image. It cannot be published without this.',
        altField: true,
      ),
      null => const _UnknownBlock(),
    };
  }

  Widget _typed() {
    final kind = block.kind!;
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: _style(kind),
      cursorColor: Palette.accent,
      onChanged: (value) => onFieldChanged('text', value),
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: _hints[kind],
        hintStyle: _style(kind).copyWith(color: Palette.hairline),
        contentPadding: EdgeInsets.zero,
      ),
    );

    // Long text is set to a smaller measure than the page, so a passage reads
    // like a passage rather than a paragraph stretched across the column (§8).
    if (kind == BlockType.longtext) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: field,
      );
    }
    return field;
  }

  /// The threshold. It draws itself as the line it is, says how much it
  /// withholds, and takes a note that only people who enter will read — the
  /// door block is gated, so an anonymous payload never contains this.
  Widget _door() {
    final above = doorAbove;
    final below = doorBelow;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Divider(height: 1, color: Palette.hairline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'DOOR',
                  style: AppType.mono(size: 9, spacing: 2.2, color: Palette.accent),
                ),
              ),
              const Expanded(child: Divider(height: 1, color: Palette.hairline)),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            focusNode: focusNode,
            maxLines: null,
            style: AppType.sans(size: 13, color: Palette.muted, height: 1.6),
            cursorColor: Palette.accent,
            onChanged: (value) => onFieldChanged('note', value),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: _hints[BlockType.door],
              hintStyle: AppType.sans(
                size: 13,
                color: Palette.hairline,
                height: 1.6,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (above != null && below != null) ...[
            const SizedBox(height: 8),
            Text(
              'Publishing shows $above ${above == 1 ? 'block' : 'blocks'} and '
              'withholds $below, starting here.',
              style: AppType.mono(size: 9, spacing: 1.2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _counter(String label, String sentence) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: counterActive ? Palette.hairline : Palette.accent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppType.mono(size: 9, spacing: 2.2)),
          const SizedBox(height: 4),
          Text(
            counterActive
                ? sentence
                : 'Needs a door above it. Without one nobody is identified, so '
                      'this will stay at zero.',
            style: AppType.sans(
              size: 13,
              color: counterActive ? Palette.muted : Palette.accent,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _profile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Palette.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PROFILE CARD', style: AppType.mono(size: 9, spacing: 2.2)),
          const SizedBox(height: 6),
          Text(
            authorName?.isNotEmpty == true ? authorName! : '@author',
            style: AppType.serif(size: 20),
          ),
          if (authorHandle != null) ...[
            const SizedBox(height: 2),
            Text(authorHandle!, style: AppType.mono(size: 10)),
          ],
        ],
      ),
    );
  }

  /// A placed image or cover: the picture, then the line of text that goes with
  /// it. `alt` is a gate, not a caption — the database refuses an image without
  /// one — so it says so where it is written.
  Widget _media(
    String label, {
    required String captionKey,
    required String captionHint,
    bool altField = false,
  }) {
    final missingAlt = altField && block.alt.trim().isEmpty;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: missingAlt ? Palette.accent : Palette.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mediaPath != null)
            MediaImage(path: mediaPath!, maxHeight: altField ? 380 : 260)
          else
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                'No image yet.',
                style: AppType.sans(size: 13, color: Palette.muted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Text(
              label,
              style: AppType.mono(
                size: 9,
                spacing: 2.2,
                color: missingAlt ? Palette.accent : Palette.muted,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: TextField(
              controller: controller,
              maxLines: null,
              style: AppType.sans(
                size: 13,
                color: missingAlt ? Palette.accent : Palette.muted,
                height: 1.6,
              ),
              cursorColor: Palette.accent,
              onChanged: (value) => onFieldChanged(captionKey, value),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: captionHint,
                hintStyle: AppType.sans(
                  size: 13,
                  color: Palette.hairline,
                  height: 1.6,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _style(BlockType kind) => switch (kind) {
    BlockType.heading => AppType.serif(size: 26, height: 1.25),
    BlockType.longtext => AppType.sans(size: 14, height: 1.8),
    _ => AppType.sans(size: 15, height: 1.7),
  };
}

/// A block this client does not understand. Kept, shown, never silently
/// dropped — the alternative is deleting an author's work to avoid a blank space.
class _UnknownBlock extends StatelessWidget {
  const _UnknownBlock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Palette.hairline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UNKNOWN BLOCK', style: AppType.mono(size: 9, spacing: 2.2)),
          const SizedBox(height: 4),
          Text(
            'This block was made by a newer version of Owniverse. It is kept '
            'exactly as it is and will reappear when this page catches up.',
            style: AppType.sans(size: 13, color: Palette.muted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
