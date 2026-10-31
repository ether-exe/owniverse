import 'dart:typed_data';

/// No picker on a non-web target yet. The media pipeline is web-only because the
/// app is (AGENTS.md); when another platform arrives it gets its own branch here,
/// not a different code path in the editor.
Future<PickedFile?> pickImageFile() async => null;

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
