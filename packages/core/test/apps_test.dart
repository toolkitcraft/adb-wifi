import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

List<String> fixture(String name) =>
    File('test/fixtures/$name').readAsLinesSync();
const pkg = 'com.eroxii.vending';
const s = '192.168.1.202:5555';

void main() {
  group('parseInstall', () {
    InstallResult parse(List<String> lines) =>
        parseInstall(ProcessCompleted(0, stdout: lines));

    test('success', () {
      expect(
        parse(['Performing Streamed Install', 'Success']),
        isA<InstallSuccess>(),
      );
    });

    test('new and old failure formats with the code and detail', () {
      final r =
          parse([
                'Performing Streamed Install',
                'adb: failed to install app.apk: Failure [INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected: Update version code 5 is older than current 7]',
              ])
              as InstallFailure;
      expect(r.code, 'INSTALL_FAILED_VERSION_DOWNGRADE');
      expect(
        r.detail,
        'Downgrade detected: Update version code 5 is older than current 7',
      );
      final old =
          parse([
                '\tpkg: /data/local/tmp/app.apk',
                'Failure [INSTALL_FAILED_ALREADY_EXISTS]',
              ])
              as InstallFailure;
      expect(old.code, 'INSTALL_FAILED_ALREADY_EXISTS');
      expect(old.detail, isNull);
    });

    test('unknown output is kept, not guessed', () {
      expect((parse(['something new']) as InstallUnknown).lines, [
        'something new',
      ]);
      expect(
        parseInstall(const ProcessTimedOut(Duration(minutes: 1))),
        isA<InstallTimedOut>(),
      );
    });
  });

  test('transferTimeout grows with the file and has limits', () {
    expect(transferTimeout(0), const Duration(minutes: 1));
    expect(transferTimeout(8 * 1024 * 1024), const Duration(seconds: 60 + 40));
    expect(
      transferTimeout(10 * 1024 * 1024 * 1024),
      const Duration(minutes: 30),
    );
    expect(
      transferTimeout(0, atLeast: const Duration(minutes: 5)),
      const Duration(minutes: 5),
    );
  });

  group('dumpsys package', () {
    test('reads the first section only', () {
      final info = parseDumpsysPackage(
        fixture('apps/dumpsys_package.txt'),
        pkg,
      )!;
      expect(info.versionName, '1.4.2');
      expect(info.versionCode, 42);
      expect(info.minSdk, 19);
      expect(info.targetSdk, 28);
      expect(info.firstInstall, '2026-11-05 10:12:01');
      expect(info.lastUpdate, '2026-11-12 15:40:22');
    });

    test('not installed', () {
      expect(
        parseDumpsysPackage(['Unable to find package: com.nope'], 'com.nope'),
        isNull,
      );
      expect(
        parseDumpsysPackage(fixture('apps/dumpsys_package.txt'), 'com.other'),
        isNull,
      );
    });
  });

  test('meminfo total PSS in every layout', () {
    expect(parseMeminfoTotalKb(fixture('apps/meminfo_android71.txt')), 56789);
    expect(
      parseMeminfoTotalKb([
        '  TOTAL PSS:    71234            TOTAL RSS:   99000',
      ]),
      71234,
    );
    expect(parseMeminfoTotalKb(['No process found for: 99']), isNull);
  });

  group('open serial ports', () {
    test('keeps /dev/tty devices only', () {
      final ports =
          parseOpenPorts(fixture('apps/ls_fd_android71.txt')) as PortsListed;
      expect(ports.ports, [
        (fd: 23, path: '/dev/ttyS1'),
        (fd: 40, path: '/dev/ttyUSB0'),
      ]);
      expect(
        (parseOpenPorts([
                  'lrwx------ 1 u0_a77 u0_a77 64 2026-11-12 10:00 5 -> /dev/ttyS3',
                ])
                as PortsListed)
            .ports,
        [(fd: 5, path: '/dev/ttyS3')],
      );
    });

    test('permission denied without root', () {
      expect(
        parseOpenPorts(['ls: /proc/2345/fd: Permission denied']),
        isA<PortsNotAllowed>(),
      );
    });
  });

  test('readAppReport runs only simple commands and parses here', () async {
    final p = FakeProcessRunner()
      ..onLines([
        '-s',
        s,
        'shell',
        'dumpsys',
        'package',
        pkg,
      ], fixture('apps/dumpsys_package.txt'))
      ..onLines(['-s', s, 'shell', 'pidof', pkg], ['2345'])
      ..onLines([
        '-s',
        s,
        'shell',
        'dumpsys',
        'meminfo',
        '2345',
      ], fixture('apps/meminfo_android71.txt'))
      ..on(
        ['-s', s, 'shell', 'ls', '-l', '/proc/2345/fd'],
        [
          const ProcessCompleted(
            1,
            stderr: ['ls: /proc/2345/fd: Permission denied'],
          ),
        ],
      );
    final adb = Adb(
      path: 'adb',
      runner: p,
      timeout: const Duration(seconds: 1),
    );
    final report = await readAppReport(adb, s, pkg, sdk: 25);
    expect(report.package?.versionCode, 42);
    expect(report.pid, 2345);
    expect(report.memoryKb, 56789);
    expect(report.ports, isA<PortsNotAllowed>());
  });

  test('readAppReport: not installed stops after dumpsys', () async {
    final p = FakeProcessRunner()
      ..onLines(
        ['-s', s, 'shell', 'dumpsys', 'package', 'com.nope'],
        ['Unable to find package: com.nope'],
      );
    final adb = Adb(
      path: 'adb',
      runner: p,
      timeout: const Duration(seconds: 1),
    );
    final report = await readAppReport(adb, s, 'com.nope', sdk: 25);
    expect(report.package, isNull);
    expect(p.calls, hasLength(1));
  });
}
