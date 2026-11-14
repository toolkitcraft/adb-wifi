import 'package:args/command_runner.dart';

import '../cli_runner.dart';
import '../version.dart';

/// `adbwifi version`: prints the tool version.
class VersionCommand extends Command<int> {
  VersionCommand(this._out);

  final StringSink _out;

  @override
  final name = 'version';

  @override
  final description = 'Show the adbwifi version.';

  @override
  int run() {
    _out.writeln('adbwifi $toolVersion');
    return ExitCodes.ok;
  }
}
