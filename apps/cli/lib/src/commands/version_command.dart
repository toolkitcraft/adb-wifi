import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../messages.dart';
import '../version.dart';

/// `adbwifi version`: the tool version, and which adb it uses.
class VersionCommand extends AdbWifiCommand {
  VersionCommand(super.holder);

  @override
  final name = 'version';

  @override
  final description = 'Show the adbwifi version and which adb it uses.';

  @override
  Future<int> run() async {
    final lookup = session.lookupAdb();
    final adbInfo = switch (lookup) {
      AdbFound(:final adb, :final others) => (
        adb: adb,
        others: others,
        version: await _readVersion(adb.path),
      ),
      AdbNotFound() => null,
    };

    if (console.json) {
      console.printJson({
        'adbwifi': toolVersion,
        'adb': switch (adbInfo) {
          null => null,
          final i => {
            'path': i.adb.path,
            'source': i.adb.source.name,
            'version': i.version?.release ?? i.version?.protocol,
            'protocol': i.version?.protocol,
            'others': [for (final o in i.others) o.path],
          },
        },
      });
      return ExitCodes.ok;
    }

    console.line('adbwifi $toolVersion');
    switch (adbInfo) {
      case null:
        console
          ..fail('adb not found.')
          ..fix(installAdbHelp(session.platform.os));
      case final i:
        final version = i.version?.toString() ?? '(version unknown)';
        console.line('adb $version');
        console.info('${i.adb.path}  (${i.adb.source.label})');
        for (final other in i.others) {
          console.info('also found: ${other.path}  (${other.source.label})');
        }
    }
    // The version was shown either way; `adbwifi doctor` is the health check.
    return ExitCodes.ok;
  }

  Future<AdbVersion?> _readVersion(String path) async {
    final outcome = await session.processes.run(path, const [
      'version',
    ], timeout: session.options.timeout);
    return switch (outcome) {
      ProcessCompleted(:final stdout) => parseAdbVersion(stdout),
      _ => null,
    };
  }
}
