import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/editor/block_editor.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';

import 'fakes/fake_space_actions.dart';

/// The canvas (SPEC §11, D28): autosave, the gutter, and the conflict choice.
///
/// Autosave is measured with the test clock rather than waited for — `pump` with
/// a duration advances the fake timer, so "800 ms" is asserted, not assumed.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const space = Space(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    visibility: 'private',
    blocksVersion: 4,
  );

  Future<FakeSpaceActions> pump(
    WidgetTester tester, {
    List<Block> blocks = const [
      Block(id: 'b1', type: 'text', data: {'text': 'First.'}),
    ],
    Size size = const Size(1000, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final actions = FakeSpaceActions();
    final document = SpaceDocument(space: space, blocks: blocks);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceActionsProvider.overrideWith((ref) => actions),
          spaceDocumentProvider.overrideWith((ref, id) async => document),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: BlockEditor(document: document, handle: '@ether'),
        ),
      ),
    );
    await tester.pump();
    return actions;
  }

  group('autosave', () {
    testWidgets('waits 800 ms after the last keystroke, no longer', (
      tester,
    ) async {
      final actions = await pump(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(actions.savedVersions, isEmpty, reason: 'still within the delay');

      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.savedVersions, ['s1@4/1']);
    });

    testWidgets('one save covers a burst of typing', (tester) async {
      final actions = await pump(tester);

      for (final text in ['a', 'ab', 'abc', 'abcd']) {
        await tester.enterText(find.byType(TextField), text);
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.pump(const Duration(milliseconds: 900));

      expect(
        actions.savedVersions,
        hasLength(1),
        reason: 'four keystrokes, one request',
      );
    });

    testWidgets('says SAVED after a save and UNSAVED while typing', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(find.text('UNSAVED'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();

      expect(find.text('SAVED'), findsOneWidget);
    });

    testWidgets('saves against the version the document was read at', (
      tester,
    ) async {
      // The optimistic lock is the whole defence against a silent overwrite, so
      // the version in the request matters more than the payload.
      final actions = await pump(tester);

      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(actions.savedVersions.single, startsWith('s1@4/'));
    });

    testWidgets('a document the database would refuse is not sent', (
      tester,
    ) async {
      // An image with no alt text is refused by `validate_blocks`. Sending it
      // would spend a round trip to be told what the client already knows.
      final actions = await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'First.'}),
          Block(id: 'b2', type: 'image', data: {'media_id': 'm1', 'alt': ''}),
        ],
      );

      await tester.enterText(find.byType(TextField).first, 'Changed');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(actions.savedVersions, isEmpty);
      expect(find.text('NOT SAVED'), findsOneWidget);
      expect(
        find.textContaining('An image needs alt text'),
        findsOneWidget,
      );
    });
  });

  group('a conflict', () {
    Future<FakeSpaceActions> conflict(WidgetTester tester) async {
      final actions = await pump(tester);
      actions
        ..savesConflict = true
        ..nextVersion = 9;

      await tester.enterText(find.byType(TextField), 'Mine');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();

      return actions;
    }

    testWidgets('is offered as two choices, never resolved silently', (
      tester,
    ) async {
      await conflict(tester);

      expect(
        find.text('This Space was changed somewhere else.'),
        findsOneWidget,
      );
      expect(find.text('Load the other version'), findsOneWidget);
      expect(find.text('Keep mine'), findsOneWidget);
      expect(find.text('NOT SAVED'), findsOneWidget);
    });

    testWidgets('Keep mine writes at the version that won', (tester) async {
      final actions = await conflict(tester);

      actions.savesConflict = false;
      await tester.tap(find.text('Keep mine'));
      await tester.pump();
      await tester.pump();

      expect(
        actions.savedVersions.last,
        startsWith('s1@9/'),
        reason: 'the other version is overwritten deliberately',
      );
      expect(find.text('This Space was changed somewhere else.'), findsNothing);
    });
  });

  group('the gutter (D38)', () {
    testWidgets('an empty canvas still offers a way in', (tester) async {
      await pump(tester, blocks: const []);

      expect(find.text('An empty page. Add a block to begin.'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
    });

    testWidgets('adding opens the picker, and the block lands below', (
      tester,
    ) async {
      await pump(tester, blocks: const []);

      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('ADD A BLOCK'), findsOneWidget);

      await tester.tap(find.text('Heading'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('1 BLOCK'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the picker refuses a second door instead of hiding it', (
      tester,
    ) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'Above.'}),
          Block(id: 'b2', type: 'door'),
        ],
      );

      // Select the first block, then open the picker from its gutter.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.tap(find.text('+').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('This page already has its door.'), findsOneWidget);
    });

    testWidgets('image and cover are offered, because the pipeline exists now', (
      tester,
    ) async {
      await pump(tester, blocks: const []);

      await tester.tap(find.text('+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Image'), findsOneWidget);
      expect(find.text('Cover'), findsOneWidget);
      // Nothing says "not built yet" any more.
      expect(find.text('Arrives with the media pipeline.'), findsNothing);
    });

  });

  group('a door (D22)', () {
    testWidgets('draws itself as a threshold and counts what it withholds', (
      tester,
    ) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'Above.'}),
          Block(id: 'b2', type: 'text', data: {'text': 'Also above.'}),
          Block(id: 'b3', type: 'door', data: {'note': ''}),
          Block(id: 'b4', type: 'text', data: {'text': 'Below.'}),
        ],
      );

      expect(find.text('DOOR'), findsOneWidget);
      expect(
        find.text('Publishing shows 2 blocks and withholds 2, starting here.'),
        findsOneWidget,
      );
    });

    testWidgets('takes a note, which is gated with the door itself', (
      tester,
    ) async {
      final actions = await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'Above.'}),
          Block(id: 'b2', type: 'door', data: {'note': ''}),
        ],
      );

      await tester.enterText(
        find.byType(TextField).last,
        'Only if you mean it.',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(actions.savedVersions, isNotEmpty);
    });
  });

  group('a counter without a door (SPEC section 9)', () {
    testWidgets('says it will stay at zero', (tester) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'readers'),
          Block(id: 'b2', type: 'text', data: {'text': 'Text.'}),
        ],
      );

      expect(find.textContaining('this will stay at zero'), findsOneWidget);
    });

    testWidgets('a counter below the door says what it counts', (tester) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'door'),
          Block(id: 'b2', type: 'readers'),
        ],
      );

      expect(find.text('How many people have entered.'), findsOneWidget);
      expect(find.textContaining('stay at zero'), findsNothing);
    });
  });

  group('the block menu (D28, D38)', () {
    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.text('\u22ef').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('moves a block up', (tester) async {
      final actions = await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'First.'}),
          Block(id: 'b2', type: 'text', data: {'text': 'Second.'}),
        ],
      );

      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await openMenu(tester);
      await tester.tap(find.text('Move up'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(actions.savedVersions, isNotEmpty);
      final first = tester.widgetList<TextField>(find.byType(TextField)).first;
      expect(first.controller!.text, 'Second.');
    });

    testWidgets('deletes a block', (tester) async {
      final actions = await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'First.'}),
          Block(id: 'b2', type: 'text', data: {'text': 'Second.'}),
        ],
      );

      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await openMenu(tester);
      await tester.tap(find.text('Delete block'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('1 BLOCK'), findsOneWidget);
      expect(find.text('Second.'), findsNothing);
      expect(actions.savedVersions, isNotEmpty);
    });
  });

  group('Backspace on an empty block (D28)', () {
    testWidgets('deletes it, and only when it is empty', (tester) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'text', data: {'text': 'Keep me.'}),
          Block(id: 'b2', type: 'text', data: {'text': ''}),
        ],
      );

      // With text in it, Backspace is a character — the block stays.
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(find.text('2 BLOCKS'), findsOneWidget);

      // Empty: the same key removes the block.
      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('1 BLOCK'), findsOneWidget);
    });
  });

  group('the phone layout (D37, D38)', () {
    testWidgets('a document holds up at 360 px', (tester) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'heading', data: {'text': 'The Threshold', 'level': 1}),
          Block(
            id: 'b2',
            type: 'longtext',
            data: {'text': 'A passage long enough to wrap several times on a narrow screen.'},
          ),
          Block(id: 'b3', type: 'door', data: {'note': ''}),
          Block(id: 'b4', type: 'readers'),
        ],
        size: const Size(360, 900),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('4 BLOCKS'), findsOneWidget);
    });
  });

  group('blocks this client does not understand', () {
    testWidgets('are kept and shown, not dropped', (tester) async {
      await pump(
        tester,
        blocks: const [
          Block(id: 'b1', type: 'gallery', data: {'items': 3}),
        ],
      );

      expect(find.text('UNKNOWN BLOCK'), findsOneWidget);
      expect(find.textContaining('kept exactly as it is'), findsOneWidget);
      expect(find.text('1 BLOCK'), findsOneWidget);
    });
  });
}
