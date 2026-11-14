import 'dart:io';

import 'ipv4.dart';

/// What happened when adbwifi tried to open a TCP connection.
sealed class PortState {
  const PortState();
}

/// Something accepted the connection: adb is (probably) listening.
final class PortOpen extends PortState {
  const PortOpen();
}

/// The device answered "nothing listens here": it is on the network, but
/// network adb is off.
final class PortRefused extends PortState {
  const PortRefused();
}

/// Nothing answered in time, or there is no route: wrong IP, another
/// network, no IP at all, or a firewall dropping the packets.
final class PortNoAnswer extends PortState {
  const PortNoAnswer({this.unreachable = false});

  /// True when the OS said "no route to host" instead of waiting.
  final bool unreachable;
}

/// Any other error, with the OS message.
final class PortError extends PortState {
  const PortError(this.message);

  final String message;
}

/// Tries TCP connections. A boundary interface for fakes.
abstract interface class PortProbe {
  Future<PortState> check(NetworkAddress address, {required Duration timeout});
}

/// Opens a real socket, then closes it at once. Sends no data.
final class LocalPortProbe implements PortProbe {
  const LocalPortProbe();

  @override
  Future<PortState> check(
    NetworkAddress address, {
    required Duration timeout,
  }) async {
    try {
      final socket = await Socket.connect(
        address.ip.toString(),
        address.port,
        timeout: timeout,
      );
      socket.destroy();
      return const PortOpen();
    } on SocketException catch (e) {
      return classifySocketError(e.osError?.errorCode, e.message);
    }
  }
}

/// Sorts a socket error by meaning, using the OS error code of macOS,
/// Linux or Windows. A Dart timeout has no OS error ([code] is null).
PortState classifySocketError(int? code, String message) {
  if (code == null) {
    return message.toLowerCase().contains('timed out')
        ? const PortNoAnswer()
        : PortError(message);
  }
  if (_refused.contains(code)) return const PortRefused();
  if (_timedOut.contains(code)) return const PortNoAnswer();
  if (_unreachable.contains(code)) return const PortNoAnswer(unreachable: true);
  return PortError('$message (error $code)');
}

/// ECONNREFUSED: macOS 61, Linux 111, Windows WSAECONNREFUSED 10061.
const _refused = {61, 111, 10061};

/// ETIMEDOUT: macOS 60, Linux 110, Windows 10060.
const _timedOut = {60, 110, 10060};

/// EHOSTUNREACH / ENETUNREACH / EHOSTDOWN: macOS 65, 51, 64;
/// Linux 113, 101, 112; Windows 10065, 10051, 10064.
const _unreachable = {65, 51, 64, 113, 101, 112, 10065, 10051, 10064};
