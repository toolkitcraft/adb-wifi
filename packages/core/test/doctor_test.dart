import 'dart:io';

import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

final tablet = NetworkAddress.tryParse('192.168.1.202')!;
final mac = (adapter: 'en0', ip: Ipv4.tryParse('192.168.1.5')!);
const adbPath = '/sdk/platform-tools/adb';

ProcessCompleted devicesOutput(String state) => ProcessCompleted(
  0,
  stdout: ['List of devices attached', '192.168.1.202:5555\t$state'],
);

final class Scenario {
  Scenario() {
    processes
      ..onLines(['version'], ['Android Debug Bridge version 1.0.41'])
      ..onLines(['start-server'], [])
      ..onLines(
        ['connect', '192.168.1.202:5555'],
        ['connected to 192.168.1.202:5555'],
      )
      ..on(['devices', '-l'], [devicesOutput('device')])
      ..onLines([
        '-s',
        '192.168.1.202:5555',
        'shell',
        'getprop',
      ], File('test/fixtures/device/getprop_yc119r.txt').readAsLinesSync())
      ..onLines(
        ['-s', '192.168.1.202:5555', 'shell', 'id'],
        ['uid=2000(shell)'],
      );
  }

  AdbLookup lookup = const AdbFound((
    path: adbPath,
    source: AdbSource.defaultSdk,
  ));
  final processes = FakeProcessRunner();
  final interfaces = FakeNetworkInterfaces([mac]);
  final probe = FakePortProbe({tablet: const PortOpen()});

  Future<DoctorReport> run([NetworkAddress? target]) => Doctor(
    lookup: lookup,
    processes: processes,
    interfaces: interfaces,
    probe: probe,
    timeout: const Duration(seconds: 1),
  ).run(target);
}

List<(DoctorStep, CheckStatus)> ladder(DoctorReport r) => [
  for (final c in r.checks) (c.step, c.status),
];

