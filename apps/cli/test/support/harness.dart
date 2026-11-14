import 'dart:io';

import 'package:adb_wifi_cli/adb_wifi_cli.dart';
import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';

const macSdkAdb = '/Users/me/Library/Android/sdk/platform-tools/adb';
final tabletIp = Ipv4.tryParse('192.168.1.202')!;
final tablet = NetworkAddress(tabletIp);
final macAddress = (adapter: 'en0', ip: Ipv4.tryParse('192.168.1.5')!);

/// A fake Mac on 192.168.1.5 with the SDK adb installed, and captured
/// output. Tests add adb answers and port states as they need.
final class Harness {
  Harness({bool adbInstalled = true})
    : files = FakeFileProbe({if (adbInstalled) macSdkAdb});

  final platform = const HostPlatform(
    os: HostOs.macos,
    environment: {'HOME': '/Users/me', 'PATH': '/usr/bin'},
  );
  final FakeFileProbe files;
  final processes = FakeProcessRunner();
  final interfaces = FakeNetworkInterfaces([macAddress]);
  final probe = FakePortProbe();
  final clock = FakeClock();
  final store = FakeDeviceStore();
  final input = ScriptedInput();
  final interrupts = FakeInterrupts();
  final writers = FakeTextWriters();
  final out = StringBuffer();
  final err = StringBuffer();

  Future<int> run(List<String> args) => runCli(
    args,
    out: out,
    err: err,
    environment: CliEnvironment(
      platform: platform,
      files: files,
      processes: processes,
      interfaces: interfaces,
      probe: probe,
      clock: clock,
      store: store,
      input: input,
      interrupts: interrupts,
      writers: writers,
    ),
  );

  /// Calls made to adb, without the executable.
  List<List<String>> get calls => processes.calls;

  /// `adb devices -l` lists [lines] (after the header).
  void devices(List<String> lines) => processes.onLines(
    ['devices', '-l'],
    ['List of devices attached', ...lines],
  );

  /// A healthy tablet at 192.168.1.202: port open, connects, answers.
  void healthyTablet({bool root = false}) {
    probe.states[tablet] = const PortOpen();
    processes
      ..onLines(['version'], ['Android Debug Bridge version 1.0.41'])
      ..onLines(['start-server'], [])
      ..onLines(
        ['connect', '192.168.1.202:5555'],
        ['connected to 192.168.1.202:5555'],
      );
    devices(['192.168.1.202:5555\tdevice product:rk3288 model:YC119R']);
    deviceAnswers('192.168.1.202:5555', root: root);
  }

  /// The device [serial] answers getprop and id.
  void deviceAnswers(String serial, {bool root = false, String sdk = '25'}) {
    processes
      ..onLines(
        ['-s', serial, 'shell', 'getprop'],
        [
          '[ro.product.model]: [YC119R]',
          '[ro.build.version.release]: [7.1.2]',
          '[ro.build.version.sdk]: [$sdk]',
          '[ro.build.type]: [userdebug]',
          '[ro.serialno]: [A1B2C3D4E5]',
        ],
      )
      ..onLines(
        ['-s', serial, 'shell', 'id'],
        [root ? 'uid=0(root) gid=0(root)' : 'uid=2000(shell) gid=2000(shell)'],
      );
  }
}

/// Answers questions from a list, as if a person typed them.
final class ScriptedInput implements UserInput {
  final answers = <String>[];

  @override
  bool canAsk = true;

  @override
  String? readLine() => answers.isEmpty ? null : answers.removeAt(0);
}

/// Ctrl+C on demand.
final class FakeInterrupts implements Interrupts {
  void Function()? _handler;

  /// Presses Ctrl+C.
  void press() => _handler?.call();

  @override
  Future<void> Function() watch(void Function() onInterrupt) {
    _handler = onInterrupt;
    return () async => _handler = null;
  }
}

/// Files written by the CLI, kept in memory.
final class FakeTextWriters implements TextWriters {
  final files = <String, List<String>>{};
  final closed = <String>{};

  @override
  TextWriter create(String path) {
    if (files.containsKey(path)) {
      throw FileSystemException('The file already exists', path);
    }
    final lines = files[path] = [];
    return _FakeWriter(lines, () => closed.add(path));
  }
}

final class _FakeWriter implements TextWriter {
  _FakeWriter(this._lines, this._onClose);

  final List<String> _lines;
  final void Function() _onClose;

  @override
  void writeln(String line) => _lines.add(line);

  @override
  Future<void> close() async => _onClose();
}
