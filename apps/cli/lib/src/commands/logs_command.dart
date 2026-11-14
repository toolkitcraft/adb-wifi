import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:args/command_runner.dart';

import '../base_command.dart';
import '../cli_environment.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../session.dart';

/// `adbwifi logs --app <package>`: one app's log, following restarts.
class LogsCommand extends AdbWifiCommand {
  LogsCommand(super.holder) {
    argParser
      ..addOption(
        'app',
        abbr: 'a',
        valueHelp: 'package',
        help: 'The app, such as com.example.app.',
      )
      ..addOption('tag', abbr: 't', help: 'Only lines with this tag.')
      ..addOption(
        'level',
        abbr: 'l',
        allowed: ['v', 'd', 'i', 'w', 'e', 'f'],
        help: 'Only this level and higher (v d i w e f).',
      )
      ..addOption('grep', abbr: 'g', help: 'Only lines that match (regex).')
      ..addOption(
        'save',
        valueHelp: 'file',
        help: 'Also write the lines to a new file (secrets hidden).',
      )
      ..addFlag(
        'clear',
        negatable: false,
        help: 'Clear the device log first (logcat -c).',
      )
      ..addFlag(
        'dump',
        negatable: false,
        help: 'Print what is in the log now, then stop.',
      );
  }

  @override
  final name = 'logs';

  @override
  final description =
      'Show one app\'s log. Follows restarts and keeps crash, ANR and '
      '"has died" lines. Ctrl+C stops.';

  @override
  String get invocation => 'adbwifi logs --app <package> [options]';

  @override
  Future<int> run() async {
    final args = argResults;
    if (args == null) return ExitCodes.usage;
    final package = args.option('app');
    if (package == null || !isValidPackage(package)) {
      throw UsageException(
        'Give the app package: --app com.example.app',
        usage,
      );
    }
    final options = LogOptions(
      tag: args.option('tag'),
      minLevel: switch (args.option('level')) {
        null => null,
        final l => LogLevel.fromLetter(l),
      },
      grep: _regex(args.option('grep')),
    );

    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    final serial = target.adbSerial;
    final sdk = await session.sdkOf(adb, serial);
    if (args.flag('clear')) await adb.onDevice(serial, const ['logcat', '-c']);
    final saving = _openSave(args.option('save'));

    final dump = args.flag('dump');
    final follower = LogFollower(
      adb: adb,
      serial: serial,
      filter: AppLogFilter(package, options: options),
      sdk: sdk,
      clock: session.environment.clock,
    );
    if (!console.json) {
      console.line(
        '📜 $package on ${target.label}'
        '${sdk == null ? '' : ' (SDK $sdk)'}'
        '${dump ? '' : '. Ctrl+C stops.'}',
      );
    }
    final stopWatching = session.environment.interrupts.watch(
      () => unawaited(follower.stop()),
    );
    var saved = 0;
    var ok = true;
    try {
      await for (final event in follower.follow(dump: dump)) {
        if (event case LogLineEvent(:final line)) {
          if (saving != null) {
            saving.writeln(redactSecrets(line.raw));
            saved++;
          }
        }
        if (event case LogEnded(message: _?)) ok = false;
        _show(event, package);
      }
    } finally {
      await stopWatching();
      await saving?.close();
    }
    if (saving != null && !console.json) {
      console.ok(
        'Saved $saved line${saved == 1 ? '' : 's'} to ${args.option('save')} '
        '(tokens, keys and passwords hidden).',
      );
    }
    return ok ? ExitCodes.ok : ExitCodes.failure;
  }

  void _show(LogEvent event, String package) {
    if (console.json) {
      console.out.writeln(jsonEncode(_json(event)));
      return;
    }
    switch (event) {
      case LogLineEvent(:final line):
        console.line(line.raw);
      case AppNotRunning():
        console.line('⏳ $package is not running. Waiting for it to start ...');
      case AppRunning(:final pid, previous: null):
        console.line('▶️  $package is running (PID $pid).');
      case AppRunning(:final pid, :final previous?):
        console.line('🔄 $package started again (PID $pid, was $previous).');
      case AppStopped(:final pid):
        console.line(
          '💥 $package stopped or crashed (PID $pid). Waiting for it to '
          'start ...',
        );
      case LogEnded(:final message?):
        console.warn(message);
      case LogEnded():
        break;
    }
  }

  static Map<String, Object?> _json(LogEvent event) => switch (event) {
    LogLineEvent(:final line, :final important) => {
      'event': 'line',
      ...line.toJson(),
      'important': important,
    },
    AppNotRunning() => {'event': 'not_running'},
    AppRunning(:final pid, :final previous) => {
      'event': 'running',
      'pid': pid,
      'previous': previous,
    },
    AppStopped(:final pid) => {'event': 'stopped', 'pid': pid},
    LogEnded(:final message) => {'event': 'ended', 'message': message},
  };

  RegExp? _regex(String? pattern) {
    if (pattern == null) return null;
    try {
      return RegExp(pattern);
    } on FormatException catch (e) {
      throw UsageException(
        '--grep is not a valid pattern: ${e.message}',
        usage,
      );
    }
  }

  TextWriter? _openSave(String? path) {
    if (path == null) return null;
    try {
      return session.environment.writers.create(path);
    } on FileSystemException catch (e) {
      throw CliFailure(
        'Cannot create $path: ${e.message}.',
        fix: 'Use a new file name; adbwifi never overwrites a file.',
      );
    }
  }
}
