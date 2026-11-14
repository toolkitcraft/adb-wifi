import 'package:args/command_runner.dart';

import 'commands/version_command.dart';

/// Exit codes, following the BSD `sysexits.h` convention where one fits.
abstract final class ExitCodes {
  static const ok = 0;
  static const failure = 1;
  static const usage = 64;
}

/// Runs adbwifi with [arguments] and returns the process exit code.
///
/// Output goes to [out] and errors to [err] instead of `stdout`/`stderr`
/// directly, so tests can capture both.
Future<int> runCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) async {
  final runner = _AdbWifiRunner(out)..addCommand(VersionCommand(out));
  try {
    return await runner.run(arguments) ?? ExitCodes.ok;
  } on UsageException catch (e) {
    err.writeln(e);
    return ExitCodes.usage;
  }
}

class _AdbWifiRunner extends CommandRunner<int> {
  _AdbWifiRunner(this._out)
    : super(
        'adbwifi',
        'Connect to Android devices over Wi-Fi and find out why it fails.',
      );

  final StringSink _out;

  // CommandRunner prints help with `print`; send it to our sink instead.
  @override
  void printUsage() => _out.writeln(usage);
}
