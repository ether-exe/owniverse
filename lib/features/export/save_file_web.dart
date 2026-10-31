// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
//
// `dart:html` is the only way to hand a browser a download without adding a
// dependency for one button. It is confined to this file, behind the conditional
// import in `save_file.dart`, so nothing else in the app — or any test — touches
// it. If a second web-only need appears, that is the moment to adopt `package:web`
// properly rather than widen this.
import 'dart:html' as html;
import 'dart:convert';

/// Hands the browser a file to save, and returns whether it was handed over.
bool saveTextFile(String name, String contents) {
  try {
    final bytes = const Utf8Encoder().convert(contents);
    final blob = html.Blob([bytes], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..download = name
      ..style.display = 'none';

    html.document.body?.children.add(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);

    return true;
  } catch (_) {
    return false;
  }
}
