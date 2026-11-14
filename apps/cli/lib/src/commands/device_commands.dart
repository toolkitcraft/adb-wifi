import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';

/// Shows the device and warns in red when adb is root over the network.
Future<bool> _warnIfRoot(
  AdbWifiCommand command,
  Adb adb,
  DeviceTarget target,
) async {
  final id = await adb.shellLines(target.adbSerial, const ['id']);
  final root = parseUid(id ?? const []) == 0;
  if (root && target.address != null && !command.console.json) {
    command.console
      ..danger(rootWarning)
      ..fix(rootFix);
  }
  return root;
}

/// `adbwifi shell [command...]`: an interactive shell, or one command.
class ShellCommand extends AdbWifiCommand {
  ShellCommand(super.holder);

  // Everything after "shell" belongs to the device command, even "-l".
  @override
  final argParser = ArgParser.allowAnything();

  @override
  final name = 'shell';

  @override
  final description =
      'Open a shell on the device, or run one command (adbwifi shell ls '
      '/sdcard). Global options go before "shell".';

  @override
  String get invocation => 'adbwifi [-d device] shell [command...]';

  @override
  Future<int> run() async {
    if (console.json) {
      throw UsageException(
        'shell is interactive; --json is not supported.',
        usage,
      );
    }
    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    await _warnIfRoot(this, adb, target);
    final command = argResults?.rest ?? const [];
    if (command.isEmpty) {
      console.line('🐚 Shell on ${target.label}. Type "exit" to leave.');
    }
    // Interactive, so no time limit: the user ends it.
    final outcome = await adb.runner.runInTerminal(adb.path, [
      '-s',
      target.adbSerial,
      'shell',
      ...command,
    ]);
    return switch (outcome) {
      ProcessCompleted(:final exitCode) => exitCode,
      ProcessTimedOut() => ExitCodes.failure,
      ProcessFailedToStart(:final message) => throw CliFailure(message),
    };
  }
}

/// Shared by pull and push: copies with adb's own progress line.
abstract class _TransferCommand extends AdbWifiCommand {
  _TransferCommand(super.holder) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Replace a local file that already exists (pull).',
    );
  }

  Future<int> transfer(
    Adb adb,
    DeviceTarget target,
    List<String> arguments, {
    required Duration timeout,
    required String done,
  }) async {
    final started = DateTime.now();
    // On a terminal adb draws its own progress line ([ 45%] file).
    final outcome = await adb.runner.runInTerminal(adb.path, [
      '-s',
      target.adbSerial,
      ...arguments,
    ], timeout: timeout);
    final took = DateTime.now().difference(started);
    final ok = outcome is ProcessCompleted && outcome.exitCode == 0;
    if (console.json) {
      console.printJson({
        'ok': ok,
        'device': target.adbSerial,
        'seconds': took.inMilliseconds / 1000,
      });
    } else if (ok) {
      console.ok('$done in ${took.inSeconds} s.');
    } else if (outcome is ProcessTimedOut) {
      console
        ..fail('Stopped after ${outcome.after.inMinutes} minutes.')
        ..fix('Check the Wi-Fi with adbwifi doctor, then try again.');
    } else {
      console.fail('adb could not copy the file (see its message above).');
    }
    return ok ? ExitCodes.ok : ExitCodes.failure;
  }
}

/// `adbwifi pull <device-path> [local-path]`.
class PullCommand extends _TransferCommand {
  PullCommand(super.holder);

  @override
  final name = 'pull';

  @override
  final description =
      'Copy a file from the device to this computer, with progress.';

  @override
  String get invocation => 'adbwifi pull <device-path> [local-path]';

  @override
  Future<int> run() async {
    final (remote, given) = switch (argResults?.rest) {
      [final r] => (r, null),
      [final r, final l] => (r, l),
      _ => throw UsageException('Give the device path.', usage),
    };
    final local = given ?? p.posix.basename(remote);
    if (session.environment.files.isFile(local) &&
        !(argResults?.flag('force') ?? false)) {
      throw CliFailure(
        '$local already exists.',
        fix: 'Give another local path, or add --force to replace it.',
      );
    }
    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    if (!console.json) {
      console.line('⬇️  $remote from ${target.label} → $local');
    }
    return transfer(
      adb,
      target,
      ['pull', remote, local],
      // The size is unknown before the copy; big files over Wi-Fi are slow.
      timeout: const Duration(minutes: 30),
      done: 'Copied to $local',
    );
  }
}

/// `adbwifi push <local-path> <device-path>`.
class PushCommand extends _TransferCommand {
  PushCommand(super.holder);

  @override
  final name = 'push';

  @override
  final description =
      'Copy a file from this computer to the device, with progress.';

  @override
  String get invocation => 'adbwifi push <local-path> <device-path>';

  @override
  Future<int> run() async {
    final (local, remote) = switch (argResults?.rest) {
      [final l, final r] => (l, r),
      _ => throw UsageException(
        'Give the local file and the device path.',
        usage,
      ),
    };
    final size = session.environment.files.length(local);
    if (size == null) {
      throw CliFailure('No file at $local.', exitCode: ExitCodes.usage);
    }
    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    if (!console.json) {
      console.line(
        '⬆️  $local (${formatBytes(size)}) → $remote on ${target.label}',
      );
    }
    return transfer(
      adb,
      target,
      ['push', local, remote],
      timeout: transferTimeout(size, atLeast: session.options.timeout),
      done: 'Copied to $remote',
    );
  }
}

/// `adbwifi disconnect [device] | --all`.
class DisconnectCommand extends AdbWifiCommand {
  DisconnectCommand(super.holder) {
    argParser.addFlag(
      'all',
      negatable: false,
      help: 'Disconnect every network device.',
    );
  }

  @override
  final name = 'disconnect';

  @override
  final description =
      'Disconnect a network device (or --all). The device itself is not '
      'changed.';

  @override
  String get invocation => 'adbwifi disconnect [device] | --all';

  @override
  Future<int> run() async {
    final adb = session.requireAdb();
    final all = argResults?.flag('all') ?? false;
    final connected = await session.connectedDevices(adb);
    final List<AdbDevice> targets;
    if (all) {
      targets = connected.where((d) => d.isNetwork).toList();
    } else {
      final target = await session.requireTarget(
        adb,
        query: optionalArgument('device'),
      );
      if (target.address == null) {
        throw CliFailure(
          '${target.label} is a USB connection; only network connections '
          'are disconnected.',
        );
      }
      targets = connected.where((d) => d.serial == target.adbSerial).toList();
      if (targets.isEmpty) {
        throw CliFailure('${target.label} is not connected.');
      }
    }

    // Check root before the connection is gone.
    final root = <String>{};
    for (final d in targets.where((d) => d.state == DeviceState.device)) {
      final id = await adb.shellLines(d.serial, const ['id']);
      if (parseUid(id ?? const []) == 0) root.add(d.serial);
    }
    for (final d in targets) {
      await adb.run(['disconnect', d.serial]);
    }

    if (console.json) {
      console.printJson({
        'ok': true,
        'disconnected': [for (final d in targets) d.serial],
        'root': root.toList(),
      });
      return ExitCodes.ok;
    }
    if (targets.isEmpty) {
      console.line('No network devices were connected.');
    }
    for (final d in targets) {
      console.ok('Disconnected ${d.serial}.');
    }
    if (root.isNotEmpty) {
      console
        ..danger(
          '${root.join(', ')} still accepts root adb from anyone on the '
          'network.',
        )
        ..fix(
          'Turn off USB debugging on production devices (Settings → '
          'Developer options).',
        );
    }
    return ExitCodes.ok;
  }
}
