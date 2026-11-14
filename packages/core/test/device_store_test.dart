import 'dart:convert';
import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

final tablet = SavedDevice(
  serial: 'A1B2C3D4E5',
  name: 'tablet',
  model: 'YC119R',
  lastIp: Ipv4.tryParse('192.168.1.202'),
  lastSeen: DateTime.utc(2026, 11, 12, 10),
);

void main() {
  group('configDirectory', () {
    test('macOS Application Support', () {
      expect(
        configDirectory(
          const HostPlatform(
            os: HostOs.macos,
            environment: {'HOME': '/Users/me'},
          ),
        ),
        '/Users/me/Library/Application Support/adbwifi',
      );
    });

    test('Windows APPDATA', () {
      expect(
        configDirectory(
          const HostPlatform(
            os: HostOs.windows,
            environment: {'APPDATA': r'C:\Users\me\AppData\Roaming'},
          ),
        ),
        r'C:\Users\me\AppData\Roaming\adbwifi',
      );
    });

    test('Linux XDG_CONFIG_HOME, else ~/.config; relative XDG is ignored', () {
      HostPlatform linux(Map<String, String> env) => HostPlatform(
        os: HostOs.linux,
        environment: {'HOME': '/home/me', ...env},
      );
      expect(
        configDirectory(linux({'XDG_CONFIG_HOME': '/cfg'})),
        '/cfg/adbwifi',
      );
      expect(configDirectory(linux({})), '/home/me/.config/adbwifi');
      expect(
        configDirectory(linux({'XDG_CONFIG_HOME': 'cfg'})),
        '/home/me/.config/adbwifi',
      );
    });

    test('null without a home folder', () {
      expect(
        configDirectory(const HostPlatform(os: HostOs.macos, environment: {})),
        isNull,
      );
    });
  });

  group('DeviceBook', () {
    test('finds by name without case, by serial and by address', () {
      final book = DeviceBook([tablet]);
      expect(book.find('TABLET'), same(tablet));
      expect(book.find('A1B2C3D4E5'), same(tablet));
      expect(
        book.byAddress(NetworkAddress.tryParse('192.168.1.202')!),
        same(tablet),
      );
      expect(book.find('kiosk'), isNull);
    });

    test('put replaces by serial; remove deletes', () {
      final moved = tablet.copyWith(
        address: NetworkAddress.tryParse('192.168.1.88'),
      );
      final book = DeviceBook([tablet]).put(moved);
      expect(book.devices, hasLength(1));
      expect(book.bySerial('A1B2C3D4E5')?.lastIp.toString(), '192.168.1.88');
      expect(book.remove('A1B2C3D4E5').isEmpty, isTrue);
    });
  });

  test('names and serials are checked', () {
    expect(isValidName('tablet-2'), isTrue);
    for (final bad in [
      '',
      '2tablet',
      '192.168.1.1',
      'a b',
      'x' * 33,
      r'$(reboot)',
    ]) {
      expect(isValidName(bad), isFalse, reason: bad);
    }
    expect(isValidSerial('192.168.1.202:5555'), isTrue);
    expect(isValidSerial('bad serial; reboot'), isFalse);
  });

  group('parseStore', () {
    test('drops invalid entries and fields', () {
      final load = parseStore(
        'f',
        jsonEncode({
          'version': 1,
          'devices': {
            'ok': {
              'serial': 'OK1',
              'name': 'bad name!',
              'lastIp': '999.1.1.1',
              'lastPort': 'x',
            },
            'bad': {'serial': 'rm -rf /'},
            'junk': 42,
          },
        }),
      );
      final devices = (load as StoreLoaded).book.devices;
      expect(devices.single.serial, 'OK1');
      expect(devices.single.name, isNull);
      expect(devices.single.lastIp, isNull);
      expect(devices.single.lastPort, 5555);
    });

    test('broken JSON is reported, not replaced', () {
      expect(parseStore('f', '{oops'), isA<StoreBroken>());
      expect(parseStore('f', '[]'), isA<StoreBroken>());
    });
  });

  group('JsonFileDeviceStore', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('adbwifi_'));
    tearDown(() => dir.delete(recursive: true));

    test('missing file means no devices', () async {
      final load = await JsonFileDeviceStore(
        '${dir.path}/none/devices.json',
      ).load();
      expect((load as StoreLoaded).book.isEmpty, isTrue);
    });

    test('saves and loads back, creating the folder', () async {
      final store = JsonFileDeviceStore('${dir.path}/adbwifi/devices.json');
      await store.save(DeviceBook([tablet]));
      final again = ((await store.load()) as StoreLoaded).book.devices.single;
      expect(again.toJson(), tablet.toJson());
      expect(File('${store.path}.tmp').existsSync(), isFalse);
    });

    test('stores only the allowed fields', () async {
      final store = JsonFileDeviceStore('${dir.path}/devices.json');
      await store.save(DeviceBook([tablet]));
      final json =
          jsonDecode(File(store.path).readAsStringSync())
              as Map<String, Object?>;
      final entry =
          (json['devices'] as Map<String, Object?>)['A1B2C3D4E5']
              as Map<String, Object?>;
      expect(entry.keys.toSet(), {
        'serial',
        'name',
        'model',
        'lastIp',
        'lastPort',
        'lastSeen',
      });
    });

    test('a broken file is reported and left alone', () async {
      final file = File('${dir.path}/devices.json')
        ..writeAsStringSync('not json');
      expect(await JsonFileDeviceStore(file.path).load(), isA<StoreBroken>());
      expect(file.readAsStringSync(), 'not json');
    });
  });
}
