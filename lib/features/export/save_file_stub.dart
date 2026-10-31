/// The VM has no browser to hand a file to.
///
/// Returns false rather than throwing: a caller in a test or on another platform
/// should be told the download did not happen, not crashed.
bool saveTextFile(String name, String contents) => false;
