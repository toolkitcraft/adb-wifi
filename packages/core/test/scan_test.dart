import 'dart:async';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

Ipv4 ip(String text) => Ipv4.tryParse(text)!;

void main() {
  group('scanSubnet24', () {
    test('checks .1 to .254 except our own address', () async {
      final probe = FakePortProbe();
      final result = await scanSubnet24(ip('192.168.1.5'), probe);
      expect(probe.checked, hasLength(253));
      expect(probe.checked.first.serial, '192.168.1.1:5555');
      expect(probe.checked.last.serial, '192.168.1.254:5555');
      expect(
        probe.checked.map((a) => a.ip),
        isNot(contains(ip('192.168.1.5'))),
      );
      expect(result.subnet, '192.168.1.0/24');
      expect(result.nothingAnswered, isTrue);
      expect(result.noAnswer, 253);
    });

    test('sorts open, refused and silent hosts', () async {
      final probe = FakePortProbe({
        NetworkAddress(ip('192.168.1.202')): const PortOpen(),
        NetworkAddress(ip('192.168.1.20')): const PortOpen(),
        NetworkAddress(ip('192.168.1.1')): const PortRefused(),
      });
      final result = await scanSubnet24(ip('192.168.1.5'), probe);
      expect(
        [for (final a in result.open) '$a'],
        ['192.168.1.20:5555', '192.168.1.202:5555'],
      );
      expect(result.refused, 1);
      expect(result.nothingAnswered, isFalse);
    });

    test('refuses to scan a public network', () {
      expect(
        () => scanSubnet24(ip('8.8.8.8'), FakePortProbe()),
        throwsArgumentError,
      );
    });
  });

  test('boundedMap never runs more than the limit and keeps order', () async {
    var running = 0;
    var most = 0;
    final results = await boundedMap(List.generate(100, (i) => i), 7, (
      i,
    ) async {
      running++;
      most = running > most ? running : most;
      await Future<void>.delayed(Duration.zero);
      running--;
      return i * 2;
    });
    expect(most, 7);
    expect(results, List.generate(100, (i) => i * 2));
  });

  test('identifyDevices connects and reads each open address', () async {
    final processes = FakeProcessRunner()
      ..onLines(
        ['connect', '192.168.1.202:5555'],
        ['connected to 192.168.1.202:5555'],
      )
      ..onLines(
        ['connect', '192.168.1.30:5555'],
        ['failed to connect to 192.168.1.30:5555'],
      )
      ..onLines(
        ['devices', '-l'],
        ['List of devices attached', '192.168.1.202:5555 device'],
      )
      ..onLines(
        ['-s', '192.168.1.202:5555', 'shell', 'getprop'],
        ['[ro.serialno]: [A1B2]'],
      )
      ..onLines(['-s', '192.168.1.202:5555', 'shell', 'id'], ['uid=0(root)']);
    final adb = Adb(
      path: 'adb',
      runner: processes,
      timeout: const Duration(seconds: 1),
    );
    final found = await identifyDevices(adb, [
      NetworkAddress(ip('192.168.1.30')),
      NetworkAddress(ip('192.168.1.202')),
    ]);
    expect(found[0].connect, isA<ConnectFailed>());
    expect(found[0].state, isNull);
    expect(found[1].state, DeviceState.device);
    expect(found[1].info?.serialNumber, 'A1B2');
    expect(found[1].info?.isRoot, isTrue);
  });
}
