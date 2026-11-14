import '../platform/file_probe.dart';
import '../platform/host_platform.dart';

/// Where an adb candidate comes from, in the order adbwifi looks.
enum AdbSource {
  androidHome('ANDROID_HOME'),
  androidSdkRoot('ANDROID_SDK_ROOT'),
  defaultSdk('Android SDK default folder'),
  homebrew('Homebrew'),
  path('PATH');

  const AdbSource(this.label);

  /// A short name to show people.
  final String label;
}

/// A path where adb may be, and why adbwifi looks there.
typedef AdbCandidate = ({String path, AdbSource source});

/// The result of looking for adb.
sealed class AdbLookup {
  const AdbLookup();
}

final class AdbFound extends AdbLookup {
  const AdbFound(this.adb, {this.others = const []});

  /// The adb to use: the first one found, in search order.
  final AdbCandidate adb;

  /// Other adb files found later in the order. Two different adb versions
  /// fight over the adb server, so the doctor checks these.
  final List<AdbCandidate> others;
}

final class AdbNotFound extends AdbLookup {
  const AdbNotFound(this.searched);

  /// Every place that was checked, in order.
  final List<AdbCandidate> searched;
}

/// Finds adb on this computer. Only checks files; it does not run adb.
AdbLookup findAdb(HostPlatform platform, FileProbe files) {
  final candidates = adbCandidates(platform);
  final found = [
    for (final c in candidates)
      if (files.isFile(c.path)) c,
  ];
  return switch (found) {
    [] => AdbNotFound(candidates),
    [final first, ...final rest] => AdbFound(
      first,
      others: List.unmodifiable(rest),
    ),
  };
}

/// Every place adbwifi looks for adb, best first, without duplicates.
///
/// SDK folders come first because Android Studio starts the SDK's adb.
/// Using a different adb version makes the two fight over the server.
List<AdbCandidate> adbCandidates(HostPlatform platform) {
  final paths = platform.paths;
  final adb = platform.isWindows ? 'adb.exe' : 'adb';
  String inSdk(String sdk) => paths.join(sdk, 'platform-tools', adb);

  final all = <AdbCandidate>[
    if (platform.variable('ANDROID_HOME') case final sdk?)
      (path: inSdk(sdk), source: AdbSource.androidHome),
    if (platform.variable('ANDROID_SDK_ROOT') case final sdk?)
      (path: inSdk(sdk), source: AdbSource.androidSdkRoot),
    if (_defaultSdk(platform) case final sdk?)
      (path: inSdk(sdk), source: AdbSource.defaultSdk),
    if (platform.os == HostOs.macos)
      for (final dir in _homebrewBins)
        (path: paths.join(dir, adb), source: AdbSource.homebrew),
    for (final dir in _pathEntries(platform))
      (path: paths.join(dir, adb), source: AdbSource.path),
  ];

  final seen = <String>{};
  final unique = <AdbCandidate>[];
  for (final candidate in all) {
    final normal = paths.normalize(candidate.path);
    // Windows paths ignore case: C:\Sdk and c:\sdk are the same file.
    if (seen.add(platform.isWindows ? normal.toLowerCase() : normal)) {
      unique.add(candidate);
    }
  }
  return List.unmodifiable(unique);
}

/// Apple Silicon first, then Intel Macs.
const _homebrewBins = ['/opt/homebrew/bin', '/usr/local/bin'];

/// The folder Android Studio installs the SDK into on each OS.
String? _defaultSdk(HostPlatform platform) {
  final (base, parts) = switch (platform.os) {
    HostOs.macos => (platform.homeDirectory, ['Library', 'Android', 'sdk']),
    HostOs.linux => (platform.homeDirectory, ['Android', 'Sdk']),
    HostOs.windows => (platform.variable('LOCALAPPDATA'), ['Android', 'Sdk']),
  };
  return base == null ? null : platform.paths.joinAll([base, ...parts]);
}

/// The absolute folders listed in PATH.
///
/// Empty and relative entries (such as `.`) are skipped on purpose: they
/// point at the current folder, where a planted `adb` could be waiting.
Iterable<String> _pathEntries(HostPlatform platform) sync* {
  final value = platform.variable('PATH');
  if (value == null) return;
  for (final raw in value.split(platform.pathListSeparator)) {
    // Windows allows quoted entries, such as "C:\Program Files\x".
    final dir = platform.isWindows ? raw.replaceAll('"', '').trim() : raw;
    if (platform.paths.isAbsolute(dir)) yield dir;
  }
}
