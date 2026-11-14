import 'adb.dart';
import 'text.dart';

/// Facts about a connected device, read with `getprop` and `id`.
final class DeviceInfo {
  const DeviceInfo({
    this.serialNumber,
    this.model,
    this.manufacturer,
    this.androidVersion,
    this.sdk,
    this.buildType,
    this.isRoot,
  });

  /// The hardware serial (`ro.serialno`). Stays the same when the IP
  /// changes, so adbwifi remembers devices by it.
  final String? serialNumber;
  final String? model;
  final String? manufacturer;

  /// For example `7.1.2`.
  final String? androidVersion;

  /// The API level, for example 25. Decides which commands exist.
  final int? sdk;

  /// `user`, `userdebug` or `eng`. Not `user` usually means a test build.
  final String? buildType;

  /// True when adb runs as root on the device (`id` shows uid 0). Null when
  /// unknown.
  final bool? isRoot;

  Map<String, Object?> toJson() => {
    'serialNumber': serialNumber,
    'model': model,
    'manufacturer': manufacturer,
    'androidVersion': androidVersion,
    'sdk': sdk,
    'buildType': buildType,
    'root': isRoot,
  };
}

/// Reads [DeviceInfo] with two simple commands: `getprop` (all values at
/// once) and `id`. Null when the device does not answer.
Future<DeviceInfo?> readDeviceInfo(Adb adb, String serial) async {
  final props = await adb.shellLines(serial, const ['getprop']);
  if (props == null) return null;
  final idLines = await adb.shellLines(serial, const ['id']);
  return deviceInfoFrom(parseGetprop(props), idLines ?? const []);
}

/// Builds [DeviceInfo] from parsed getprop values and `id` output.
DeviceInfo deviceInfoFrom(Map<String, String> props, Iterable<String> id) {
  String? prop(String key) {
    final value = props[key];
    return (value == null || value.isEmpty) ? null : cleanDeviceText(value);
  }

  return DeviceInfo(
    serialNumber: prop('ro.serialno') ?? prop('ro.boot.serialno'),
    model: prop('ro.product.model'),
    manufacturer: prop('ro.product.manufacturer'),
    androidVersion: prop('ro.build.version.release'),
    sdk: int.tryParse(props['ro.build.version.sdk'] ?? ''),
    buildType: prop('ro.build.type'),
    isRoot: switch (parseUid(id)) {
      null => null,
      final uid => uid == 0,
    },
  );
}

/// Reads `getprop` output: lines like `[ro.product.model]: [YC119R]`.
Map<String, String> parseGetprop(Iterable<String> lines) => {
  for (final line in lines)
    if (_prop.firstMatch(line.trim()) case final m?) m.group(1)!: m.group(2)!,
};

// Both groups always take part in a match, so `!` above is safe.
final _prop = RegExp(r'^\[([^\]]+)\]: \[(.*)\]$');

/// The user id from `id` output, such as `uid=0(root) gid=0(root) ...`.
///
/// `id` is used instead of `id -u` because Android 4.4's toolbox `id`
/// has no `-u`.
int? parseUid(Iterable<String> lines) {
  for (final line in lines) {
    final m = _uid.firstMatch(line);
    if (m != null) return int.tryParse(m.group(1) ?? '');
  }
  return null;
}

final _uid = RegExp(r'\buid=(\d+)');
