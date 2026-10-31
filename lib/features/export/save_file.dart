/// Saving a file, on the platforms that can.
///
/// Owniverse is web-only (AGENTS.md), so the real implementation is
/// `save_file_web.dart`. The stub exists so that `flutter test` — which runs on
/// the VM — compiles the editor without dragging a browser library into a test
/// binary. That is the whole reason for the conditional import.
library;

export 'save_file_stub.dart'
    if (dart.library.html) 'save_file_web.dart';
