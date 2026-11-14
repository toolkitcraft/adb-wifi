import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:args/command_runner.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../session.dart';

/// `adbwifi app ...`: commands about one installed app.
class AppCommand extends Command<int> {
  AppCommand(SessionHolder holder) {
    addSubcommand(AppInfoCommand(holder));
  }

  @override
  final name = 'app';

  @override
  final description = 'Commands about one app (see "adbwifi app info").';
}

/// `adbwifi app info <package>`: version, PID, memory, serial ports.
class AppInfoCommand extends AdbWifiCommand {
  AppInfoCommand(super.holder);

  @override
  final name = 'info';

  @override
  final description =
      'Show an app\'s version, whether it runs (PID), its memory and the '
      'serial ports it has open.';

  @override
  String get invocation => 'adbwifi app info <package>';

  @override
  Future<int> run() async {
    final package = requiredArgument('package');
    if (!isValidPackage(package)) {
      throw UsageException('"$package" is not a package name.', usage);
    }
    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    final sdk = await session.sdkOf(adb, target.adbSerial);
    final report = await readAppReport(
      adb,
      target.adbSerial,
      package,
      sdk: sdk,
    );
    final info = report.package;

    if (console.json) {
      console.printJson({
        'package': package,
        'device': target.adbSerial,
        'installed': info != null,
        'version': info?.toJson(),
        'pid': report.pid,
        'memoryKb': report.memoryKb,
        'serialPorts': switch (report.ports) {
          PortsListed(:final ports) => [
            for (final port in ports) {'fd': port.fd, 'path': port.path},
          ],
          PortsNotAllowed() => 'not allowed',
          null => null,
        },
      });
      return info == null ? ExitCodes.failure : ExitCodes.ok;
    }
    if (info == null) {
      throw CliFailure(
        '$package is not installed on ${target.label}.',
        fix: 'Install it: adbwifi install app.apk',
      );
    }
    console
      ..line('$package on ${target.label}')
      ..info(
        'version:   ${info.versionName ?? '-'} (build ${info.versionCode ?? '-'})',
      )
      ..info(
        'sdk:       min ${info.minSdk ?? '-'}, target ${info.targetSdk ?? '-'}',
      )
      ..info(
        'installed: ${info.firstInstall ?? '-'}, updated ${info.lastUpdate ?? '-'}',
      );
    final pid = report.pid;
    if (pid == null) {
      console.warn('Not running.');
      return ExitCodes.ok;
    }
    console.ok('Running, PID $pid');
    if (report.memoryKb case final kb?) {
      console.info('memory:    ${(kb / 1024).toStringAsFixed(1)} MB (PSS)');
    }
    switch (report.ports) {
      case PortsListed(ports: []):
        console.info('serial ports: none open');
      case PortsListed(:final ports):
        console.info(
          'serial ports: ${[for (final port in ports) '${port.path} (fd ${port.fd})'].join(', ')}',
        );
      case PortsNotAllowed():
        console.info('serial ports: not allowed to look (needs root adb)');
      case null:
        break;
    }
    return ExitCodes.ok;
  }
}
