import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/auth/auth_providers.dart';
import 'package:owniverse/features/auth/profile.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/space_page.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';

import 'fakes/fake_space_actions.dart';

/// `/space/:id` loads the Space and its document, then hands them to the editor.
/// These assertions are about the *hosting* — loading, ownership, failure — so
/// they stay true however the canvas itself changes.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const me = Profile(id: 'u1', username: 'ether', name: 'Ether');
  const space = Space(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    visibility: 'private',
  );

  Future<FakeSpaceActions> pump(
    WidgetTester tester, {
    SpaceDocument? document = const SpaceDocument(
      space: space,
      blocks: [],
    ),
    Size size = const Size(1000, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final actions = FakeSpaceActions();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => me),
          spaceActionsProvider.overrideWith((ref) => actions),
          spaceDocumentProvider.overrideWith((ref, id) async => document),
        ],
        child: MaterialApp(theme: buildTheme(), home: const SpacePage(id: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump();
    return actions;
  }

  testWidgets('shows the title, the address and the state', (tester) async {
    await pump(tester);

    expect(find.text('My Journey'), findsOneWidget);
    expect(find.text('@ether/my-journey'), findsOneWidget);
    expect(find.text('DRAFT'), findsOneWidget);
  });

  testWidgets('a renamed but unpublished Space shows the frozen address', (
    tester,
  ) async {
    // D9: the editor opens on the working document, but the address a reader
    // would type has not moved until the next publish.
    await pump(
      tester,
      document: SpaceDocument(
        space: Space(
          id: 's1',
          title: 'A Better Title',
          slug: 'a-better-title',
          visibility: 'public',
          publishedAt: DateTime.utc(2026, 10, 29),
          publishedSlug: 'my-journey',
          publishedTitle: 'My Journey',
        ),
        blocks: const [],
      ),
    );

    expect(find.text('A Better Title'), findsOneWidget);
    expect(find.text('@ether/my-journey'), findsOneWidget);
    expect(find.text('PUBLISHED'), findsOneWidget);
  });

  testWidgets('an empty document is blank with one way in (D7)', (tester) async {
    await pump(tester);

    expect(find.text('An empty page. Add a block to begin.'), findsOneWidget);
    // D7: no title field and no heading pretending to be one.
    expect(find.byType(TextField), findsNothing);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('renders the stored blocks', (tester) async {
    await pump(
      tester,
      document: SpaceDocument(
        space: space,
        blocks: const [
          Block(id: 'b1', type: 'heading', data: {'text': 'The Threshold', 'level': 1}),
          Block(id: 'b2', type: 'text', data: {'text': 'A first paragraph.'}),
        ],
      ),
    );

    expect(find.text('The Threshold'), findsOneWidget);
    expect(find.text('A first paragraph.'), findsOneWidget);
    expect(find.text('2 BLOCKS'), findsOneWidget);
  });

  testWidgets('a Space that is not there is a 404, not a blank page', (
    tester,
  ) async {
    await pump(tester, document: null);

    expect(
      find.textContaining('There is nothing at /space/s1.'),
      findsOneWidget,
    );
  });

  testWidgets('a failed read says so and offers to ask again', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith((ref) async => me),
          spaceDocumentProvider.overrideWith(
            (ref, id) async => throw Exception('offline'),
          ),
        ],
        child: MaterialApp(theme: buildTheme(), home: const SpacePage(id: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('This Space could not be loaded.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the editor holds up at 360 px', (tester) async {
    await pump(
      tester,
      document: SpaceDocument(
        space: Space(
          id: 's1',
          title: 'A Rather Long Title For A Narrow Screen Indeed',
          slug: 'a-rather-long-title-for-a-narrow-screen-indeed',
          visibility: 'private',
        ),
        blocks: const [
          Block(
            id: 'b1',
            type: 'longtext',
            data: {'text': 'A passage long enough to wrap on a narrow screen.'},
          ),
        ],
      ),
      size: const Size(360, 900),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1 BLOCK'), findsOneWidget);
    expect(find.text('← @ether'), findsOneWidget);
  });
}
