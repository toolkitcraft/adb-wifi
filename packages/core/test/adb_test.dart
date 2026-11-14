import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

List<String> fixture(String name) =>
    File('test/fixtures/adb/$name').readAsLinesSync();

void main() {
  group('parseAdbVersion', () {
    test('reads platform-tools 36 (captured on macOS)', () {
      final version = parseAdbVersion(fixture('version_36.0.0_macos.txt'));
      expect(version?.protocol, '1.0.41');
      expect(version?.release, '36.0.0-13206524');
      expect(version.toString(), '36.0.0-13206524 (1.0.41)');
    });

    test('reads old adb that prints only the protocol line', () {
      final version = parseAdbVersion(['Android Debug Bridge version 1.0.32']);
      expect(version?.protocol, '1.0.32');
      expect(version?.release, isNull);
    });

    test('returns null for text that is not adb', () {
      expect(parseAdbVersion(['zsh: command not found: adb']), isNull);
    });
  });

  test('findVersionFight reads both versions from adb\'s warning', () {
    expect(
      findVersionFight([
        '* daemon not running; starting now at tcp:5037',
        "adb server version (40) doesn't match this client (41); killing...",
      ]),
      (server: '40', client: '41'),
    );
    expect(findVersionFight(['List of devices attached']), isNull);
  });

  group('Adb', () {
    late FakeProcessRunner runner;
    late Adb adb;

    setUp(() {
      runner = FakeProcessRunner();
      adb = Adb(
        path: '/sdk/adb',
        runner: runner,
        timeout: const Duration(seconds: 1),
      );
    });

    test('onDevice always passes -s serial first', () async {
      runner.onLines(['-s', 'X', 'get-state'], ['device']);
      await adb.onDevice('X', ['get-state']);
      expect(runner.calls, [
        ['-s', 'X', 'get-state'],
      ]);
    });

    test(
      'shellLines returns output even when the device exit code is not 0',
      () async {
        runner.on(
          ['-s', 'X', 'shell', 'pidof', 'com.example'],
          [const ProcessCompleted(1)],
        );
        expect(await adb.shellLines('X', ['pidof', 'com.example']), isEmpty);
      },
    );

    test('shellLines returns null when adb itself fails', () async {
      runner.on(
        ['-s', 'X', 'shell', 'id'],
        [
          const ProcessCompleted(1, stderr: ["error: device 'X' not found"]),
        ],
      );
      expect(await adb.shellLines('X', ['id']), isNull);
      runner.on(
        ['-s', 'X', 'shell', 'id'],
        [const ProcessTimedOut(Duration.zero)],
      );
      expect(await adb.shellLines('X', ['id']), isNull);
    });
  });

  group('LoggingProcessRunner', () {
    test('logs the command, raw output and exit code', () async {
      final fake = FakeProcessRunner()
        ..onLines(['devices'], ['List of devices attached']);
      final log = <String>[];
      await LoggingProcessRunner(
        fake,
        log.add,
      ).run('/My SDK/adb', ['devices'], timeout: const Duration(seconds: 1));
      expect(log, [
        r'$ "/My SDK/adb" devices',
        'List of devices attached',
        '(exit code 0)',
      ]);
    });

    test('logs a timeout', () async {
      final fake = FakeProcessRunner()
        ..on(
          ['connect', '1.2.3.4:5555'],
          [const ProcessTimedOut(Duration(seconds: 10))],
        );
      final log = <String>[];
      await LoggingProcessRunner(fake, log.add).run('adb', [
        'connect',
        '1.2.3.4:5555',
      ], timeout: const Duration(seconds: 10));
      expect(log.last, '(killed after 10000 ms: no answer)');
    });
  });
}
