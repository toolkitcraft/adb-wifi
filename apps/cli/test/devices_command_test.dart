import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late Harness h;
  setUp(() {
    h = Harness()..healthyTablet();
    h.store.book = DeviceBook([
      SavedDevice(
        serial: 'A1B2C3D4E5',
        name: 'tablet',
        lastIp: Ipv4.tryParse('192.168.1.150'),
      ),
      SavedDevice(
        serial: 'K518X',
        name: 'kiosk',
        model: 'K518',
        lastIp: Ipv4.tryParse('192.168.1.60'),
      ),
    ]);
    h.devices([
      '192.168.1.150:5555\toffline',
      '192.168.1.202:5555\tdevice model:YC119R',
      'A1B2C3D4E5\tdevice usb:1-1 model:YC119R',
      '192.168.1.77:5555\tunauthorized',
    ]);
    for (final serial in ['192.168.1.202:5555', 'A1B2C3D4E5']) {
      h.processes.onLines(
        ['-s', serial, 'shell', 'getprop', 'ro.serialno'],
        ['A1B2C3D4E5'],
      );
    }
  });

  test('one line per device, stale entries hidden, saved names shown', () async {
    expect(await h.run(['devices']), ExitCodes.ok);
    final out = h.out.toString();
    expect(
      out,
      contains(
        '🟢  tablet  YC119R  device        wifi 192.168.1.202:5555, usb 1-1  A1B2C3D4E5',
      ),
    );
    expect(
      out,
      contains('🔴  -       -       unauthorized  wifi 192.168.1.77:5555'),
    );
    expect(
      out,
      contains('⚪  kiosk   K518    saved         last 192.168.1.60:5555'),
    );
    expect(out, contains('Hidden: 192.168.1.150:5555 (stale offline)'));
    expect(out, contains('tap Allow'));
  });

  test('--json', () async {
    await h.run(['--json', 'devices']);
    final json = jsonDecode(h.out.toString()) as Map<String, Object?>;
    final first =
        (json['devices'] as List<Object?>).first as Map<String, Object?>;
    expect(first['name'], 'tablet');
    expect(first['hiddenStale'], ['192.168.1.150:5555']);
  });

  test(
    'USB + Wi-Fi of one device is one choice when nothing is given',
    () async {
      h.devices(['192.168.1.202:5555\tdevice', 'A1B2C3D4E5\tdevice usb:1-1']);
      h.input.canAsk = false;
      expect(await h.run(['doctor']), ExitCodes.ok);
      expect(
        h.out.toString(),
        contains('Checking tablet (192.168.1.202:5555)'),
      );
    },
  );
}
