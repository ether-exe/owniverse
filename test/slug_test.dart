import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/spaces/slug.dart';

/// D18: the title a person types becomes the address a reader types.
///
/// The database validates `^[a-z0-9]+(?:-[a-z0-9]+)*$` and 2–60 characters. No
/// test here can prove the database is right; these prove the client never
/// hands it something it would reject.
void main() {
  final shape = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

  void expectValid(String title) {
    final slug = slugify(title);
    expect(
      shape.hasMatch(slug),
      isTrue,
      reason: '"$title" produced "$slug", which is not a legal slug',
    );
    expect(slug.length, greaterThanOrEqualTo(minSlugLength));
    expect(slug.length, lessThanOrEqualTo(maxSlugLength));
  }

  group('slugify', () {
    test('a title becomes its address', () {
      expect(slugify('My Journey'), 'my-journey');
      expect(slugify('  My Journey  '), 'my-journey');
      expect(slugify('MY JOURNEY'), 'my-journey');
    });

    test('case is folded before the address is formed', () {
      // D18: `My Journey` and `my journey` must collide for the same author,
      // because they would otherwise claim two addresses that read the same.
      expect(slugify('My Journey'), slugify('my journey'));
      expect(slugify('My Journey'), slugify('MY JOURNEY'));
    });

    test('punctuation becomes a separator, never a gap', () {
      expect(slugify('Hello, World!'), 'hello-world');
      expect(slugify('Hello---World'), 'hello-world');
      expect(slugify('  ---  '), startsWith('page-'));
      expect(slugify('a/b//c'), 'a-b-c');
    });

    test('accents fold to their Latin letters', () {
      expect(slugify('Café Olé'), 'cafe-ole');
      expect(slugify('Straße'), 'strasse');
      expect(slugify('Æther'), 'aether');
      expect(slugify('Łódź'), 'lodz');
    });

    test('emoji disappear without leaving a hole', () {
      expect(slugify('Hello 🎉 World'), 'hello-world');
      expect(slugify('🎉'), startsWith('page-'));
    });

    test('a title with no Latin letters still gets a stable address', () {
      final tokyo = slugify('東京');
      final kyoto = slugify('京都');

      expect(tokyo, startsWith('page-'));
      expect(tokyo, shape.hasMatch);
      // Two different titles must not collapse onto one slug by accident.
      expect(tokyo, isNot(kyoto));
      // ...and the same title must always produce the same one, on every run.
      expect(slugify('東京'), tokyo);
    });

    test('an over-long title is cut to fit and never ends in a dash', () {
      final title = List.filled(30, 'word').join(' '); // 149 characters
      final slug = slugify(title);

      expect(slug.length, lessThanOrEqualTo(maxSlugLength));
      expect(slug.endsWith('-'), isFalse);
      expect(slug, shape.hasMatch);
    });

    test('exactly sixty characters is left alone', () {
      final title = 'a' * maxSlugLength;
      expect(slugify(title), title);
      expect(slugify('$title-b'), hasLength(maxSlugLength));
    });

    test('every awkward title in the suite still satisfies the database', () {
      for (final title in [
        '',
        ' ',
        'a',
        'A',
        'ab',
        'a b',
        'a_b',
        'a.b',
        'Hello, World!',
        'Café Olé',
        'Straße',
        '🎉🎉🎉',
        '東京',
        'My Journey',
        '- leading and trailing -',
        '123',
        '123 456',
        List.filled(40, 'x').join(),
      ]) {
        expectValid(title);
      }
    });
  });

  group('the database shape', () {
    test('minSlugLength and maxSlugLength match SPEC §6.2', () {
      // 2–60 characters, `^[a-z0-9]+(?:-[a-z0-9]+)*$`. If the spec moves, this
      // test is the thing that has to move with it.
      expect(minSlugLength, 2);
      expect(maxSlugLength, 60);
    });

    test('a two-character title is accepted rather than rescued', () {
      expect(slugify('ab'), 'ab');
    });

    test('a one-character title is rescued, because the database would not', () {
      expect(slugify('a'), isNot('a'));
      expectValid('a');
    });
  });
}
