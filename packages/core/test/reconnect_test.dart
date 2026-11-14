import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:adb_wifi_core/testing.dart';
import 'package:test/test.dart';

final old = NetworkAddress.tryParse('192.168.1.202')!;
final moved = NetworkAddress.tryParse('192.168.1.88')!;
final mine = (adapter: 'en0', ip: Ipv4.tryParse('192.168.1.5')!);
const saved = SavedDevice(serial: 'A1B2C3D4E5', name: 'tablet');

ProcessCompleted listing(String serial, String state) => ProcessCompleted(
  0,
  stdout: ['List of devices attached', '$serial\t$state'],
);

void answers(FakeProcessRunner p, String serial) => p
  ..onLines(['connect', serial], ['connected to $serial'])
  ..onLines(['-s', serial, 'shell', 'getprop'], ['[ro.serialno]: [A1B2C3D4E5]'])
  ..onLines(['-s', serial, 'shell', 'id'], ['uid=2000(shell)']);

void main() {
  late FakeProcessRunner processes;
  late FakePortProbe probe;
  late Reconnector reconnector;

  setUp(() {
    processes = FakeProcessRunner();
    probe = FakePortProbe();
    reconnector = Reconnector(
      adb: Adb(
        path: 'adb',
        runner: processes,
        timeout: const Duration(seconds: 1),
      ),
      probe: probe,
    );
  });

  test('saved IP answers: connected', () async {
    probe.states[old] = const PortOpen();
    answers(processes, old.serial);
    processes.on(['devices', '-l'], [listing(old.serial, 'device')]);
    final outcome = await reconnector.connect(old, saved: saved);
    expect(outcome, isA<ReconnectReady>());
    expect((outcome as ReconnectReady).info?.serialNumber, 'A1B2C3D4E5');
    expect(outcome.movedFrom, isNull);
  });

  test('no answer and the user says no: no scan', () async {
    final outcome = await reconnector.connect(
      old,
      saved: saved,
      rescanFrom: () async => null,
    );
    expect((outcome as ReconnectBlocked).issue, isA<NoAnswer>());
    expect(probe.checked, [old]);
  });

  test('no answer: rescans and finds the same serial at a new IP', () async {
    probe.states[moved] = const PortOpen();
    answers(processes, moved.serial);
    processes.on(['devices', '-l'], [listing(moved.serial, 'device')]);
    final outcome = await reconnector.connect(
      old,
      saved: saved,
      rescanFrom: () async => mine,
    );
    expect(outcome, isA<ReconnectReady>());
    expect(outcome.address, moved);
    expect(outcome.movedFrom, old);
  });

  test('rescan finds another device only: not found', () async {
    probe.states[moved] = const PortOpen();
    answers(processes, moved.serial);
    processes
      ..onLines(
        ['-s', moved.serial, 'shell', 'getprop'],
        ['[ro.serialno]: [SOMEONE_ELSE]'],
      )
      ..on(['devices', '-l'], [listing(moved.serial, 'device')]);
    final outcome = await reconnector.connect(
      old,
      saved: saved,
      rescanFrom: () async => mine,
    );
    expect(outcome, isA<ReconnectNotFound>());
    expect((outcome as ReconnectNotFound).scan.open, [moved]);
  });

  test('port refused: no rescan, the fix is on the device', () async {
    probe.states[old] = const PortRefused();
    var asked = false;
    final outcome = await reconnector.connect(
      old,
      saved: saved,
      rescanFrom: () async {
        asked = true;
        return mine;
      },
    );
    expect((outcome as ReconnectBlocked).issue, isA<PortClosed>());
    expect(asked, isFalse);
  });

  group('waitUntilReady', () {
    setUp(() => processes.onLines(['disconnect', old.serial], []));

    test('retries every 2 s until the device comes back', () async {
      answers(processes, old.serial);
      processes.on(
        ['devices', '-l'],
        [
          listing(old.serial, 'offline'),
          listing(old.serial, 'offline'),
          listing(old.serial, 'device'),
        ],
      );
      final clock = FakeClock();
      final retries = <DoctorIssue>[];
      final outcome = await reconnector.waitUntilReady(
        old,
        clock,
        onRetry: retries.add,
      );
      expect(outcome, isA<ReconnectReady>());
      expect(clock.sleeps, [
        const Duration(seconds: 2),
        const Duration(seconds: 2),
      ]);
      expect(retries, everyElement(isA<StillOffline>()));
    });

    test('gives up after 2 minutes', () async {
      answers(processes, old.serial);
      processes.on(['devices', '-l'], [listing(old.serial, 'offline')]);
      final clock = FakeClock();
      final outcome = await reconnector.waitUntilReady(old, clock);
      expect((outcome as ReconnectBlocked).issue, isA<StillOffline>());
      expect(clock.sleeps, hasLength(60));
    });

    test('stops when asked (Ctrl+C)', () async {
      answers(processes, old.serial);
      processes.on(['devices', '-l'], [listing(old.serial, 'unauthorized')]);
      final clock = FakeClock();
      var tries = 0;
      final outcome = await reconnector.waitUntilReady(
        old,
        clock,
        stopped: () => ++tries > 3,
      );
      expect((outcome as ReconnectBlocked).issue, isA<Unauthorized>());
      expect(clock.sleeps.length, lessThan(3));
    });
  });
}