void main() {
  late Scenario s;
  setUp(() => s = Scenario());

  test('a healthy device passes every rung', () async {
    final report = await s.run(tablet);
    expect(ladder(report), [
      (DoctorStep.adb, CheckStatus.ok),
      (DoctorStep.computer, CheckStatus.ok),
      (DoctorStep.subnet, CheckStatus.ok),
      (DoctorStep.port, CheckStatus.ok),
      (DoctorStep.connect, CheckStatus.ok),
      (DoctorStep.state, CheckStatus.ok),
      (DoctorStep.device, CheckStatus.ok),
    ]);
    expect(report.passed, isTrue);
    expect(report.info?.model, 'YC119R');
    expect(report.info?.isRoot, isFalse);
  });

  test('1. adb missing stops at once', () async {
    s.lookup = const AdbNotFound([]);
    final report = await s.run(tablet);
    expect(ladder(report), [(DoctorStep.adb, CheckStatus.failed)]);
    expect(report.failure?.issue, isA<AdbMissing>());
    expect(s.processes.calls, isEmpty);
  });

  test('1. a hung adb server stops the ladder', () async {
    s.processes.on(
      ['start-server'],
      [const ProcessTimedOut(Duration(seconds: 1))],
    );
    final report = await s.run(tablet);
    expect(report.failure?.issue, isA<AdbServerStuck>());
  });

  test('1. two adb versions fighting is a warning, not a stop', () async {
    s.processes.on(
      ['start-server'],
      [
        const ProcessCompleted(
          0,
          stderr: [
            "adb server version (40) doesn't match this client (41); killing...",
          ],
        ),
      ],
    );
    final report = await s.run(tablet);
    final adb = report.checks.first;
    expect(adb.status, CheckStatus.warning);
    expect((adb.issue as AdbVersionsFight).server, '40');
    expect(report.passed, isTrue);
  });

  test('2. no usable network address', () async {
    s.interfaces.addresses
      ..clear()
      ..add((adapter: 'utun0', ip: Ipv4.tryParse('10.8.0.2')!));
    final report = await s.run(tablet);
    expect(report.failure?.step, DoctorStep.computer);
    expect(report.failure?.issue, isA<NoNetwork>());
  });

  test('2. picks the address on the device subnet', () async {
    s.interfaces.addresses.insert(0, (
      adapter: 'en1',
      ip: Ipv4.tryParse('10.0.0.3')!,
    ));
    final report = await s.run(tablet);
    expect(report.checks[1].facts['adapter'], 'en0');
    expect(report.checks[2].status, CheckStatus.ok);
  });

  test('no device given: only the computer is checked', () async {
    final report = await s.run();
    expect(report.failure?.issue, isA<NoDeviceGiven>());
    expect(s.probe.checked, isEmpty);
  });

  test('3. a public address is refused before any network call', () async {
    final report = await s.run(NetworkAddress.tryParse('8.8.8.8'));
    expect(report.failure?.issue, isA<NotLocalAddress>());
    expect(s.probe.checked, isEmpty);
  });

  test('3. a different subnet warns and keeps testing', () async {
    final other = NetworkAddress.tryParse('192.168.0.202')!;
    s.probe.states[other] = const PortRefused();
    final report = await s.run(other);
    expect(report.checks[2].status, CheckStatus.warning);
    expect(report.checks[2].issue, isA<DifferentSubnet>());
    expect(report.failure?.step, DoctorStep.port);
  });

  test('4. port refused: adb is not listening', () async {
    s.probe.states[tablet] = const PortRefused();
    final report = await s.run(tablet);
    expect(report.failure?.issue, isA<PortClosed>());
    expect(
      s.processes.calls,
      isNot(anyElement(equals(['connect', '192.168.1.202:5555']))),
    );
  });

  test('4. no answer: cannot reach the device', () async {
    s.probe.states[tablet] = const PortNoAnswer(unreachable: true);
    final report = await s.run(tablet);
    expect((report.failure?.issue as NoAnswer).unreachable, isTrue);
  });

  test('5. adb connect hangs and is killed', () async {
    s.processes.on(
      ['connect', '192.168.1.202:5555'],
      [const ProcessTimedOut(Duration(seconds: 1))],
    );
    final report = await s.run(tablet);
    expect(report.failure?.step, DoctorStep.connect);
    expect(report.failure?.issue, isA<ConnectHung>());
  });

  test('6. unauthorized: tap Allow', () async {
    s.processes.on(['devices', '-l'], [devicesOutput('unauthorized')]);
    final report = await s.run(tablet);
    expect(report.failure?.issue, isA<Unauthorized>());
  });

  test('6. offline is fixed by one disconnect and reconnect', () async {
    s.processes
      ..on(
        ['devices', '-l'],
        [devicesOutput('offline'), devicesOutput('device')],
      )
      ..onLines(
        ['disconnect', '192.168.1.202:5555'],
        ['disconnected 192.168.1.202:5555'],
      );
    final report = await s.run(tablet);
    expect(report.checks[5].status, CheckStatus.ok);
    expect(report.checks[5].facts['reconnected'], isTrue);
    expect(
      s.processes.calls,
      anyElement(equals(['disconnect', '192.168.1.202:5555'])),
    );
  });

  test('6. still offline: the fix is on the device', () async {
    s.processes
      ..on(['devices', '-l'], [devicesOutput('offline')])
      ..onLines(
        ['connect', '192.168.1.202:5555'],
        ['failed to connect to 192.168.1.202:5555'],
      );
    final report = await s.run(tablet);
    expect(report.failure?.issue, isA<StillOffline>());
  });

  test('6. connect failed and the device is not listed', () async {
    s.processes
      ..on(
        ['devices', '-l'],
        [
          const ProcessCompleted(0, stdout: ['List of devices attached']),
        ],
      )
      ..onLines(
        ['connect', '192.168.1.202:5555'],
        ['failed to connect to 192.168.1.202:5555'],
      );
    final report = await s.run(tablet);
    expect(
      (report.failure?.issue as ConnectError).message,
      'failed to connect to 192.168.1.202:5555',
    );
  });

  test('7. root adb on the network is a warning', () async {
    s.processes.onLines(
      ['-s', '192.168.1.202:5555', 'shell', 'id'],
      ['uid=0(root) gid=0(root)'],
    );
    final report = await s.run(tablet);
    expect(report.checks.last.status, CheckStatus.warning);
    expect(report.checks.last.issue, isA<RootOverNetwork>());
    expect(report.info?.isRoot, isTrue);
  });
}
