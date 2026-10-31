import 'dart:math';

/// One block of a Space's document (SPEC §8).
///
/// Shape: `{ id, type, v, data }`. Order is array order — no fractional indices,
/// no reindexing (PLAN, the blocks decision).
///
/// `type` stays a **String** rather than becoming an enum. A document written by
/// a newer client must survive being opened by this one: if an unknown type were
/// parsed into nothing, the first save would silently delete a block its author
/// can see. Instead the unknown block is carried through untouched and rendered
/// as a quiet placeholder — never a crash, never a deletion.
class Block {
  const Block({
    required this.id,
    required this.type,
    this.data = const {},
    this.v = 1,
  });

  final String id;

  /// Raw type, preserved even when [kind] is null.
  final String type;

  final Map<String, Object?> data;

  /// Schema version of the block. `1` is the only one this client writes.
  final int v;

  /// The schema version this client understands.
  static const int schemaVersion = 1;

  /// The nine types of SPEC §8, or null for one this client does not know.
  BlockType? get kind => BlockType.tryParse(type);

  /// False for an unknown type or a newer schema — the case that renders the
  /// placeholder and is excluded from editing, not from the document.
  bool get isRenderable => kind != null && v <= schemaVersion;

  /// `text` and `longtext` carry their content here; `heading` carries it too.
  String get text => switch (data['text']) {
    final String value => value,
    _ => '',
  };

  /// `heading` only. Anything else reads as 1, which the database accepts.
  int get level => switch (data['level']) {
    final int value => value,
    final num value => value.toInt(),
    _ => 1,
  };

  /// `image` and `cover` point at a row in `media`.
  String? get mediaId => switch (data['media_id']) {
    final String value when value.isNotEmpty => value,
    _ => null,
  };

  /// `image` requires this. The database refuses the save without it.
  String get alt => switch (data['alt']) {
    final String value => value,
    _ => '',
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'v': v,
    'data': data,
  };

  /// Tolerant on purpose. A malformed block is carried, not dropped, because
  /// dropping it is the one outcome the author cannot undo from this screen.
  factory Block.fromJson(Map<String, Object?> json) {
    final data = json['data'];

    return Block(
      id: switch (json['id']) {
        final String value when value.isNotEmpty => value,
        _ => newBlockId(),
      },
      type: switch (json['type']) {
        final String value => value,
        _ => '',
      },
      data: data is Map ? Map<String, Object?>.from(data) : const {},
      v: switch (json['v']) {
        final int value => value,
        final num value => value.toInt(),
        _ => schemaVersion,
      },
    );
  }

  /// A new block of [type] with the smallest valid payload.
  ///
  /// `heading` starts at level 1 and `image` starts with an empty `alt`, which
  /// the database will refuse until someone writes one. That refusal is the
  /// point: alt text is a gate, not a suggestion (SPEC §8, DoD 7).
  factory Block.blank(BlockType type) => Block(
    id: newBlockId(),
    type: type.name,
    data: switch (type) {
      BlockType.text || BlockType.longtext => {'text': ''},
      BlockType.heading => {'text': '', 'level': 1},
      BlockType.cover => {'media_id': ''},
      BlockType.image => {'media_id': '', 'alt': ''},
      BlockType.profile => {'show_email': false},
      BlockType.door => {'note': ''},
      BlockType.readers || BlockType.likes => const {},
    },
  );

  Block withData(Map<String, Object?> next) =>
      Block(id: id, type: type, data: next, v: v);

  /// Copies with one key of `data` replaced — the editor's most common write.
  Block withField(String key, Object? value) =>
      withData({...data, key: value});
}

/// The nine block types of SPEC §8, in the order the picker offers them.
///
/// `door`, `readers` and `likes` are the three that make the product, and the
/// three a generic block editor has no reason to invent.
enum BlockType {
  text,
  heading,
  longtext,
  cover,
  image,
  profile,
  door,
  readers,
  likes;

  static BlockType? tryParse(String name) => switch (name) {
    'text' => BlockType.text,
    'heading' => BlockType.heading,
    'longtext' => BlockType.longtext,
    'cover' => BlockType.cover,
    'image' => BlockType.image,
    'profile' => BlockType.profile,
    'door' => BlockType.door,
    'readers' => BlockType.readers,
    'likes' => BlockType.likes,
    _ => null,
  };

  /// What the picker says. Sentence case, no verbs — the block is named, the
  /// action is implied by the panel being open.
  String get label => switch (this) {
    BlockType.text => 'Text',
    BlockType.heading => 'Heading',
    BlockType.longtext => 'Long text',
    BlockType.cover => 'Cover',
    BlockType.image => 'Image',
    BlockType.profile => 'Profile card',
    BlockType.door => 'Door',
    BlockType.readers => 'Readers',
    BlockType.likes => 'Likes',
  };

  /// One line of explanation in the picker. The door's is the only one that
  /// changes the shape of the page, so it is the only one that says so.
  String get hint => switch (this) {
    BlockType.text => 'A paragraph.',
    BlockType.heading => 'A title inside the page.',
    BlockType.longtext => 'A longer passage, set narrower.',
    BlockType.cover => 'A wide image at the top.',
    BlockType.image => 'An image with alt text.',
    BlockType.profile => 'You, as the author.',
    BlockType.door => 'Everything after this is for people who enter.',
    BlockType.readers => 'How many people have entered.',
    BlockType.likes => 'A count, and a way to add one.',
  };

  /// The six content types, which need no explanation to place. The other
  /// three are grouped apart in the picker because they change what the page
  /// *does*, not just what it says.
  bool get isContent =>
      this != BlockType.door &&
      this != BlockType.readers &&
      this != BlockType.likes;
}

/// A v4-shaped id, generated locally.
///
/// There is no `uuid` dependency for one function, and the only requirement is
/// uniqueness inside a single document — the database treats it as opaque text.
String newBlockId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));

  // Version 4, variant 1, as the shape promises.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Parses what the database sends back, whatever it is.
List<Block> blocksFromJson(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) Block.fromJson(Map<String, Object?>.from(item)),
  ];
}

List<Map<String, Object?>> blocksToJson(List<Block> blocks) => [
  for (final block in blocks) block.toJson(),
];
