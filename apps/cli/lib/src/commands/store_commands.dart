import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:args/command_runner.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';
import '../table.dart';

/// `adbwifi name <device> <name>`: gives a device a short name.
class NameCommand extends AdbWifiCommand {
  NameCommand(super.holder);

  @override
  final name = 'name';

  @override
  final description = 'Give a device a short name, such as "tablet".';

  @override
  String get invocation => 'adbwifi name <device> <name>';

  @override
  Future<int> run() async {
    final [query, newName] = switch (argResults?.rest) {
      [final a, final b] => [a, b],
      _ => throw UsageException('Give the device and the name.', usage),
    };
    if (!isValidName(newName)) {
      throw UsageException(
        'A name starts with a letter and has up to 32 letters, digits, '
        '".", "_" or "-".',
        usage,
      );
    }
    final adb = session.requireAdb();
    final target = await session.requireTarget(adb, query: query);
    final device = target.saved ?? await _identify(adb, target);

    final book = await session.loadBook();
    final taken = book.byName(newName);
    if (taken != null && taken.serial != device.serial) {
      throw CliFailure(
        '"$newName" is already the name of ${taken.model ?? taken.serial}.',
        fix: 'Choose another name, or run: adbwifi forget $newName',
      );
    }
    final named = (book.bySerial(device.serial) ?? device).copyWith(
      name: newName,
    );
    await session.store.save(book.put(named));
    if (console.json) {
      console.printJson({'ok': true, 'device': named.toJson()});
    } else {
      console.ok('${named.model ?? named.serial} is now "$newName".');
      console.fix('Use it anywhere: adbwifi doctor $newName');
    }
    return ExitCodes.ok;
  }

  /// Reads the serial of a device that is not saved yet.
  Future<SavedDevice> _identify(Adb adb, DeviceTarget target) async {
    if (target.address case final address?) await adbConnect(adb, address);
    final info = await readDeviceInfo(adb, target.adbSerial);
    final serial = info?.serialNumber;
    if (info == null || serial == null || !isValidSerial(serial)) {
      throw CliFailure(
        'Could not read the serial of ${target.adbSerial}.',
        fix: 'Check the connection first: adbwifi doctor ${target.adbSerial}',
      );
    }
    await session.remember(info, target.address);
    return (await session.loadBook()).bySerial(serial) ??
        SavedDevice(serial: serial);
  }
}

/// `adbwifi forget <device>`: deletes a saved device.
class ForgetCommand extends AdbWifiCommand {
  ForgetCommand(super.holder);

  @override
  final name = 'forget';

  @override
  final description =
      'Delete a saved device (only from adbwifi; the device is not touched).';

  @override
  String get invocation => 'adbwifi forget <device>';

  @override
  Future<int> run() async {
    final query = requiredArgument('device');
    final book = await session.loadBook();
    final device =
        book.find(query) ??
        switch (NetworkAddress.tryParse(query)) {
          null => null,
          final address => book.byAddress(address),
        };
    if (device == null) {
      throw CliFailure(
        'No saved device called "$query".',
        fix: 'See the saved devices: adbwifi info',
      );
    }
    await session.store.save(book.remove(device.serial));
    if (console.json) {
      console.printJson({'ok': true, 'forgot': device.serial});
    } else {
      console.ok('Forgot ${device.label} (${device.serial}).');
    }
    return ExitCodes.ok;
  }
}

/// `adbwifi info [device]`: what adbwifi knows about saved devices.
class InfoCommand extends AdbWifiCommand {
  InfoCommand(super.holder);

  @override
  final name = 'info';

  @override
  final description =
      'Show saved devices, or one device with live details when it is '
      'connected.';

  @override
  String get invocation => 'adbwifi info [device]';

  @override
  Future<int> run() async {
    final query = optionalArgument('device') ?? session.options.device;
    if (query == null) return _listSaved();

    final adb = session.requireAdb();
    final target = await session.requireTarget(adb, query: query);
    final serial = target.adbSerial;
    final connected = await session.connectedDevices(adb);
    final online = connected.any(
      (d) => d.serial == serial && d.state == DeviceState.device,
    );
    final live = online ? await readDeviceInfo(adb, serial) : null;
    if (live != null) await session.remember(live, target.address);

    if (console.json) {
      console.printJson({
        'device': serial,
        'saved': target.saved?.toJson(),
        'connected': online,
        'info': live?.toJson(),
      });
      return ExitCodes.ok;
    }
    console.line(target.label);
    if (target.saved case final saved?) {
      console
        ..info('serial:    ${saved.serial}')
        ..info('name:      ${saved.name ?? '-'}')
        ..info('last IP:   ${saved.lastAddress ?? '-'}')
        ..info('last seen: ${_when(saved.lastSeen)}');
    } else {
      console.info('not saved');
    }
    if (live == null) {
      console.warn('Not connected now.');
      console.fix('Connect it: adbwifi connect $query');
    } else {
      console.ok(describeDevice(live));
      if (live.isRoot == true && target.address != null) {
        console
          ..danger(rootWarning)
          ..fix(rootFix);
      }
    }
    return ExitCodes.ok;
  }

  Future<int> _listSaved() async {
    final book = await session.loadBook();
    if (console.json) {
      console.printJson({
        'store': session.store.location,
        'devices': [for (final d in book.devices) d.toJson()],
      });
      return ExitCodes.ok;
    }
    if (book.isEmpty) {
      console
        ..line('No saved devices.')
        ..fix('Find devices on your network: adbwifi find');
      return ExitCodes.ok;
    }
    console
      ..line(
        table(
          ['NAME', 'MODEL', 'LAST IP', 'LAST SEEN', 'SERIAL'],
          [
            for (final d in book.devices)
              [
                d.name ?? '-',
                d.model ?? '-',
                '${d.lastAddress ?? '-'}',
                _when(d.lastSeen),
                d.serial,
              ],
          ],
        ),
      )
      ..line()
      ..info('Saved in ${session.store.location}');
    return ExitCodes.ok;
  }

  String _when(DateTime? time) {
    if (time == null) return '-';
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
