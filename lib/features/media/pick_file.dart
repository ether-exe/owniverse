/// Choosing a file, on the platforms that can.
///
/// Same shape as `export/save_file.dart`: the real implementation is web-only and
/// the stub keeps the VM test binary free of browser libraries.
library;

export 'pick_file_stub.dart'
    if (dart.library.html) 'pick_file_web.dart';
