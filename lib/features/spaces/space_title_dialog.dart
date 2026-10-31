import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'slug.dart';
import 'space.dart';
import 'space_actions.dart';
import 'spaces_providers.dart';

/// One dialog for naming and renaming, because they ask the same question
/// (D15: *New Space (Title dialog)*, *Rename*). What differs is the heading, the
/// verb, and what happens to the answer.
///
/// The author types a title. The address is shown underneath, live, because it
/// is the one consequence of the title they cannot see otherwise (D18) — and
/// because a collision is the only way this dialog can fail.
class SpaceTitleDialog extends ConsumerStatefulWidget {
  const SpaceTitleDialog({super.key, required this.handle, this.space});

  /// `@handle`, for the address preview. Always the signed-in user's own, and
  /// already carrying its `@`.
  final String handle;

  /// Null creates; a Space renames that Space.
  final Space? space;

  /// Returns the Space that was created or renamed, or null if nothing happened.
  static Future<Space?> show(
    BuildContext context, {
    required String handle,
    Space? space,
  }) {
    return showDialog<Space>(
      context: context,
      barrierColor: const Color(0xB3000000),
      builder: (_) => SpaceTitleDialog(handle: handle, space: space),
    );
  }

  @override
  ConsumerState<SpaceTitleDialog> createState() => _SpaceTitleDialogState();
}

class _SpaceTitleDialogState extends ConsumerState<SpaceTitleDialog> {
  static const int _minTitle = 2;
  static const int _maxTitle = 80;

  final _title = TextEditingController();

  bool _busy = false;
  String? _error;

  /// Set when the title collides with a Space in the Trash: D19's polish is to
  /// offer a way out instead of a bare "taken".
  Space? _holder;

  bool get _isCreate => widget.space == null;

  @override
  void initState() {
    super.initState();
    final existing = widget.space?.title;
    if (existing != null) {
      // Renaming usually means replacing the whole thing; do not make them
      // delete a word first.
      _title.text = existing;
      _title.selection = TextSelection(
        baseOffset: 0,
        extentOffset: existing.length,
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _invalidate() {
    ref.invalidate(ownerSpacesProvider);
    ref.invalidate(trashedSpacesProvider);
  }

  Future<void> _submit() async {
    if (_busy) return;

    final title = _title.text.trim();

    if (title.length < _minTitle) {
      setState(() => _error = 'A title, at least two characters.');
      return;
    }
    if (title.length > _maxTitle) {
      setState(() => _error = 'Eighty characters is the limit.');
      return;
    }
    // Renaming to the name it already has is not an edit.
    if (!_isCreate && title == widget.space!.title) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final actions = ref.read(spaceActionsProvider);

    try {
      final space = _isCreate
          ? await actions.create(title: title)
          : await actions.rename(widget.space!.id, title: title);

      _invalidate();
      if (mounted) Navigator.of(context).pop(space);
    } on SpaceFailure catch (failure) {
      if (!mounted) return;

      if (failure.code == 'slug_taken' && _isCreate) {
        // Ask whether the holder is in the Trash before saying no. A bare
        // "taken" would be true and useless (D19).
        final holder = await actions.trashedBySlug(slugify(title));
        if (!mounted) return;
        setState(() {
          _holder = holder;
          _error = holder == null ? failure.message : null;
          _busy = false;
        });
        return;
      }

      setState(() {
        _error = failure.message;
        _busy = false;
      });
    }
  }

  /// The author wanted that title back, not a new Space. Restoring brings back
  /// the Space that holds it, which is what they were asking for.
  Future<void> _restoreHolder() async {
    final holder = _holder;
    if (holder == null || _busy) return;

    setState(() => _busy = true);

    try {
      await ref.read(spaceActionsProvider).restore(holder.id);
      _invalidate();
      if (mounted) Navigator.of(context).pop();
    } on SpaceFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Free the title and use it, in that order, because that is what "delete it
  /// permanently" means in the middle of creating something with the same name.
  /// If the second half fails, the Space is gone and no new one exists — the
  /// message says so rather than pretending both halves are one thing.
  Future<void> _deleteHolderAndCreate() async {
    final holder = _holder;
    if (holder == null || _busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final actions = ref.read(spaceActionsProvider);

    try {
      await actions.deleteForever(holder.id);
      final space = await actions.create(title: _title.text.trim());
      _invalidate();
      if (mounted) Navigator.of(context).pop(space);
    } on SpaceFailure catch (failure) {
      if (!mounted) return;
      _invalidate();
      setState(() {
        _holder = null;
        _error = failure.code == 'slug_taken'
            ? 'The title was freed but the Space was not made. Try again.'
            : failure.message;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = slugify(_title.text);

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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isCreate ? 'NEW SPACE' : 'RENAME',
                  style: AppType.mono(size: 10, spacing: 2.4),
                ),
                const SizedBox(height: 16),
                Text(
                  _isCreate ? 'What is it called?' : 'What should it be called?',
                  style: AppType.serif(size: 26),
                ),
                const SizedBox(height: 10),
                Text(
                  _isCreate
                      ? 'The address is made from the title. Renaming later moves '
                            'the address only when you publish again.'
                      : 'If this Space is published, its address keeps answering '
                            'until you publish again.',
                  style: AppType.sans(
                    size: 13,
                    color: Palette.muted,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _title,
                  autofocus: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppType.sans(size: 16),
                  cursorColor: Palette.accent,
                  onChanged: (_) => setState(() {
                    _error = null;
                    _holder = null;
                  }),
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: 'My Journey'),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.handle}/$slug',
                  style: AppType.mono(size: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_holder != null) ...[
                  const SizedBox(height: 18),
                  _TrashedCollision(
                    busy: _busy,
                    onRestore: _restoreHolder,
                    onDelete: _deleteHolderAndCreate,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    _error!,
                    style: AppType.mono(size: 11, color: Palette.accent),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: AppType.sans(size: 14, color: Palette.muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _busy ? null : _submit,
                      style: TextButton.styleFrom(
                        foregroundColor: Palette.accent,
                      ),
                      child: Text(
                        _busy
                            ? (_isCreate ? 'Creating…' : 'Renaming…')
                            : (_isCreate ? 'Create' : 'Rename'),
                        style: AppType.sans(size: 14, color: Palette.accent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// D19: the title is not lost, it is in the Trash. Two ways out, both spelled
/// out, neither of them a shrug.
class _TrashedCollision extends StatelessWidget {
  const _TrashedCollision({
    required this.busy,
    required this.onRestore,
    required this.onDelete,
  });

  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A Space with that title is in the Trash.',
          style: AppType.sans(size: 13, color: Palette.ink, height: 1.5),
        ),
        const SizedBox(height: 4),
        Text(
          'Restore it, or delete it permanently to free the title.',
          style: AppType.sans(size: 13, color: Palette.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            TextButton(
              onPressed: busy ? null : onRestore,
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text('Restore it', style: AppType.sans(size: 13)),
            ),
            TextButton(
              onPressed: busy ? null : onDelete,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                foregroundColor: Palette.accent,
              ),
              child: Text(
                'Delete it permanently',
                style: AppType.sans(size: 13, color: Palette.accent),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
