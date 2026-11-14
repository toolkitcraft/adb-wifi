import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';

/// `adbwifi connect [device] [--wait]`: connects, finds the device again
/// when its IP changed, and can wait while it is offline.
class ConnectCommand extends AdbWifiCommand {
  ConnectCommand(super.holder) {
    argParser
      ..addFlag(
        'wait',
        abbr: 'w',
        negatable: false,
        help:
            'If the device is offline or waits for Allow, retry every 2 s '
            'for up to 2 minutes (Ctrl+C stops).',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Rescan the network without asking when the saved IP is gone.',
      );
  }

  @override
  final name = 'connect';

  @override
  final description =
      'Connect to a device over Wi-Fi. Finds it again if its IP changed.';

  @override
  String get invocation => 'adbwifi connect [device] [--wait]';

  @override
  Future<int> run() async {
    final adb = session.requireAdb();
    final target = await session.requireTarget(
      adb,
      query: optionalArgument('device'),
    );
    final address = target.address;
    if (address == null) {
      throw CliFailure(
        '${target.label} is connected by USB, not over the network.',
        fix: 'Give its IP to connect over Wi-Fi: adbwifi connect 192.168.1.20',
      );
    }
    final reconnector = Reconnector(adb: adb, probe: session.environment.probe);
    var outcome = await reconnector.connect(
      address,
      saved: target.saved,
      rescanFrom: () => _askRescan(target),
    );
    if (argResults?.flag('wait') ?? false) {
      outcome = await _maybeWait(reconnector, outcome);
    }

    if (outcome case ReconnectReady(:final info?)) {
      await session.remember(info, outcome.address);
    }
    if (console.json) {
      console.printJson(_json(outcome));
    } else {
      _print(outcome, target);
    }
    return outcome is ReconnectReady ? ExitCodes.ok : ExitCodes.failure;
  }

  /// The saved IP is silent: may we scan for the device's new IP?
  Future<HostAddress?> _askRescan(DeviceTarget target) async {
    final mine = await session.chooseNetwork();
    final yes =
        (argResults?.flag('yes') ?? false) ||
        session.confirm(
          '${target.label} does not answer. Its IP may have changed. Scan '
          '${mine.ip.subnet24} to find it?',
        );
    if (yes && !console.json) console.line('Scanning ${mine.ip.subnet24} ...');
    return yes ? mine : null;
  }

  Future<ReconnectOutcome> _maybeWait(
    Reconnector reconnector,
    ReconnectOutcome outcome,
  ) async {
    final waitable = switch (outcome) {
      ReconnectBlocked(issue: StillOffline() || Unauthorized()) => true,
      _ => false,
    };
    if (!waitable) return outcome;
    var stopped = false;
    final stopWatching = session.environment.interrupts.watch(
      () => stopped = true,
    );
    try {
      if (!console.json) {
        final issue = (outcome as ReconnectBlocked).issue;
        console
          ..warn(explain(issue, session.platform.os).problem)
          ..fix(explain(issue, session.platform.os).fix)
          ..line('Waiting for the device (up to 2 minutes, Ctrl+C stops) ...');
      }
      return await reconnector.waitUntilReady(
        outcome.address,
        session.environment.clock,
        stopped: () => stopped,
      );
    } finally {
      await stopWatching();
    }
  }

  void _print(ReconnectOutcome outcome, DeviceTarget target) {
    final name = target.saved?.name ?? target.saved?.model;
    final who = name == null
        ? '${outcome.address}'
        : '$name (${outcome.address})';
    switch (outcome) {
      case ReconnectReady(:final info, :final reconnected):
        console.ok('Connected to $who.');
        if (reconnected) console.info('It was offline; a reconnect fixed it.');
        if (info != null) console.info(describeDevice(info));
        if (info?.isRoot == true) {
          console
            ..danger(rootWarning)
            ..fix(rootFix);
        }
      case ReconnectBlocked(:final issue):
        final text = explain(issue, session.platform.os);
        console
          ..fail(text.problem)
          ..fix(text.fix);
      case ReconnectNotFound(:final scan):
        console
          ..fail(
            '${target.label} is not on ${scan.subnet} '
            '(${scan.open.length} adb device(s) answered; none has its '
            'serial).',
          )
          ..fix(
            'Check that it is on and on this Wi-Fi. Find its IP on the '
            'device (Settings → About → Status), then: adbwifi connect <ip>',
          );
    }
    if (outcome.movedFrom case final old?) {
      console
        ..warn(
          'Its IP changed from ${old.ip} to ${outcome.address.ip}. '
          'Saved the new one.',
        )
        ..fix(
          'Give it a fixed IP in your router (a "DHCP reservation"), so it '
          'stays the same.',
        );
    }
  }

  Map<String, Object?> _json(ReconnectOutcome outcome) => {
    'ok': outcome is ReconnectReady,
    'address': outcome.address.serial,
    'movedFrom': outcome.movedFrom?.serial,
    ...switch (outcome) {
      ReconnectReady(:final info, :final reconnected) => {
        'reconnected': reconnected,
        'info': info?.toJson(),
      },
      ReconnectBlocked(:final issue) => {
        'issue': issueCode(issue),
        'problem': explain(issue, session.platform.os).problem,
        'fix': explain(issue, session.platform.os).fix,
      },
      ReconnectNotFound(:final scan) => {
        'issue': 'not_found_on_rescan',
        'subnet': scan.subnet,
      },
    },
  };
}
