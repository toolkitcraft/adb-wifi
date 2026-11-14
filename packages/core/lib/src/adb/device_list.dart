import '../network/scan.dart';
import '../store/device_store.dart';
import 'adb.dart';
import 'device_info.dart';
import 'devices.dart';

/// One physical device, with every way adb reaches it (USB, network).
final class DeviceEntry {
  const DeviceEntry({
    required this.key,
    required this.connections,
    this.saved,
    this.hiddenStale = const [],
  });

  /// The hardware serial when known, else the adb serial.
  final String key;

  /// Live connections, best state first. Empty for a saved device that is
  /// not connected.
  final List<AdbDevice> connections;
  final SavedDevice? saved;

  /// Offline entries left over from an old IP or a retry, hidden because
  /// the same device is connected another way.
  final List<AdbDevice> hiddenStale;

  /// The best state of any connection; null when not connected.
  DeviceState? get state => connections.firstOrNull?.state;

  String? get model =>
      connections.map((c) => c.model).nonNulls.firstOrNull ?? saved?.model;
}

/// Lists devices as people think of them: one entry per device.
///
/// adb shows one line per connection, so a device on USB and Wi-Fi shows
/// twice, and failed retries leave `offline` lines behind. This reads the
/// hardware serial of each ready connection and merges by it.
Future<List<DeviceEntry>> listDeviceEntries(
  Adb adb,
  List<AdbDevice> connected,
  DeviceBook book,
) async {
  final serials = await boundedMap(connected, 8, (d) async {
    if (d.state != DeviceState.device) return null;
    final lines = await adb.shellLines(d.serial, const [
      'getprop',
      'ro.serialno',
    ]);
    final serial = lines?.firstOrNull?.trim();
    return serial != null && isValidSerial(serial) ? serial : null;
  });
  return mergeDevices([
    for (final (i, d) in connected.indexed) (device: d, serial: serials[i]),
  ], book);
}

/// Merges connections by hardware serial. A connection without a known
/// serial (offline, unauthorized) is matched to a saved device by its
/// address, or else stands alone. Saved devices that are not connected
/// are added at the end.
List<DeviceEntry> mergeDevices(
  List<({AdbDevice device, String? serial})> connections,
  DeviceBook book,
) {
  final groups = <String, List<AdbDevice>>{};
  for (final (:device, :serial) in connections) {
    final byAddress = switch (device.address) {
      final address? => book.byAddress(address)?.serial,
      null => null,
    };
    final key = serial ?? byAddress ?? device.serial;
    (groups[key] ??= []).add(device);
  }

  final entries = <DeviceEntry>[];
  for (final MapEntry(:key, value: devices) in groups.entries) {
    devices.sort((a, b) => _rank(a.state).compareTo(_rank(b.state)));
    final ready = devices.any((d) => d.state == DeviceState.device);
    bool stale(AdbDevice d) => ready && d.state == DeviceState.offline;
    entries.add(
      DeviceEntry(
        key: key,
        connections: devices.where((d) => !stale(d)).toList(),
        saved: book.bySerial(key),
        hiddenStale: devices.where(stale).toList(),
      ),
    );
  }
  for (final saved in book.devices) {
    if (!groups.containsKey(saved.serial)) {
      entries.add(
        DeviceEntry(key: saved.serial, connections: const [], saved: saved),
      );
    }
  }
  return entries;
}

int _rank(DeviceState state) => switch (state) {
  DeviceState.device => 0,
  DeviceState.unauthorized => 1,
  DeviceState.offline => 2,
  DeviceState.noPermissions => 3,
  DeviceState.other => 4,
};

/// Reads [DeviceInfo] for one entry's best ready connection.
Future<DeviceInfo?> entryInfo(Adb adb, DeviceEntry entry) async {
  final ready = entry.connections
      .where((c) => c.state == DeviceState.device)
      .firstOrNull;
  return ready == null ? null : readDeviceInfo(adb, ready.serial);
}
