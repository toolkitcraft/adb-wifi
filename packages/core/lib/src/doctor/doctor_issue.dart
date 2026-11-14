import '../adb/adb_locator.dart';
import '../network/ipv4.dart';

/// A problem the doctor found. Each kind maps to exactly one fix, which
/// the CLI (and later the GUI) turns into words.
sealed class DoctorIssue {
  const DoctorIssue();
}

final class AdbMissing extends DoctorIssue {
  const AdbMissing(this.searched);

  final List<AdbCandidate> searched;
}

/// `adb start-server` did not answer.
final class AdbServerStuck extends DoctorIssue {
  const AdbServerStuck();
}

/// Two different adb programs fight over the server on port 5037.
final class AdbVersionsFight extends DoctorIssue {
  const AdbVersionsFight(this.server, this.client);

  final String server;
  final String client;
}

/// No private IPv4 address on a real adapter.
final class NoNetwork extends DoctorIssue {
  const NoNetwork();
}

/// The user named no device, so only the computer was checked.
final class NoDeviceGiven extends DoctorIssue {
  const NoDeviceGiven();
}

/// A public address. adbwifi only works on the local network.
final class NotLocalAddress extends DoctorIssue {
  const NotLocalAddress(this.ip);

  final Ipv4 ip;
}

/// Warning only: it works if the router connects both networks.
final class DifferentSubnet extends DoctorIssue {
  const DifferentSubnet({required this.computer, required this.device});

  final Ipv4 computer;
  final Ipv4 device;
}

/// The device answered, but nothing listens on the adb port.
final class PortClosed extends DoctorIssue {
  const PortClosed(this.address);

  final NetworkAddress address;
}

/// Nothing answered on the adb port.
final class NoAnswer extends DoctorIssue {
  const NoAnswer(this.address, this.unreachable);

  final NetworkAddress address;

  /// The OS said "no route to host" (instead of waiting).
  final bool unreachable;
}

final class NetworkError extends DoctorIssue {
  const NetworkError(this.address, this.message);

  final NetworkAddress address;
  final String message;
}

/// `adb connect` hung and was killed.
final class ConnectHung extends DoctorIssue {
  const ConnectHung(this.after);

  final Duration after;
}

/// `adb connect` failed and the device is not listed.
final class ConnectError extends DoctorIssue {
  const ConnectError(this.message);

  final String message;
}

/// The device waits for someone to tap Allow.
final class Unauthorized extends DoctorIssue {
  const Unauthorized();
}

/// Still `offline` after a disconnect and a reconnect.
final class StillOffline extends DoctorIssue {
  const StillOffline();
}

final class OtherState extends DoctorIssue {
  const OtherState(this.state);

  final String state;
}

/// Connected, but `getprop` did not answer.
final class InfoUnavailable extends DoctorIssue {
  const InfoUnavailable();
}

/// adb runs as root on a device anyone on the network can reach.
final class RootOverNetwork extends DoctorIssue {
  const RootOverNetwork();
}
