import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';

/// Everything the CLI uses to reach the outside world.
///
/// [CliEnvironment.local] is the real computer; tests pass fakes, so every
/// command can be tested without adb, a network or a device.
final class CliEnvironment {
  const CliEnvironment({
    required this.platform,
    required this.files,
    required this.processes,
    required this.interfaces,
    required this.probe,
    required this.clock,
    this.store,
    this.input = const NoInput(),
    this.colors = false,
    this.interrupts = const NoInterrupts(),
    this.writers = const LocalTextWriters(),
  });

  factory CliEnvironment.local() => CliEnvironment(
    platform: HostPlatform.current(),
    files: const LocalFileProbe(),
    processes: const LocalProcessRunner(),
    interfaces: const LocalNetworkInterfaces(),
    probe: const LocalPortProbe(),
    clock: const SystemClock(),
    input: const TerminalInput(),
    colors: stdout.hasTerminal && stdout.supportsAnsiEscapes,
    interrupts: const CtrlC(),
  );

  final HostPlatform platform;
  final FileProbe files;
  final ProcessRunner processes;
  final NetworkInterfaces interfaces;
  final PortProbe probe;
  final Clock clock;

  /// Saved devices. Null means the JSON file in the OS config folder.
  final DeviceStore? store;
  final UserInput input;

  /// True when the terminal shows colors (used for the red root warning).
  final bool colors;

  /// Ctrl+C, for commands that run until stopped.
  final Interrupts interrupts;

  /// Creates text files (`logs --save`).
  final TextWriters writers;
}

/// Creates new text files. A boundary interface for fakes.
abstract interface class TextWriters {
  /// Creates [path] for writing. Never replaces a file that exists: throws
  /// [FileSystemException] instead.
  TextWriter create(String path);
}

/// A text file being written.
abstract interface class TextWriter {
  void writeln(String line);
  Future<void> close();
}

final class LocalTextWriters implements TextWriters {
  const LocalTextWriters();

  @override
  TextWriter create(String path) {
    final file = File(path);
    if (file.existsSync()) {
      throw FileSystemException('The file already exists', path);
    }
    return _SinkWriter(file.openWrite());
  }
}

final class _SinkWriter implements TextWriter {
  _SinkWriter(this._sink);

  final IOSink _sink;

  @override
  void writeln(String line) => _sink.writeln(line);

  @override
  Future<void> close() => _sink.close();
}

/// Reads answers typed by the user.
abstract interface class UserInput {
  /// True when a person can answer questions (stdin is a terminal).
  bool get canAsk;

  /// The next line typed, or null at end of input.
  String? readLine();
}

/// Reads from the terminal.
final class TerminalInput implements UserInput {
  const TerminalInput();

  @override
  bool get canAsk => stdin.hasTerminal;

  @override
  String? readLine() => stdin.readLineSync();
}

/// No one to ask: questions get no answer.
final class NoInput implements UserInput {
  const NoInput();

  @override
  bool get canAsk => false;

  @override
  String? readLine() => null;
}

/// Tells long-running commands that the user pressed Ctrl+C.
abstract interface class Interrupts {
  /// Calls [onInterrupt] on each Ctrl+C until the returned function is
  /// called.
  Future<void> Function() watch(void Function() onInterrupt);
}

/// The real Ctrl+C (SIGINT; Dart also delivers it on Windows).
final class CtrlC implements Interrupts {
  const CtrlC();

  @override
  Future<void> Function() watch(void Function() onInterrupt) {
    // Cancelled by the caller through the returned function.
    // ignore: cancel_subscriptions
    final subscription = ProcessSignal.sigint.watch().listen(
      (_) => onInterrupt(),
    );
    return subscription.cancel;
  }
}

/// Never interrupted (scripts without a terminal, tests).
final class NoInterrupts implements Interrupts {
  const NoInterrupts();

  @override
  Future<void> Function() watch(void Function() onInterrupt) => () async {};
}
