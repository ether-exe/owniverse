/// D18: a title becomes an address.
///
/// `spaces.slug` is checked by the database against
/// `^[a-z0-9]+(?:-[a-z0-9]+)*$`, 2–60 characters. Titles are 2–80. This is the
/// one place those two shapes meet, so it is the one place that can be wrong in
/// a way a person notices: they typed a title, they did not type an address.
///
/// Everything here is pure and web-safe: no regular expression on user text
/// apart from collapsing and trimming, and no integer arithmetic that would
/// lose precision on JavaScript numbers.
library;

/// Shortest and longest slug the database will accept (SPEC §6.2).
const int minSlugLength = 2;
const int maxSlugLength = 60;

/// Latin letters that `slugify` folds rather than drops. A title is allowed to
/// be `Café`, and the address it produces should still be readable.
const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ă': 'a', 'ą': 'a', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
  'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i',
  'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o',
  'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', 'ř': 'r', 'ś': 's',
  'š': 's', 'ş': 's', 'ť': 't', 'ţ': 't', 'ù': 'u', 'ú': 'u', 'û': 'u',
  'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ý': 'y', 'ÿ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z',
  'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'þ': 'th', 'ð': 'd', 'ı': 'i',
};

/// A valid slug for [title], always. Never null, never empty, never longer
/// than 60 or shorter than 2 — the caller does not have to validate it before
/// handing it to `create_space`.
///
/// A title with no Latin letters in it (`東京`) still needs an address that is
/// stable and distinct from every other title, so it folds to
/// `page-<base36 hash>` rather than to a shared placeholder. Two different
/// titles must never collapse onto one slug by accident; if the *same* title is
/// used twice, `slug_taken` is the correct answer and the database gives it.
String slugify(String title) {
  final buffer = StringBuffer();

  for (final rune in title.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _fold[char];
    if (folded != null) {
      buffer.write(folded);
    } else if (_isAlphanumeric(rune)) {
      buffer.write(char);
    } else {
      buffer.write('-');
    }
  }

  var slug = buffer
      .toString()
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  if (slug.length > maxSlugLength) {
    // Cut, then strip the dash the cut may have exposed. Cutting mid-word is
    // uglier than cutting at a boundary but predictable; a boundary search here
    // would silently shorten a long title to its first word.
    slug = slug
        .substring(0, maxSlugLength)
        .replaceAll(RegExp(r'-+$'), '');
  }

  if (slug.length < minSlugLength) {
    slug = 'page-${_suffix(title)}';
  }

  return slug;
}

bool _isAlphanumeric(int rune) =>
    (rune >= 0x61 && rune <= 0x7a) || (rune >= 0x30 && rune <= 0x39);

/// djb2, masked to 32 bits. Deliberately not FNV-1a: its 32×32 multiply exceeds
/// 2^53 and would give a different answer in a browser than in a VM, so a slug
/// derived on web would not match one derived in a test.
String _suffix(String title) {
  var hash = 5381;
  for (final rune in title.runes) {
    hash = ((hash << 5) + hash + rune) & 0xFFFFFFFF;
  }
  return hash.toRadixString(36).padLeft(7, '0');
}
