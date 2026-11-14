import '../process/process_runner.dart';

/// Runs one adb program. Every call has a timeout.
final class Adb {
  const Adb({
    required this.path,
    required ProcessRunner runner,
    required this.timeout,
  }) : _runner = runner;

  /// Full path of the adb executable.
  final String path;

  /// Time limit for one adb call, unless a call gives its own.
  final Duration timeout;

  final ProcessRunner _runner;

  /// The process runner, for callers that stream or need the terminal.
  ProcessRunner get runner => _runner;

  /// Runs `adb <arguments>`.
  Future<ProcessOutcome> run(List<String> arguments, {Duration? timeout}) =>
      _runner.run(path, arguments, timeout: timeout ?? this.timeout);

  /// Runs `adb -s <serial> <arguments>`. Always name the device: with two
  /// devices attached, adb refuses to guess.
  Future<ProcessOutcome> onDevice(
    String serial,
    List<String> arguments, {
    Duration? timeout,
  }) => run(['-s', serial, ...arguments], timeout: timeout);

  /// Runs `adb -s <serial> shell <command>` and returns its output lines, or
  /// null when adb itself failed (device gone, timeout, could not start).
  ///
  /// The device command's exit code is ignored on purpose: Android 6 and
  /// older always report 0, so callers read the output instead.
  ///
  /// adb joins [command] into one string for the device's shell, so every
  /// word must be a constant or a value checked by the caller.
  Future<List<String>?> shellLines(
    String serial,
    List<String> command, {
    Duration? timeout,
  }) async {
    final outcome = await onDevice(serial, [
      'shell',
      ...command,
    ], timeout: timeout);
    return switch (outcome) {
      ProcessCompleted(:final stdout, :final stderr)
          when !stderr.any(isAdbError) =>
        stdout,
      _ => null,
    };
  }
}

/// True for a line where adb (not the device) reports an error, such as
/// `error: device '1.2.3.4:5555' not found` or `adb: device offline`.
bool isAdbError(String line) {
  final text = line.trimLeft();
  return text.startsWith('error:') || text.startsWith('adb: ');
}

/// The version adb reports with `adb version`.
final class AdbVersion {
  const AdbVersion({required this.protocol, this.release});

  /// The "Android Debug Bridge version" line, e.g. `1.0.41`.
  final String protocol;

  /// The platform-tools release, e.g. `36.0.0-13206524`. Old adb lacks it.
  final String? release;

  @override
  String toString() => release == null ? protocol : '$release ($protocol)';
}

/// Reads the output of `adb version`. Null when the text is not adb's.
AdbVersion? parseAdbVersion(Iterable<String> lines) {
  String? protocol;
  String? release;
  for (final line in lines) {
    final text = line.trim();
    final p = _protocolLine.firstMatch(text);
    if (p != null) protocol = p.group(1);
    final r = _releaseLine.firstMatch(text);
    if (r != null) release = r.group(1);
  }
  return protocol == null
      ? null
      : AdbVersion(protocol: protocol, release: release);
}

final _protocolLine = RegExp(r'^Android Debug Bridge version (\S+)$');
final _releaseLine = RegExp(r'^Version (\S+)$');

/// The client and server versions from adb's warning that two different
/// adb programs fight over the server, for example:
/// `adb server version (40) doesn't match this client (41); killing...`
({String server, String client})? findVersionFight(Iterable<String> lines) {
  for (final line in lines) {
    final m = _fightLine.firstMatch(line);
    if (m != null) {
      return (server: m.group(1) ?? '?', client: m.group(2) ?? '?');
    }
  }
  return null;
}

final _fightLine = RegExp(
  r"adb server version \((\d+)\) doesn't match this client \((\d+)\)",
);
