import 'dart:async';
import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

const pkg = 'com.eroxii.vending';
const serial = '192.168.1.202:5555';

List<String> fixture(String name) =>
    File('test/fixtures/$name').readAsLinesSync();

List<LogLine> logLines() => [
  for (final raw in fixture('logs/threadtime_crash.txt')) ?parseLogLine(raw),
];

void main() {
  test('package names are checked before they reach the device shell', () {
    expect(isValidPackage(pkg), isTrue);
    for (final bad in [
      'vending',
      'com.x;reboot',
      'com.x y',
      r'com.$(id)',
      '.com.x',
      'com..x',
      '',
    ]) {
      expect(isValidPackage(bad), isFalse, reason: bad);
    }
  });

  group('ps', () {
    test('Android 4.4 toolbox: exact name only (not :remote)', () {
      final rows = parsePs(fixture('device/ps_android44.txt'));
      expect(rows.where((r) => r.name == pkg).single.pid, 1234);
      expect(rows.where((r) => r.name == '$pkg:remote').single.pid, 1290);
    });

    test('Android 7.1 toolbox and Android 9 toybox', () {
      expect(parsePs(fixture('device/ps_android71.txt')).last, (
        pid: 2345,
        name: pkg,
      ));
      expect(parsePs(fixture('device/ps_android9_toybox.txt')).last, (
        pid: 4567,
        name: pkg,
      ));
    });

    test('pidof output', () {
      expect(parsePidof(['2345']), 2345);
      expect(parsePidof(['2345 2390']), 2345);
      expect(parsePidof(['']), isNull);
      expect(parsePidof(['/system/bin/sh: pidof: not found']), isNull);
    });
  });

  group('findAppPid', () {
    late FakeProcessRunner p;
    late Adb adb;
    setUp(() {
      p = FakeProcessRunner();
      adb = Adb(path: 'adb', runner: p, timeout: const Duration(seconds: 1));
    });

    test('Android 7+: pidof', () async {
      p.onLines(['-s', serial, 'shell', 'pidof', pkg], ['2345']);
      expect(await findAppPid(adb, serial, pkg, sdk: 25), 2345);
      expect(p.calls, hasLength(1));
    });

    test('Android 7+: empty pidof means not running, no ps', () async {
      p.on(['-s', serial, 'shell', 'pidof', pkg], [const ProcessCompleted(1)]);
      expect(await findAppPid(adb, serial, pkg, sdk: 25), isNull);
      expect(p.calls, hasLength(1));
    });

    test('a ROM without pidof falls back to ps', () async {
      p
        ..onLines(
          ['-s', serial, 'shell', 'pidof', pkg],
          ['sh: pidof: not found'],
        )
        ..onLines([
          '-s',
          serial,
          'shell',
          'ps',
        ], fixture('device/ps_android71.txt'));
      expect(await findAppPid(adb, serial, pkg, sdk: 25), 2345);
    });

    test('Android 4.4: ps only, filtered on the computer', () async {
      p.onLines([
        '-s',
        serial,
        'shell',
        'ps',
      ], fixture('device/ps_android44.txt'));
      expect(await findAppPid(adb, serial, pkg, sdk: 19), 1234);
      expect(p.calls.single, ['-s', serial, 'shell', 'ps']);
    });

    test('Android 8+: ps -A', () async {
      p
        ..on(
          ['-s', serial, 'shell', 'pidof', pkg],
          [
            const ProcessCompleted(0, stdout: ['x']),
          ],
        )
        ..onLines([
          '-s',
          serial,
          'shell',
          'ps',
          '-A',
        ], fixture('device/ps_android9_toybox.txt'));
      expect(await findAppPid(adb, serial, pkg, sdk: 28), 4567);
    });

    test('a bad package name never reaches adb', () {
      expect(
        () => findAppPid(adb, serial, 'x;reboot', sdk: 25),
        throwsArgumentError,
      );
      expect(p.calls, isEmpty);
    });
  });

  group('parseLogLine', () {
    test('reads threadtime lines, skips the rest', () {
      final lines = logLines();
      expect(lines, hasLength(13));
      final first = lines.first;
      expect(first.time, '11-14 10:22:33.123');
      expect((first.pid, first.tid), (1234, 1250));
      expect(first.level, LogLevel.info);
      expect(first.tag, 'VendingApp');
      expect(first.message, 'motor 3 started');
      expect(lines[6].tag, 'DEBUG');
      expect(lines.last.message, '');
      expect(parseLogLine('--------- beginning of main'), isNull);
    });
  });

  group('AppLogFilter', () {
    test(
      'keeps the app, the crash report and what the system says about it',
      () {
        final filter = AppLogFilter(pkg)..pid = 1234;
        final kept = [for (final l in logLines()) ?filter.check(l)];
        final messages = [for (final k in kept) k.line.message];
        expect(messages, isNot(contains(contains('com.other.app'))));
        expect(messages, isNot(contains('unrelated')));
        expect(
          messages,
          contains('Process com.eroxii.vending (pid 1234) has died'),
        );
        expect(messages, contains('ANR in com.eroxii.vending'));
        expect(
          messages,
          contains('    #00 pc 0001a2b4  /system/lib/libc.so (abort+63)'),
        );
        expect(kept.where((k) => k.important).map((k) => k.line.tag).toSet(), {
          'DEBUG',
          'ActivityManager',
        });
      },
    );

    test('user filters apply to app lines; important lines always show', () {
      final filter = AppLogFilter(
        pkg,
        options: const LogOptions(minLevel: LogLevel.error),
      )..pid = 1234;
      final kept = [for (final l in logLines()) ?filter.check(l)];
      expect(kept.where((k) => !k.important).map((k) => k.line.tag).toSet(), {
        'AndroidRuntime',
      });
      expect(
        kept.where((k) => k.line.message.contains('has died')),
        hasLength(1),
      );
    });

    test('--tag and --grep', () {
      final filter = AppLogFilter(
        pkg,
        options: LogOptions(tag: 'SerialPort', grep: RegExp('ttyS1')),
      )..pid = 1234;
      final app = [
        for (final l in logLines()) ?filter.check(l),
      ].where((k) => !k.important);
      expect(app.single.line.tag, 'SerialPort');
    });

    test('remembers only the current and the previous PID', () {
      final filter = AppLogFilter(pkg)
        ..pid = 1
        ..pid = 2
        ..pid = 3;
      LogLine line(int pid) =>
          parseLogLine('11-14 10:00:00.000  $pid  $pid I T: x')!;
      expect(filter.check(line(1)), isNull);
      expect(filter.check(line(2)), isNotNull);
      expect(filter.check(line(3)), isNotNull);
    });
  });

  test('redactSecrets hides tokens, keys and passwords', () {
    expect(
      redactSecrets('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def'),
      'Authorization: Bearer ***',
    );
    expect(redactSecrets('url?token=abc123&user=me'), 'url?token=***&user=me');
    expect(
      redactSecrets('api_key=XYZ password=hunter2'),
      'api_key=*** password=***',
    );
    expect(
      redactSecrets('{"password":"hunter2","name":"a"}'),
      '{"password":"***","name":"a"}',
    );
    expect(redactSecrets('motor 3 started'), 'motor 3 started');
  });

  group('LogFollower', () {
    late FakeProcessRunner p;
    late FakeRunningProcess logcat;
    late FakeClock clock;
    late LogFollower follower;

    setUp(() {
      p = FakeProcessRunner();
      logcat = FakeRunningProcess();
      clock = FakeClock();
      p.onStream(['-s', serial, 'logcat', '-v', 'threadtime'], logcat);
      follower = LogFollower(
        adb: Adb(path: 'adb', runner: p, timeout: const Duration(seconds: 1)),
        serial: serial,
        filter: AppLogFilter(pkg),
        sdk: 25,
        clock: clock,
      );
    });

    test('streams app lines, then sees the crash and the restart', () async {
      p.on(
        ['-s', serial, 'shell', 'pidof', pkg],
        [
          const ProcessCompleted(0, stdout: ['1234']),
          const ProcessCompleted(0, stdout: ['1234']),
          const ProcessCompleted(1),
          const ProcessCompleted(0, stdout: ['5678']),
        ],
      );
      var polls = 0;
      clock.onSleep = () {
        polls++;
        switch (polls) {
          case 1:
            logcat.emit('11-14 10:00:00.000  1234  1234 I VendingApp: hello');
          case 4:
            logcat.emit('11-14 10:00:09.000  5678  5678 I VendingApp: back');
          case 5:
            unawaited(logcat.finish());
        }
      };
      final events = await follower.follow().toList();
      String describe(LogEvent e) => switch (e) {
        AppRunning(:final pid, :final previous) =>
          'running $pid after $previous',
        AppStopped(:final pid) => 'stopped $pid',
        AppNotRunning() => 'not running',
        LogLineEvent(:final line) => 'line ${line.message}',
        LogEnded(:final message) => 'ended $message',
      };
      expect(events.map(describe), [
        'running 1234 after null',
        'line hello',
        'stopped 1234',
        'running 5678 after 1234',
        'line back',
        'ended null',
      ]);
      expect(clock.sleeps, everyElement(const Duration(seconds: 2)));
    });

    test('stop() kills logcat and ends the stream', () async {
      p.onLines(['-s', serial, 'shell', 'pidof', pkg], ['1234']);
      clock.onSleep = () => unawaited(follower.stop());
      final events = await follower.follow().toList();
      expect(logcat.killed, isTrue);
      expect(events.last, isA<LogEnded>());
    });

    test('--dump: reads the buffer once, no PID polling', () async {
      final dump = FakeRunningProcess();
      p
        ..onLines(['-s', serial, 'shell', 'pidof', pkg], ['1234'])
        ..onStream(['-s', serial, 'logcat', '-v', 'threadtime', '-d'], dump);
      final done = follower.follow(dump: true).toList();
      await Future<void>.delayed(Duration.zero);
      for (final raw in fixture('logs/threadtime_crash.txt')) {
        dump.emit(raw);
      }
      await dump.finish();
      final events = await done;
      // 10: the tombstone's first "*** ***" line comes before the line that
      // names the app, so it is not kept.
      expect(events.whereType<LogLineEvent>(), hasLength(10));
      expect(clock.sleeps, isEmpty);
    });
  });
}
