import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

final moved = NetworkAddress.tryParse('192.168.1.88')!;
final saved = SavedDevice(
  serial: 'A1B2C3D4E5',
  name: 'tablet',
  model: 'YC119R',
  lastIp: tabletIp,
);

void main() {
  late Harness h;
  setUp(() {
    h = Harness()..healthyTablet();
    h.store.book = DeviceBook([saved]);
  });

  test('connects to the saved IP', () async {
    expect(await h.run(['connect', 'tablet']), ExitCodes.ok);
    expect(
      h.out.toString(),
      contains('✅ Connected to tablet (192.168.1.202:5555).'),
    );
    expect(h.out.toString(), contains('YC119R · Android 7.1.2'));
    expect(h.store.book.bySerial('A1B2C3D4E5')?.lastSeen, h.clock.now());
  });

  test('IP changed: asks, rescans, finds it, saves the new IP', () async {
    h.probe.states
      ..remove(tablet)
      ..[moved] = const PortOpen();
    h.processes.onLines(
      ['connect', moved.serial],
      ['connected to ${moved.serial}'],
    );
    h.devices(['${moved.serial}\tdevice']);
    h.deviceAnswers(moved.serial);
    h.input.answers.add('y');
    expect(await h.run(['connect', 'tablet']), ExitCodes.ok);
    final out = h.out.toString();
    expect(
      out,
      contains('does not answer. Its IP may have changed. Scan 192.168.1.0/24'),
    );
    expect(out, contains('✅ Connected to tablet (192.168.1.88:5555).'));
    expect(out, contains('Its IP changed from 192.168.1.202 to 192.168.1.88'));
    expect(out, contains('DHCP reservation'));
    expect(h.store.book.byName('tablet')?.lastAddress, moved);
  });

  test('IP changed but the user says no: no scan', () async {
    h.probe.states.remove(tablet);
    h.input.answers.add('n');
    expect(await h.run(['connect', 'tablet']), ExitCodes.failure);
    expect(h.probe.checked, [tablet]);
    expect(h.out.toString(), contains('❌ No answer from 192.168.1.202:5555.'));
  });

  test('offline without --wait: the device-side fix', () async {
    h.devices(['192.168.1.202:5555\toffline']);
    h.processes.onLines(['disconnect', '192.168.1.202:5555'], []);
    expect(await h.run(['connect', 'tablet']), ExitCodes.failure);
    expect(h.out.toString(), contains('USB debugging OFF, then ON'));
    expect(h.clock.sleeps, isEmpty);
  });

  test('offline with --wait: retries until it is back', () async {
    h.processes
      // Lists: choosing the target, connect, reconnect, first wait try;
      // then the device is back.
      ..on(
        ['devices', '-l'],
        [
          for (var i = 0; i < 4; i++)
            const ProcessCompleted(
              0,
              stdout: [
                'List of devices attached',
                '192.168.1.202:5555\toffline',
              ],
            ),
          const ProcessCompleted(
            0,
            stdout: ['List of devices attached', '192.168.1.202:5555\tdevice'],
          ),
        ],
      )
      ..onLines(['disconnect', '192.168.1.202:5555'], []);
    expect(await h.run(['connect', 'tablet', '--wait']), ExitCodes.ok);
    expect(h.out.toString(), contains('Waiting for the device'));
    expect(h.out.toString(), contains('✅ Connected to tablet'));
    expect(h.clock.sleeps, isNotEmpty);
  });

  test('--wait stops on Ctrl+C', () async {
    h.devices(['192.168.1.202:5555\tunauthorized']);
    h.processes.onLines(['disconnect', '192.168.1.202:5555'], []);
    var sleeps = 0;
    h.clock.onSleep = () {
      if (++sleeps == 2) h.interrupts.press();
    };
    expect(await h.run(['connect', 'tablet', '--wait']), ExitCodes.failure);
    expect(h.clock.sleeps, hasLength(2));
    expect(h.out.toString(), contains('tap Allow'));
  });

  test('a USB-only device is refused', () async {
    h.store.book = DeviceBook([]);
    h.devices(['0123456789ABCDEF\tdevice usb:1-1']);
    expect(await h.run(['connect']), ExitCodes.failure);
    expect(h.err.toString(), contains('is connected by USB'));
  });

  test('--json', () async {
    h.probe.states[tablet] = const PortRefused();
    expect(
      await h.run(['--json', 'connect', '192.168.1.202']),
      ExitCodes.failure,
    );
    final json = jsonDecode(h.out.toString()) as Map<String, Object?>;
    expect(json, containsPair('issue', 'port_closed'));
  });
}
