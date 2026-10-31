import 'block.dart';

/// One reason a document cannot be published, in the words the author will read.
class BlockProblem {
  const BlockProblem({
    required this.code,
    required this.message,
    this.blockId,
  });

  /// The database's own identifier, so the two agree about *what* is wrong
  /// even though only one of them is the authority.
  final String code;

  final String message;

  /// Which block to point at, or null for a problem about the document.
  final String? blockId;
}

/// The result of checking a document before it is saved or published.
class DocumentCheck {
  const DocumentCheck({
    this.problems = const [],
    this.countersNeedDoor = false,
  });

  final List<BlockProblem> problems;

  /// SPEC §9: a `readers` or `likes` block with no door above it can never
  /// count anybody. This is a rule, not a dismissible warning — but it does not
  /// block publishing, because a page can legitimately be written before the
  /// door is placed.
  final bool countersNeedDoor;

  bool get canPublish => problems.isEmpty;

  bool get hasNotices => countersNeedDoor;
}

/// The limits `private.validate_blocks` enforces in the database (SPEC §8).
///
/// Duplicated on purpose: this one runs while the author types so nothing is
/// lost to a rejected save, and the database's runs again on every write because
/// a client is not an authority. If the two ever disagree, the database wins and
/// the author sees its refusal — so these numbers must be kept in step with the
/// migration, and `test/block_rules_test.dart` names each one.
const int maxBlocks = 200;
const int maxTextLength = 20000;
const int maxLongTextLength = 60000;
const int maxHeadingLength = 200;

/// Checks a document the way `private.validate_blocks` will.
///
/// Deliberately **not** checked here: whether a `cover` or `image` points at
/// media that belongs to this Space. That needs a query, and ownership is a
/// security boundary — the server answers `media_not_owned` and this function
/// has no business pretending it could.
DocumentCheck checkDocument(List<Block> blocks) {
  final problems = <BlockProblem>[];

  // Same order as the migration, so the first problem reported is the first
  // problem the database would report.
  if (blocks.length > maxBlocks) {
    problems.add(
      const BlockProblem(
        code: 'too_many_blocks',
        message: 'A Space holds two hundred blocks at most.',
      ),
    );
  }

  for (final block in blocks) {
    if (block.type.isEmpty) {
      problems.add(
        BlockProblem(
          code: 'block_shape_invalid',
          message: 'A block is missing its type, so nothing can be done with it.',
          blockId: block.id,
        ),
      );
    }
  }

  final doors = blocks.where((b) => b.type == 'door').toList();
  if (doors.length > 1) {
    problems.add(
      BlockProblem(
        code: 'multiple_doors',
        message:
            'A page has one door. Two would mean two rules about who reads '
            'what, and there is only one.',
        blockId: doors[1].id,
      ),
    );
  }

  for (final block in blocks) {
    switch (block.type) {
      case 'text' when block.text.length > maxTextLength:
        problems.add(
          BlockProblem(
            code: 'text_too_long',
            message: 'A text block holds 20,000 characters. This one is longer.',
            blockId: block.id,
          ),
        );

      case 'longtext' when block.text.length > maxLongTextLength:
        problems.add(
          BlockProblem(
            code: 'longtext_too_long',
            message:
                'A long text block holds 60,000 characters. This one is longer.',
            blockId: block.id,
          ),
        );

      case 'heading'
          when block.text.length > maxHeadingLength ||
              block.level < 1 ||
              block.level > 3:
        problems.add(
          BlockProblem(
            code: 'heading_invalid',
            message:
                'A heading is up to 200 characters, at level 1, 2 or 3.',
            blockId: block.id,
          ),
        );

      case 'image' when block.alt.trim().isEmpty:
        problems.add(
          BlockProblem(
            code: 'image_alt_required',
            message:
                'An image needs alt text. It is how a reader who cannot see '
                'this page still gets it.',
            blockId: block.id,
          ),
        );
    }
  }

  return DocumentCheck(
    problems: problems,
    countersNeedDoor: _countersNeedDoor(blocks),
  );
}

/// SPEC §9. A counter above the door counts nothing, because nobody is ever
/// identified before it — so the editor states the rule where it applies.
bool _countersNeedDoor(List<Block> blocks) {
  final doorAt = blocks.indexWhere((b) => b.type == 'door');
  final firstCounter = blocks.indexWhere(
    (b) => b.type == 'readers' || b.type == 'likes',
  );

  if (firstCounter < 0) return false;

  // No door at all, or a counter placed above the only door.
  return doorAt < 0 || firstCounter < doorAt;
}
