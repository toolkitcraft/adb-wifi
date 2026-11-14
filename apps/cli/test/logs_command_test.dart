import 'dart:async';
import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const pkg = 'com.eroxii.vending';
const s = '192.168.1.202:5555';

void main() {
  late Harness h;
  late FakeRunningProcess logcat;

  setUp(() {
    h = Harness()..healthyTablet();
    logcat = FakeRunningProcess();
    h.processes
      ..onLines(['-s', s, 'shell', 'getprop', 'ro.build.version.sdk'], ['25'])
      ..onLines(['-s', s, 'shell', 'pidof', pkg], ['1234'])
      ..onStream(['-s', s, 'logcat', '-v', 'threadtime'], logcat);
    // After the first PID check, print two lines, then Ctrl+C.
    var polls = 0;
    h.clock.onSleep = () {
      if (++polls == 1) {
        logcat
          ..emit('11-14 10:00:00.000  1234  1234 I VendingApp: token=abc123 ok')
          ..emit('11-14 10:00:00.100  999  999 I Other: noise');
      } else if (polls == 2) {
        h.interrupts.press();
      }
    };
  });

  test('follows the app until Ctrl+C, then kills logcat', () async {
    expect(await h.run(['logs', '--app', pkg]), ExitCodes.ok);
    final out = h.out.toString();
    expect(
      out,
      contains('📜 $pkg on 192.168.1.202:5555 (SDK 25). Ctrl+C stops.'),
    );
    expect(out, contains('▶️  $pkg is running (PID 1234).'));
    expect(out, contains('VendingApp: token=abc123 ok'));
    expect(out, isNot(contains('noise')));
    expect(logcat.killed, isTrue);
  });

  test('--save writes a new file with secrets hidden', () async {
    expect(
      await h.run(['logs', '--app', pkg, '--save', 'app.log']),
      ExitCodes.ok,
    );
    expect(h.writers.files['app.log'], [
      '11-14 10:00:00.000  1234  1234 I VendingApp: token=*** ok',
    ]);
    expect(h.writers.closed, {'app.log'});
    expect(h.out.toString(), contains('Saved 1 line to app.log'));
  });

  test('--save never overwrites a file', () async {
    h.writers.files['app.log'] = ['old'];
    expect(
      await h.run(['logs', '--app', pkg, '--save', 'app.log']),
      ExitCodes.failure,
    );
    expect(h.writers.files['app.log'], ['old']);
    expect(h.calls, isNot(anyElement(contains('logcat'))));
  });

  test('--clear runs logcat -c first', () async {
    h.processes.onLines(['-s', s, 'logcat', '-c'], []);
    await h.run(['logs', '--app', pkg, '--clear']);
    final i = h.calls.indexWhere((c) => c.join(' ') == '-s $s logcat -c');
    final j = h.calls.indexWhere(
      (c) => c.join(' ') == '-s $s logcat -v threadtime',
    );
    expect(i, greaterThanOrEqualTo(0));
    expect(i, lessThan(j));
  });

  test('--json prints one JSON object per event', () async {
    await h.run(['--json', 'logs', '--app', pkg]);
    final events = [
      for (final line in const LineSplitter().convert(h.out.toString()))
        (jsonDecode(line) as Map<String, Object?>)['event'],
    ];
    expect(events, ['running', 'line', 'ended']);
  });

  test('a bad package or regex is a usage error, before adb', () async {
    expect(await h.run(['logs']), ExitCodes.usage);
    expect(await h.run(['logs', '--app', 'x;reboot']), ExitCodes.usage);
    expect(await h.run(['logs', '--app', pkg, '--grep', '(']), ExitCodes.usage);
    expect(h.calls, isEmpty);
  });

  test('an offline device gets its fix instead of logs', () async {
    h.devices(['$s\toffline']);
    expect(await h.run(['logs', '--app', pkg]), ExitCodes.failure);
    expect(h.err.toString(), contains('USB debugging OFF, then ON'));
  });

  test('--dump prints the buffer and ends without polling', () async {
    final dump = FakeRunningProcess();
    h.processes.onStream(['-s', s, 'logcat', '-v', 'threadtime', '-d'], dump);
    h.clock.onSleep = null;
    final done = h.run(['logs', '--app', pkg, '--dump']);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    dump.emit('11-14 10:00:00.000  1234  1234 E VendingApp: boom');
    unawaited(dump.finish());
    expect(await done, ExitCodes.ok);
    expect(h.out.toString(), contains('VendingApp: boom'));
    expect(h.clock.sleeps, isEmpty);
  });
}
