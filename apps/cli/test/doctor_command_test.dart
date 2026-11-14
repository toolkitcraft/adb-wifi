import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

void main() {
  late Harness h;
  setUp(() => h = Harness());

  test('a healthy tablet: every step passes and it is remembered', () async {
    h.healthyTablet();
    expect(await h.run(['doctor', '192.168.1.202']), ExitCodes.ok);
    expect(h.out.toString(), '''
Checking 192.168.1.202:5555

✅ adb 1.0.41: $macSdkAdb
✅ This computer: 192.168.1.5 on en0
✅ Same network: 192.168.1.0/24
✅ Port open: 192.168.1.202:5555
✅ adb connect: connected
✅ State: device
✅ YC119R · Android 7.1.2 (SDK 25) · userdebug · serial A1B2C3D4E5

✅ Ready: use -d 192.168.1.202:5555 with any adbwifi command.
''');
    final saved = h.store.book.bySerial('A1B2C3D4E5');
    expect(saved?.lastAddress, tablet);
    expect(saved?.model, 'YC119R');
    expect(saved?.lastSeen, h.clock.now());
  });

  test('root adb gets the red warning and the fix', () async {
    h.healthyTablet(root: true);
    expect(await h.run(['doctor', '192.168.1.202']), ExitCodes.ok);
    expect(h.out.toString(), contains('· ROOT\n🚨 adb runs as ROOT'));
    expect(h.out.toString(), contains('👉 Turn off USB debugging'));
  });

  test('port refused: one problem, one fix, exit 1', () async {
    h.healthyTablet();
    h.probe.states[tablet] = const PortRefused();
    expect(await h.run(['doctor', '192.168.1.202']), ExitCodes.failure);
    final out = h.out.toString();
    expect(
      out,
      contains(
        '❌ The device answered at 192.168.1.202, but adb is not listening on port 5555.',
      ),
    );
    expect(out, contains('👉 On the device: Settings → Developer options'));
    expect(out, isNot(contains('adb connect')));
    expect(out, contains('❌ Not ready'));
  });

  test('offline that stays offline: the fix is on the device', () async {
    h.healthyTablet();
    h.devices(['192.168.1.202:5555\toffline']);
    h.processes.onLines(['disconnect', '192.168.1.202:5555'], []);
    expect(await h.run(['doctor', '192.168.1.202']), ExitCodes.failure);
    expect(h.out.toString(), contains('USB debugging OFF, then ON'));
  });

  test('a saved name is checked at its last IP', () async {
    h.healthyTablet();
    h.store.book = DeviceBook([
      SavedDevice(serial: 'A1B2C3D4E5', name: 'tablet', lastIp: tabletIp),
    ]);
    expect(await h.run(['doctor', 'tablet']), ExitCodes.ok);
    expect(
      h.out.toString(),
      startsWith('Checking tablet (192.168.1.202:5555)'),
    );
  });

  test('-d works like the argument', () async {
    h.healthyTablet();
    expect(await h.run(['-d', '192.168.1.202', 'doctor']), ExitCodes.ok);
  });

  test('no device anywhere: checks the computer and says what to do', () async {
    h.healthyTablet();
    h.devices([]);
    expect(await h.run(['doctor']), ExitCodes.failure);
    final out = h.out.toString();
    expect(out, contains('✅ This computer: 192.168.1.5 on en0'));
    expect(out, contains('👉 No device given'));
    expect(out, isNot(contains('❌')));
  });

  test('adb missing: install steps, even with an IP', () async {
    h = Harness(adbInstalled: false);
    expect(await h.run(['doctor', '192.168.1.202']), ExitCodes.failure);
    expect(h.out.toString(), contains('❌ adb not found.'));
    expect(h.calls, isEmpty);
  });

  test('an unknown name is a usage error', () async {
    h.healthyTablet();
    expect(await h.run(['doctor', 'kiosk']), ExitCodes.usage);
    expect(h.err.toString(), contains('No device called "kiosk"'));
  });

  test('--json gives every check with codes and fixes', () async {
    h.healthyTablet();
    h.probe.states[tablet] = const PortNoAnswer();
    expect(
      await h.run(['--json', 'doctor', '192.168.1.202']),
      ExitCodes.failure,
    );
    final json = jsonDecode(h.out.toString()) as Map<String, Object?>;
    expect(json['ok'], false);
    final checks = json['checks'] as List<Object?>;
    final last = checks.last as Map<String, Object?>;
    expect(last['step'], 'port');
    expect(last['issue'], 'no_answer');
    expect(last['fix'], contains('guest Wi-Fi'));
  });

  test('several connected devices and no terminal: asks for -d', () async {
    h.healthyTablet();
    h.devices(['192.168.1.202:5555\tdevice', '192.168.1.77:5555\tdevice']);
    h.input.canAsk = false;
    expect(await h.run(['doctor']), ExitCodes.usage);
    expect(h.err.toString(), contains('Several devices fit'));
  });

  test('several connected devices: the user picks one', () async {
    h.healthyTablet();
    h.devices(['192.168.1.77:5555\tdevice', '192.168.1.202:5555\tdevice']);
    h.input.answers.add('2');
    expect(await h.run(['doctor']), ExitCodes.ok);
    expect(
      h.out.toString(),
      contains('Which one? [1-2]: Checking 192.168.1.202:5555'),
    );
  });
}
