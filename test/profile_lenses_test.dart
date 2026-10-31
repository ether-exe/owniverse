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

/// D14: one URL, rendered by who is asking. The owner sees drafts, chips, the
/// New Space tile and a count; a visitor sees published rows and none of it.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const me = Profile(id: 'u1', username: 'ether', name: 'Ether');

  final journey = Space(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    visibility: 'public',
    publishedAt: DateTime.utc(2026, 10, 29),
    publishedSlug: 'my-journey',
    publishedTitle: 'My Journey',
  );
  const draft = Space(
    id: 's2',
    title: 'Not Yet',
    slug: 'not-yet',
    visibility: 'private',
  );
  final unlisted = Space(
    id: 's3',
    title: 'Hidden Away',
    slug: 'hidden-away',
    visibility: 'private',
    publishedAt: DateTime.utc(2026, 10, 28),
    publishedSlug: 'hidden-away',
    publishedTitle: 'Hidden Away',
  );

  Future<void> pumpOwner(
    WidgetTester tester, {
    List<Space> spaces = const [],
    Size size = const Size(1000, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => me),
          ownerSpacesProvider.overrideWith((ref) async => spaces),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const ProfilePage(username: 'ether'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('the owner lens', () {
    testWidgets('lists every Space with its state', (tester) async {
      await pumpOwner(tester, spaces: [journey, draft, unlisted]);

      expect(find.text('My Journey'), findsOneWidget);
      expect(find.text('Not Yet'), findsOneWidget);
      expect(find.text('Hidden Away'), findsOneWidget);

      expect(find.text('PUBLISHED'), findsOneWidget);
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('UNLISTED'), findsOneWidget);
    });

    testWidgets('shows the frozen address, not the working one', (tester) async {
      // D9: a renamed Space keeps answering at the address it published to.
      await pumpOwner(
        tester,
        spaces: [
          Space(
            id: 's4',
            title: 'A Better Title',
            slug: 'a-better-title',
            visibility: 'public',
            publishedAt: DateTime.utc(2026, 10, 29),
            publishedSlug: 'my-journey',
            publishedTitle: 'My Journey',
          ),
        ],
      );

      expect(find.text('A Better Title'), findsOneWidget);
      expect(find.text('@ether/my-journey'), findsOneWidget);
      expect(find.text('@ether/a-better-title'), findsNothing);
    });

    testWidgets('counts what it lists', (tester) async {
      await pumpOwner(tester, spaces: [journey, draft, unlisted]);
      expect(find.text('SPACES 3'), findsOneWidget);
    });

    testWidgets('offers New Space even when the column is empty', (tester) async {
      await pumpOwner(tester);

      expect(
        find.text('Nothing here yet. Your first Space will sit in this column.'),
        findsOneWidget,
      );
      expect(find.text('NEW SPACE'), findsOneWidget);
      expect(find.text('SPACES 0'), findsOneWidget);
    });

    testWidgets('says so when the list cannot be read', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) async => me),
            ownerSpacesProvider.overrideWith(
              (ref) async => throw Exception('offline'),
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

      expect(find.text('Your Spaces could not be loaded.'), findsOneWidget);
    });

    testWidgets('holds up at 360 px', (tester) async {
      await pumpOwner(
        tester,
        spaces: [journey, draft, unlisted],
        size: const Size(360, 900),
      );

      // A RenderFlex overflow throws during layout and fails the test; this is
      // the assertion that says the column was actually laid out.
      expect(find.text('NEW SPACE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the visitor lens', () {
    Future<void> pumpVisitor(
      WidgetTester tester, {
      required List<Map<String, dynamic>> spaces,
    }) async {
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
                'spaces': spaces,
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
    }

    testWidgets('shows published rows and no controls at all', (tester) async {
      await pumpVisitor(
        tester,
        spaces: [
          {
            'id': 's1',
            'title': 'My Journey',
            'slug': 'my-journey',
            'published_at': '2026-10-29T09:00:00Z',
          },
        ],
      );

      expect(find.text('My Journey'), findsOneWidget);
      expect(find.text('@ether/my-journey'), findsOneWidget);

      // DoD 16: no chips, no count, no tile — no trace of an owner's tools.
      expect(find.text('PUBLISHED'), findsNothing);
      expect(find.text('DRAFT'), findsNothing);
      expect(find.textContaining('SPACES'), findsNothing);
      expect(find.text('NEW SPACE'), findsNothing);
    });

    testWidgets('says nothing is published rather than nothing exists', (
      tester,
    ) async {
      await pumpVisitor(tester, spaces: const []);

      expect(find.text('Nothing published here yet.'), findsOneWidget);
      expect(find.text('NEW SPACE'), findsNothing);
    });
  });
}
