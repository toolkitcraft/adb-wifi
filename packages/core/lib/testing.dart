/// Fakes for the boundary interfaces, for tests of this package and of the
/// apps built on it. Not for production code.
library;

import 'dart:async';

import 'adb_wifi_core.dart';

/// A file system that holds exactly the files in [existing], with sizes
/// from [sizes] (0 when not given).
final class FakeFileProbe implements FileProbe {
  FakeFileProbe([Set<String>? existing]) : existing = existing ?? {};

  final Set<String> existing;
  final sizes = <String, int>{};

  @override
  bool isFile(String path) => existing.contains(path);

  @override
  int? length(String path) => isFile(path) ? sizes[path] ?? 0 : null;
}

/// A clock that starts at [start] and jumps forward instead of waiting.
final class FakeClock implements Clock {
  FakeClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 11, 14, 9);

  DateTime _now;

  /// Every wait asked for, in order.
  final sleeps = <Duration>[];

  /// Called on each wait, after the time moved on.
  void Function()? onSleep;

  @override
  DateTime now() => _now;

  @override
  Future<void> sleep(Duration duration) async {
    sleeps.add(duration);
    _now = _now.add(duration);
    onSleep?.call();
    // Let timers and I/O run, as a real wait would; a loop that sleeps
    // must never starve the event loop in tests.
    await Future<void>.delayed(Duration.zero);
  }
}

/// Keeps devices in memory.
final class FakeDeviceStore implements DeviceStore {
  FakeDeviceStore([DeviceBook? book]) : book = book ?? DeviceBook();

  DeviceBook book;

  /// Set to make [load] report a broken file.
  String? brokenReason;
  int saves = 0;

  @override
  String get location => '/fake/devices.json';

  @override
  Future<StoreLoad> load() async => switch (brokenReason) {
    null => StoreLoaded(book),
    final reason => StoreBroken(location, reason),
  };

  @override
  Future<void> save(DeviceBook book) async {
    this.book = book;
    saves++;
  }
}

/// A computer with exactly the [addresses] given.
final class FakeNetworkInterfaces implements NetworkInterfaces {
  FakeNetworkInterfaces([List<HostAddress>? addresses])
    : addresses = addresses ?? [];

  final List<HostAddress> addresses;

  @override
  Future<List<HostAddress>> list() async => addresses;
}

/// A network where only the addresses in [states] answer; every other
/// address gives [otherwise].
final class FakePortProbe implements PortProbe {
  FakePortProbe([Map<NetworkAddress, PortState>? states])
    : states = states ?? {};

  final Map<NetworkAddress, PortState> states;
  PortState otherwise = const PortNoAnswer();

  /// Every address that was checked.
  final checked = <NetworkAddress>[];

  @override
  Future<PortState> check(
    NetworkAddress address, {
    required Duration timeout,
  }) async {
    checked.add(address);
    return states[address] ?? otherwise;
  }
}

/// A process runner that answers from a script instead of running programs.
///
/// Answers are keyed by the argument list (the executable is ignored). An
/// answer can be a list of outcomes, used in order; the last one repeats.
final class FakeProcessRunner implements ProcessRunner {
  final _answers = <String, List<ProcessOutcome>>{};
  final _streams = <String, FakeRunningProcess>{};

  /// Every argument list that was run, in order.
  final calls = <List<String>>[];

  /// Answers [arguments] with [outcomes], one per call.
  void on(List<String> arguments, List<ProcessOutcome> outcomes) {
    _answers[_key(arguments)] = [...outcomes];
  }

  /// Answers [arguments] with lines on stdout and exit code 0.
  void onLines(List<String> arguments, List<String> lines) =>
      on(arguments, [ProcessCompleted(0, stdout: lines)]);

  /// Answers a streamed [arguments] with [process].
  void onStream(List<String> arguments, FakeRunningProcess process) {
    _streams[_key(arguments)] = process;
  }

  @override
  Future<ProcessOutcome> run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls.add(arguments);
    return _next(arguments);
  }

  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments,
  ) async {
    calls.add(arguments);
    final process = _streams[_key(arguments)];
    if (process == null) {
      throw ProcessStartException('no fake stream for $arguments');
    }
    return process;
  }

  @override
  Future<ProcessOutcome> runInTerminal(
    String executable,
    List<String> arguments, {
    Duration? timeout,
  }) async {
    calls.add(arguments);
    return _next(arguments);
  }

  ProcessOutcome _next(List<String> arguments) {
    final queue = _answers[_key(arguments)];
    if (queue == null || queue.isEmpty) {
      return ProcessCompleted(
        1,
        stderr: ['error: fake has no answer for ${arguments.join(' ')}'],
      );
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }

  static String _key(List<String> arguments) => arguments.join('\u0000');
}

/// A streaming process controlled by the test.
final class FakeRunningProcess implements RunningProcess {
  final _stdout = StreamController<String>();
  final _stderr = StreamController<String>();
  final _exit = Completer<int>();

  bool killed = false;

  /// Sends one stdout line.
  void emit(String line) => _stdout.add(line);

  /// Ends the process with [code]. Like a real pipe, closing does not wait
  /// for anyone to read the rest.
  Future<void> finish([int code = 0]) async {
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<String> get stdoutLines => _stdout.stream;

  @override
  Stream<String> get stderrLines => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void kill() {
    killed = true;
    unawaited(finish(-15));
  }
}
