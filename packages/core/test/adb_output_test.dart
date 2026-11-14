import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

List<String> fixture(String name) =>
    File('test/fixtures/$name').readAsLinesSync();

void main() {
  group('parseConnect', () {
    test('connected and already connected', () {
      expect(
        parseConnect(['connected to 192.168.1.202:5555']),
        isA<Connected>(),
      );
      final again = parseConnect(['already connected to 192.168.1.202:5555']);
      expect((again as Connected).already, isTrue);
    });

    test('skips adb server start lines', () {
      expect(
        parseConnect([
          '* daemon not running; starting now at tcp:5037',
          '* daemon started successfully',
          'connected to 192.168.1.202:5555',
        ]),
        isA<Connected>(),
      );
    });

    test('refused, in new and old wording', () {
      expect(
        parseConnect([
          "failed to connect to '192.168.1.50:5555': Connection refused",
        ]),
        isA<ConnectRefused>(),
      );
      expect(
        parseConnect([
          'unable to connect to 192.168.1.50:5555: Connection refused',
        ]),
        isA<ConnectRefused>(),
      );
    });

    test('failed to authenticate means unauthorized', () {
      expect(
        parseConnect(['failed to authenticate to 192.168.1.202:5555']),
        isA<ConnectUnauthorized>(),
      );
    });

    test('other failures keep adb\'s words', () {
      final result = parseConnect([
        "failed to connect to '192.168.0.9:5555': No route to host",
      ]);
      expect(
        (result as ConnectFailed).message,
        "failed to connect to '192.168.0.9:5555': No route to host",
      );
      expect(
        (parseConnect(['failed to connect to 192.168.1.202:5555'])
                as ConnectFailed)
            .message,
        'failed to connect to 192.168.1.202:5555',
      );
      expect(
        (parseConnect([]) as ConnectFailed).message,
        'adb connect printed nothing',
      );
    });
  });

  group('parseDevices', () {
    test('reads every state and detail', () {
      final devices = parseDevices(fixture('adb/devices_mixed.txt'));
      expect(
        [for (final d in devices) d.serial],
        [
          '192.168.1.202:5555',
          '192.168.1.77:5555',
          '0123456789ABCDEF',
          '5a3f9c21',
        ],
      );
      expect(
        [for (final d in devices) d.state],
        [
          DeviceState.device,
          DeviceState.offline,
          DeviceState.unauthorized,
          DeviceState.noPermissions,
        ],
      );
      final tablet = devices.first;
      expect(tablet.model, 'YC119R');
      expect(tablet.transportId, '3');
      expect(tablet.isNetwork, isTrue);
      expect(tablet.address?.port, 5555);
      expect(devices[2].usb, '1-1');
      expect(devices[2].isNetwork, isFalse);
      expect(devices[3].usb, '3-2');
    });

    test('an empty list and Windows line endings', () {
      expect(parseDevices(['List of devices attached', '']), isEmpty);
      expect(
        parseDevices([
          'List of devices attached\r',
          '192.168.1.202:5555\tdevice\r',
        ]).single.state,
        DeviceState.device,
      );
    });

    test('ignores lines before the header', () {
      expect(parseDevices(['192.168.1.202:5555 device']), isEmpty);
    });
  });

  group('device info', () {
    test('reads getprop and a root id', () {
      final info = deviceInfoFrom(
        parseGetprop(fixture('device/getprop_yc119r.txt')),
        fixture('device/id_root.txt'),
      );
      expect(info.model, 'YC119R');
      expect(info.manufacturer, 'rockchip');
      expect(info.androidVersion, '7.1.2');
      expect(info.sdk, 25);
      expect(info.buildType, 'userdebug');
      expect(info.serialNumber, 'A1B2C3D4E5');
      expect(info.isRoot, isTrue);
    });

    test('Android 4.4 shell user is not root', () {
      expect(parseUid(fixture('device/id_shell_kitkat.txt')), 2000);
    });

    test('unknown root and missing values stay null', () {
      final info = deviceInfoFrom(
        {'ro.build.version.sdk': 'x'},
        ['sh: id: not found'],
      );
      expect(info.isRoot, isNull);
      expect(info.sdk, isNull);
      expect(info.model, isNull);
    });

    test('device text loses control characters and is cut short', () {
      final props = parseGetprop([
        '[ro.product.model]: [Evil\u001b[2J${'x' * 300}]',
      ]);
      final model = deviceInfoFrom(props, []).model!;
      expect(model, startsWith('Evil[2J'));
      expect(model.length, 120);
    });
  });
}
