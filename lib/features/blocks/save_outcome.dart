/// What `save_blocks` answered (SPEC §11, D28).
///
/// The database is the one that knows whether this write was based on the
/// version it still holds. A stale write returns `conflict` with the version
/// that won; the editor then offers *Reload* or *Overwrite* rather than
/// silently keeping one of the two — never a silent loss.
sealed class SaveOutcome {
  const SaveOutcome();

  /// Reads the `jsonb` `save_blocks` returns.
  ///
  /// `{"status":"saved","version":n}` or `{"status":"conflict","version":n}`.
  /// Anything else is treated as a conflict, because the only safe assumption
  /// about an answer this client does not understand is *that it did not save*.
  ///
  /// A `saved` with no positive version counts as one of those. The version to
  /// carry forward is the whole point of the answer — trusting `0` would mean
  /// every later save arrives stale and conflicts forever.
  factory SaveOutcome.fromRpc(Map<String, Object?> json) {
    final version = switch (json['version']) {
      final int value => value,
      final num value => value.toInt(),
      _ => 0,
    };

    if (json['status'] == 'saved' && version > 0) return Saved(version);
    return Conflict(version);
  }
}

/// The document is stored, and the Space is now at [version].
final class Saved extends SaveOutcome {
  const Saved(this.version);
  final int version;
}

/// Someone else wrote first — most likely the same author in another tab. The
/// database still holds [version], which is what the document must be reconciled
/// against.
final class Conflict extends SaveOutcome {
  const Conflict(this.version);
  final int version;
}
