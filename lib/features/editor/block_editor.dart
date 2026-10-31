import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Block` is also a name in go_router (its route-blocking type); this file means
// the document block.
import 'package:go_router/go_router.dart' hide Block;

import '../../core/theme.dart';
import '../auth/auth_providers.dart';
import '../media/media.dart';
import '../blocks/block.dart';
import '../blocks/block_rules.dart';
import '../blocks/publish_split.dart';
import '../blocks/save_outcome.dart';
import '../spaces/space.dart';
import '../spaces/space_actions.dart';
import '../spaces/space_feedback.dart';
import '../spaces/spaces_providers.dart';import 'block_field.dart';
import 'block_picker.dart';

/// The canvas (SPEC §11, D28).
///
/// The document is local state, not a provider. It belongs to this screen: it is
/// edited hundreds of times a minute, saved on a timer, and thrown away on
/// navigation. Putting it in a global store would mean every keystroke travelling
/// through app-wide state to reach one text field.
///
/// **D38's layout:** one column, a gutter that is 24 px below 600 px and 32 px
/// above, page padding 16 or 24, measure capped at 680. Nothing sits in the
/// gutter at rest — it appears on the selected block — which is why it can be
/// thin.
class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({super.key, required this.document, required this.handle});

  final SpaceDocument document;
  final String handle;

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

/// D28: 800 ms after the last keystroke — long enough not to send every word,
/// short enough that closing the tab rarely costs more than one.
const Duration _autosaveDelay = Duration(milliseconds: 800);

enum _Status { clean, unsaved, saving, saved, stopped }

class _BlockEditorState extends ConsumerState<BlockEditor> {
  late List<Block> _blocks;
  late int _version;

  /// Captured once, because `ref` cannot be used from `dispose` — and the last
  /// autosave has to happen while the page is being torn down.
  late final SpaceActions _actions;

  final _controllers = <String, TextEditingController>{};
  final _focusNodes = <String, FocusNode>{};

  String? _selectedId;
  String? _failure;
  Conflict? _conflict;
  _Status _status = _Status.clean;

  Timer? _debounce;
  AppLifecycleListener? _lifecycle;

  /// Counts edits, so a save that finishes while the author is still typing does
  /// not mark the newer keystrokes as saved.
  int _edits = 0;
  int _savedEdits = 0;
  bool _saving = false;

  Space get _space => widget.document.space;
  bool get _dirty => _edits != _savedEdits;

  @override
  void initState() {
    super.initState();
    _actions = ref.read(spaceActionsProvider);
    _resetTo(widget.document);

    // SPEC §11: flush on `visibilitychange`. Flutter reports the browser hiding
    // as hidden/paused, which is the same event.
    _lifecycle = AppLifecycleListener(
      onHide: _flush,
      onPause: _flush,
    );
  }

  @override
  void didUpdateWidget(covariant BlockEditor old) {
    super.didUpdateWidget(old);
    // A new document instance means the editor was reloaded — the *Reload* half
    // of the conflict choice.
    if (!identical(old.document, widget.document)) _resetTo(widget.document);
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _debounce?.cancel();
    _flush();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _resetTo(SpaceDocument document) {
    _debounce?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();

    _blocks = List.of(document.blocks);
    _version = document.version;
    _conflict = null;
    _failure = null;
    _savedEdits = _edits;
    _status = _Status.clean;
    _selectedId = null;
  }

  // ---------------------------------------------------------------- editing

  TextEditingController _controllerFor(Block block) {
    return _controllers.putIfAbsent(block.id, () {
      final controller = TextEditingController(text: block.text);
      // Keep the caret at the end of pre-filled text rather than selecting all.
      controller.selection = TextSelection.collapsed(offset: block.text.length);
      return controller;
    });
  }

  /// Selecting a text block happens through focus, not through a tap on the row:
  /// the text field claims the tap for itself, so the row's GestureDetector never
  /// hears about a click that lands in the words.
  FocusNode _focusFor(Block block) {
    return _focusNodes.putIfAbsent(block.id, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus && mounted) setState(() => _selectedId = block.id);
      });
      return node;
    });
  }

  void _onFieldChanged(Block block, String key, Object? value) {
    final index = _blocks.indexWhere((b) => b.id == block.id);
    if (index < 0) return;

    setState(() {
      _blocks[index] = block.withField(key, value);
      _edits++;
      _selectedId = block.id;
      if (_status != _Status.stopped) _status = _Status.unsaved;
    });

    if (_conflict == null) _scheduleSave();
  }

  // ------------------------------------------------------------ structure

  void _move(String id, int delta) {
    final from = _blocks.indexWhere((b) => b.id == id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _blocks.length) return;

    setState(() {
      _blocks.insert(to, _blocks.removeAt(from));
      _edits++;
      if (_status != _Status.stopped) _status = _Status.unsaved;
    });

    if (_conflict == null) _scheduleSave();
  }

  void _delete(String id) {
    setState(() {
      _blocks.removeWhere((b) => b.id == id);
      _edits++;
      if (_selectedId == id) _selectedId = null;
      if (_status != _Status.stopped) _status = _Status.unsaved;
    });

    // The controller and focus node are left in their maps rather than disposed
    // here: disposing them mid-frame, while the field that owns them is still in
    // the tree, is the kind of teardown that throws. They are released with the
    // editor, or on reload.

    if (_conflict == null) _scheduleSave();
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(_autosaveDelay, _save);
  }

  // ----------------------------------------------------------------- saving

  Future<void> _save({int? atVersion}) async {
    _debounce?.cancel();
    if (_saving || !_dirty) return;

    // The same rules the database will apply. Checking here means an invalid
    // document is explained instead of bounced — and no round trip is spent
    // finding out that the server agrees.
    final check = checkDocument(_blocks);
    if (!check.canPublish) {
      final problem = check.problems.first;
      setState(() {
        _status = _Status.stopped;
        _failure = problem.message;
        _selectedId = problem.blockId ?? _selectedId;
      });
      return;
    }

    final editsAtStart = _edits;
    setState(() {
      _saving = true;
      _status = _Status.saving;
    });

    try {
      final outcome = await _actions.saveBlocks(
        _space.id,
        _blocks,
        version: atVersion ?? _version,
      );

      if (!mounted) return;

      switch (outcome) {
        case Saved(:final version):
          setState(() {
            _version = version;
            _savedEdits = editsAtStart;
            _conflict = null;
            _failure = null;
            _status = _dirty ? _Status.unsaved : _Status.saved;
          });
          // Keystrokes that landed mid-save are still unsaved.
          if (_dirty) _scheduleSave();

        case Conflict():
          setState(() {
            _conflict = outcome;
            _status = _Status.stopped;
          });
      }
    } on SpaceFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _status = _Status.stopped;
        _failure = failure.message;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Best-effort save when the page is being left. `dispose` cannot await, and
  /// losing the last edit to a route change is exactly what D28 forbids.
  void _flush() {
    if (!_dirty || _saving || _conflict != null) return;
    final check = checkDocument(_blocks);
    if (!check.canPublish) return;
    unawaited(
      _actions.saveBlocks(_space.id, _blocks, version: _version),
    );
  }

  // -------------------------------------------------------------- structure

  Future<void> _addAfter(String? afterId) async {
    final hasDoor = _blocks.any((b) => b.type == 'door');

    final type = await BlockPicker.show(context, canAddDoor: !hasDoor);
    if (type == null || !mounted) return;

    // An image is the one block that cannot exist without bytes, so it is placed
    // by taking the bytes first and refusing to insert a placeholder that could
    // never be saved.
    final Block block;
    if (type == BlockType.image || type == BlockType.cover) {
      final writer = ref.read(mediaWriterProvider);
      final picked = await writer.pick();
      if (picked == null || !mounted) return;

      try {
        final uploaded = await writer.upload(
          spaceId: _space.id,
          file: picked,
        );
        if (!mounted) return;
        ref.invalidate(ownerMediaPathsProvider(_space.id));
        block = Block(
          id: newBlockId(),
          type: type.name,
          data: type == BlockType.image
              ? imageData(mediaId: uploaded.id)
              : coverData(mediaId: uploaded.id),
        );
      } catch (error) {
        if (!mounted) return;
        showSpaceNotice(
          context,
          'The image could not be uploaded. Nothing was added.',
          bad: true,
        );
        return;
      }
    } else {
      block = Block.blank(type);
    }

    final at = afterId == null
        ? _blocks.length
        : _blocks.indexWhere((b) => b.id == afterId) + 1;

    setState(() {
      _blocks.insert(at.clamp(0, _blocks.length), block);
      _edits++;
      _selectedId = block.id;
      _status = _Status.unsaved;
    });

    _scheduleSave();
  }

  /// *Reload* on a conflict: throw away this version and read the other one.
  void _reload() => ref.invalidate(spaceDocumentProvider(_space.id));

  /// *Keep mine* on a conflict: write using the version that won, which makes
  /// this document the newer one.
  void _keepMine() {
    final conflict = _conflict;
    if (conflict == null) return;
    setState(() {
      _conflict = null;
      _version = conflict.version;
    });
    _save(atVersion: conflict.version);
  }

  @override
  Widget build(BuildContext context) {
    final authorName = ref.watch(profileProvider).value?.displayName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final gutter = narrow ? 24.0 : 32.0;
        final padding = narrow ? 16.0 : 24.0;

        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: padding,
                vertical: padding + 16,
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(space: _space, handle: widget.handle),
                      const SizedBox(height: 28),
                      ..._slots(gutter, authorName),
                      if (_blocks.isEmpty)
                        _EmptyCanvas(
                          gutter: gutter,
                          onAdd: () => _addAfter(null),
                        ),
                      const SizedBox(height: 12),
                      if (_conflict != null)
                        _ConflictBar(
                          onReload: _reload,
                          onKeepMine: _keepMine,
                        ),
                      const SizedBox(height: 24),
                      _Footer(
                        status: _status,
                        failure: _failure,
                        blockCount: _blocks.length,
                        handle: widget.handle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The three types that are typed into — the only ones Backspace can empty.
  static bool _isTyped(Block block) =>
      block.kind == BlockType.text ||
      block.kind == BlockType.heading ||
      block.kind == BlockType.longtext;

  List<Widget> _slots(double gutter, String? authorName) {
    final split = splitAtDoor(_blocks);
    final doorIndex = _blocks.indexWhere((b) => b.type == 'door');
    final mediaPaths =
        ref.watch(ownerMediaPathsProvider(_space.id)).value ??
        const <String, String>{};
    final widgets = <Widget>[];

    for (var i = 0; i < _blocks.length; i++) {
      final block = _blocks[i];
      final selected = block.id == _selectedId;

      widgets.add(
        _Slot(
          key: ValueKey(block.id),
          gutter: gutter,
          selected: selected,
          onSelect: () => setState(() => _selectedId = block.id),
          onAdd: () => _addAfter(block.id),
          onMoveUp: i == 0 ? null : () => _move(block.id, -1),
          onMoveDown: i == _blocks.length - 1
              ? null
              : () => _move(block.id, 1),
          onDelete: () => _delete(block.id),
          child: _EmptyBackspace(
            // D28: an empty block plus Backspace deletes it. The shortcut is
            // only installed while the block is empty — installing it always
            // would eat every backspace the author types.
            enabled:
                _isTyped(block) && _controllerFor(block).text.isEmpty,
            onDelete: () => _delete(block.id),
            child: BlockField(
              block: block,
              controller: _controllerFor(block),
              focusNode: _focusFor(block),
              autofocus: selected && block.text.isEmpty,
            onFieldChanged: (key, value) => _onFieldChanged(block, key, value),
            doorAbove: block.kind == BlockType.door ? split.publicCount : null,
            doorBelow: block.kind == BlockType.door ? split.gatedCount : null,
            counterActive:
                block.kind == BlockType.readers ||
                block.kind == BlockType.likes
                ? doorIndex >= 0 && i > doorIndex
                : false,
            authorName: authorName,
            authorHandle: widget.handle,
              mediaPath: switch (block.mediaId) {
                final id? => mediaPaths[id],
                _ => null,
              },
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}

// ---------------------------------------------------------------- the pieces

/// The page's identity above the canvas. Title and address are metadata: they are
/// renamed from the profile card, never here (D7, SPEC §11).
class _Header extends StatelessWidget {
  const _Header({required this.space, required this.handle});

  final Space space;
  final String handle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          space.state.label,
          style: AppType.mono(
            size: 9,
            spacing: 2.2,
            color: space.state == SpaceState.published
                ? Palette.ink
                : Palette.muted,
          ),
        ),
        const SizedBox(height: 10),
        Text(space.title, style: AppType.serif(size: 34, height: 1.2)),
        const SizedBox(height: 6),
        Text('$handle/${space.addressSlug}', style: AppType.mono(size: 11)),
      ],
    );
  }
}

/// One block plus its gutter. The gutter is empty until the block is selected
/// (D38), so at rest the text runs the full measure.
class _Slot extends StatefulWidget {
  const _Slot({
    super.key,
    required this.gutter,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    required this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    required this.child,
  });

  final double gutter;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onAdd;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final Widget child;

  @override
  State<_Slot> createState() => _SlotState();
}

class _SlotState extends State<_Slot> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final showActions = widget.selected || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onSelect,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: widget.gutter,
                child: showActions
                    ? Column(
                        children: [
                          _GutterAdd(onPressed: widget.onAdd),
                          _BlockMenu(
                            onMoveUp: widget.onMoveUp,
                            onMoveDown: widget.onMoveDown,
                            onDelete: widget.onDelete,
                          ),
                        ],
                      )
                    : null,
              ),
              Expanded(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BlockAction { up, down, delete }

/// The block's own menu, in the gutter. D28 asks for a drag handle; a menu does
/// the same three things with a keyboard and a thumb, at every width, and is
/// recorded as the remaining gap in instead of being quietly absent.
class _BlockMenu extends StatelessWidget {
  const _BlockMenu({
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BlockAction>(
      tooltip: 'This block',
      offset: const Offset(0, 20),
      color: Palette.canvas,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: Palette.hairline),
      ),
      onSelected: (action) => switch (action) {
        _BlockAction.up => onMoveUp?.call(),
        _BlockAction.down => onMoveDown?.call(),
        _BlockAction.delete => onDelete(),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _BlockAction.up,
          enabled: onMoveUp != null,
          height: 38,
          child: Text('Move up', style: AppType.sans(size: 14)),
        ),
        PopupMenuItem(
          value: _BlockAction.down,
          enabled: onMoveDown != null,
          height: 38,
          child: Text('Move down', style: AppType.sans(size: 14)),
        ),
        PopupMenuItem(
          value: _BlockAction.delete,
          height: 38,
          child: Text(
            'Delete block',
            style: AppType.sans(size: 14, color: Palette.accent),
          ),
        ),
      ],
      child: SizedBox(
        width: 24,
        height: 20,
        child: Center(
          child: Text(
            '⋯',
            style: AppType.mono(size: 13, color: Palette.muted),
          ),
        ),
      ),
    );
  }
}

class _GutterAdd extends StatelessWidget {
  const _GutterAdd({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Tooltip(
        message: 'Add a block below',
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 24,
            height: 30,
            child: Center(
              child: Text(
                '+',
                style: AppType.mono(size: 14, color: Palette.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// D7: the canvas opens blank — no title field, no heading — so an empty
/// document needs exactly one way in.
class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({required this.gutter, required this.onAdd});

  final double gutter;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: gutter,
          child: _GutterAdd(onPressed: onAdd),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              'An empty page. Add a block to begin.',
              style: AppType.sans(size: 15, color: Palette.muted, height: 1.7),
            ),
          ),
        ),
      ],
    );
  }
}

/// D28: never a silent loss. Two ways out, both spelled out.
class _ConflictBar extends StatelessWidget {
  const _ConflictBar({required this.onReload, required this.onKeepMine});

  final VoidCallback onReload;
  final VoidCallback onKeepMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border.all(color: Palette.accent)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This Space was changed somewhere else.',
            style: AppType.sans(size: 13, color: Palette.accent, height: 1.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Saving now would overwrite that version. Load it, or keep what is '
            'on this screen.',
            style: AppType.sans(size: 13, color: Palette.muted, height: 1.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 2,
            children: [
              TextButton(
                onPressed: onReload,
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: Text('Load the other version', style: AppType.sans(size: 13)),
              ),
              TextButton(
                onPressed: onKeepMine,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  foregroundColor: Palette.accent,
                ),
                child: Text(
                  'Keep mine',
                  style: AppType.sans(size: 13, color: Palette.accent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the editor is doing with the document, said plainly and quietly.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.status,
    required this.failure,
    required this.blockCount,
    required this.handle,
  });

  final _Status status;
  final String? failure;
  final int blockCount;
  final String handle;

  @override
  Widget build(BuildContext context) {
    final (label, bad) = switch (status) {
      _Status.clean => ('', false),
      _Status.unsaved => ('UNSAVED', false),
      _Status.saving => ('SAVING…', false),
      _Status.saved => ('SAVED', false),
      _Status.stopped => ('NOT SAVED', true),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null) ...[
          Text(
            failure!,
            style: AppType.sans(size: 13, color: Palette.accent, height: 1.5),
          ),
          const SizedBox(height: 8),
        ],
        const Divider(height: 1, color: Palette.hairline),
        const SizedBox(height: 10),
        Row(
          children: [
            if (label.isNotEmpty)
              Text(
                label,
                style: AppType.mono(
                  size: 9,
                  spacing: 2.2,
                  color: bad ? Palette.accent : Palette.muted,
                ),
              ),
            const Spacer(),
            Text(
              blockCount == 1 ? '1 BLOCK' : '$blockCount BLOCKS',
              style: AppType.mono(size: 9, spacing: 2.2),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: () => context.go('/$handle'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Text('← $handle', style: AppType.mono(size: 11)),
        ),
      ],
    );
  }
}

/// The intent Backspace maps to while a block is empty.
class _DeleteBlockIntent extends Intent {
  const _DeleteBlockIntent();
}

/// D28: an empty text block plus Backspace deletes the block.
///
/// The shortcut is installed **only while the block is empty**. Installing it
/// always would make Backspace delete a block instead of a character, which is
/// the obvious way to get this wrong; the editor rebuilds on every keystroke, so
/// the wrapper appears exactly when the field goes empty.
class _EmptyBackspace extends StatelessWidget {
  const _EmptyBackspace({
    required this.enabled,
    required this.onDelete,
    required this.child,
  });

  final bool enabled;
  final VoidCallback onDelete;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteBlockIntent(),
      },
      child: Actions(
        actions: {
          _DeleteBlockIntent: CallbackAction<_DeleteBlockIntent>(
            onInvoke: (_) {
              onDelete();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
