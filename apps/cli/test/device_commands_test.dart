import 'dart:convert';
import 'dart:io';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const s = '192.168.1.202:5555';
const pkg = 'com.eroxii.vending';

List<String> coreFixture(String name) =>
    File('../../packages/core/test/fixtures/$name').readAsLinesSync();

void main() {
  late Harness h;
  setUp(() => h = Harness()..healthyTablet());

  group('install', () {
    setUp(() {
      h.files.existing.add('app.apk');
      h.files.sizes['app.apk'] = 8 * 1024 * 1024;
    });

    test('shows the target first, then installs with -r', () async {
      h.processes.onLines(
        ['-s', s, 'install', '-r', 'app.apk'],
        ['Performing Streamed Install', 'Success'],
      );
      expect(await h.run(['install', 'app.apk']), ExitCodes.ok);
      final out = h.out.toString();
      expect(
        out,
        contains(
          '📦 Installing app.apk (8.0 MB) on 192.168.1.202:5555, about 5 s over Wi-Fi',
        ),
      );
      expect(out, contains('✅ Installed in'));
    });

    test('a lower build number gets a plain explanation', () async {
      h.processes.onLines(
        ['-s', s, 'install', '-r', 'app.apk'],
        [
          'adb: failed to install app.apk: Failure [INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected]',
        ],
      );
      expect(await h.run(['install', 'app.apk']), ExitCodes.failure);
      expect(
        h.out.toString(),
        contains(
          '❌ The installed app has a higher build number than this APK.',
        ),
      );
      expect(
        h.out.toString(),
        contains('must be higher than the installed one'),
      );
      expect(h.out.toString(), contains('(Android said: Downgrade detected)'));
    });

    test('signature mismatch', () async {
      h.processes.onLines(
        ['-s', s, 'install', '-r', 'app.apk'],
        [
          'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Package com.x signatures do not match]',
        ],
      );
      await h.run(['install', 'app.apk']);
      expect(h.out.toString(), contains('signed with a different key'));
    });

    test('missing or non-APK file: usage error before adb', () async {
      expect(await h.run(['install', 'nope.apk']), ExitCodes.usage);
      h.files.existing.add('notes.txt');
      expect(await h.run(['install', 'notes.txt']), ExitCodes.usage);
      expect(h.calls, isEmpty);
    });

    test('--json gives the code', () async {
      h.processes.onLines(
        ['-s', s, 'install', '-r', 'app.apk'],
        ['Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]'],
      );
      await h.run(['--json', 'install', 'app.apk']);
      expect(
        jsonDecode(h.out.toString()),
        containsPair('code', 'INSTALL_FAILED_INSUFFICIENT_STORAGE'),
      );
    });
  });

  group('shell', () {
    test('runs in the terminal with the command as it is', () async {
      h.processes.on(
        ['-s', s, 'shell', 'ls', '-l', '/sdcard'],
        [const ProcessCompleted(0)],
      );
      expect(await h.run(['shell', 'ls', '-l', '/sdcard']), ExitCodes.ok);
      expect(h.calls.last, ['-s', s, 'shell', 'ls', '-l', '/sdcard']);
    });

    test('root over the network: red warning first', () async {
      h.deviceAnswers(s, root: true);
      h.processes.on(['-s', s, 'shell'], [const ProcessCompleted(0)]);
      await h.run(['shell']);
      final out = h.out.toString();
      expect(out.indexOf('🚨'), lessThan(out.indexOf('🐚')));
    });

    test('passes the exit code through; --json is refused', () async {
      h.processes.on(['-s', s, 'shell', 'false'], [const ProcessCompleted(1)]);
      expect(await h.run(['shell', 'false']), 1);
      expect(await h.run(['--json', 'shell']), ExitCodes.usage);
    });
  });

  group('pull and push', () {
    test('pull never overwrites without --force', () async {
      h.files.existing.add('base.apk');
      expect(await h.run(['pull', '/data/app/x/base.apk']), ExitCodes.failure);
      expect(h.err.toString(), contains('base.apk already exists'));
      h.processes.on(
        ['-s', s, 'pull', '/data/app/x/base.apk', 'base.apk'],
        [const ProcessCompleted(0)],
      );
      expect(
        await h.run(['pull', '--force', '/data/app/x/base.apk']),
        ExitCodes.ok,
      );
    });

    test('push shows size and target, then copies', () async {
      h.files.existing.add('cfg.json');
      h.files.sizes['cfg.json'] = 2048;
      h.processes.on(
        ['-s', s, 'push', 'cfg.json', '/sdcard/cfg.json'],
        [const ProcessCompleted(0)],
      );
      expect(
        await h.run(['push', 'cfg.json', '/sdcard/cfg.json']),
        ExitCodes.ok,
      );
      expect(
        h.out.toString(),
        contains(
          '⬆️  cfg.json (2 KB) → /sdcard/cfg.json on 192.168.1.202:5555',
        ),
      );
    });

    test('a failed copy is a failure', () async {
      h.processes.on(
        ['-s', s, 'pull', '/nope', 'nope'],
        [const ProcessCompleted(1)],
      );
      expect(await h.run(['pull', '/nope']), ExitCodes.failure);
    });
  });

  group('disconnect', () {
    test('a root device gets the reminder', () async {
      h.deviceAnswers(s, root: true);
      h.processes.onLines(['disconnect', s], ['disconnected $s']);
      expect(await h.run(['disconnect', '192.168.1.202']), ExitCodes.ok);
      expect(h.out.toString(), contains('✅ Disconnected $s.'));
      expect(
        h.out.toString(),
        contains('Turn off USB debugging on production devices'),
      );
    });

    test('--all disconnects every network device, not USB', () async {
      h.devices([
        '$s\tdevice',
        '192.168.1.77:5555\toffline',
        'A1B2C3\tdevice usb:1-1',
      ]);
      h.processes
        ..onLines(['disconnect', s], [])
        ..onLines(['disconnect', '192.168.1.77:5555'], []);
      expect(await h.run(['disconnect', '--all']), ExitCodes.ok);
      final disconnects = h.calls
          .where((c) => c.first == 'disconnect')
          .map((c) => c.last);
      expect(disconnects, [s, '192.168.1.77:5555']);
    });
  });

  group('app info', () {
    setUp(() {
      h.processes
        ..onLines(['-s', s, 'shell', 'getprop', 'ro.build.version.sdk'], ['25'])
        ..onLines([
          '-s',
          s,
          'shell',
          'dumpsys',
          'package',
          pkg,
        ], coreFixture('apps/dumpsys_package.txt'))
        ..onLines(['-s', s, 'shell', 'pidof', pkg], ['2345'])
        ..onLines([
          '-s',
          s,
          'shell',
          'dumpsys',
          'meminfo',
          '2345',
        ], coreFixture('apps/meminfo_android71.txt'))
        ..onLines([
          '-s',
          s,
          'shell',
          'ls',
          '-l',
          '/proc/2345/fd',
        ], coreFixture('apps/ls_fd_android71.txt'));
    });

    test('version, PID, memory and serial ports', () async {
      expect(await h.run(['app', 'info', pkg]), ExitCodes.ok);
      final out = h.out.toString();
      expect(out, contains('version:   1.4.2 (build 42)'));
      expect(out, contains('✅ Running, PID 2345'));
      expect(out, contains('memory:    55.5 MB (PSS)'));
      expect(
        out,
        contains('serial ports: /dev/ttyS1 (fd 23), /dev/ttyUSB0 (fd 40)'),
      );
    });

    test('not running', () async {
      h.processes.on(
        ['-s', s, 'shell', 'pidof', pkg],
        [const ProcessCompleted(1)],
      );
      await h.run(['app', 'info', pkg]);
      expect(h.out.toString(), contains('⚠️  Not running.'));
    });

    test('not installed', () async {
      h.processes.onLines(
        ['-s', s, 'shell', 'dumpsys', 'package', 'com.nope'],
        ['Unable to find package'],
      );
      expect(await h.run(['app', 'info', 'com.nope']), ExitCodes.failure);
      expect(h.err.toString(), contains('com.nope is not installed'));
    });

    test('a bad package name never reaches adb', () async {
      expect(await h.run(['app', 'info', 'x;reboot']), ExitCodes.usage);
      expect(h.calls, isEmpty);
    });
  });
}
