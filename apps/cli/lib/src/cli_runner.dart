import 'package:args/args.dart';
import 'package:args/command_runner.dart';

import 'base_command.dart';
import 'cli_environment.dart';
import 'commands/app_command.dart';
import 'commands/connect_command.dart';
import 'commands/device_commands.dart';
import 'commands/devices_command.dart';
import 'commands/doctor_command.dart';
import 'commands/find_command.dart';
import 'commands/install_command.dart';
import 'commands/logs_command.dart';
import 'commands/store_commands.dart';
import 'commands/version_command.dart';
import 'console.dart';
import 'session.dart';

/// Exit codes, following the BSD `sysexits.h` convention where one fits.
abstract final class ExitCodes {
  static const ok = 0;
  static const failure = 1;
  static const usage = 64;
}

/// Runs adbwifi with [arguments] and returns the process exit code.
///
/// Output goes to [out] and errors to [err] instead of `stdout`/`stderr`
/// directly, and the outside world comes from [environment], so tests can
/// capture output and use fakes.
Future<int> runCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
  CliEnvironment? environment,
}) async {
  final holder = SessionHolder();
  final runner =
      _AdbWifiRunner(
          out: out,
          err: err,
          environment: environment ?? CliEnvironment.local(),
          holder: holder,
        )
        ..addCommand(AppCommand(holder))
        ..addCommand(DisconnectCommand(holder))
        ..addCommand(DoctorCommand(holder))
        ..addCommand(FindCommand(holder))
        ..addCommand(ConnectCommand(holder))
        ..addCommand(DevicesCommand(holder))
        ..addCommand(LogsCommand(holder))
        ..addCommand(NameCommand(holder))
        ..addCommand(ForgetCommand(holder))
        ..addCommand(InfoCommand(holder))
        ..addCommand(InstallCommand(holder))
        ..addCommand(PullCommand(holder))
        ..addCommand(PushCommand(holder))
        ..addCommand(ShellCommand(holder))
        ..addCommand(VersionCommand(holder));
  try {
    return await runner.run(arguments) ?? ExitCodes.ok;
  } on UsageException catch (e) {
    err.writeln(e);
    return ExitCodes.usage;
  } on CliFailure catch (failure) {
    runner.report(failure);
    return failure.exitCode;
  }
}

class _AdbWifiRunner extends CommandRunner<int> {
  _AdbWifiRunner({
    required StringSink out,
    required StringSink err,
    required CliEnvironment environment,
    required SessionHolder holder,
  }) : _out = out,
       _err = err,
       _environment = environment,
       _holder = holder,
       super(
         'adbwifi',
         'Connect to Android devices over Wi-Fi and find out why it fails.',
       ) {
    GlobalOptions.addTo(argParser);
  }

  final StringSink _out;
  final StringSink _err;
  final CliEnvironment _environment;
  final SessionHolder _holder;
  Console? _console;

  // CommandRunner prints help with `print`; send it to our sink instead.
  @override
  void printUsage() => _out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) {
    final options = GlobalOptions.from(topLevelResults);
    final console = Console(
      _out,
      _err,
      json: options.json,
      colors: _environment.colors && !options.json,
    );
    _console = console;
    _holder.session = Session(
      environment: _environment,
      options: options,
      console: console,
    );
    return super.runCommand(topLevelResults);
  }

  /// Prints a failure: JSON on stdout with `--json`, else text on stderr.
  void report(CliFailure failure) {
    final console = _console;
    if (console != null && console.json) {
      console.printJson(failure.toJson());
      return;
    }
    final text = Console(_err, _err)..fail(failure.message);
    if (failure.fix case final fix?) text.fix(fix);
  }
}
