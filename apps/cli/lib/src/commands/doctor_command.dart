import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';

/// `adbwifi doctor [device]`: finds out, step by step, why the device
/// cannot be used over Wi-Fi, and says what to do.
class DoctorCommand extends AdbWifiCommand {
  DoctorCommand(super.holder);

  @override
  final name = 'doctor';

  @override
  final description =
      'Check adb, this computer\'s network, port 5555, the connection and '
      'the device. Stops at the first problem and says how to fix it.';

  @override
  String get invocation => 'adbwifi doctor [device]';

  @override
  Future<int> run() async {
    final query = optionalArgument('device');
    final target = await _target(query);
    final report = await Doctor(
      lookup: session.lookupAdb(),
      processes: session.processes,
      interfaces: session.environment.interfaces,
      probe: session.environment.probe,
      timeout: session.options.timeout,
    ).run(target?.address);

    final info = report.info;
    if (report.passed && info != null) {
      await session.remember(info, target?.address);
    }

    if (console.json) {
      console.printJson(_json(report, target));
    } else {
      _print(report, target);
    }
    return report.passed ? ExitCodes.ok : ExitCodes.failure;
  }

  /// The device to check. Without adb, the ladder reports that first.
  Future<DeviceTarget?> _target(String? query) async {
    if (session.lookupAdb() is AdbNotFound) {
      return switch (NetworkAddress.tryParse(query ?? '')) {
        null => null,
        final address => DeviceTarget(address: address),
      };
    }
    final target = await session.chooseTarget(
      session.requireAdb(),
      query: query,
      required: false,
    );
    if (target != null && target.address == null) {
      throw CliFailure(
        '${target.label} is connected by USB; doctor checks the network '
        'connection.',
        fix: 'Give the device IP: adbwifi doctor 192.168.1.20',
        exitCode: ExitCodes.usage,
      );
    }
    return target;
  }

  void _print(DoctorReport report, DeviceTarget? target) {
    if (target != null) console.line('Checking ${target.label}\n');
    for (final check in report.checks) {
      _printCheck(check, report.info);
    }
    console.line();
    if (report.passed) {
      console.ok(
        'Ready: use -d ${target?.adbSerial ?? '<device>'} with any '
        'adbwifi command.',
      );
    } else if (report.failure?.issue is! NoDeviceGiven) {
      console.fail('Not ready: fix the problem above, then run this again.');
    }
  }

  void _printCheck(DoctorCheck check, DeviceInfo? info) {
    final ok = _okText(check, info);
    final issue = check.issue;
    if (issue == null) {
      console.ok(ok);
      return;
    }
    final text = explain(issue, session.platform.os);
    switch ((check.status, issue)) {
      case (_, NoDeviceGiven()):
        console.fix('${text.problem}\n${text.fix}');
      case (_, RootOverNetwork()):
        console
          ..ok(ok)
          ..danger(text.problem)
          ..fix(text.fix);
      case (CheckStatus.warning, _):
        console
          ..warn(text.problem)
          ..fix(text.fix);
      case _:
        console
          ..fail(text.problem)
          ..fix(text.fix);
    }
  }

  String _okText(DoctorCheck check, DeviceInfo? info) {
    final f = check.facts;
    return switch (check.step) {
      DoctorStep.adb =>
        'adb ${f['version'] ?? '(version unknown)'}: ${f['path']}',
      DoctorStep.computer => 'This computer: ${f['ip']} on ${f['adapter']}',
      DoctorStep.subnet => 'Same network: ${f['subnet']}',
      DoctorStep.port => 'Port open: ${f['address']}',
      DoctorStep.connect => 'adb connect: ${f['result']}',
      DoctorStep.state =>
        f['reconnected'] == true
            ? 'State: device (it was offline; a reconnect fixed it)'
            : 'State: device',
      DoctorStep.device => info == null ? 'Device' : describeDevice(info),
    };
  }

  Map<String, Object?> _json(DoctorReport report, DeviceTarget? target) => {
    'ok': report.passed,
    'device': target?.adbSerial,
    'checks': [
      for (final c in report.checks)
        {
          'step': c.step.name,
          'status': c.status.name,
          if (c.issue case final issue?) ...{
            'issue': issueCode(issue),
            'problem': explain(issue, session.platform.os).problem,
            'fix': explain(issue, session.platform.os).fix,
          },
          'facts': c.facts,
        },
    ],
    'info': report.info?.toJson(),
  };
}
