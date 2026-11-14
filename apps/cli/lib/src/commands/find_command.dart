import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';
import '../table.dart';

/// `adbwifi find`: scans this computer's /24 for adb on port 5555, after
/// the user agrees.
class FindCommand extends AdbWifiCommand {
  FindCommand(super.holder) {
    argParser
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Scan without asking first.',
      )
      ..addOption(
        'interface',
        valueHelp: 'name',
        help: 'The network adapter to scan from, such as en0 or Wi-Fi.',
      );
  }

  @override
  final name = 'find';

  @override
  final description =
      'Find Android devices with network adb on this computer\'s local '
      'network (asks before it scans).';

  @override
  Future<int> run() async {
    final adb = session.requireAdb();
    final mine = await session.chooseNetwork(
      adapter: argResults?.option('interface'),
    );
    final subnet = mine.ip.subnet24;
    if (!(argResults?.flag('yes') ?? false) &&
        !session.confirm(
          'Scan $subnet (254 addresses, port 5555) from ${mine.adapter}? '
          'It only talks to your own network.',
        )) {
      throw CliFailure(
        'Not scanned.',
        fix:
            'Run "adbwifi find --yes" to scan, or give the IP: '
            'adbwifi doctor <ip>',
      );
    }

    if (!console.json) console.line('Scanning $subnet ...');
    final scan = await scanSubnet24(mine.ip, session.environment.probe);
    final found = await identifyDevices(adb, scan.open);
    for (final device in found) {
      if (device.info case final info?) {
        await session.remember(info, device.address);
      }
    }

    if (console.json) {
      console.printJson({
        'subnet': subnet,
        'from': '${mine.adapter} ${mine.ip}',
        'seconds': scan.elapsed.inMilliseconds / 1000,
        'refused': scan.refused,
        'noAnswer': scan.noAnswer,
        'devices': [
          for (final d in found)
            {
              'address': d.address.serial,
              'state': d.state?.name,
              'info': d.info?.toJson(),
            },
        ],
      });
      return found.isEmpty ? ExitCodes.failure : ExitCodes.ok;
    }
    _print(scan, found);
    return found.isEmpty ? ExitCodes.failure : ExitCodes.ok;
  }

  void _print(ScanResult scan, List<FoundDevice> found) {
    final seconds = (scan.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    if (found.isEmpty) {
      console.fail('No adb devices on ${scan.subnet} (took $seconds s).');
      if (scan.nothingAnswered) {
        console.warn(
          'Nothing on this network answered at all. A guest Wi-Fi often '
          'hides devices from each other (AP isolation).',
        );
      }
      console.fix(
        'On the device, turn on USB debugging (and ADB over network). If '
        'it is on another network, give its IP: adbwifi doctor <ip>',
      );
      return;
    }
    final n = found.length;
    console
      ..ok(
        'Found $n device${n == 1 ? '' : 's'} on ${scan.subnet} '
        '(took $seconds s):',
      )
      ..line()
      ..line(
        table(
          ['ADDRESS', 'STATE', 'MODEL', 'ANDROID', 'BUILD', 'ROOT', 'SERIAL'],
          [
            for (final d in found)
              [
                d.address.serial,
                d.state?.name ?? 'not adb',
                d.info?.model ?? '-',
                d.info?.androidVersion ?? '-',
                d.info?.buildType ?? '-',
                switch (d.info?.isRoot) {
                  true => 'YES',
                  false => 'no',
                  null => '-',
                },
                d.info?.serialNumber ?? '-',
              ],
          ],
        ),
      )
      ..line();
    if (found.any((d) => d.info?.isRoot == true)) {
      console
        ..danger(rootWarning)
        ..fix(rootFix);
    }
    if (found.any((d) => d.state == DeviceState.unauthorized)) {
      console.fix(explain(const Unauthorized(), session.platform.os).fix);
    }
    final saved = found.where((d) => d.info?.serialNumber != null);
    if (saved.isNotEmpty) {
      console.fix(
        'Saved. Give it a name: adbwifi name ${saved.first.address.ip} tablet',
      );
    }
  }
}
