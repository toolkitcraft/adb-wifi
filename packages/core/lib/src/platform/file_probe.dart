import 'dart:io';

/// Answers questions about local files. A boundary interface, so tests can
/// describe any folder layout.
abstract interface class FileProbe {
  bool isFile(String path);

  /// The size in bytes, or null when [path] is not a readable file.
  int? length(String path);
}

/// Checks the real file system. Follows symlinks, so Homebrew's
/// `/opt/homebrew/bin/adb` link counts as a file.
final class LocalFileProbe implements FileProbe {
  const LocalFileProbe();

  @override
  bool isFile(String path) => FileSystemEntity.isFileSync(path);

  @override
  int? length(String path) {
    try {
      return isFile(path) ? File(path).lengthSync() : null;
    } on FileSystemException {
      return null;
    }
  }
}
