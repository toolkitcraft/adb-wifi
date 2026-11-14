import 'package:args/command_runner.dart';

import 'console.dart';
import 'session.dart';

/// Holds the [Session] of the current run. The runner sets it after it
/// reads the global options and before any command runs.
final class SessionHolder {
  Session? _session;

  Session get session =>
      _session ?? (throw StateError('A command ran before its session.'));

  set session(Session value) => _session = value;
}

/// Base class for adbwifi commands.
abstract class AdbWifiCommand extends Command<int> {
  AdbWifiCommand(this._holder);

  final SessionHolder _holder;

  Session get session => _holder.session;
  Console get console => session.console;

  /// The only positional argument, or null; more is a usage error.
  String? optionalArgument(String what) => switch (argResults?.rest) {
    null || [] => null,
    [final one] => one,
    _ => throw UsageException('Give at most one $what.', usage),
  };

  /// The single required positional argument.
  String requiredArgument(String what) =>
      optionalArgument(what) ??
      (throw UsageException('Give the $what.', usage));
}
