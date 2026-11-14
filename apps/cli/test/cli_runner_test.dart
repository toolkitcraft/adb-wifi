import 'dart:convert';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

const versionLines = [
  'Android Debug Bridge version 1.0.41',
  'Version 36.0.0-13206524',
];

void main() {
  late Harness h;

  setUp(() => h = Harness());

  group('version', () {
    test('shows the tool version and the SDK adb with its version', () async {
      h.processes.onLines(['version'], versionLines);
      expect(await h.run(['version']), ExitCodes.ok);
      expect(h.out.toString(), '''
adbwifi $toolVersion
adb 36.0.0-13206524 (1.0.41)
   $macSdkAdb  (Android SDK default folder)
''');
      expect(h.err.toString(), isEmpty);
    });

    test('lists other adb programs it found', () async {
      h.files.existing.add('/opt/homebrew/bin/adb');
      h.processes.onLines(['version'], versionLines);
      await h.run(['version']);
      expect(
        h.out.toString(),
        contains('also found: /opt/homebrew/bin/adb  (Homebrew)'),
      );
    });

    test('still works when adb hangs on "adb version"', () async {
      h.processes.on(
        ['version'],
        [const ProcessTimedOut(Duration(seconds: 10))],
      );
      expect(await h.run(['version']), ExitCodes.ok);
      expect(h.out.toString(), contains('adb (version unknown)'));
    });

    test('explains how to install adb when it is missing', () async {
      h = Harness(adbInstalled: false);
      expect(await h.run(['version']), ExitCodes.ok);
      expect(h.out.toString(), contains('❌ adb not found.'));
      expect(
        h.out.toString(),
        contains('brew install --cask android-platform-tools'),
      );
    });

    test('--json prints one JSON document', () async {
      h.processes.onLines(['version'], versionLines);
      expect(await h.run(['--json', 'version']), ExitCodes.ok);
      expect(jsonDecode(h.out.toString()), {
        'adbwifi': toolVersion,
        'adb': {
          'path': macSdkAdb,
          'source': 'defaultSdk',
          'version': '36.0.0-13206524',
          'protocol': '1.0.41',
          'others': <String>[],
        },
      });
    });

    test('--verbose shows the adb command and raw output on stderr', () async {
      h.processes.onLines(['version'], versionLines);
      await h.run(['-v', 'version']);
      expect(h.err.toString(), '''
[adb] \$ $macSdkAdb version
[adb] Android Debug Bridge version 1.0.41
[adb] Version 36.0.0-13206524
[adb] (exit code 0)
''');
    });
  });

  group('global options', () {
    test('a bad --timeout is a usage error', () async {
      expect(await h.run(['--timeout', 'abc', 'version']), ExitCodes.usage);
      expect(h.err.toString(), contains('--timeout must be a number'));
      expect(await h.run(['--timeout', '0', 'version']), ExitCodes.usage);
    });
  });

  test('no arguments prints help that lists the commands', () async {
    expect(await h.run([]), ExitCodes.ok);
    expect(h.out.toString(), contains('Usage: adbwifi <command>'));
    expect(h.out.toString(), contains('version'));
    expect(h.out.toString(), contains('--json'));
  });

  test('an unknown command is a usage error on stderr', () async {
    expect(await h.run(['nope']), ExitCodes.usage);
    expect(h.out.toString(), isEmpty);
    expect(h.err.toString(), contains('Could not find a command named "nope"'));
  });
}
