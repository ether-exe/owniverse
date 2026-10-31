import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/blocks/publish_split.dart';

/// D22 and D33: the split happens on the server, from the server's own copy.
/// This is the client's *preview* of it, so the author can see what publishing
/// will do before pressing the button.
///
/// The interesting assertion is not that the code splits a list. It is that the
/// door block itself goes with the gated half, which means the anonymous payload
/// never contains the door's own note.
void main() {
  Block b(String id, String type) => Block(id: id, type: type);

  group('with no door', () {
    test('everything is public and nothing is withheld', () {
      final split = splitAtDoor([b('1', 'text'), b('2', 'heading')]);

      expect(split.hasDoor, isFalse);
      expect(split.publicCount, 2);
      expect(split.gatedCount, 0);
      expect(split.total, 2);
    });

    test('an empty document splits into nothing at all', () {
      final split = splitAtDoor(const []);

      expect(split.hasDoor, isFalse);
      expect(split.total, 0);
    });
  });

  group('with a door', () {
    test('the door and everything after it are withheld', () {
      final split = splitAtDoor([
        b('1', 'text'),
        b('2', 'text'),
        b('3', 'door'),
        b('4', 'text'),
        b('5', 'readers'),
      ]);

      expect(split.publicBlocks.map((x) => x.id), ['1', '2']);
      expect(split.gatedBlocks.map((x) => x.id), ['3', '4', '5']);
      expect(split.hasDoor, isTrue);
      expect(split.gatedCount, 3);
    });

    test('the door is gated, so its note never reaches an anonymous reader', () {
      // `ord >= door_ord` in private.split_at_door. Worth stating: the note is
      // written for someone about to enter, and only they receive it.
      final split = splitAtDoor([
        b('1', 'text'),
        Block(id: '3', type: 'door', data: {'note': 'For whoever finds this.'}),
      ]);

      expect(split.publicBlocks.any((x) => x.type == 'door'), isFalse);
      expect(
        split.publicBlocks.any((x) => x.data.containsValue('For whoever finds this.')),
        isFalse,
      );
    });

    test('a door at the top publishes nothing but the threshold', () {
      final split = splitAtDoor([b('1', 'door'), b('2', 'longtext')]);

      expect(split.publicCount, 0);
      expect(split.gatedCount, 2);
      expect(split.hasDoor, isTrue);
      expect(opensWithADoor([b('1', 'door')]), isTrue);
    });

    test('a door at the very end gates only itself', () {
      final split = splitAtDoor([b('1', 'text'), b('2', 'door')]);

      expect(split.publicCount, 1);
      expect(split.gatedCount, 1);
    });
  });

  group('only the first door counts', () {
    test('a second door does not move the threshold', () {
      // The database forbids two doors (`multiple_doors`), so this document
      // cannot be saved. The split still has to be defined rather than
      // arbitrary, because the preview is shown against unsaved documents.
      final split = splitAtDoor([
        b('1', 'text'),
        b('2', 'door'),
        b('3', 'text'),
        b('4', 'door'),
      ]);

      expect(split.publicCount, 1);
      expect(split.gatedCount, 3);
    });
  });

  test('opensWithADoor is about the first block only', () {
    expect(opensWithADoor([b('1', 'text'), b('2', 'door')]), isFalse);
    expect(opensWithADoor(const []), isFalse);
  });

  test('the split never reorders or drops a block', () {
    final blocks = [
      b('1', 'text'),
      b('2', 'heading'),
      b('3', 'door'),
      b('4', 'image'),
      b('5', 'likes'),
    ];
    final split = splitAtDoor(blocks);

    expect(
      [...split.publicBlocks, ...split.gatedBlocks].map((x) => x.id),
      blocks.map((x) => x.id),
      reason: 'the two halves together are the document',
    );
  });
}
