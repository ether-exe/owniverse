import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/auth/auth_providers.dart';
import 'package:owniverse/features/auth/profile.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';
import 'package:owniverse/features/trash/trash_page.dart';

import 'fakes/fake_space_actions.dart';

/// D3 and D19: a trashed Space keeps its title for thirty days, comes back if
/// restored, and frees the title only when it is really gone.
///
/// These prove what the page does with what the database said. They do not prove
/// the purge job runs, or that RLS stops a stranger — `db-test.mjs` does that.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const me = Profile(id: 'u1', username: 'ether', name: 'Ether');

  Space trashedIn(int days) => Space(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    visibility: 'private',
    deletedAt: DateTime.now(),
    purgeAfter: DateTime.now().add(Duration(days: days)),
  );

  var trashBuilds = 0;

  Future<FakeSpaceActions> pump(
    WidgetTester tester, {
    List<Space> spaces = const [],
    Size size = const Size(1000, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final actions = FakeSpaceActions();
    trashBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => me),
          spaceActionsProvider.overrideWith((ref) => actions),
          trashedSpacesProvider.overrideWith((ref) async {
            trashBuilds++;
            return spaces;
          }),
        ],
        child: MaterialApp(theme: buildTheme(), home: const TrashPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return actions;
  }

  group('the list', () {
    testWidgets('says who, where, and how long is left', (tester) async {
      await pump(tester, spaces: [trashedIn(12)]);

      expect(find.text('My Journey'), findsOneWidget);
      expect(find.text('@ether/my-journey'), findsOneWidget);
      expect(find.text('12 DAYS LEFT'), findsOneWidget);
    });

    testWidgets('the last day is said, not rounded to zero', (tester) async {
      // Under a day left reads as "LAST DAY", never "0 DAYS LEFT".
      await pump(tester, spaces: [trashedIn(0)]);
      expect(find.text('LAST DAY'), findsOneWidget);
    });

    testWidgets('an empty Trash says so and offers nothing to do', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Nothing in the Trash.'), findsOneWidget);
      expect(find.text('Restore'), findsNothing);
      expect(find.text('Delete forever'), findsNothing);
    });

    testWidgets('a failed read says so and offers to ask again', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) async => me),
            trashedSpacesProvider.overrideWith(
              (ref) async => throw Exception('offline'),
            ),
          ],
          child: MaterialApp(theme: buildTheme(), home: const TrashPage()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('The Trash could not be loaded.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('restoring', () {
    testWidgets('brings the Space back and refreshes both lists', (
      tester,
    ) async {
      final actions = await pump(tester, spaces: [trashedIn(12)]);
      final before = trashBuilds;

      await tester.tap(find.text('Restore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.restored, ['s1']);
      expect(trashBuilds, greaterThan(before));
      expect(find.text('Restored to @ether.'), findsOneWidget);
    });

    testWidgets('is not asked for, because it is undoable', (tester) async {
      final actions = await pump(tester, spaces: [trashedIn(12)]);

      await tester.tap(find.text('Restore'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('This cannot be undone.'), findsNothing);
      expect(actions.restored, ['s1']);
    });
  });

  group('deleting forever', () {
    testWidgets('asks first, and does nothing if the answer is no', (
      tester,
    ) async {
      final actions = await pump(tester, spaces: [trashedIn(12)]);

      await tester.tap(find.text('Delete forever'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('This cannot be undone.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.deleted, isEmpty);
      expect(find.text('My Journey'), findsOneWidget, reason: 'still there');
    });

    testWidgets('deletes, refreshes, and says the title is free again', (
      tester,
    ) async {
      // DoD 18's last clause, in words the author can act on.
      final actions = await pump(tester, spaces: [trashedIn(12)]);
      final before = trashBuilds;

      await tester.tap(find.text('Delete forever'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Two buttons now say "Delete forever": the row's, and the dialog's.
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Delete forever'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.deleted, ['s1']);
      expect(trashBuilds, greaterThan(before));
      expect(
        find.text('Gone. Its title is free to use again.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the page holds up at 360 px', (tester) async {
    await pump(tester, spaces: [trashedIn(12)], size: const Size(360, 900));

    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Delete forever'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
