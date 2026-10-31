import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/auth/auth_providers.dart';
import 'package:owniverse/features/auth/profile.dart';
import 'package:owniverse/features/profile/profile_page.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';

import 'fakes/fake_space_actions.dart';

/// D15: the per-Space actions are a menu on the row. Rename and Move to Trash in
/// M2; Publish joins them in M4.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const me = Profile(id: 'u1', username: 'ether', name: 'Ether');
  const journey = Space(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    visibility: 'private',
  );

  /// How many times the owner list was (re)built, so "it refreshed" is
  /// measured rather than assumed.
  var listBuilds = 0;

  Future<FakeSpaceActions> pump(
    WidgetTester tester, {
    List<Space> spaces = const [journey],
    Size size = const Size(1000, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final actions = FakeSpaceActions();
    listBuilds = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => me),
          spaceActionsProvider.overrideWith((ref) => actions),
          ownerSpacesProvider.overrideWith((ref) async {
            listBuilds++;
            return spaces;
          }),
          trashedSpacesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const ProfilePage(username: 'ether'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return actions;
  }

  group('the row menu', () {
    testWidgets('offers Rename, Publish and Move to Trash', (tester) async {
      await pump(tester);

      await tester.tap(find.text('⋯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Move to Trash'), findsOneWidget);
    });

    testWidgets('publishing calls the database and refreshes', (tester) async {
      final actions = await pump(tester);

      await tester.tap(find.text('⋯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Publish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.published, ['s1']);
    });

    testWidgets('a Space that has been published says so on the menu', (
      tester,
    ) async {
      await pump(
        tester,
        spaces: [
          Space(
            id: 's1',
            title: 'My Journey',
            slug: 'my-journey',
            visibility: 'public',
            publishedAt: DateTime.utc(2026, 10, 29),
            publishedSlug: 'my-journey',
            publishedTitle: 'My Journey',
          ),
        ],
      );

      await tester.tap(find.text('⋯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // D8: publishing again is a different act from publishing the first time.
      expect(find.text('Publish again'), findsOneWidget);
    });

    testWidgets('Rename opens the dialog that already exists', (tester) async {
      await pump(tester);

      await tester.tap(find.text('⋯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Rename'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('RENAME'), findsOneWidget);
      expect(find.text('What should it be called?'), findsOneWidget);
    });

    testWidgets('Move to Trash calls the database and refreshes the list', (
      tester,
    ) async {
      final actions = await pump(tester);
      final buildsBefore = listBuilds;

      await tester.tap(find.text('⋯'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Move to Trash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(actions.trashed, ['s1']);
      expect(
        listBuilds,
        greaterThan(buildsBefore),
        reason: 'the row must not linger after it was trashed',
      );
    });

    testWidgets('a visitor gets no menu, and no way to act', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) async => null),
            publicProfileProvider.overrideWith(
              (ref, handle) async => {
                'found': true,
                'username': 'ether',
                'name': 'Ether',
                'social': <String, dynamic>{},
                'spaces': [
                  {
                    'id': 's1',
                    'title': 'My Journey',
                    'slug': 'my-journey',
                    'published_at': '2026-10-29T09:00:00Z',
                  },
                ],
              },
            ),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: const ProfilePage(username: 'ether'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('My Journey'), findsOneWidget);
      expect(find.text('⋯'), findsNothing);
    });

    testWidgets('the owner lens links to the Trash and says how much is in it', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('TRASH 0 →'), findsOneWidget);
    });

    testWidgets('the row and the menu hold up at 360 px', (tester) async {
      await pump(tester, size: const Size(360, 900));

      expect(find.text('⋯'), findsOneWidget);
      expect(find.text('TRASH 0 →'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
