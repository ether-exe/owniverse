import 'dart:convert';

import '../blocks/block.dart';
import '../spaces/spaces_providers.dart';

/// DoD 19: one file that reproduces the document.
///
/// The blocks are written exactly as they are stored — no normalising, no
/// re-ordering, no "helpful" defaults — because the definition of done says
/// re-importing it reproduces the document **byte for byte**. Anything this
/// function tidied up would be a difference on the way back in.
///
/// `owniverse` is a format marker, not a version of the app: it exists so a file
/// from a much later version can be recognised rather than misread.
const int exportFormat = 1;

/// The export, as one JSON string.
String exportDocument(SpaceDocument document) {
  final space = document.space;

  return const JsonEncoder.withIndent('  ').convert({
    'owniverse': exportFormat,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'space': {
      'title': space.title,
      'slug': space.slug,
      'visibility': space.visibility,
      'blocks_version': space.blocksVersion,
      'published_at': space.publishedAt?.toUtc().toIso8601String(),
      'published_slug': space.publishedSlug,
      'published_title': space.publishedTitle,
    },
    'blocks': blocksToJson(document.blocks),
  });
}

/// What the browser should call the file. The slug, because that is what the
/// author already knows the Space by.
String exportFileName(SpaceDocument document) {
  final slug = document.space.slug.trim();
  return slug.isEmpty ? 'space.json' : '$slug.json';
}
