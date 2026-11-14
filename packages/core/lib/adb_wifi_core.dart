/// Core logic for adbwifi, shared by the CLI and (later) the GUI.
///
/// Rules for this package:
/// - Pure Dart: no Flutter imports, no printing to the terminal.
/// - Every process and network call has a timeout.
/// - Talk to the outside world (adb, sockets, files, clock) only through
///   small interfaces, so tests can use fakes.
library;

export 'src/adb/adb.dart';
export 'src/adb/adb_locator.dart';
export 'src/adb/connect.dart';
export 'src/adb/connection.dart';
export 'src/adb/device_info.dart';
export 'src/adb/device_list.dart';
export 'src/adb/devices.dart';
export 'src/adb/text.dart';
export 'src/apps/app_info.dart';
export 'src/apps/install.dart';
export 'src/connect/reconnect.dart';
export 'src/doctor/doctor.dart';
export 'src/logs/app_process.dart';
export 'src/logs/log_follower.dart';
export 'src/logs/log_line.dart';
export 'src/network/ipv4.dart';
export 'src/network/network_interfaces.dart';
export 'src/network/port_probe.dart';
export 'src/network/scan.dart';
export 'src/platform/clock.dart';
export 'src/platform/file_probe.dart';
export 'src/platform/host_platform.dart';
export 'src/process/logging_process_runner.dart';
export 'src/process/process_runner.dart';
export 'src/store/device_store.dart';
export 'src/store/device_target.dart';
