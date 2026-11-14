import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

const wifi = AdbDevice(
  serial: '192.168.1.202:5555',
  state: DeviceState.device,
  model: 'YC119R',
);
const usb = AdbDevice(
  serial: 'A1B2C3D4E5',
  state: DeviceState.device,
  usb: '1-1',
);
const oldIp = AdbDevice(
  serial: '192.168.1.150:5555',
  state: DeviceState.offline,
);
const stranger = AdbDevice(
  serial: '192.168.1.77:5555',
  state: DeviceState.unauthorized,
);

final saved = SavedDevice(
  serial: 'A1B2C3D4E5',
  name: 'tablet',
  lastIp: Ipv4.tryParse('192.168.1.150'),
);

void main() {
  test('USB and Wi-Fi of one device merge; the stale old IP is hidden', () {
    final entries = mergeDevices([
      (device: oldIp, serial: null),
      (device: wifi, serial: 'A1B2C3D4E5'),
      (device: usb, serial: 'A1B2C3D4E5'),
      (device: stranger, serial: null),
    ], DeviceBook([saved]));
    expect(entries, hasLength(2));
    final tablet = entries.first;
    expect(tablet.key, 'A1B2C3D4E5');
    expect(tablet.saved?.name, 'tablet');
    expect(
      [for (final c in tablet.connections) c.serial],
      ['192.168.1.202:5555', 'A1B2C3D4E5'],
    );
    expect(
      [for (final c in tablet.hiddenStale) c.serial],
      ['192.168.1.150:5555'],
    );
    expect(tablet.model, 'YC119R');
    expect(entries.last.key, '192.168.1.77:5555');
    expect(entries.last.state, DeviceState.unauthorized);
  });

  test('an offline device alone is kept, not hidden', () {
    final entries = mergeDevices([
      (device: oldIp, serial: null),
    ], DeviceBook([saved]));
    expect(entries.single.state, DeviceState.offline);
    expect(entries.single.hiddenStale, isEmpty);
  });

  test('saved devices that are not connected come last', () {
    final entries = mergeDevices([
      (device: stranger, serial: null),
    ], DeviceBook([saved]));
    expect(entries.last.key, 'A1B2C3D4E5');
    expect(entries.last.connections, isEmpty);
    expect(entries.last.state, isNull);
  });

  test(
    'listDeviceEntries asks only ready connections for their serial',
    () async {
      final processes = FakeProcessRunner()
        ..onLines(
          ['-s', '192.168.1.202:5555', 'shell', 'getprop', 'ro.serialno'],
          ['A1B2C3D4E5'],
        )
        ..onLines(
          ['-s', 'A1B2C3D4E5', 'shell', 'getprop', 'ro.serialno'],
          ['A1B2C3D4E5\r'],
        );
      final adb = Adb(
        path: 'adb',
        runner: processes,
        timeout: const Duration(seconds: 1),
      );
      final entries = await listDeviceEntries(adb, [
        wifi,
        usb,
        oldIp,
      ], DeviceBook([saved]));
      expect(entries, hasLength(1));
      expect(processes.calls, hasLength(2));
    },
  );
}
