import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The result of running a program to the end.
sealed class ProcessOutcome {
  const ProcessOutcome();
}

/// The program ended by itself.
final class ProcessCompleted extends ProcessOutcome {
  const ProcessCompleted(
    this.exitCode, {
    this.stdout = const [],
    this.stderr = const [],
  });

  final int exitCode;

  /// Output lines, without line endings (`\r\n` and `\n` both removed).
  final List<String> stdout;
  final List<String> stderr;

  /// Both streams, stdout first. adb prints some messages on either one.
  Iterable<String> get allLines => [...stdout, ...stderr];
}

/// The program did not end in time and was killed.
final class ProcessTimedOut extends ProcessOutcome {
  const ProcessTimedOut(
    this.after, {
    this.stdout = const [],
    this.stderr = const [],
  });

  final Duration after;

  /// What it printed before it was killed.
  final List<String> stdout;
  final List<String> stderr;
}

/// The program could not start (missing, not executable, ...).
final class ProcessFailedToStart extends ProcessOutcome {
  const ProcessFailedToStart(this.message);

  final String message;
}

/// A program that is still running and streams its output.
abstract interface class RunningProcess {
  /// Output lines, one at a time. Never holds the whole output.
  Stream<String> get stdoutLines;
  Stream<String> get stderrLines;
  Future<int> get exitCode;

  /// Stops the program. Safe to call more than once.
  void kill();
}

/// Starts programs. A boundary interface, so tests can use fakes.
///
/// Programs always get an argument list and never go through a shell, so
/// paths with spaces work and nothing is interpreted as shell syntax.
abstract interface class ProcessRunner {
  /// Runs [executable] until it ends, or kills it after [timeout].
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  });

  /// Starts [executable] and streams its output. The caller must kill it
  /// or wait for [RunningProcess.exitCode]. Throws [ProcessStartException]
  /// when it cannot start.
  Future<RunningProcess> start(String executable, List<String> arguments);

  /// Runs [executable] connected to this terminal (keyboard and screen), so
  /// it can be interactive or draw its own progress. Kills it after
  /// [timeout] when one is given.
  Future<ProcessOutcome> runInTerminal(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  });
}

/// Thrown by [ProcessRunner.start] when the program cannot start.
final class ProcessStartException implements Exception {
  const ProcessStartException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs real programs with `dart:io`.
final class LocalProcessRunner implements ProcessRunner {
  const LocalProcessRunner({this.maxLines = 200000});

  /// Lines kept per stream by [run]. Device output is untrusted, so memory
  /// stays bounded even if a command prints forever.
  final int maxLines;

  /// How long to wait for the last output after the program ends.
  static const _drainTime = Duration(seconds: 1);

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException catch (e) {
      return ProcessFailedToStart(_startError(executable, e));
    }
    final out = <String>[];
    final err = <String>[];
    final outSub = decodeLines(process.stdout).listen(_keepInto(out));
    final errSub = decodeLines(process.stderr).listen(_keepInto(err));
    final pipesClosed = Future.wait([
      outSub.asFuture<void>(),
      errSub.asFuture<void>(),
    ]);

    final code = await process.exitCode
        .then<int?>((code) => code)
        .timeout(timeout, onTimeout: () => null);
    if (code == null) await _stop(process);

    // A child it started (such as the adb server) can keep a pipe open, so
    // wait only a short time for the rest of the output.
    try {
      await pipesClosed.timeout(_drainTime, onTimeout: () => const []);
    } on Object {
      // A broken pipe only loses the last output; the exit code still counts.
    }
    await outSub.cancel();
    await errSub.cancel();

    return code == null
        ? ProcessTimedOut(timeout, stdout: out, stderr: err)
        : ProcessCompleted(code, stdout: out, stderr: err);
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    try {
      return _LocalRunningProcess(await Process.start(executable, arguments));
    } on ProcessException catch (e) {
      throw ProcessStartException(_startError(executable, e));
    }
  }

  @override
  Future<ProcessOutcome> runInTerminal(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.inheritStdio,
      );
    } on ProcessException catch (e) {
      return ProcessFailedToStart(_startError(executable, e));
    }
    if (timeout == null) return ProcessCompleted(await process.exitCode);
    final code = await process.exitCode
        .then<int?>((code) => code)
        .timeout(timeout, onTimeout: () => null);
    if (code == null) {
      await _stop(process);
      return ProcessTimedOut(timeout);
    }
    return ProcessCompleted(code);
  }

  void Function(String) _keepInto(List<String> lines) => (line) {
    if (lines.length < maxLines) lines.add(line);
  };

  /// Asks the program to stop, then forces it if it is still running.
  static Future<void> _stop(Process process) async {
    process.kill();
    final ended = await process.exitCode
        .then((_) => true)
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    if (!ended) process.kill(ProcessSignal.sigkill);
  }

  static String _startError(String executable, ProcessException e) =>
      'Could not start $executable: ${e.message}';
}

final class _LocalRunningProcess implements RunningProcess {
  _LocalRunningProcess(this._process);

  final Process _process;

  @override
  late final Stream<String> stdoutLines = decodeLines(_process.stdout);

  @override
  late final Stream<String> stderrLines = decodeLines(_process.stderr);

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  void kill() => _process.kill();
}

/// Turns raw program output into lines.
///
/// Bad UTF-8 from a device becomes U+FFFD instead of an error. Line endings
/// (`\r\n` on Windows and old Android shells) and trailing spaces go.
Stream<String> decodeLines(Stream<List<int>> bytes) => bytes
    .transform(const Utf8Decoder(allowMalformed: true))
    .transform(const LineSplitter())
    .map((line) => line.trimRight());
