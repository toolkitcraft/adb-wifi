import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../session.dart';
import '../table.dart';

/// `adbwifi devices`: one line per device, with saved names.
class DevicesCommand extends AdbWifiCommand {
  DevicesCommand(super.holder);

  @override
  final name = 'devices';

  @override
  final description =
      'List devices: one line per device (USB and Wi-Fi merged), stale '
      'offline entries hidden, saved names shown.';

  @override
  Future<int> run() async {
    final adb = session.requireAdb();
    final book = await session.loadBook();
    final entries = await listDeviceEntries(
      adb,
      await session.connectedDevices(adb),
      book,
    );

    if (console.json) {
      console.printJson({
        'devices': [
          for (final e in entries)
            {
              'serial': e.key,
              'name': e.saved?.name,
              'model': e.model,
              'state': e.state?.name ?? 'saved',
              'connections': [
                for (final c in e.connections)
                  {'serial': c.serial, 'state': c.state.name, 'usb': c.usb},
              ],
              'hiddenStale': [for (final c in e.hiddenStale) c.serial],
            },
        ],
      });
      return ExitCodes.ok;
    }
    if (entries.isEmpty) {
      console
        ..line('No devices connected or saved.')
        ..fix('Find devices on your network: adbwifi find');
      return ExitCodes.ok;
    }
    console.line(
      table(
        ['', 'NAME', 'MODEL', 'STATE', 'CONNECTIONS', 'SERIAL'],
        [
          for (final e in entries)
            [
              _icon(e.state),
              e.saved?.name ?? '-',
              e.model ?? '-',
              e.state?.name ?? 'saved',
              _connections(e),
              e.key,
            ],
        ],
      ),
    );
    _hints(entries);
    return ExitCodes.ok;
  }

  void _hints(List<DeviceEntry> entries) {
    final stale = [for (final e in entries) ...e.hiddenStale];
    final states = {for (final e in entries) e.state};
    if (stale.isNotEmpty || states.any((s) => s != DeviceState.device)) {
      console.line();
    }
    if (stale.isNotEmpty) {
      console.info(
        'Hidden: ${stale.map((d) => d.serial).join(', ')} (stale offline). '
        'Remove with: adbwifi disconnect ${stale.first.serial}',
      );
    }
    if (states.contains(DeviceState.unauthorized)) {
      console.fix(
        '🔴 unauthorized: tap Allow on the device (tick "Always allow").',
      );
    }
    if (states.contains(DeviceState.offline)) {
      console.fix(
        '🟡 offline: run adbwifi connect <device> --wait, and turn USB '
        'debugging off and on, on the device.',
      );
    }
    if (states.contains(null)) {
      console.fix('⚪ saved: not connected now. Run adbwifi connect <name>.');
    }
  }

  static String _icon(DeviceState? state) => switch (state) {
    DeviceState.device => '🟢',
    DeviceState.offline => '🟡',
    DeviceState.unauthorized || DeviceState.noPermissions => '🔴',
    DeviceState.other => '🟠',
    null => '⚪',
  };

  static String _connections(DeviceEntry e) {
    if (e.connections.isEmpty) return 'last ${e.saved?.lastAddress ?? '-'}';
    return [
      for (final c in e.connections)
        c.isNetwork ? 'wifi ${c.serial}' : 'usb ${c.usb ?? c.serial}',
    ].join(', ');
  }
}
