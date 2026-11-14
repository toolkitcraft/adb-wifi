import '../adb/adb.dart';

/// A Java package name such as `com.example.app`. It is passed to the
/// device's shell, so only this exact shape is allowed (no spaces, quotes
/// or shell characters).
bool isValidPackage(String name) =>
    name.length <= 255 && _package.hasMatch(name);

final _package = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');

/// One row of `ps`.
typedef PsRow = ({int pid, String name});

/// Reads `ps` output in the old (Android 4.4 to 7) and the toybox
/// (Android 8+) format. Both have a header with `PID`, and the process
/// name is the last column. The old format has an extra unnamed state
/// column, so only the PID position and the last column are trusted.
List<PsRow> parsePs(Iterable<String> lines) {
  int? pidColumn;
  final rows = <PsRow>[];
  for (final line in lines) {
    final words = line.trim().split(RegExp(r'\s+'));
    if (words.length < 2) continue;
    if (pidColumn == null) {
      final i = words.indexOf('PID');
      if (i >= 0) pidColumn = i;
      continue;
    }
    if (pidColumn >= words.length) continue;
    final pid = int.tryParse(words[pidColumn]);
    if (pid != null) rows.add((pid: pid, name: words.last));
  }
  return rows;
}

/// The first PID in `pidof` output (`1234` or `1234 5678`). Null when the
/// output is empty or an error such as `pidof: not found`.
int? parsePidof(Iterable<String> lines) {
  for (final line in lines) {
    final words = line.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) continue;
    return words.every((w) => int.tryParse(w) != null)
        ? int.parse(words.first)
        : null;
  }
  return null;
}

/// Finds the PID of [package]'s main process on the device.
///
/// Android 7+ (SDK 24+) has `pidof`. Older devices (such as Android 4.4)
/// do not, so `ps` is read and searched here, on the computer. Android 8+
/// `ps` lists only the shell's own processes without `-A`.
Future<int?> findAppPid(
  Adb adb,
  String serial,
  String package, {
  required int? sdk,
}) async {
  if (!isValidPackage(package)) {
    throw ArgumentError.value(package, 'package', 'not a package name');
  }
  if ((sdk ?? 0) >= 24) {
    final pidof = await adb.shellLines(serial, ['pidof', package]);
    if (pidof == null) return null;
    // No output: not running. Other text: no pidof on this ROM, use ps.
    if (pidof.every((l) => l.trim().isEmpty)) return null;
    final pid = parsePidof(pidof);
    if (pid != null) return pid;
  }
  final ps = await adb.shellLines(serial, ['ps', if ((sdk ?? 0) >= 26) '-A']);
  if (ps == null) return null;
  return parsePs(ps).where((r) => r.name == package).firstOrNull?.pid;
}
