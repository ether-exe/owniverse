import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/space_actions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Space as the client understands it: three states (D17), Trash as a flag
/// (D34), and a frozen snapshot that survives a rename (D9).
///
/// These are the rules DoD 11 and 15 lean on. Proving them here proves the
/// client agrees with the migrations; it does not prove the database does, and
/// it says nothing about the routes that will eventually answer the URLs.
void main() {
  Map<String, dynamic> row({
    String? publishedAt,
    String? publishedSlug,
    String? publishedTitle,
    String visibility = 'private',
    String? deletedAt,
    String? purgeAfter,
  }) => {
    'id': 's1',
    'title': 'My Journey',
    'slug': 'my-journey',
    'visibility': visibility,
    'published_at': publishedAt,
    'published_slug': publishedSlug,
    'published_title': publishedTitle,
    'blocks_version': 4,
    'updated_at': '2026-10-30T10:00:00Z',
    'deleted_at': deletedAt,
    'purge_after': purgeAfter,
  };

  group('the three states of D17', () {
    test('a Space that has never been published is a draft', () {
      final space = Space.fromRow(row());

      expect(space.state, SpaceState.draft);
      expect(space.hasSnapshot, isFalse);
      expect(space.state.label, 'DRAFT');
    });

    test('public plus a snapshot is published', () {
      final space = Space.fromRow(
        row(
          visibility: 'public',
          publishedAt: '2026-10-29T09:00:00Z',
          publishedSlug: 'my-journey',
          publishedTitle: 'My Journey',
        ),
      );

      expect(space.state, SpaceState.published);
      expect(space.hasSnapshot, isTrue);
      expect(space.state.label, 'PUBLISHED');
    });

    test('a snapshot made private is unlisted, not a draft', () {
      // D17 and DoD 15: the URL stops answering, the bytes are retained.
      final space = Space.fromRow(
        row(
          publishedAt: '2026-10-29T09:00:00Z',
          publishedSlug: 'my-journey',
          publishedTitle: 'My Journey',
        ),
      );

      expect(space.state, SpaceState.unlisted);
      expect(space.hasSnapshot, isTrue, reason: 'the snapshot is kept');
      expect(space.publishedAt, isNotNull);
      expect(space.state.label, 'UNLISTED');
    });
  });

  group('the frozen address of D8 and D9', () {
    test('a draft has no reader-facing address; it shows its working one', () {
      final space = Space.fromRow(row());

      expect(space.addressSlug, 'my-journey');
      expect(space.addressTitle, 'My Journey');
    });

    test('renaming before republishing leaves the public address untouched', () {
      // DoD 11's data half. The working title moves; the published one does not.
      final space = Space.fromRow({
        ...row(
          visibility: 'public',
          publishedAt: '2026-10-29T09:00:00Z',
          publishedSlug: 'my-journey',
          publishedTitle: 'My Journey',
        ),
        'title': 'A Better Title',
        'slug': 'a-better-title',
      });

      expect(space.title, 'A Better Title');
      expect(space.slug, 'a-better-title');
      expect(space.addressSlug, 'my-journey', reason: 'still answering');
      expect(space.addressTitle, 'My Journey', reason: 'still saying this');
    });
  });

  group('Trash is a flag, not a state', () {
    test('a trashed Space keeps its state', () {
      final space = Space.fromRow(
        row(
          visibility: 'public',
          publishedAt: '2026-10-29T09:00:00Z',
          publishedSlug: 'my-journey',
          publishedTitle: 'My Journey',
          deletedAt: '2026-10-30T12:00:00Z',
          purgeAfter: '2026-11-29T12:00:00Z',
        ),
      );

      expect(space.isTrashed, isTrue);
      expect(space.state, SpaceState.published);
    });

    test('days remaining round up, so the last day never reads zero', () {
      final space = Space.fromRow(
        row(
          deletedAt: '2026-10-30T12:00:00Z',
          purgeAfter: '2026-11-29T12:00:00Z',
        ),
      );
      final trashedAt = DateTime.utc(2026, 10, 30, 12);

      expect(space.remainingDays(trashedAt), 30);
      expect(space.remainingDays(trashedAt.add(const Duration(days: 29))), 1);
      expect(
        space.remainingDays(trashedAt.add(const Duration(days: 29, hours: 20))),
        1,
        reason: 'four hours left is still "1 day", not "0 days"',
      );
      expect(space.remainingDays(trashedAt.add(const Duration(days: 31))), 0);
    });

    test('a Space with no purge date falls back to the 30-day figure', () {
      final space = Space.fromRow(row(deletedAt: '2026-10-30T12:00:00Z'));
      expect(space.remainingDays(DateTime.utc(2026, 10, 30)), 30);
    });
  });

  group('parsing', () {
    test('Space.columns covers every field fromRow reads', () {
      // The select list and the parser sit next to each other for a reason.
      // This fails the day someone adds a field and forgets the column.
      const declared = [
        'id',
        'title',
        'slug',
        'visibility',
        'published_at',
        'published_slug',
        'published_title',
        'blocks_version',
        'updated_at',
        'deleted_at',
        'purge_after',
      ];

      final selected = Space.columns.split(',').map((c) => c.trim()).toSet();
      expect(selected, containsAll(declared));
      expect(selected.length, declared.length, reason: 'nothing extra either');
    });

    test('a missing optional column reads as absent, not as a crash', () {
      final minimal = {
        'id': 's1',
        'title': 'Bare',
        'slug': 'bare',
      };

      final space = Space.fromRow(minimal);
      expect(space.visibility, 'private');
      expect(space.blocksVersion, 1);
      expect(space.publishedAt, isNull);
      expect(space.isTrashed, isFalse);
      expect(space.state, SpaceState.draft);
    });

    test('a visitor row is always a published one', () {
      // `profile_public` has already done the filtering (D24), so there is
      // nothing left for the client to decide.
      final space = Space.fromPublicMap({
        'id': 's1',
        'title': 'My Journey',
        'slug': 'my-journey',
        'published_at': '2026-10-29T09:00:00Z',
      });

      expect(space.state, SpaceState.published);
      expect(space.addressSlug, 'my-journey');
      expect(space.addressTitle, 'My Journey');
    });

    test('a write RPC answers with what changed, and defaults the rest', () {
      final space = Space.fromRpc({
        'id': 's1',
        'title': 'My Journey',
        'slug': 'my-journey',
        'visibility': 'private',
        'blocks_version': 1,
      });

      expect(space.id, 's1');
      expect(space.state, SpaceState.draft);
      expect(space.updatedAt, isNull);
    });
  });

  group('the failures the database can raise', () {
    SpaceFailure map(String message) =>
        spaceFailureFrom(PostgrestException(message: message));

    test('each identifier becomes a sentence, not the identifier', () {
      for (final code in [
        'slug_taken',
        'profile_incomplete',
        'auth_required',
        'space_trashed',
        'not_found',
        'invalid_visibility',
      ]) {
        final failure = map(code);
        expect(failure.code, code);
        expect(failure.message, isNotEmpty);
        expect(failure.message, isNot(contains('_')));
        expect(failure.message, isNot(contains('Exception')));
      }
    });

    test('slug_taken says it is the title, because the author typed a title', () {
      expect(map('slug_taken').message, contains('title'));
    });

    test('an identifier nobody mapped degrades to a sentence, still', () {
      final failure = map('some_new_database_error');
      expect(failure.code, 'unknown');
      expect(failure.message, 'That did not save. Try again.');
    });

    test('a thrown failure passes through rather than being remapped', () {
      const original = SpaceFailure('slug_taken', 'kept as-is');
      expect(spaceFailureFrom(original), same(original));
    });

    test('anything that is not a database error is a network sentence', () {
      final failure = spaceFailureFrom(const FormatException('bad json'));
      expect(failure.code, 'network');
      expect(failure.message, isNotEmpty);
    });
  });
}
