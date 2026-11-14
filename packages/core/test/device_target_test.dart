import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

final saved = SavedDevice(
  serial: 'A1B2C3D4E5',
  name: 'tablet',
  lastIp: Ipv4.tryParse('192.168.1.202'),
);
final book = DeviceBook([saved]);
const network = AdbDevice(
  serial: '192.168.1.202:5555',
  state: DeviceState.device,
);
const usb = AdbDevice(serial: 'A1B2C3D4E5', state: DeviceState.device);
const other = AdbDevice(
  serial: '192.168.1.77:5555',
  state: DeviceState.offline,
);

DeviceTarget found(TargetResolution r) => (r as TargetFound).target;

void main() {
  test('an IP is used as it is, with port 5555 by default', () {
    final target = found(resolveTarget('192.168.1.50', DeviceBook(), []));
    expect(target.adbSerial, '192.168.1.50:5555');
    expect(target.saved, isNull);
  });

  test('an IP that is saved brings its name', () {
    expect(
      found(resolveTarget('192.168.1.202', book, [])).label,
      'tablet (192.168.1.202:5555)',
    );
  });

  test('a saved name gives its last IP', () {
    expect(
      found(resolveTarget('Tablet', book, [])).adbSerial,
      '192.168.1.202:5555',
    );
  });

  test('a saved device on USB right now uses the USB serial', () {
    expect(found(resolveTarget('tablet', book, [usb])).adbSerial, 'A1B2C3D4E5');
  });

  test('a connected serial', () {
    expect(
      found(resolveTarget('192.168.1.77:5555', book, [other])).adbSerial,
      '192.168.1.77:5555',
    );
    const emulator = AdbDevice(
      serial: 'emulator-5554',
      state: DeviceState.device,
    );
    expect(
      found(resolveTarget('emulator-5554', book, [emulator])).serial,
      'emulator-5554',
    );
  });

  test('an unknown name', () {
    expect(resolveTarget('kiosk', book, [network]), isA<UnknownTarget>());
  });

  group('nothing given', () {
    test('the only connected device', () {
      expect(found(resolveTarget(null, book, [network])).saved, same(saved));
    });

    test('several connected: the user chooses', () {
      final r = resolveTarget(null, book, [network, other]) as TargetAmbiguous;
      expect(
        [for (final c in r.choices) c.adbSerial],
        ['192.168.1.202:5555', '192.168.1.77:5555'],
      );
    });

    test('none connected: the only saved device', () {
      expect(
        found(resolveTarget(null, book, [])).adbSerial,
        '192.168.1.202:5555',
      );
    });

    test('none connected, none saved', () {
      expect(resolveTarget(null, DeviceBook(), []), isA<NoTarget>());
    });
  });
}
