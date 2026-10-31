import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/blocks/save_outcome.dart';

/// SPEC §8: `{ id, type, v, data }`, order is array order, and a block this
/// client does not understand must be carried rather than dropped.
void main() {
  group('a block', () {
    test('survives JSON in both directions unchanged', () {
      const block = Block(
        id: 'b1',
        type: 'heading',
        data: {'text': 'The threshold', 'level': 2},
      );

      final round = Block.fromJson(block.toJson());
      expect(round.id, 'b1');
      expect(round.type, 'heading');
      expect(round.text, 'The threshold');
      expect(round.level, 2);
      expect(round.v, 1);
    });

    test('survives being encoded and decoded as a real JSON string', () {
      // The RPC layer serialises through `jsonEncode`; a value that survives a
      // Map copy but not a string round-trip would save a corrupted document.
      const block = Block(
        id: 'b1',
        type: 'text',
        data: {'text': 'He said "no" — twice.'},
      );

      final decoded = jsonDecode(jsonEncode(block.toJson())) as Map;
      final round = Block.fromJson(Map<String, Object?>.from(decoded));

      expect(round.text, 'He said "no" — twice.');
    });

    test('an unknown type is carried, not dropped', () {
      // The case that matters: a newer client writes `gallery`, this one opens
      // the Space. Dropping it would delete a block the author can see.
      const block = Block(id: 'b1', type: 'gallery', data: {'items': 3});

      expect(block.kind, isNull);
      expect(block.isRenderable, isFalse);
      expect(block.toJson()['type'], 'gallery');
      expect(block.toJson()['data'], {'items': 3});
    });

    test('a newer schema version is carried, and not rendered', () {
      const block = Block(id: 'b1', type: 'text', data: {'text': 'x'}, v: 2);

      expect(block.kind, BlockType.text);
      expect(block.isRenderable, isFalse, reason: 'v > schemaVersion');
    });

    test('a block missing its id is given one rather than lost', () {
      final block = Block.fromJson({'type': 'text', 'data': {'text': 'hi'}});

      expect(block.id, isNotEmpty);
      expect(block.text, 'hi');
    });

    test('garbage data reads as empty, never as a crash', () {
      for (final data in [null, 'text', 42, <Object?>[]]) {
        final block = Block.fromJson({'id': 'b1', 'type': 'text', 'data': data});
        expect(block.data, isEmpty);
        expect(block.text, '');
        expect(block.level, 1);
        expect(block.alt, '');
        expect(block.mediaId, isNull);
      }
    });

    test('a level sent as a JSON number is read as an int', () {
      final block = Block.fromJson({
        'id': 'b1',
        'type': 'heading',
        'data': {'text': 'a', 'level': 3.0},
      });
      expect(block.level, 3);
    });
  });

  group('blank blocks', () {
    test('each type starts valid enough to exist', () {
      for (final type in BlockType.values) {
        final block = Block.blank(type);
        expect(block.type, type.name);
        expect(block.v, Block.schemaVersion);
        expect(block.data, isA<Map<String, Object?>>());
      }
    });

    test('an image starts with empty alt, which the database will refuse', () {
      // Not an oversight: alt text is a gate (SPEC §8, DoD 7), so a blank
      // image cannot be saved until someone writes one.
      final image = Block.blank(BlockType.image);
      expect(image.alt, '');
    });

    test('a heading starts at level 1', () {
      expect(Block.blank(BlockType.heading).level, 1);
    });

    test('ids are unique across many blocks', () {
      final ids = {for (var i = 0; i < 500; i++) Block.blank(BlockType.text).id};
      expect(ids, hasLength(500));
    });

    test('ids are uuid-shaped', () {
      final id = newBlockId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });
  });

  group('the block types of SPEC §8', () {
    test('there are nine, and the picker names each one once', () {
      // §4 says "five block types + the door + two counter blocks"; §8's table
      // has nine rows and §11 says "nine block types". Nine is what is built.
      expect(BlockType.values, hasLength(9));

      final labels = BlockType.values.map((t) => t.label).toSet();
      expect(labels, hasLength(9));
    });

    test('every type round-trips through its own name', () {
      for (final type in BlockType.values) {
        expect(BlockType.tryParse(type.name), type);
      }
      expect(BlockType.tryParse('gallery'), isNull);
      expect(BlockType.tryParse(''), isNull);
    });

    test('the three that change behaviour are not "content"', () {
      expect(BlockType.door.isContent, isFalse);
      expect(BlockType.readers.isContent, isFalse);
      expect(BlockType.likes.isContent, isFalse);
      expect(BlockType.text.isContent, isTrue);
      expect(BlockType.profile.isContent, isTrue);
    });
  });

  group('parsing a whole document', () {
    test('a list of maps becomes blocks, anything else becomes empty', () {
      expect(
        blocksFromJson([
          {'id': 'a', 'type': 'text', 'data': {'text': 'one'}},
          {'id': 'b', 'type': 'door', 'data': <String, Object?>{}},
        ]),
        hasLength(2),
      );

      expect(blocksFromJson(null), isEmpty);
      expect(blocksFromJson('not a list'), isEmpty);
      expect(blocksFromJson({'id': 'a'}), isEmpty);
    });

    test('order is preserved exactly', () {
      final blocks = [
        for (final type in ['text', 'heading', 'door', 'likes'])
          Block(id: type, type: type),
      ];
      expect(
        blocksFromJson(blocksToJson(blocks)).map((b) => b.type),
        ['text', 'heading', 'door', 'likes'],
      );
    });

    test('non-map entries are skipped rather than crashing the page', () {
      final parsed = blocksFromJson([
        {'id': 'a', 'type': 'text', 'data': <String, Object?>{}},
        'garbage',
        42,
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.single.id, 'a');
    });
  });

  group('what save_blocks answered', () {
    test('a save reports the version it produced', () {
      final outcome = SaveOutcome.fromRpc({'status': 'saved', 'version': 5});
      expect(outcome, isA<Saved>());
      expect((outcome as Saved).version, 5);
    });

    test('a conflict reports the version that won', () {
      final outcome = SaveOutcome.fromRpc({'status': 'conflict', 'version': 9});
      expect(outcome, isA<Conflict>());
      expect((outcome as Conflict).version, 9);
    });

    test('an answer nobody expected is treated as a conflict', () {
      // The only safe assumption about a reply this client cannot read is that
      // the document did *not* save.
      for (final json in <Map<String, Object?>>[
        {},
        {'status': 'queued'},
        {'version': 3},
        // A "saved" that does not say which version it produced is not
        // something to build on: carrying 0 forward would make every later
        // save arrive stale.
        {'status': 'saved'},
        {'status': 'saved', 'version': 0},
      ]) {
        expect(SaveOutcome.fromRpc(json), isA<Conflict>());
      }
    });
  });
}
