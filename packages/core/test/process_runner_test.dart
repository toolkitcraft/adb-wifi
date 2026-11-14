import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:test/test.dart';

/// Runs a helper program in test/programs with the Dart that runs the test,
/// so the test needs no OS tools and works on macOS, Windows and Linux.
Future<ProcessOutcome> runProgram(String name, Duration timeout) =>
    const LocalProcessRunner().run(Platform.resolvedExecutable, [
      'test/programs/$name.dart',
    ], timeout: timeout);

void main() {
  group('LocalProcessRunner.run', () {
    test('returns exit code and clean lines from both streams', () async {
      final outcome = await runProgram(
        'echo_lines',
        const Duration(seconds: 30),
      );
      expect(outcome, isA<ProcessCompleted>());
      final done = outcome as ProcessCompleted;
      expect(done.exitCode, 3);
      expect(done.stdout, ['first', 'second', 'bad�']);
      expect(done.stderr, ['warning']);
    });

    test('kills a program that hangs and keeps what it printed', () async {
      final clock = Stopwatch()..start();
      final outcome = await runProgram('hang', const Duration(seconds: 3));
      expect(outcome, isA<ProcessTimedOut>());
      expect((outcome as ProcessTimedOut).after, const Duration(seconds: 3));
      // Dart may need a moment to start the helper, so "started" is
      // usually there but not guaranteed.
      expect(outcome.stdout, anyOf(isEmpty, ['started']));
      expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('reports a program that cannot start', () async {
      final outcome = await const LocalProcessRunner().run(
        'adbwifi-no-such-program',
        ['version'],
        timeout: const Duration(seconds: 5),
      );
      expect(outcome, isA<ProcessFailedToStart>());
      expect(
        (outcome as ProcessFailedToStart).message,
        startsWith('Could not start adbwifi-no-such-program'),
      );
    });

    test('keeps at most maxLines lines per stream', () async {
      final outcome = await const LocalProcessRunner(maxLines: 2).run(
        Platform.resolvedExecutable,
        ['test/programs/echo_lines.dart'],
        timeout: const Duration(seconds: 30),
      );
      expect((outcome as ProcessCompleted).stdout, ['first', 'second']);
    });
  });

  group('LocalProcessRunner.start', () {
    test('streams lines and can be killed', () async {
      final process = await const LocalProcessRunner().start(
        Platform.resolvedExecutable,
        ['test/programs/hang.dart'],
      );
      expect(await process.stdoutLines.first, 'started');
      process.kill();
      expect(
        await process.exitCode.timeout(const Duration(seconds: 10)),
        isNot(0),
      );
    });

    test('throws ProcessStartException when it cannot start', () {
      expect(
        const LocalProcessRunner().start('adbwifi-no-such-program', []),
        throwsA(isA<ProcessStartException>()),
      );
    });
  });

  test('decodeLines splits \\n, \\r\\n and trims the line end', () async {
    final lines = await decodeLines(
      Stream.value('a\r\nb  \nc'.codeUnits),
    ).toList();
    expect(lines, ['a', 'b', 'c']);
  });
}
