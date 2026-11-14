import 'dart:async';

import '../adb/adb.dart';
import '../platform/clock.dart';
import '../process/process_runner.dart';
import 'app_process.dart';
import 'log_line.dart';

/// The user's filters for `adbwifi logs`.
final class LogOptions {
  const LogOptions({this.tag, this.minLevel, this.grep});

  /// Only this tag (exact).
  final String? tag;

  /// Only this level and higher.
  final LogLevel? minLevel;

  /// Only lines that match.
  final RegExp? grep;

  bool allows(LogLine line) {
    final (tag, minLevel, grep) = (this.tag, this.minLevel, this.grep);
    return (tag == null || line.tag == tag) &&
        (minLevel == null || line.level.index >= minLevel.index) &&
        (grep == null || grep.hasMatch(line.raw));
  }
}

/// Decides which logcat lines belong to the app. Stateful: it knows the
/// app's PIDs and whether a native crash report is being printed.
final class AppLogFilter {
  AppLogFilter(this.package, {this.options = const LogOptions()})
    : _mention = RegExp(RegExp.escape(package));

  final String package;
  final LogOptions options;
  final RegExp _mention;

  /// The current PID and the one before it (its last lines can still
  /// arrive after a restart).
  final _pids = <int>[];

  /// DEBUG lines still to keep from a native crash report.
  int _crashLines = 0;
  static const _crashReportLines = 300;

  int? get pid => _pids.lastOrNull;

  set pid(int? value) {
    if (value == null || value == pid) return;
    _pids.add(value);
    if (_pids.length > 2) _pids.removeAt(0);
  }

  /// The line to show, or null. `important` lines (the system talking
  /// about the app: "has died", "ANR in", a native crash report) are
  /// shown even when the user's filters would hide them.
  ({LogLine line, bool important})? check(LogLine line) {
    final mentions = _mention.hasMatch(line.message);
    if (line.tag == 'DEBUG') {
      // A tombstone starts with ">>> com.example.app <<<".
      if (mentions) _crashLines = _crashReportLines;
      if (_crashLines > 0) {
        _crashLines--;
        return (line: line, important: true);
      }
    }
    if (_pids.contains(line.pid)) {
      return options.allows(line) ? (line: line, important: false) : null;
    }
    return mentions ? (line: line, important: true) : null;
  }
}

/// Something that happened while following an app's log.
sealed class LogEvent {
  const LogEvent();
}

final class LogLineEvent extends LogEvent {
  const LogLineEvent(this.line, {this.important = false});

  final LogLine line;
  final bool important;
}

/// The app is running with [pid] (at the start, or after a restart).
final class AppRunning extends LogEvent {
  const AppRunning(this.pid, {this.previous});

  final int pid;

  /// The PID before a restart.
  final int? previous;
}

/// The app's process is gone: it stopped or crashed.
final class AppStopped extends LogEvent {
  const AppStopped(this.pid);

  final int pid;
}

/// The app is not running yet; adbwifi waits for it.
final class AppNotRunning extends LogEvent {
  const AppNotRunning();
}

/// logcat ended (device gone, or `--dump` finished).
final class LogEnded extends LogEvent {
  const LogEnded({this.message});

  /// Why, when it was not a normal end.
  final String? message;
}

/// Streams one app's log lines and notices restarts and crashes.
///
/// It reads the whole `logcat -v threadtime` stream and filters on the
/// computer, for every Android version. That keeps the lines other
/// processes write about the app (ActivityManager "has died", "ANR in",
/// the DEBUG crash report), which `logcat --pid` would drop, and it works
/// on Android 4.4 to 6, which have no `--pid`. Every 2 seconds it checks
/// the PID: `pidof` on Android 7+, `ps` on older devices.
final class LogFollower {
  LogFollower({
    required this.adb,
    required this.serial,
    required this.filter,
    required this.sdk,
    required this.clock,
    this.pollEvery = const Duration(seconds: 2),
  });

  final Adb adb;
  final String serial;
  final AppLogFilter filter;
  final int? sdk;
  final Clock clock;
  final Duration pollEvery;

  RunningProcess? _logcat;
  bool _stopped = false;

  /// Follows the log until [stop] or until logcat ends. With [dump], prints
  /// what is in the buffer now and ends (`logcat -d`).
  Stream<LogEvent> follow({bool dump = false}) {
    late final StreamController<LogEvent> events;
    events = StreamController<LogEvent>(
      onListen: () => unawaited(_run(events, dump: dump)),
      onCancel: stop,
    );
    return events.stream;
  }

  /// Stops following and kills logcat.
  Future<void> stop() async {
    _stopped = true;
    _logcat?.kill();
  }

  Future<void> _run(
    StreamController<LogEvent> events, {
    required bool dump,
  }) async {
    final pid = await _findPid();
    filter.pid = pid;
    events.add(pid == null ? const AppNotRunning() : AppRunning(pid));

    final RunningProcess logcat;
    try {
      logcat = await adb.runner.start(adb.path, [
        '-s',
        serial,
        'logcat',
        '-v',
        'threadtime',
        if (dump) '-d',
      ]);
    } on ProcessStartException catch (e) {
      events.add(LogEnded(message: e.message));
      await events.close();
      return;
    }
    _logcat = logcat;
    if (_stopped) logcat.kill();

    final linesDone = Completer<void>();
    final lines = logcat.stdoutLines.listen((raw) {
      final line = parseLogLine(raw);
      if (line == null) return;
      final kept = filter.check(line);
      if (kept != null) {
        events.add(LogLineEvent(kept.line, important: kept.important));
      }
    }, onDone: linesDone.complete);
    final polling = dump ? Future<void>.value() : _poll(events, pid);
    final code = await logcat.exitCode;
    _stopped = true;
    // The last lines can arrive just after the exit; wait a little.
    await linesDone.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    await lines.cancel();
    await polling;
    events.add(
      LogEnded(
        message: dump || code == 0 || code < 0
            ? null
            : 'logcat stopped (exit code $code): the device may be gone.',
      ),
    );
    await events.close();
  }

  /// Checks the PID every [pollEvery] and reports stops and restarts.
  Future<void> _poll(StreamController<LogEvent> events, int? first) async {
    var current = first;
    var last = first;
    while (!_stopped) {
      await clock.sleep(pollEvery);
      if (_stopped) return;
      final now = await _findPid();
      if (_stopped || now == current) continue;
      if (now == null) {
        // The filter keeps the old PID: its last lines may still arrive.
        events.add(AppStopped(last ?? 0));
      } else {
        filter.pid = now;
        events.add(AppRunning(now, previous: last));
        last = now;
      }
      current = now;
    }
  }

  Future<int?> _findPid() => findAppPid(adb, serial, filter.package, sdk: sdk);
}
