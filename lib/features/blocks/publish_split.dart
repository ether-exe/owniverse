import 'block.dart';

/// The document cut in two at the first door (D22, D33).
///
/// Mirrors `private.split_at_door` exactly, because the editor has to *show* the
/// author what publishing will do before they do it. The database performs the
/// real split from its own copy of the document — the client never sends this
/// result anywhere, which is why a crafted request cannot choose what goes
/// public.
class PublishSplit {
  const PublishSplit({required this.publicBlocks, required this.gatedBlocks});

  /// Everything above the door. This is the entire anonymous payload.
  final List<Block> publicBlocks;

  /// The door and everything after it. Absent from every anonymous response.
  final List<Block> gatedBlocks;

  bool get hasDoor => gatedBlocks.isNotEmpty;
  int get publicCount => publicBlocks.length;
  int get gatedCount => gatedBlocks.length;
  int get total => publicCount + gatedCount;
}

/// Splits at the **first** door, matching the database.
///
/// The door block itself lands in [PublishSplit.gatedBlocks] — `ord >= door_ord`
/// in the SQL. That is deliberate and worth remembering: an anonymous reader
/// does not receive the door's own `note`, so the note can say something only a
/// person who is about to enter should read.
PublishSplit splitAtDoor(List<Block> blocks) {
  final doorAt = blocks.indexWhere((block) => block.type == 'door');

  if (doorAt < 0) {
    return PublishSplit(
      publicBlocks: List.unmodifiable(blocks),
      gatedBlocks: const [],
    );
  }

  return PublishSplit(
    publicBlocks: List.unmodifiable(blocks.sublist(0, doorAt)),
    gatedBlocks: List.unmodifiable(blocks.sublist(doorAt)),
  );
}

/// True when this document would publish an empty threshold: a door with
/// nothing above it. Legal, and probably not what the author meant.
bool opensWithADoor(List<Block> blocks) =>
    blocks.isNotEmpty && blocks.first.type == 'door';
