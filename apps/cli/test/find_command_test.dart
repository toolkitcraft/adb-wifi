import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late Harness h;
  setUp(() {
    h = Harness();
    h.healthyTablet();
    // Something else on the network that refuses port 5555.
    h.probe.states[NetworkAddress(Ipv4.tryParse('192.168.1.1')!)] =
        const PortRefused();
  });

  test('asks first; "no" means no scan at all', () async {
    h.input.answers.add('n');
    expect(await h.run(['find']), ExitCodes.failure);
    expect(
      h.out.toString(),
      contains('Scan 192.168.1.0/24 (254 addresses, port 5555) from en0?'),
    );
    expect(h.probe.checked, isEmpty);
    expect(h.err.toString(), contains('Not scanned.'));
  });

  test('no terminal and no --yes: no scan', () async {
    h.input.canAsk = false;
    expect(await h.run(['find']), ExitCodes.failure);
    expect(h.probe.checked, isEmpty);
  });

  test('finds, shows and saves the tablet', () async {
    h.input.answers.add('y');
    expect(await h.run(['find']), ExitCodes.ok);
    final out = h.out.toString();
    expect(out, contains('✅ Found 1 device on 192.168.1.0/24'));
    expect(
      out,
      contains(
        'ADDRESS             STATE   MODEL   ANDROID  BUILD      ROOT  SERIAL',
      ),
    );
    expect(
      out,
      contains(
        '192.168.1.202:5555  device  YC119R  7.1.2    userdebug  no    A1B2C3D4E5',
      ),
    );
    expect(out, contains('adbwifi name 192.168.1.202 tablet'));
    expect(h.probe.checked, hasLength(253));
    expect(h.store.book.bySerial('A1B2C3D4E5')?.lastAddress, tablet);
  });

  test('--yes skips the question; root gets the red warning', () async {
    h.deviceAnswers('192.168.1.202:5555', root: true);
    expect(await h.run(['find', '--yes']), ExitCodes.ok);
    expect(h.out.toString(), isNot(contains('[y/N]')));
    expect(h.out.toString(), contains('🚨 adb runs as ROOT'));
  });

  test('nothing answers at all: hint at guest Wi-Fi', () async {
    h.probe.states.clear();
    expect(await h.run(['find', '-y']), ExitCodes.failure);
    expect(h.out.toString(), contains('❌ No adb devices on 192.168.1.0/24'));
    expect(h.out.toString(), contains('guest Wi-Fi'));
  });

  test('several networks: asks which one', () async {
    h.interfaces.addresses.add((
      adapter: 'en7',
      ip: Ipv4.tryParse('10.0.0.3')!,
    ));
    h.input.answers.addAll(['2', 'y']);
    await h.run(['find']);
    expect(h.out.toString(), contains('1. en0  192.168.1.5  (192.168.1.0/24)'));
    expect(h.out.toString(), contains('Scan 10.0.0.0/24'));
  });

  test(
    '--interface picks the adapter; a wrong name is a usage error',
    () async {
      h.interfaces.addresses.add((
        adapter: 'en7',
        ip: Ipv4.tryParse('10.0.0.3')!,
      ));
      expect(await h.run(['find', '-y', '--interface', 'en0']), ExitCodes.ok);
      expect(
        await h.run(['find', '-y', '--interface', 'eth9']),
        ExitCodes.usage,
      );
      expect(h.err.toString(), contains('Choose one of: en0, en7'));
    },
  );

  test('--json lists devices and counts', () async {
    expect(await h.run(['--json', 'find', '--yes']), ExitCodes.ok);
    final json = jsonDecode(h.out.toString()) as Map<String, Object?>;
    expect(json['subnet'], '192.168.1.0/24');
    expect(json['refused'], 1);
    expect(
      (json['devices'] as List<Object?>).single,
      containsPair('address', '192.168.1.202:5555'),
    );
  });
}
