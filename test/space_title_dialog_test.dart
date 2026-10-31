import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/space_title_dialog.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';

import 'fakes/fake_space_actions.dart';

/// The dialog is where a title becomes an address, and where a collision has to
/// become something a person can act on (D18, D19).
///
/// Everything here runs against the shared fake, so these tests prove what the
/// dialog decides — which call, with which title, and what it says after a
/// failure. They prove nothing about the database; the 42-assertion suite does
/// that.

/// Opens the dialog and keeps the value it closes with, which arrives after the
/// test has finished interacting.
class _Harness {
  _Harness(this.actions, {this.space});

  final FakeSpaceActions actions;
  final Space? space;

  Space? result;
  bool closed = false;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [spaceActionsProvider.overrideWith((ref) => actions)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    result = await SpaceTitleDialog.show(
                      context,
                      handle: '@ether',
                      space: space,
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);
  }

  /// Not `pumpAndSettle`: the text field's cursor blinks forever and settling
  /// would time out on it.
  static Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }
}

const _trashed = Space(
  id: 'gone',
  title: 'My Journey',
  slug: 'my-journey',
  visibility: 'private',
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('creating', () {
    testWidgets('asks for a title and shows the address it will make', (
      tester,
    ) async {
      final harness = _Harness(FakeSpaceActions());
      await harness.open(tester);

      expect(find.text('NEW SPACE'), findsOneWidget);
      expect(find.text('What is it called?'), findsOneWidget);

      await harness.type(tester, 'My Journey');

      // D18, made visible: the author never types this, they only see it.
      expect(find.text('@ether/my-journey'), findsOneWidget);
    });

    testWidgets('sends the trimmed title and hands back the new Space', (
      tester,
    ) async {
      final harness = _Harness(FakeSpaceActions());
      await harness.open(tester);

      await harness.type(tester, '  My Journey  ');
      await harness.tap(tester, 'Create');

      expect(harness.actions.created, ['My Journey']);
      expect(harness.result?.slug, 'my-journey');
      expect(harness.closed, isTrue, reason: 'the dialog closed on success');
    });

    testWidgets('a title too short never reaches the database', (tester) async {
      final harness = _Harness(FakeSpaceActions());
      await harness.open(tester);

      await harness.type(tester, 'a');
      await harness.tap(tester, 'Create');

      expect(harness.actions.created, isEmpty);
      expect(find.text('A title, at least two characters.'), findsOneWidget);
    });

    testWidgets('a title too long never reaches the database', (tester) async {
      final harness = _Harness(FakeSpaceActions());
      await harness.open(tester);

      await harness.type(tester, 'a' * 81);
      await harness.tap(tester, 'Create');

      expect(harness.actions.created, isEmpty);
      expect(find.text('Eighty characters is the limit.'), findsOneWidget);
    });
  });

  group('a title already in use', () {
    testWidgets('says so plainly when the holder is a live Space', (
      tester,
    ) async {
      final actions = FakeSpaceActions()..slugTaken = true;
      final harness = _Harness(actions);
      await harness.open(tester);

      await harness.type(tester, 'My Journey');
      await harness.tap(tester, 'Create');

      expect(
        find.text('One of your Spaces already uses that title.'),
        findsOneWidget,
      );
      // Nothing to offer: the holder is visible on the profile already.
      expect(find.text('Restore it'), findsNothing);
    });

    testWidgets('offers a way out when the holder is in the Trash', (
      tester,
    ) async {
      // D19's build-time polish: a bare "taken" here would be true and useless.
      final actions = FakeSpaceActions(trashedHolder: _trashed)..slugTaken = true;
      final harness = _Harness(actions);
      await harness.open(tester);

      await harness.type(tester, 'My Journey');
      await harness.tap(tester, 'Create');

      expect(
        find.text('A Space with that title is in the Trash.'),
        findsOneWidget,
      );
      expect(find.text('Restore it'), findsOneWidget);
      expect(find.text('Delete it permanently'), findsOneWidget);
    });

    testWidgets('restoring brings the trashed Space back, and stops there', (
      tester,
    ) async {
      final actions = FakeSpaceActions(trashedHolder: _trashed)..slugTaken = true;
      final harness = _Harness(actions);
      await harness.open(tester);

      await harness.type(tester, 'My Journey');
      await harness.tap(tester, 'Create');
      await harness.tap(tester, 'Restore it');

      expect(actions.restored, ['gone']);
      // The author wanted the Space, not a duplicate of it.
      expect(actions.created, ['My Journey'], reason: 'only the first attempt');
      expect(harness.closed, isTrue);
    });

    testWidgets('deleting permanently frees the title and then creates', (
      tester,
    ) async {
      final actions = FakeSpaceActions(trashedHolder: _trashed)..slugTaken = true;
      final harness = _Harness(actions);
      await harness.open(tester);

      await harness.type(tester, 'My Journey');
      await harness.tap(tester, 'Create');

      actions.slugTaken = false;
      await harness.tap(tester, 'Delete it permanently');

      expect(actions.deleted, ['gone']);
      expect(
        actions.created,
        ['My Journey', 'My Journey'],
        reason: 'the first attempt, then the retry after freeing the title',
      );
      expect(harness.closed, isTrue);
    });
  });

  group('at phone width', () {
    testWidgets('the dialog fits 360 px without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final harness = _Harness(FakeSpaceActions());
      await harness.open(tester);
      await harness.type(tester, 'My Journey');

      expect(find.text('What is it called?'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
      // A RenderFlex overflow throws during layout and fails the test here.
      expect(tester.takeException(), isNull);
    });

    testWidgets('the trashed-title escape hatch fits too', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final actions = FakeSpaceActions(trashedHolder: _trashed)..slugTaken = true;
      final harness = _Harness(actions);
      await harness.open(tester);

      await harness.type(tester, 'My Journey');
      await harness.tap(tester, 'Create');

      expect(find.text('Restore it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('renaming', () {
    const existing = Space(
      id: 's1',
      title: 'My Journey',
      slug: 'my-journey',
      visibility: 'private',
    );

    testWidgets('starts with the current title selected', (tester) async {
      final harness = _Harness(FakeSpaceActions(), space: existing);
      await harness.open(tester);

      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('What should it be called?'), findsOneWidget);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'My Journey');
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 10),
        reason: 'renaming usually replaces the whole title',
      );
    });

    testWidgets('sends the Space id with the new title', (tester) async {
      final harness = _Harness(FakeSpaceActions(), space: existing);
      await harness.open(tester);

      await harness.type(tester, 'A Better Title');
      await harness.tap(tester, 'Rename');

      expect(harness.actions.renamed, ['s1:A Better Title']);
    });

    testWidgets('renaming to the same title is not an edit', (tester) async {
      final harness = _Harness(FakeSpaceActions(), space: existing);
      await harness.open(tester);

      await harness.tap(tester, 'Rename');

      expect(harness.actions.renamed, isEmpty);
      expect(harness.closed, isTrue);
    });
  });
}
