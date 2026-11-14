import '../adb/adb.dart';
import '../adb/adb_locator.dart';
import '../adb/connect.dart';
import '../adb/connection.dart';
import '../adb/device_info.dart';
import '../network/ipv4.dart';
import '../network/network_interfaces.dart';
import '../network/port_probe.dart';
import '../process/process_runner.dart';
import 'doctor_issue.dart';

export 'doctor_issue.dart';

/// The rungs of the doctor ladder, in order.
enum DoctorStep { adb, computer, subnet, port, connect, state, device }

enum CheckStatus { ok, warning, failed }

/// The result of one rung. [issue] says what is wrong (warnings and
/// failures); [facts] holds what was seen, for text and JSON output.
final class DoctorCheck {
  const DoctorCheck(
    this.step,
    this.status, {
    this.issue,
    this.facts = const {},
  });

  final DoctorStep step;
  final CheckStatus status;
  final DoctorIssue? issue;
  final Map<String, Object?> facts;
}

/// Everything the doctor found, in ladder order.
final class DoctorReport {
  const DoctorReport(this.checks, {this.info});

  final List<DoctorCheck> checks;

  /// The device, when the ladder got that far.
  final DeviceInfo? info;

  /// The failure that stopped the ladder, if any.
  DoctorCheck? get failure =>
      checks.where((c) => c.status == CheckStatus.failed).firstOrNull;

  bool get passed => failure == null;
}

/// Checks, step by step, why a computer cannot use a device over Wi-Fi.
///
/// It stops at the first hard failure, because later steps cannot work
/// without it, and each failure maps to one fix. Warnings do not stop it.
final class Doctor {
  const Doctor({
    required this.lookup,
    required this.processes,
    required this.interfaces,
    required this.probe,
    required this.timeout,
  });

  final AdbLookup lookup;
  final ProcessRunner processes;
  final NetworkInterfaces interfaces;
  final PortProbe probe;
  final Duration timeout;

  /// Runs the ladder for [target], or only the computer checks if null.
  Future<DoctorReport> run(NetworkAddress? target) async {
    final checks = <DoctorCheck>[];
    DoctorReport stop([DeviceInfo? info]) =>
        DoctorReport(List.unmodifiable(checks), info: info);

    // 1. adb
    final AdbCandidate found;
    switch (lookup) {
      case AdbNotFound(:final searched):
        checks.add(_failed(DoctorStep.adb, AdbMissing(searched)));
        return stop();
      case AdbFound(:final adb):
        found = adb;
    }
    final adb = Adb(path: found.path, runner: processes, timeout: timeout);
    final adbCheck = await _checkAdb(adb);
    checks.add(adbCheck);
    if (adbCheck.status == CheckStatus.failed) return stop();

    // 2. The computer's network
    final addresses = lanAddresses(await interfaces.list());
    if (addresses.isEmpty) {
      checks.add(_failed(DoctorStep.computer, const NoNetwork()));
      return stop();
    }
    final mine = _pick(addresses, target?.ip);
    checks.add(
      DoctorCheck(
        DoctorStep.computer,
        CheckStatus.ok,
        facts: {
          'adapter': mine.adapter,
          'ip': '${mine.ip}',
          'all': [for (final a in addresses) '${a.adapter} ${a.ip}'],
        },
      ),
    );
    if (target == null) {
      checks.add(_failed(DoctorStep.subnet, const NoDeviceGiven()));
      return stop();
    }

    // 3. Same subnet. Only private addresses: adbwifi stays on the LAN.
    if (!target.ip.isPrivate) {
      checks.add(_failed(DoctorStep.subnet, NotLocalAddress(target.ip)));
      return stop();
    }
    checks.add(
      mine.ip.sameSubnet24(target.ip)
          ? DoctorCheck(
              DoctorStep.subnet,
              CheckStatus.ok,
              facts: {'subnet': mine.ip.subnet24},
            )
          : DoctorCheck(
              DoctorStep.subnet,
              CheckStatus.warning,
              issue: DifferentSubnet(computer: mine.ip, device: target.ip),
            ),
    );

    // 4. TCP port
    final port = await probe.check(target, timeout: timeout);
    final portIssue = switch (port) {
      PortOpen() => null,
      PortRefused() => PortClosed(target),
      PortNoAnswer(:final unreachable) => NoAnswer(target, unreachable),
      PortError(:final message) => NetworkError(target, message),
    };
    if (portIssue != null) {
      checks.add(_failed(DoctorStep.port, portIssue));
      return stop();
    }
    checks.add(
      DoctorCheck(
        DoctorStep.port,
        CheckStatus.ok,
        facts: {'address': target.serial},
      ),
    );

    // 5. adb connect, then 6. the state adb reports
    final connection = await connectAndCheck(adb, target);
    if (connection.connect case ConnectTimedOut(:final after)) {
      checks.add(_failed(DoctorStep.connect, ConnectHung(after)));
      return stop();
    }
    checks.add(
      DoctorCheck(
        DoctorStep.connect,
        CheckStatus.ok,
        facts: {'result': _connectWord(connection.connect)},
      ),
    );
    final stateFacts = {
      'state': connection.state?.name,
      'reconnected': connection.reconnected,
    };
    if (connection.issue case final issue?) {
      checks.add(
        DoctorCheck(
          DoctorStep.state,
          CheckStatus.failed,
          issue: issue,
          facts: stateFacts,
        ),
      );
      return stop();
    }
    checks.add(
      DoctorCheck(DoctorStep.state, CheckStatus.ok, facts: stateFacts),
    );

    // 7. The device
    final info = await readDeviceInfo(adb, target.serial);
    checks.add(switch (info) {
      null => _warning(DoctorStep.device, const InfoUnavailable()),
      DeviceInfo(isRoot: true) => DoctorCheck(
        DoctorStep.device,
        CheckStatus.warning,
        issue: const RootOverNetwork(),
        facts: info.toJson(),
      ),
      _ => DoctorCheck(DoctorStep.device, CheckStatus.ok, facts: info.toJson()),
    });
    return stop(info);
  }

