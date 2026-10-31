import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/blocks/block_rules.dart';

/// The client's copy of `private.validate_blocks`, and SPEC §9's counter rule.
///
/// These prove the client agrees with the migration about *what is wrong*. They
/// do not prove the migration enforces it — the 42-assertion HTTP suite does
/// that, and if the two ever disagree the database wins.
void main() {
  Block text(String body, {String id = 't'}) =>
      Block(id: id, type: 'text', data: {'text': body});

  Block heading(String body, {int level = 1, String id = 'h'}) =>
      Block(id: id, type: 'heading', data: {'text': body, 'level': level});

  Block image({required String alt, String id = 'i'}) =>
      Block(id: id, type: 'image', data: {'media_id': 'm1', 'alt': alt});

  const door = Block(id: 'd', type: 'door', data: {'note': ''});
  const readers = Block(id: 'r', type: 'readers');
  const likes = Block(id: 'l', type: 'likes');

  group('a document that is fine', () {
    test('has nothing to report and may publish', () {
      final check = checkDocument([text('Hello'), heading('A title')]);

      expect(check.problems, isEmpty);
      expect(check.canPublish, isTrue);
      expect(check.countersNeedDoor, isFalse);
      expect(check.hasNotices, isFalse);
    });

    test('an empty document is legal — it is just an empty Space', () {
      expect(checkDocument(const []).canPublish, isTrue);
    });
  });

  group('the limits, matching the migration', () {
    test('the numbers themselves, named where they can be seen', () {
      // §8 and `20261029000006_private_helpers.sql`: 200 blocks, 20 000 for
      // text, 60 000 for long text, 200 for a heading, levels 1–3.
      expect(maxBlocks, 200);
      expect(maxTextLength, 20000);
      expect(maxLongTextLength, 60000);
      expect(maxHeadingLength, 200);
    });

    test('two hundred blocks pass, two hundred and one do not', () {
      List<Block> many(int n) => [
        for (var i = 0; i < n; i++) text('p', id: '$i'),
      ];

      expect(checkDocument(many(200)).canPublish, isTrue);

      final over = checkDocument(many(201));
      expect(over.canPublish, isFalse);
      expect(over.problems.single.code, 'too_many_blocks');
    });

    test('a text block at the limit passes, one over does not', () {
      expect(
        checkDocument([text('a' * maxTextLength)]).canPublish,
        isTrue,
      );
      expect(
        checkDocument([text('a' * (maxTextLength + 1))]).problems.single.code,
        'text_too_long',
      );
    });

    test('long text has its own, larger ceiling', () {
      final long = Block(
        id: 'l',
        type: 'longtext',
        data: {'text': 'a' * (maxLongTextLength + 1)},
      );
      expect(checkDocument([long]).problems.single.code, 'longtext_too_long');

      // A body that fits long text must not be judged by the text limit.
      final fits = Block(
        id: 'l',
        type: 'longtext',
        data: {'text': 'a' * (maxTextLength + 1)},
      );
      expect(checkDocument([fits]).canPublish, isTrue);
    });

    test('a heading is limited in both length and level', () {
      expect(checkDocument([heading('a' * 200)]).canPublish, isTrue);
      expect(
        checkDocument([heading('a' * 201)]).problems.single.code,
        'heading_invalid',
      );
      expect(
        checkDocument([heading('ok', level: 0)]).problems.single.code,
        'heading_invalid',
      );
      expect(
        checkDocument([heading('ok', level: 4)]).problems.single.code,
        'heading_invalid',
      );
      for (final level in [1, 2, 3]) {
        expect(checkDocument([heading('ok', level: level)]).canPublish, isTrue);
      }
    });
  });

  group('the door', () {
    test('one door is fine, two are not', () {
      expect(checkDocument([text('a'), door]).canPublish, isTrue);

      final two = checkDocument([door, text('a'), const Block(id: 'd2', type: 'door')]);
      expect(two.problems.single.code, 'multiple_doors');
      expect(two.problems.single.blockId, 'd2', reason: 'point at the second one');
    });
  });

  group('alt text', () {
    test('an image without it cannot be published', () {
      final check = checkDocument([image(alt: '')]);

      expect(check.canPublish, isFalse);
      expect(check.problems.single.code, 'image_alt_required');
      expect(check.problems.single.blockId, 'i');
    });

    test('whitespace is not alt text', () {
      expect(checkDocument([image(alt: '   ')]).canPublish, isFalse);
    });

    test('a real description is', () {
      expect(
        checkDocument([image(alt: 'A blue frog on a wet leaf.')]).canPublish,
        isTrue,
      );
    });
  });

  group('the counter rule of SPEC §9', () {
    test('a counter with a door above it counts nothing', () {
      final check = checkDocument([readers, text('a'), door]);

      expect(check.countersNeedDoor, isTrue);
      expect(check.hasNotices, isTrue);
      // A rule, not a blocker: a page can be written before the door is placed.
      expect(check.canPublish, isTrue);
    });

    test('a counter with no door at all counts nothing either', () {
      expect(checkDocument([text('a'), likes]).countersNeedDoor, isTrue);
    });

    test('a counter below the door is exactly right', () {
      final check = checkDocument([text('a'), door, readers, likes]);

      expect(check.countersNeedDoor, isFalse);
      expect(check.hasNotices, isFalse);
    });

    test('no counters means no notice, door or not', () {
      expect(checkDocument([text('a')]).countersNeedDoor, isFalse);
      expect(checkDocument([text('a'), door]).countersNeedDoor, isFalse);
    });
  });

  group('a malformed block', () {
    test('with no type is reported against its own id', () {
      final check = checkDocument([
        text('fine'),
        const Block(id: 'broken', type: ''),
      ]);

      expect(check.problems.single.code, 'block_shape_invalid');
      expect(check.problems.single.blockId, 'broken');
    });
  });

  group('what this function does not check', () {
    test('media ownership, because that is a security boundary', () {
      // A cover pointing at somebody else's media passes here and is refused by
      // the database with `media_not_owned`. Pretending otherwise would move a
      // server decision into a client that can be edited.
      final check = checkDocument([
        const Block(
          id: 'c',
          type: 'cover',
          data: {'media_id': 'not-mine'},
        ),
      ]);

      expect(check.canPublish, isTrue);
    });
  });

  group('several problems at once', () {
    test('are all reported, in the order the database checks them', () {
      final check = checkDocument([
        const Block(id: 'no-type', type: ''),
        door,
        const Block(id: 'd2', type: 'door'),
        text('a' * (maxTextLength + 1), id: 'long'),
        image(alt: ''),
      ]);

      expect(
        check.problems.map((p) => p.code),
        [
          'block_shape_invalid',
          'multiple_doors',
          'text_too_long',
          'image_alt_required',
        ],
        reason: 'the same order as private.validate_blocks',
      );
    });

    test('every message is a sentence a person can read', () {
      final check = checkDocument([
        const Block(id: 'x', type: ''),
        text('a' * (maxTextLength + 1), id: 'long'),
        image(alt: ''),
        heading('a' * 300, id: 'h'),
      ]);

      for (final problem in check.problems) {
        expect(problem.message, endsWith('.'), reason: problem.code);
        expect(problem.message, isNot(contains('_')));
        expect(problem.message[0], problem.message[0].toUpperCase());
      }
    });
  });
}
