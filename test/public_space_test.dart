import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:owniverse/core/theme.dart';
import 'package:owniverse/features/auth/auth_providers.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/public_space/public_space.dart';
import 'package:owniverse/features/public_space/public_space_page.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fakes/fake_space_actions.dart';

/// The frozen page and its door (D5, D22).
///
/// These assert what the page does with the payload it is given. They cannot
/// assert that the payload is really gated — that is the server's job, and
/// assertion 19 of `scripts/db-test.mjs` proves it on the wire.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  const publicText = Block(
    id: 'b1',
    type: 'text',
    data: {'text': 'What anyone can read.'},
  );
  const gatedText = Block(
    id: 'b2',
    type: 'text',
    data: {'text': 'What only readers get.'},
  );
  const door = Block(id: 'b3', type: 'door', data: {'note': ''});
  const readers = Block(id: 'b4', type: 'readers');
  const likes = Block(id: 'b5', type: 'likes');

  /// Before entering: the public slice only.
  const head = PublicSpace(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    blocks: [publicText],
    hasDoor: true,
    readers: 1,
    likes: 0,
    authorName: 'Ether',
    authorHandle: 'ether',
  );

  /// After entering: the whole frozen document, including the door itself.
  const entered = PublicSpace(
    id: 's1',
    title: 'My Journey',
    slug: 'my-journey',
    blocks: [publicText, gatedText, door, readers, likes],
    hasDoor: true,
    readers: 1,
    likes: 2,
    authorName: 'Ether',
    authorHandle: 'ether',
  );

  Session? session;

  Future<FakeSpaceActions> pump(
    WidgetTester tester, {
    PublicSpace? space = head,
    Session? signedIn,
    Map<String, Object?>? enterResult,
  }) async {
    session = signedIn;
    final actions = FakeSpaceActions()..enterResult = enterResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => session),
          spaceActionsProvider.overrideWith((ref) => actions),
          publicSpaceProvider.overrideWith((ref, address) async => space),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const PublicSpacePage(handle: 'ether', slug: 'my-journey'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return actions;
  }

  group('before the door', () {
    testWidgets('shows only what the public slice contains', (tester) async {
      await pump(tester);

      expect(find.text('What anyone can read.'), findsOneWidget);
      expect(find.text('What only readers get.'), findsNothing);
    });

    testWidgets('shows a door, not a dead end', (tester) async {
      await pump(tester);

      expect(find.text('A DOOR'), findsOneWidget);
      expect(
        find.textContaining('There is more past this point'),
        findsOneWidget,
      );
    });

    testWidgets('an anonymous reader is offered sign-in, not entry', (
      tester,
    ) async {
      // `space_enter` requires a session; the page must not pretend otherwise.
      await pump(tester);

      expect(find.text('Sign in to enter →'), findsOneWidget);
      expect(find.text('Enter →'), findsNothing);
    });

    testWidgets('shows no counters, which the door has not yet earned', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('ENTERED'), findsNothing);
      expect(find.textContaining('LIKE'), findsNothing);
    });
  });

  group('entering', () {
    testWidgets('asks the database once and expands the page in place', (
      tester,
    ) async {
      final actions = await pump(
        tester,
        signedIn: _session(),
        enterResult: _enteredJson(),
      );

      await tester.tap(find.text('Enter →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(actions.entered, ['ether/my-journey']);
      expect(find.text('What only readers get.'), findsOneWidget);
    });

    testWidgets('the door collapses to a hairline, and stays where it was', (
      tester,
    ) async {
      // SPEC §11: the door collapses to a hairline labelled Entered and the page
      // re-expands without a route change.
      await pump(
        tester,
        signedIn: _session(),
        enterResult: _enteredJson(),
      );

      await tester.tap(find.text('Enter →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('ENTERED'), findsOneWidget);
      expect(find.text('A DOOR'), findsNothing);
      expect(find.text('What anyone can read.'), findsOneWidget);
    });

    testWidgets('the reader count arrives with the document', (tester) async {
      await pump(
        tester,
        signedIn: _session(),
        enterResult: _enteredJson(),
      );

      await tester.tap(find.text('Enter →'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('1 PERSON HAS ENTERED'), findsOneWidget);
    });
  });

  group('liking', () {
    testWidgets('a missing session offers a sentence, not a button', (
      tester,
    ) async {
      await pump(tester, space: entered);

      expect(find.text('Sign in to add one.'), findsOneWidget);
    });

    testWidgets('a reader can add one, and the count follows', (tester) async {
      final actions = await pump(tester, space: entered, signedIn: _session());
      actions.likeCount = 2;

      await tester.tap(find.text('Like'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(actions.likedByMe, isTrue);
      expect(find.text('Liked'), findsOneWidget);
      expect(find.text('3 LIKES'), findsOneWidget);
    });
  });

  testWidgets('an address with nothing behind it is a 404', (tester) async {
    await pump(tester, space: null);

    expect(find.text('404'), findsOneWidget);
  });
}

/// A `Session` good enough for "is someone signed in" — no network is involved.
Session _session() => Session(
  accessToken: 'test-token',
  tokenType: 'bearer',
  user: User(
    id: 'reader-1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-10-30T00:00:00Z',
  ),
);

Map<String, Object?> _enteredJson() => {
  'found': true,
  'id': 's1',
  'title': 'My Journey',
  'slug': 'my-journey',
  'blocks': const [
    {
      'id': 'b1',
      'type': 'text',
      'v': 1,
      'data': {'text': 'What anyone can read.'},
    },
    {
      'id': 'b2',
      'type': 'text',
      'v': 1,
      'data': {'text': 'What only readers get.'},
    },
    {
      'id': 'b3',
      'type': 'door',
      'v': 1,
      'data': {'note': ''},
    },
    {
      'id': 'b4',
      'type': 'readers',
      'v': 1,
      'data': <String, Object?>{},
    },
    {
      'id': 'b5',
      'type': 'likes',
      'v': 1,
      'data': <String, Object?>{},
    },
  ],
  'has_door': true,
  'readers': 1,
  'likes': 2,
  'liked_by_me': false,
  'author': {'username': 'ether', 'name': 'Ether'},
};
