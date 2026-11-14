import '../adb/adb.dart';
import '../adb/connection.dart';
import '../adb/device_info.dart';
import '../doctor/doctor_issue.dart';
import '../network/ipv4.dart';
import '../network/network_interfaces.dart';
import '../network/port_probe.dart';
import '../network/scan.dart';
import '../platform/clock.dart';
import '../store/device_store.dart';

/// The result of `adbwifi connect`.
sealed class ReconnectOutcome {
  const ReconnectOutcome({required this.address, this.movedFrom});

  /// Where the device is (or was tried).
  final NetworkAddress address;

  /// The old address when a rescan found the device at a new IP.
  final NetworkAddress? movedFrom;
}

final class ReconnectReady extends ReconnectOutcome {
  const ReconnectReady({
    required super.address,
    super.movedFrom,
    this.info,
    this.reconnected = false,
  });

  final DeviceInfo? info;

  /// It was offline and one reconnect fixed it.
  final bool reconnected;
}

/// Something stops the connection; [issue] says what to do.
final class ReconnectBlocked extends ReconnectOutcome {
  const ReconnectBlocked({
    required super.address,
    required this.issue,
    super.movedFrom,
  });

  final DoctorIssue issue;
}

/// The saved IP did not answer, and a rescan did not find the serial.
final class ReconnectNotFound extends ReconnectOutcome {
  const ReconnectNotFound({required super.address, required this.scan});

  final ScanResult scan;
}

/// Connects to a device, and finds it again when DHCP gave it a new IP.
final class Reconnector {
  const Reconnector({required this.adb, required this.probe});

  final Adb adb;
  final PortProbe probe;

  /// Connects to [address]. If nothing answers there and [saved] is known,
  /// asks [rescanFrom] for the network to scan (null: the user said no),
  /// then looks for the same serial at a new IP.
  Future<ReconnectOutcome> connect(
    NetworkAddress address, {
    SavedDevice? saved,
    Future<HostAddress?> Function()? rescanFrom,
  }) async {
    final port = await probe.check(address, timeout: adb.timeout);
    switch (port) {
      case PortOpen():
        return _connectOpen(address);
      case PortRefused():
        return ReconnectBlocked(address: address, issue: PortClosed(address));
      case PortError(:final message):
        return ReconnectBlocked(
          address: address,
          issue: NetworkError(address, message),
        );
      case PortNoAnswer(:final unreachable):
        final noAnswer = ReconnectBlocked(
          address: address,
          issue: NoAnswer(address, unreachable),
        );
        if (saved == null || rescanFrom == null) return noAnswer;
        final network = await rescanFrom();
        if (network == null) return noAnswer;
        return _rescan(address, saved, network);
    }
  }

  Future<ReconnectOutcome> _connectOpen(
    NetworkAddress address, {
    NetworkAddress? movedFrom,
  }) async {
    final check = await connectAndCheck(adb, address);
    return _outcome(address, check, movedFrom: movedFrom);
  }

  Future<ReconnectOutcome> _outcome(
    NetworkAddress address,
    ConnectionCheck check, {
    NetworkAddress? movedFrom,
  }) async {
    if (check.issue case final issue?) {
      return ReconnectBlocked(
        address: address,
        issue: issue,
        movedFrom: movedFrom,
      );
    }
    return ReconnectReady(
      address: address,
      movedFrom: movedFrom,
      info: await readDeviceInfo(adb, address.serial),
      reconnected: check.reconnected,
    );
  }

  Future<ReconnectOutcome> _rescan(
    NetworkAddress old,
    SavedDevice saved,
    HostAddress network,
  ) async {
    final scan = await scanSubnet24(network.ip, probe, port: old.port);
    final found = await identifyDevices(adb, scan.open);
    final same = found
        .where((d) => d.info?.serialNumber == saved.serial)
        .firstOrNull;
    if (same == null) return ReconnectNotFound(address: old, scan: scan);
    return _connectOpen(same.address, movedFrom: old);
  }

  /// Retries every [interval] until the device is ready, [limit] has
  /// passed, or [stopped] returns true (Ctrl+C). Used for `--wait` while
  /// the user toggles USB debugging or taps Allow on the device.
  Future<ReconnectOutcome> waitUntilReady(
    NetworkAddress address,
    Clock clock, {
    Duration interval = const Duration(seconds: 2),
    Duration limit = const Duration(minutes: 2),
    bool Function()? stopped,
    void Function(DoctorIssue issue)? onRetry,
  }) async {
    final deadline = clock.now().add(limit);
    var check = await reconnect(adb, address);
    while (!check.ready &&
        clock.now().isBefore(deadline) &&
        !(stopped?.call() ?? false)) {
      if (check.issue case final issue?) onRetry?.call(issue);
      await clock.sleep(interval);
      if (stopped?.call() ?? false) break;
      check = await reconnect(adb, address);
    }
    return _outcome(address, check);
  }
}
