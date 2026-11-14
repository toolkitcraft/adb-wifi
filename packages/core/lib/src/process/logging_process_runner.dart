import 'process_runner.dart';

/// Wraps a [ProcessRunner] and reports every command and its raw output.
///
/// Used for `--verbose`. Core never prints; [log] decides where text goes.
final class LoggingProcessRunner implements ProcessRunner {
  const LoggingProcessRunner(this._inner, this._log);

  final ProcessRunner _inner;
  final void Function(String line) _log;

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    _log('\$ ${commandLine(executable, arguments)}');
    final outcome = await _inner.run(executable, arguments, timeout: timeout);
    switch (outcome) {
      case ProcessCompleted(:final exitCode, :final stdout, :final stderr):
        stdout.forEach(_log);
        stderr.forEach(_log);
        _log('(exit code $exitCode)');
      case ProcessTimedOut(:final after, :final stdout, :final stderr):
        stdout.forEach(_log);
        stderr.forEach(_log);
        _log('(killed after ${after.inMilliseconds} ms: no answer)');
      case ProcessFailedToStart(:final message):
        _log('($message)');
    }
    return outcome;
  }

  @override
  Future<RunningProcess> start(String executable, List<String> arguments) {
    _log('\$ ${commandLine(executable, arguments)}  (streaming)');
    return _inner.start(executable, arguments);
  }

  @override
  Future<ProcessOutcome> runInTerminal(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) {
    _log('\$ ${commandLine(executable, arguments)}  (interactive)');
    return _inner.runInTerminal(executable, arguments, timeout: timeout);
  }
}

/// A readable command line, for logs only. Never run this string: programs
/// always start from an argument list.
String commandLine(String executable, List<String> arguments) =>
    [executable, ...arguments].map(_quoteIfNeeded).join(' ');

String _quoteIfNeeded(String word) =>
    word.isEmpty || word.contains(RegExp(r'\s')) ? '"$word"' : word;
