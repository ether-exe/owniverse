/// One row of `public.spaces`, as the client needs it.
///
/// Three states, not four (D17). Trash is **not** a fourth state: it is
/// `deleted_at` on a row that still exists, and the owner is allowed to read
/// their own trashed rows precisely so that `/trash` can list them (D34). So it
/// is a flag here, and Trash is a separate list rather than a filter value.
class Space {
  const Space({
    required this.id,
    required this.title,
    required this.slug,
    required this.visibility,
    this.publishedAt,
    this.publishedSlug,
    this.publishedTitle,
    this.blocksVersion = 1,
    this.updatedAt,
    this.deletedAt,
    this.purgeAfter,
  });

  final String id;

  /// The working title — what the owner sees now, including unpublishable edits.
  final String title;

  /// The working slug. Changes on every rename until the next publish.
  final String slug;

  /// `private` | `public`. Only `public` plus a snapshot is readable by anyone.
  final String visibility;

  /// The frozen snapshot (D5, D8): set on first publish, never cleared by a
  /// rename. `null` means this Space has never been published.
  final DateTime? publishedAt;
  final String? publishedSlug;
  final String? publishedTitle;

  /// Optimistic lock for autosave (SPEC §11). Carried here so the M3 editor does
  /// not have to re-read the row before its first save.
  final int blocksVersion;

  final DateTime? updatedAt;

  /// Set while the row is in the Trash, cleared by restore (D3, D19).
  final DateTime? deletedAt;

  /// `deleted_at + 30 days`, written by a trigger. Null while not trashed.
  final DateTime? purgeAfter;

  static const String publicVisibility = 'public';

  /// D17, as an enum. `unlisted` is a published snapshot that its owner has
  /// since made private: the URL 404s, the bytes are retained.
  SpaceState get state {
    if (publishedAt == null) return SpaceState.draft;
    return visibility == publicVisibility
        ? SpaceState.published
        : SpaceState.unlisted;
  }

  bool get hasSnapshot => publishedAt != null;
  bool get isTrashed => deletedAt != null;

  /// The slug a reader would type. Frozen at publish, so a renamed-but-not-
  /// republished Space still answers at its old address (D9, DoD 11).
  String get addressSlug => publishedSlug ?? slug;

  /// The title a reader would see, frozen with the slug.
  String get addressTitle => publishedTitle ?? title;

  /// Whole days until this row is purged, rounded up so "1 day" is never shown
  /// as "0 days" on its last afternoon. Only meaningful while [isTrashed].
  int remainingDays(DateTime now) {
    final end = purgeAfter;
    if (end == null) return 30;
    final left = end.difference(now);
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

  /// Every column this client cares about. Kept next to the parser so the two
  /// cannot drift — a missing column here is a `null` field there.
  static const String columns =
      'id, title, slug, visibility, published_at, published_slug, '
      'published_title, blocks_version, updated_at, deleted_at, purge_after';

  /// The owner's row, read directly under `spaces_select_own`.
  factory Space.fromRow(Map<String, dynamic> json) => Space(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    visibility: (json['visibility'] as String?) ?? 'private',
    publishedAt: _date(json['published_at']),
    publishedSlug: json['published_slug'] as String?,
    publishedTitle: json['published_title'] as String?,
    blocksVersion: (json['blocks_version'] as num?)?.toInt() ?? 1,
    updatedAt: _date(json['updated_at']),
    deletedAt: _date(json['deleted_at']),
    purgeAfter: _date(json['purge_after']),
  );

  /// A row of `profile_public` (D24). Already filtered to public-and-published
  /// and already carrying the frozen title and slug, so there is nothing left
  /// to decide: a visitor's Space is always published.
  factory Space.fromPublicMap(Map<String, dynamic> json) => Space(
    id: (json['id'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    visibility: publicVisibility,
    publishedAt: _date(json['published_at']),
    publishedSlug: json['slug'] as String?,
    publishedTitle: json['title'] as String?,
  );

  /// The `jsonb` a write RPC returns. Deliberately partial: create and rename
  /// answer with what changed, not with the whole row, and the caller's list is
  /// invalidated anyway.
  factory Space.fromRpc(Map<String, dynamic> json) => Space(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    slug: (json['slug'] as String?) ?? '',
    visibility: (json['visibility'] as String?) ?? 'private',
    publishedSlug: json['published_slug'] as String?,
    blocksVersion: (json['blocks_version'] as num?)?.toInt() ?? 1,
  );
}

/// The three states of D17, in the order a Space moves through them.
enum SpaceState { draft, published, unlisted }

extension SpaceStateLabel on SpaceState {
  /// Mono, uppercase, 10 px — a chip made of type, not of a badge.
  String get label => switch (this) {
    SpaceState.draft => 'DRAFT',
    SpaceState.published => 'PUBLISHED',
    SpaceState.unlisted => 'UNLISTED',
  };
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
