import '../adb/adb.dart';
import '../adb/connect.dart';
import '../adb/device_info.dart';
import '../adb/devices.dart';
import 'ipv4.dart';
import 'port_probe.dart';

/// What a subnet scan saw.
final class ScanResult {
  const ScanResult({
    required this.subnet,
    required this.open,
    required this.refused,
    required this.noAnswer,
    required this.elapsed,
  });

  /// For example `192.168.1.0/24`.
  final String subnet;

  /// Addresses where something accepted a connection, in IP order.
  final List<NetworkAddress> open;

  /// Hosts that answered "nothing listens here": they exist.
  final int refused;
  final int noAnswer;
  final Duration elapsed;

  /// Not one host answered, not even with "refused". On a busy network
  /// that hints at a guest Wi-Fi that hides devices from each other.
  bool get nothingAnswered => open.isEmpty && refused == 0;
}

/// Checks [port] on `.1` to `.254` of [own]'s /24, except [own] itself.
///
/// Only private addresses: a public [own] throws [ArgumentError], so a
/// scan never leaves the local network. At most [concurrency] sockets are
/// open at a time; with 64 and 400 ms a /24 takes about 2 to 3 seconds.
Future<ScanResult> scanSubnet24(
  Ipv4 own,
  PortProbe probe, {
  int port = NetworkAddress.defaultAdbPort,
  Duration timeout = const Duration(milliseconds: 400),
  int concurrency = 64,
  Stopwatch? stopwatch,
}) async {
  if (!own.isPrivate) {
    throw ArgumentError.value(own, 'own', 'only private networks are scanned');
  }
  final clock = (stopwatch ?? Stopwatch())..start();
  final targets = [
    for (var host = 1; host <= 254; host++)
      if (own.withHost(host) != own) NetworkAddress(own.withHost(host), port),
  ];
  final states = await boundedMap(
    targets,
    concurrency,
    (address) => probe.check(address, timeout: timeout),
  );
  final open = <NetworkAddress>[];
  var refused = 0;
  var noAnswer = 0;
  for (final (i, state) in states.indexed) {
    switch (state) {
      case PortOpen():
        open.add(targets[i]);
      case PortRefused():
        refused++;
      case PortNoAnswer() || PortError():
        noAnswer++;
    }
  }
  return ScanResult(
    subnet: own.subnet24,
    open: List.unmodifiable(open),
    refused: refused,
    noAnswer: noAnswer,
    elapsed: clock.elapsed,
  );
}

/// Runs [work] on every item with at most [concurrency] running at once,
/// and returns the results in the order of [items].
Future<List<R>> boundedMap<T, R>(
  List<T> items,
  int concurrency,
  Future<R> Function(T item) work,
) async {
  final results = List<R?>.filled(items.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      final i = next++;
      results[i] = await work(items[i]);
    }
  }

  await Future.wait([
    for (var w = 0; w < concurrency && w < items.length; w++) worker(),
  ]);
  // Every index was filled by a worker above.
  return [for (final r in results) r as R];
}

/// A device found by a scan, after `adb connect`.
final class FoundDevice {
  const FoundDevice({
    required this.address,
    required this.connect,
    this.state,
    this.info,
  });

  final NetworkAddress address;
  final ConnectResult connect;

  /// The state adb reports after connecting; null if it is not listed.
  final DeviceState? state;

  /// Read only when the state is `device`.
  final DeviceInfo? info;
}

/// Connects to each open address and reads what it is.
///
/// Something else may listen on port 5555; it then fails to connect and is
/// reported as such, not guessed at.
Future<List<FoundDevice>> identifyDevices(
  Adb adb,
  List<NetworkAddress> open,
) async {
  final connects = await boundedMap(
    open,
    8,
    (address) => adbConnect(adb, address),
  );
  final listed = {
    for (final d in await listDevices(adb) ?? const <AdbDevice>[])
      d.serial: d.state,
  };
  return boundedMap([for (var i = 0; i < open.length; i++) i], 8, (i) async {
    final address = open[i];
    final state = listed[address.serial];
    return FoundDevice(
      address: address,
      connect: connects[i],
      state: state,
      info: state == DeviceState.device
          ? await readDeviceInfo(adb, address.serial)
          : null,
    );
  });
}
