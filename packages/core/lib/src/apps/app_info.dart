import '../adb/adb.dart';
import '../adb/text.dart';
import '../process/process_runner.dart';
import '../logs/app_process.dart';

/// What `dumpsys package <pkg>` says about an installed app.
final class PackageInfo {
  const PackageInfo({
    this.versionName,
    this.versionCode,
    this.minSdk,
    this.targetSdk,
    this.firstInstall,
    this.lastUpdate,
  });

  final String? versionName;

  /// The build number. A new APK must have a higher one.
  final int? versionCode;
  final int? minSdk;
  final int? targetSdk;

  /// As the device prints it, e.g. `2026-11-05 10:12:01`.
  final String? firstInstall;
  final String? lastUpdate;

  Map<String, Object?> toJson() => {
    'versionName': versionName,
    'versionCode': versionCode,
    'minSdk': minSdk,
    'targetSdk': targetSdk,
    'firstInstall': firstInstall,
    'lastUpdate': lastUpdate,
  };
}

/// Reads the `Package [pkg]` section of `dumpsys package <pkg>`. Null when
/// the app is not installed. Other sections (such as hidden system
/// packages) also have `versionCode=`, so only the first section counts.
PackageInfo? parseDumpsysPackage(Iterable<String> lines, String package) {
  final values = <String, String>{};
  var inSection = false;
  for (final line in lines) {
    if (!inSection) {
      inSection = line.trim().startsWith('Package [$package]');
      continue;
    }
    if (line.trim().startsWith('Package [') ||
        (line.isNotEmpty && !line.startsWith(' '))) {
      break;
    }
    for (final m in _keyValue.allMatches(line)) {
      values.putIfAbsent(m.group(1) ?? '', () => m.group(2) ?? '');
    }
  }
  if (!inSection) return null;
  String? text(String key) =>
      values[key] == null ? null : cleanDeviceText(values[key] ?? '');
  return PackageInfo(
    versionName: text('versionName'),
    versionCode: int.tryParse(values['versionCode'] ?? ''),
    minSdk: int.tryParse(values['minSdk'] ?? ''),
    targetSdk: int.tryParse(values['targetSdk'] ?? ''),
    firstInstall: text('firstInstallTime'),
    lastUpdate: text('lastUpdateTime'),
  );
}

// `versionCode=42 minSdk=19 targetSdk=28`; times contain one space.
final _keyValue = RegExp(
  r'\b(versionName|versionCode|minSdk|targetSdk|firstInstallTime|lastUpdateTime)='
  r'(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d|\S+)',
);

/// The app's memory (total PSS) in KB from `dumpsys meminfo <pid>`.
///
/// Old Android prints `TOTAL  56789 ...` in the table; newer adds
/// `TOTAL: 56789` or `TOTAL PSS: 56789` in the summary. The first one wins.
int? parseMeminfoTotalKb(Iterable<String> lines) {
  for (final line in lines) {
    final m = _total.firstMatch(line.trim());
    if (m != null) return int.tryParse(m.group(1) ?? '');
  }
  return null;
}

final _total = RegExp(r'^TOTAL(?: PSS)?:?\s+(\d+)');

/// Serial devices an app has open, from `ls -l /proc/<pid>/fd`.
sealed class OpenPorts {
  const OpenPorts();
}

final class PortsListed extends OpenPorts {
  const PortsListed(this.ports);

  /// fd number → device path, such as `23 → /dev/ttyS1`.
  final List<({int fd, String path})> ports;
}

/// The shell may not read another app's fds (needs root adb).
final class PortsNotAllowed extends OpenPorts {
  const PortsNotAllowed();
}

/// Reads `ls -l /proc/<pid>/fd` in toolbox and toybox format: each line
/// ends with `<fd> -> <target>`. Keeps only serial devices (`/dev/tty…`).
OpenPorts parseOpenPorts(Iterable<String> lines) {
  final ports = <({int fd, String path})>[];
  for (final line in lines) {
    if (line.toLowerCase().contains('permission denied')) {
      return const PortsNotAllowed();
    }
    final m = _fdLine.firstMatch(line.trim());
    if (m == null) continue;
    final fd = int.tryParse(m.group(1) ?? '');
    final path = m.group(2) ?? '';
    if (fd != null && _serialDevice.hasMatch(path)) {
      ports.add((fd: fd, path: cleanDeviceText(path)));
    }
  }
  return PortsListed(ports);
}

final _fdLine = RegExp(r'(\d+) -> (\S+)$');
final _serialDevice = RegExp(r'^/dev/tty[A-Za-z]*\d+$');

/// Everything `adbwifi app info` shows.
final class AppReport {
  const AppReport({this.package, this.pid, this.memoryKb, this.ports});

  /// Null when the app is not installed.
  final PackageInfo? package;
  final int? pid;
  final int? memoryKb;
  final OpenPorts? ports;
}

/// Reads [package]'s version, PID, memory and open serial ports. Every
/// command is simple and parsed here; the PID comes from our own parser,
/// so it is a number before it goes into `/proc/<pid>/fd`.
Future<AppReport> readAppReport(
  Adb adb,
  String serial,
  String package, {
  required int? sdk,
}) async {
  if (!isValidPackage(package)) {
    throw ArgumentError.value(package, 'package', 'not a package name');
  }
  final dump = await adb.shellLines(serial, ['dumpsys', 'package', package]);
  final info = dump == null ? null : parseDumpsysPackage(dump, package);
  if (info == null) return const AppReport();
  final pid = await findAppPid(adb, serial, package, sdk: sdk);
  if (pid == null) return AppReport(package: info);
  final meminfo = await adb.shellLines(serial, ['dumpsys', 'meminfo', '$pid']);
  // "Permission denied" goes to stderr on Android 7+, so read both.
  final fds = switch (await adb.onDevice(serial, [
    'shell',
    'ls',
    '-l',
    '/proc/$pid/fd',
  ])) {
    ProcessCompleted(:final allLines, :final stderr)
        when !stderr.any(isAdbError) =>
      allLines.toList(),
    _ => null,
  };
  return AppReport(
    package: info,
    pid: pid,
    memoryKb: meminfo == null ? null : parseMeminfoTotalKb(meminfo),
    ports: fds == null ? null : parseOpenPorts(fds),
  );
}
