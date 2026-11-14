import 'dart:io' show Platform;

import 'package:path/path.dart' as p;

/// The desktop operating systems adbwifi supports.
enum HostOs { macos, windows, linux }

/// Facts about the computer adbwifi runs on: its OS and environment.
///
/// Logic takes a [HostPlatform] instead of reading `dart:io` [Platform]
/// directly, so tests can describe a Windows or Linux computer on a Mac.
final class HostPlatform {
  const HostPlatform({required this.os, required this.environment});

  /// The computer this program is running on.
  factory HostPlatform.current() =>
      HostPlatform(os: _currentOs(), environment: Platform.environment);

  final HostOs os;

  /// Environment variables. The real Windows map ignores the case of keys;
  /// a test map does not, so tests use the usual spelling (`PATH`).
  final Map<String, String> environment;

  bool get isWindows => os == HostOs.windows;

  /// Joins and normalizes paths in this OS's style (`\` on Windows).
  p.Context get paths =>
      p.Context(style: isWindows ? p.Style.windows : p.Style.posix);

  /// The separator between entries in `PATH`.
  String get pathListSeparator => isWindows ? ';' : ':';

  /// The user's home folder, or null when the environment does not say.
  String? get homeDirectory => variable(isWindows ? 'USERPROFILE' : 'HOME');

  /// The value of environment variable [name], or null if unset or blank.
  String? variable(String name) {
    final value = environment[name]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  static HostOs _currentOs() {
    if (Platform.isMacOS) return HostOs.macos;
    if (Platform.isWindows) return HostOs.windows;
    if (Platform.isLinux) return HostOs.linux;
    throw UnsupportedError(
      'adbwifi runs on macOS, Windows and Linux, '
      'not ${Platform.operatingSystem}.',
    );
  }
}
