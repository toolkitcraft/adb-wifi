import '../doctor/doctor_issue.dart';
import '../network/ipv4.dart';
import 'adb.dart';
import 'connect.dart';
import 'devices.dart';

/// What happened after `adb connect` and a look at `adb devices`.
final class ConnectionCheck {
  const ConnectionCheck({
    required this.connect,
    this.state,
    this.reconnected = false,
  });

  final ConnectResult connect;

  /// The state adb lists for the address; null when it is not listed.
  final DeviceState? state;

  /// True when it was offline and got one disconnect and reconnect.
  final bool reconnected;

  bool get ready => state == DeviceState.device;

  /// What is wrong, or null when [ready].
  DoctorIssue? get issue => switch (state) {
    DeviceState.device => null,
    DeviceState.unauthorized => const Unauthorized(),
    DeviceState.offline => const StillOffline(),
    DeviceState.noPermissions ||
    DeviceState.other => OtherState(state?.name ?? '?'),
    null => switch (connect) {
      ConnectTimedOut(:final after) => ConnectHung(after),
      ConnectUnauthorized() => const Unauthorized(),
      ConnectFailed(:final message) => ConnectError(message),
      _ => const ConnectError('the device is not in "adb devices"'),
    },
  };
}

/// Runs `adb connect` and reads the state. An `offline` device gets one
/// `adb disconnect` and a new connect, which clears a stale entry; if it
/// is still offline, the fix is on the device.
Future<ConnectionCheck> connectAndCheck(Adb adb, NetworkAddress address) async {
  final connect = await adbConnect(adb, address);
  if (connect is ConnectTimedOut) return ConnectionCheck(connect: connect);
  final state = await stateOf(adb, address.serial);
  if (state != DeviceState.offline) {
    return ConnectionCheck(connect: connect, state: state);
  }
  return reconnect(adb, address);
}

/// `adb disconnect` then `adb connect` again, and the new state.
Future<ConnectionCheck> reconnect(Adb adb, NetworkAddress address) async {
  await adb.run(['disconnect', address.serial]);
  final connect = await adbConnect(adb, address);
  final state = connect is ConnectTimedOut
      ? null
      : await stateOf(adb, address.serial);
  return ConnectionCheck(connect: connect, state: state, reconnected: true);
}

/// The state adb lists for [serial], or null if it is not listed.
Future<DeviceState?> stateOf(Adb adb, String serial) async =>
    (await listDevices(
      adb,
    ))?.where((d) => d.serial == serial).map((d) => d.state).firstOrNull;
