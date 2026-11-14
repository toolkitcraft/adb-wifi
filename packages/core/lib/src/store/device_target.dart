import '../adb/devices.dart';
import '../network/ipv4.dart';
import 'device_store.dart';

/// The device a command works on.
final class DeviceTarget {
  const DeviceTarget({this.address, this.serial, this.saved})
    : assert(address != null || serial != null, 'needs address or serial');

  /// Where it listens on the network, when known.
  final NetworkAddress? address;

  /// The adb serial of a USB (or other non-IP) connection.
  final String? serial;

  /// What adbwifi remembers about it, if anything.
  final SavedDevice? saved;

  /// The serial to pass to `adb -s`: the network address when there is
  /// one (`ip:port`), else the USB serial.
  String get adbSerial => address?.serial ?? serial ?? '';

  /// For people: the saved name or model, plus the address.
  String get label {
    final name = saved?.name ?? saved?.model;
    return name == null ? adbSerial : '$name ($adbSerial)';
  }
}

/// The result of turning `-d <device>` (or nothing) into a [DeviceTarget].
sealed class TargetResolution {
  const TargetResolution();
}

final class TargetFound extends TargetResolution {
  const TargetFound(this.target);

  final DeviceTarget target;
}

/// Several devices fit and the user must choose.
final class TargetAmbiguous extends TargetResolution {
  const TargetAmbiguous(this.choices);

  final List<DeviceTarget> choices;
}

/// Nothing connected and nothing saved.
final class NoTarget extends TargetResolution {
  const NoTarget();
}

/// [query] is not an IP, a saved name or a known serial.
final class UnknownTarget extends TargetResolution {
  const UnknownTarget(this.query);

  final String query;
}

/// Picks the device for [query]: an IP (`ip` or `ip:port`) is used as it
/// is; then a saved name; then a saved or connected serial. With no
/// [query]: the only connected device, else the only saved one.
TargetResolution resolveTarget(
  String? query,
  DeviceBook book,
  List<AdbDevice> connected,
) {
  DeviceTarget fromAdb(AdbDevice d) => switch (d.address) {
    final address? => DeviceTarget(
      address: address,
      saved: book.byAddress(address),
    ),
    null => DeviceTarget(serial: d.serial, saved: book.bySerial(d.serial)),
  };

  DeviceTarget fromSaved(SavedDevice saved) => switch (saved.lastAddress) {
    final address? => DeviceTarget(address: address, saved: saved),
    null => DeviceTarget(serial: saved.serial, saved: saved),
  };

  if (query == null) {
    if (connected.isNotEmpty) {
      final targets = connected.map(fromAdb).toList();
      return targets.length == 1
          ? TargetFound(targets.single)
          : TargetAmbiguous(targets);
    }
    final saved = book.devices.where((d) => d.lastAddress != null).toList();
    return switch (saved) {
      [] => const NoTarget(),
      [final only] => TargetFound(fromSaved(only)),
      _ => TargetAmbiguous(saved.map(fromSaved).toList()),
    };
  }

  if (NetworkAddress.tryParse(query) case final address?) {
    return TargetFound(
      DeviceTarget(address: address, saved: book.byAddress(address)),
    );
  }
  if (book.find(query) case final saved?) {
    // Connected over USB right now? Then use that connection.
    final usb = connected.where((d) => d.serial == saved.serial).firstOrNull;
    return TargetFound(
      usb == null
          ? fromSaved(saved)
          : DeviceTarget(serial: usb.serial, saved: saved),
    );
  }
  if (connected.where((d) => d.serial == query).firstOrNull case final d?) {
    return TargetFound(fromAdb(d));
  }
  return UnknownTarget(query);
}
