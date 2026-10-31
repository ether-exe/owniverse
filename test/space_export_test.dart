import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:owniverse/features/blocks/block.dart';
import 'package:owniverse/features/export/space_export.dart';
import 'package:owniverse/features/spaces/space.dart';
import 'package:owniverse/features/spaces/spaces_providers.dart';

/// DoD 19: the export is the document, not a summary of it.
void main() {
  final document = SpaceDocument(
    space: Space(
      id: 's1',
      title: 'My Journey',
      slug: 'my-journey',
      visibility: 'public',
      blocksVersion: 7,
      publishedAt: DateTime.utc(2026, 10, 29),
      publishedSlug: 'my-journey',
      publishedTitle: 'My Journey',
    ),
    blocks: const [
      Block(
        id: 'b1',
        type: 'heading',
        data: {'text': 'The Threshold', 'level': 2},
      ),
      Block(id: 'b2', type: 'text', data: {'text': 'A paragraph.'}),
      Block(id: 'b3', type: 'door', data: {'note': 'Only if you mean it.'}),
    ],
  );

  group('the file', () {
    test('is valid JSON with a format marker', () {
      final decoded = jsonDecode(exportDocument(document)) as Map;

      expect(decoded['owniverse'], exportFormat);
      expect(decoded['exported_at'], isA<String>());
    });

    test('carries the blocks exactly as stored, in order', () {
      // Byte-for-byte is the requirement: anything this tidied would come back
      // different. `jsonDecode` of what we wrote must equal what we read.
      final decoded = jsonDecode(exportDocument(document)) as Map;
      final blocks = decoded['blocks'] as List;

      expect(blocks, hasLength(3));
      expect(
        blocks.map((b) => (b as Map)['id']),
        ['b1', 'b2', 'b3'],
        reason: 'array order is the document order',
      );
      expect(blocks[0]['data'], {'text': 'The Threshold', 'level': 2});
      expect(blocks[2]['data'], {'note': 'Only if you mean it.'});
    });

    test('includes the working document and the frozen snapshot separately', () {
      // D8: they are different documents until the next publish, and an export
      // that merged them would lose the fact that they differ.
      final decoded = jsonDecode(exportDocument(document)) as Map;
      final space = decoded['space'] as Map;

      expect(space['title'], 'My Journey');
      expect(space['slug'], 'my-journey');
      expect(space['published_slug'], 'my-journey');
      expect(space['blocks_version'], 7);
      expect(space['visibility'], 'public');
    });

    test('an unknown block type survives the round trip', () {
      // The one case where an export matters most: a document this client only
      // half understands must still leave intact.
      final odd = SpaceDocument(
        space: document.space,
        blocks: const [
          Block(id: 'x', type: 'gallery', data: {'items': 3}),
        ],
      );

      final decoded = jsonDecode(exportDocument(odd)) as Map;
      expect((decoded['blocks'] as List).single, {
        'id': 'x',
        'type': 'gallery',
        'v': 1,
        'data': {'items': 3},
      });
    });

    test('re-reading the export reproduces every block', () {
      final decoded = jsonDecode(exportDocument(document)) as Map;
      final back = blocksFromJson(decoded['blocks']);

      expect(back.map((b) => b.id), document.blocks.map((b) => b.id));
      expect(back.map((b) => b.type), document.blocks.map((b) => b.type));
      expect(back.map((b) => b.data), document.blocks.map((b) => b.data));
    });
  });

  group('the name', () {
    test('is the slug the author already knows', () {
      expect(exportFileName(document), 'my-journey.json');
    });

    test('falls back rather than producing ".json"', () {
      final nameless = SpaceDocument(
        space: const Space(id: 's1', title: 'x', slug: '', visibility: 'private'),
        blocks: const [],
      );
      expect(exportFileName(nameless), 'space.json');
    });
  });
}
