import '../network/ipv4.dart';
import '../process/process_runner.dart';
import 'adb.dart';
import 'text.dart';

/// The state adb shows for a device.
enum DeviceState {
  /// Ready to use.
  device,

  /// Known to adb but not talking. Over the network this is a problem on
  /// the device's side; restarting adb on the computer does not fix it.
  offline,

  /// Waiting for someone to tap Allow on the device.
  unauthorized,

  /// Linux: the USB device cannot be opened (udev rules).
  noPermissions,

  /// Any other state (bootloader, recovery, authorizing, ...).
  other,
}

/// One line of `adb devices -l`.
final class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.stateText = '',
    this.model,
    this.product,
    this.transportId,
    this.usb,
  });

  /// What adb calls this connection: `ip:port` over the network, the
  /// hardware serial over USB.
  final String serial;
  final DeviceState state;

  /// adb's word for the state, as printed.
  final String stateText;

  final String? model;
  final String? product;
  final String? transportId;

  /// The USB port, such as `1-1`. Null over the network.
  final String? usb;

  /// The network address when this is a network connection.
  NetworkAddress? get address => NetworkAddress.tryParse(serial);
  bool get isNetwork => address != null;
}

/// Runs `adb devices -l`. Null when adb failed or timed out.
Future<List<AdbDevice>?> listDevices(Adb adb) async {
  final outcome = await adb.run(['devices', '-l']);
  return switch (outcome) {
    ProcessCompleted(exitCode: 0, :final stdout) => parseDevices(stdout),
    _ => null,
  };
}

/// Reads `adb devices -l` output.
///
/// Lines before the header (such as `* daemon started successfully`) and
/// blank lines are skipped. The format is
/// `<serial> <state> [key:value ...]`, and the state can be two words
/// (`no permissions (…)` on Linux).
List<AdbDevice> parseDevices(Iterable<String> lines) {
  final devices = <AdbDevice>[];
  var inList = false;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('List of devices attached')) {
      inList = true;
      continue;
    }
    if (!inList || line.isEmpty || line.startsWith('* ')) continue;
    final device = _parseLine(line);
    if (device != null) devices.add(device);
  }
  return devices;
}

AdbDevice? _parseLine(String line) {
  final words = line.split(RegExp(r'\s+'));
  if (words.length < 2) return null;
  final serial = cleanDeviceText(words[0]);
  final rest = words.sublist(1);
  final details = <String, String>{
    for (final word in rest)
      if (_detail.firstMatch(word) case final m?) m.group(1)!: m.group(2)!,
  };
  final stateText = rest.first == 'no' && rest.length > 1
      ? 'no permissions'
      : rest.first;
  return AdbDevice(
    serial: serial,
    state: _state(stateText),
    stateText: cleanDeviceText(stateText),
    model: _clean(details['model']),
    product: _clean(details['product']),
    transportId: _clean(details['transport_id']),
    usb: _clean(details['usb']),
  );
}

// Both groups always take part in a match, so `!` above is safe.
final _detail = RegExp(r'^([a-z_]+):(.+)$');

String? _clean(String? text) => text == null ? null : cleanDeviceText(text);

DeviceState _state(String text) => switch (text) {
  'device' => DeviceState.device,
  'offline' => DeviceState.offline,
  'unauthorized' => DeviceState.unauthorized,
  'no permissions' => DeviceState.noPermissions,
  _ => DeviceState.other,
};
