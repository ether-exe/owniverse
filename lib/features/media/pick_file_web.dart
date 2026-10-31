// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
//
// Confined, and for the same reason as `save_file_web.dart`: no dependency for
// one button. See that file's note.
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens the browser's file chooser and resolves to the chosen image, or null if
/// the author backed out. Anything that is not an image the spec accepts is
/// refused here, before it costs an upload.
Future<PickedFile?> pickImageFile() async {
  final completer = Completer<PickedFile?>();

  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/webp,image/gif'
    ..style.display = 'none';

  html.document.body?.children.add(input);

  void finish(PickedFile? value) {
    input.remove();
    if (!completer.isCompleted) completer.complete(value);
  }

  input.onChange.listen((_) {
    final file = input.files?.isEmpty == false ? input.files!.first : null;
    if (file == null) {
      finish(null);
      return;
    }

    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is! ByteBuffer) {
        finish(null);
        return;
      }
      finish(
        PickedFile(
          bytes: Uint8List.view(result),
          mime: file.type.isEmpty ? 'application/octet-stream' : file.type,
          name: file.name,
        ),
      );
    });
    reader.onError.listen((_) => finish(null));
    reader.readAsArrayBuffer(file);
  });

  input.click();
  return completer.future;
}

/// What the picker hands back: the bytes, the declared type, and a name to take
/// an extension from.
class PickedFile {
  const PickedFile({
    required this.bytes,
    required this.mime,
    required this.name,
  });

  final Uint8List bytes;
  final String mime;
  final String name;
}
