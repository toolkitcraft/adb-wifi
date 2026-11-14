import 'dart:async';

import 'package:adb_wifi_core/adb_wifi_core.dart';

import '../base_command.dart';
import '../cli_runner.dart';
import '../console.dart';
import '../messages.dart';
import '../session.dart';

/// `adbwifi install <apk>`: installs or updates an app.
class InstallCommand extends AdbWifiCommand {
  InstallCommand(super.holder);

  @override
  final name = 'install';

  @override
  final description =
      'Install or update an APK (adb install -r) on the device, and explain '
      'why it fails.';

  @override
  String get invocation => 'adbwifi install <file.apk>';

  @override
  Future<int> run() async {
    final apk = requiredArgument('APK file');
    final size = session.environment.files.length(apk);
    if (size == null) {
      throw CliFailure('No file at $apk.', exitCode: ExitCodes.usage);
    }
    if (!apk.toLowerCase().endsWith('.apk')) {
      throw CliFailure('$apk is not an .apk file.', exitCode: ExitCodes.usage);
    }
    final adb = session.requireAdb();
    final target = await session.readyTarget(adb);
    final timeout = transferTimeout(size, atLeast: session.options.timeout);
    final seconds = (size / (1.8 * 1024 * 1024)).ceil();
    if (!console.json) {
      console.line(
        '📦 Installing $apk (${formatBytes(size)}) on ${_who(target)}, '
        'about $seconds s over Wi-Fi ...',
      );
    }

    final progress = _showProgress();
    final started = DateTime.now();
    final ProcessOutcome outcome;
    try {
      outcome = await adb.onDevice(target.adbSerial, [
        'install',
        '-r',
        apk,
      ], timeout: timeout);
    } finally {
      progress?.cancel();
      if (progress != null) console.out.write('\r');
    }
    final took = DateTime.now().difference(started);
    final result = parseInstall(outcome);

    if (console.json) {
      console.printJson({
        'ok': result is InstallSuccess,
        'device': target.adbSerial,
        'apk': apk,
        'bytes': size,
        'seconds': took.inMilliseconds / 1000,
        ...switch (result) {
          InstallSuccess() => <String, Object?>{},
          InstallFailure(:final code, :final detail) => {
            'code': code,
            'detail': detail,
            'problem': explainInstall(code, detail).problem,
          },
          InstallTimedOut() => {'code': 'TIMED_OUT'},
          InstallUnknown(:final lines) => {'code': 'UNKNOWN', 'output': lines},
        },
      });
      return result is InstallSuccess ? ExitCodes.ok : ExitCodes.failure;
    }
    switch (result) {
      case InstallSuccess():
        console.ok('Installed in ${took.inSeconds} s.');
        return ExitCodes.ok;
      case InstallFailure(:final code, :final detail):
        final text = explainInstall(code, detail);
        console
          ..fail(text.problem)
          ..fix(text.fix);
      case InstallTimedOut(:final after):
        console
          ..fail('The install did not finish in ${after.inSeconds} s.')
          ..fix('Check the Wi-Fi with adbwifi doctor, then try again.');
      case InstallUnknown(:final lines):
        console
          ..fail('adb install did not say Success:')
          ..info(lines.join('\n'));
    }
    return ExitCodes.failure;
  }

  /// A seconds counter on the same line, only on a real terminal.
  Timer? _showProgress() {
    if (!session.environment.colors || console.json) return null;
    var seconds = 0;
    return Timer.periodic(const Duration(seconds: 1), (_) {
      seconds++;
      console.out.write('\r⏳ $seconds s');
    });
  }

  static String _who(DeviceTarget target) {
    final saved = target.saved;
    final parts = [?saved?.name, ?saved?.model, target.adbSerial];
    return parts.length == 1
        ? parts.single
        : '${parts.first} (${parts.skip(1).join(', ')})';
  }
}