  /// Reads the adb version, and starts the server while watching for a
  /// different adb that already runs it.
  Future<DoctorCheck> _checkAdb(Adb adb) async {
    final versionOutcome = await adb.run(const ['version']);
    final version = switch (versionOutcome) {
      ProcessCompleted(:final stdout) => parseAdbVersion(stdout),
      _ => null,
    };
    final facts = {'path': adb.path, 'version': version?.toString()};

    final server = await adb.run(const ['start-server']);
    switch (server) {
      case ProcessTimedOut():
      case ProcessFailedToStart():
        return DoctorCheck(
          DoctorStep.adb,
          CheckStatus.failed,
          issue: const AdbServerStuck(),
          facts: facts,
        );
      case ProcessCompleted():
        final fight = findVersionFight(server.allLines);
        if (fight != null) {
          return DoctorCheck(
            DoctorStep.adb,
            CheckStatus.warning,
            issue: AdbVersionsFight(fight.server, fight.client),
            facts: facts,
          );
        }
    }
    return DoctorCheck(DoctorStep.adb, CheckStatus.ok, facts: facts);
  }

  /// The address on the device's /24 if there is one, else the first.
  static HostAddress _pick(List<HostAddress> addresses, Ipv4? device) =>
      (device == null
          ? null
          : addresses.where((a) => a.ip.sameSubnet24(device)).firstOrNull) ??
      addresses.first;

  static String _connectWord(ConnectResult result) => switch (result) {
    Connected(already: true) => 'already connected',
    Connected() => 'connected',
    ConnectRefused() => 'refused',
    ConnectUnauthorized() => 'unauthorized',
    ConnectTimedOut() => 'timed out',
    ConnectFailed(:final message) => message,
  };

  static DoctorCheck _failed(DoctorStep step, DoctorIssue issue) =>
      DoctorCheck(step, CheckStatus.failed, issue: issue);

  static DoctorCheck _warning(DoctorStep step, DoctorIssue issue) =>
      DoctorCheck(step, CheckStatus.warning, issue: issue);
}
