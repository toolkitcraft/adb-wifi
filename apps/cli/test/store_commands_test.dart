import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

final saved = SavedDevice(
  serial: 'A1B2C3D4E5',
  model: 'YC119R',
  lastIp: tabletIp,
  lastSeen: DateTime.utc(2026, 11, 12, 10),
);

void main() {
  late Harness h;
  setUp(() => h = Harness()..healthyTablet());

  group('name', () {
    test('names a saved device', () async {
      h.store.book = DeviceBook([saved]);
      expect(await h.run(['name', '192.168.1.202', 'tablet']), ExitCodes.ok);
      expect(h.store.book.byName('tablet')?.serial, 'A1B2C3D4E5');
      expect(h.out.toString(), contains('✅ YC119R is now "tablet".'));
    });

    test('a new device: connects, reads its serial and saves it', () async {
      expect(await h.run(['name', '192.168.1.202', 'tablet']), ExitCodes.ok);
      final device = h.store.book.byName('tablet');
      expect(device?.serial, 'A1B2C3D4E5');
      expect(device?.lastAddress, tablet);
      expect(h.calls, anyElement(equals(['connect', '192.168.1.202:5555'])));
    });

    test('bad names are usage errors', () async {
      for (final bad in ['2fast', '192.168.1.9', 'a b', r'$(reboot)']) {
        expect(
          await h.run(['name', '192.168.1.202', bad]),
          ExitCodes.usage,
          reason: bad,
        );
      }
      expect(await h.run(['name', 'onlyone']), ExitCodes.usage);
    });

    test('a name used by another device is refused', () async {
      h.store.book = DeviceBook([
        saved,
        const SavedDevice(serial: 'OTHER', name: 'tablet', model: 'K518'),
      ]);
      expect(
        await h.run(['name', '192.168.1.202', 'tablet']),
        ExitCodes.failure,
      );
      expect(h.err.toString(), contains('already the name of K518'));
    });
  });

  group('forget', () {
    test('by name, serial or IP; the device is not touched', () async {
      for (final query in ['tablet', 'A1B2C3D4E5', '192.168.1.202']) {
        h.store.book = DeviceBook([saved.copyWith(name: 'tablet')]);
        expect(await h.run(['forget', query]), ExitCodes.ok, reason: query);
        expect(h.store.book.isEmpty, isTrue);
      }
      expect(h.calls, isEmpty);
    });

    test('unknown device', () async {
      expect(await h.run(['forget', 'kiosk']), ExitCodes.failure);
      expect(h.err.toString(), contains('No saved device called "kiosk"'));
    });
  });

  group('info', () {
    test('lists saved devices without calling adb', () async {
      h.store.book = DeviceBook([saved.copyWith(name: 'tablet')]);
      expect(await h.run(['info']), ExitCodes.ok);
      expect(
        h.out.toString(),
        contains('NAME    MODEL   LAST IP             LAST SEEN'),
      );
      expect(h.out.toString(), contains('tablet  YC119R  192.168.1.202:5555'));
      expect(h.calls, isEmpty);
    });

    test('no saved devices', () async {
      await h.run(['info']);
      expect(h.out.toString(), contains('No saved devices.'));
    });

    test('one connected device: saved data and live details', () async {
      h.store.book = DeviceBook([saved.copyWith(name: 'tablet')]);
      expect(await h.run(['info', 'tablet']), ExitCodes.ok);
      final out = h.out.toString();
      expect(out, startsWith('tablet (192.168.1.202:5555)'));
      expect(out, contains('serial:    A1B2C3D4E5'));
      expect(out, contains('✅ YC119R · Android 7.1.2'));
    });

    test('not connected: says how to connect', () async {
      h.store.book = DeviceBook([saved.copyWith(name: 'tablet')]);
      h.devices([]);
      await h.run(['info', 'tablet']);
      expect(h.out.toString(), contains('⚠️  Not connected now.'));
      expect(
        h.calls,
        isNot(anyElement(equals(['connect', '192.168.1.202:5555']))),
      );
    });

    test('--json', () async {
      h.store.book = DeviceBook([saved]);
      await h.run(['--json', 'info']);
      final json = jsonDecode(h.out.toString()) as Map<String, Object?>;
      expect(
        (json['devices'] as List<Object?>).single,
        containsPair('serial', 'A1B2C3D4E5'),
      );
    });
  });

  test('a broken store file stops with a clear fix', () async {
    h.store.brokenReason = 'it is not valid JSON';
    expect(await h.run(['info']), ExitCodes.failure);
    expect(
      h.err.toString(),
      contains('Cannot read the saved devices: it is not valid JSON.'),
    );
    expect(h.err.toString(), contains('adbwifi never overwrites it'));
  });
}
