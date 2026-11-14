import 'package:adb_wifi_core/adb_wifi_core.dart';
import 'package:args/args.dart';

import 'cli_environment.dart';
import 'console.dart';
import 'messages.dart';

/// The global options, read once per run.
final class GlobalOptions {
  const GlobalOptions({
    this.device,
    this.timeout = defaultTimeout,
    this.json = false,
    this.verbose = false,
  });

  static const defaultTimeout = Duration(seconds: 10);
  static const maxTimeoutSeconds = 600;

  /// Adds the options every command accepts to [parser].
  static void addTo(ArgParser parser) {
    parser
      ..addOption(
        'device',
        abbr: 'd',
        valueHelp: 'ip|name',
        help:
            'The device: an IP (port 5555 if not given), a saved name or '
            'a serial.',
      )
      ..addOption(
        'timeout',
        valueHelp: 'seconds',
        defaultsTo: '${defaultTimeout.inSeconds}',
        help: 'Time limit for each adb and network call.',
      )
      ..addFlag('json', negatable: false, help: 'Print JSON for scripts.')
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Print every adb command and its raw output (on stderr).',
      );
  }

  /// Reads the options; throws [CliFailure] with exit code 64 when one is
  /// not valid.
  factory GlobalOptions.from(ArgResults results) {
    final seconds = num.tryParse(results.option('timeout') ?? '');
    if (seconds == null || seconds <= 0 || seconds > maxTimeoutSeconds) {
      throw const CliFailure(
        '--timeout must be a number of seconds from 1 to $maxTimeoutSeconds.',
        exitCode: 64,
      );
    }
    final device = results.option('device')?.trim();
    return GlobalOptions(
      device: (device == null || device.isEmpty) ? null : device,
      timeout: Duration(milliseconds: (seconds * 1000).round()),
      json: results.flag('json'),
      verbose: results.flag('verbose'),
    );
  }

  final String? device;
  final Duration timeout;
  final bool json;
  final bool verbose;
}

/// What one command run needs: options, output and the outside world.
final class Session {
  Session({
    required this.environment,
    required this.options,
    required this.console,
  }) : processes = options.verbose
           ? LoggingProcessRunner(
               environment.processes,
               (line) => console.err.writeln('[adb] $line'),
             )
           : environment.processes;

  final CliEnvironment environment;
  final GlobalOptions options;
  final Console console;

  /// Runs programs; logs them with `--verbose`.
  final ProcessRunner processes;

  HostPlatform get platform => environment.platform;

  AdbLookup? _lookup;

  /// Where adb is, looked up once per run.
  AdbLookup lookupAdb() =>
      _lookup ??= findAdb(environment.platform, environment.files);

  /// The adb to use; throws a [CliFailure] with install steps if missing.
  Adb requireAdb() => switch (lookupAdb()) {
    AdbFound(:final adb) => Adb(
      path: adb.path,
      runner: processes,
      timeout: options.timeout,
    ),
    AdbNotFound() => throw adbMissing(),
  };

  CliFailure adbMissing() =>
      CliFailure('adb not found.', fix: installAdbHelp(platform.os));
}

/// Saved devices and choosing the device to work on.
extension SessionDevices on Session {
  DeviceStore get store {
    final custom = environment.store;
    if (custom != null) return custom;
    try {
      return JsonFileDeviceStore.forPlatform(platform);
    } on StateError catch (e) {
      throw CliFailure(e.message);
    }
  }

  /// The saved devices; a broken file stops the command.
  Future<DeviceBook> loadBook() async => switch (await store.load()) {
    StoreLoaded(:final book) => book,
    StoreBroken(:final path, :final reason) => throw CliFailure(
      'Cannot read the saved devices: $reason.',
      fix: 'Fix or delete $path (adbwifi never overwrites it).',
    ),
  };

  /// `adb devices -l`, or a failure when adb does not answer.
  Future<List<AdbDevice>> connectedDevices(Adb adb) async =>
      await listDevices(adb) ??
      (throw const CliFailure(
        'adb devices did not answer.',
        fix: 'Run adbwifi doctor to find out why.',
      ));

  /// The device for [query] (or `-d`), asking the user when several fit.
  /// Null when there is none and [required] is false.
  Future<DeviceTarget?> chooseTarget(
    Adb adb, {
    String? query,
    bool required = true,
  }) async {
    final wanted = query ?? options.device;
    final book = await loadBook();
    // An IP needs no adb call; anything else may be a connected serial.
    final connected = NetworkAddress.tryParse(wanted ?? '') == null
        ? await connectedDevices(adb)
        : const <AdbDevice>[];
    if (wanted == null && connected.length > 1) {
      // One device on USB and Wi-Fi is one choice, not two.
      final choices = [
        for (final entry in await listDeviceEntries(adb, connected, book))
          if (_preferred(entry) case final c?)
            DeviceTarget(
              address: c.address,
              serial: c.serial,
              saved: entry.saved,
            ),
      ];
      return choices.length == 1 ? choices.single : _ask(choices);
    }
    switch (resolveTarget(wanted, book, connected)) {
      case TargetFound(:final target):
        return target;
      case UnknownTarget(:final query):
        throw CliFailure(
          'No device called "$query".',
          fix:
              'Use an IP (adbwifi doctor 192.168.1.20), a name from '
              '"adbwifi devices", or run adbwifi find.',
          exitCode: 64,
        );
      case NoTarget():
        if (!required) return null;
        throw const CliFailure(
          'No device connected or saved.',
          fix:
              'Run adbwifi find, or give the IP: -d 192.168.1.20 '
              '(on the device: Settings → About → Status → IP address).',
        );
      case TargetAmbiguous(:final choices):
        return _ask(choices);
    }
  }

  /// The connection to use for an entry: a ready network one first.
  static AdbDevice? _preferred(DeviceEntry entry) {
    final ready = entry.connections.where((c) => c.state == DeviceState.device);
    return ready.where((c) => c.isNetwork).firstOrNull ??
        ready.firstOrNull ??
        entry.connections.firstOrNull;
  }

  /// Like [chooseTarget], but never null: no device is a failure.
  Future<DeviceTarget> requireTarget(Adb adb, {String? query}) async =>
      await chooseTarget(adb, query: query) ??
      (throw const CliFailure('No device.'));

  DeviceTarget _ask(List<DeviceTarget> choices) {
    final list = [
      for (final (i, c) in choices.indexed) '  ${i + 1}. ${c.label}',
    ].join('\n');
    if (console.json || !environment.input.canAsk) {
      throw CliFailure(
        'Several devices fit:\n$list',
        fix: 'Choose one with -d <ip|name>.',
        exitCode: 64,
      );
    }
    console
      ..line('Several devices:')
      ..line(list)
      ..ask('Which one? [1-${choices.length}]: ');
    final answer = int.tryParse(environment.input.readLine()?.trim() ?? '');
    if (answer == null || answer < 1 || answer > choices.length) {
      throw const CliFailure('No device chosen.', exitCode: 64);
    }
    return choices[answer - 1];
  }

  /// Asks a yes/no question. No terminal or no answer means no.
  bool confirm(String question) {
    if (!environment.input.canAsk) return false;
    console.ask('$question [y/N]: ');
    final answer = environment.input.readLine()?.trim().toLowerCase();
    return answer == 'y' || answer == 'yes';
  }

  /// Remembers [info] for the device at [address] (only allowed fields).
  Future<void> remember(DeviceInfo info, NetworkAddress? address) async {
    final serial = info.serialNumber;
    if (serial == null || !isValidSerial(serial)) return;
    final book = await loadBook();
    final old = book.bySerial(serial) ?? SavedDevice(serial: serial);
    await store.save(
      book.put(
        old.copyWith(
          model: info.model,
          address: address,
          lastSeen: environment.clock.now(),
        ),
      ),
    );
  }
}

/// Choosing this computer's network.
extension SessionNetwork on Session {
  /// The address to scan from: the only LAN address, the one on
  /// [adapter], or the user's choice when there are several.
  Future<HostAddress> chooseNetwork({String? adapter}) async {
    final all = lanAddresses(await environment.interfaces.list());
    if (all.isEmpty) {
      throw const CliFailure(
        'This computer is not on a network (no Wi-Fi or LAN address).',
        fix: 'Connect it to the same Wi-Fi as the device.',
      );
    }
    if (adapter != null) {
      return all.where((a) => a.adapter == adapter).firstOrNull ??
          (throw CliFailure(
            'No network adapter "$adapter" with a local address.',
            fix: 'Choose one of: ${all.map((a) => a.adapter).join(', ')}',
            exitCode: 64,
          ));
    }
    if (all.length == 1) return all.single;
    final list = [
      for (final (i, a) in all.indexed)
        '  ${i + 1}. ${a.adapter}  ${a.ip}  (${a.ip.subnet24})',
    ].join('\n');
    if (console.json || !environment.input.canAsk) {
      throw CliFailure(
        'This computer is on several networks:\n$list',
        fix: 'Choose one with --interface <name>.',
        exitCode: 64,
      );
    }
    console
      ..line('This computer is on several networks:')
      ..line(list)
      ..ask('Which one is the device on? [1-${all.length}]: ');
    final answer = int.tryParse(environment.input.readLine()?.trim() ?? '');
    if (answer == null || answer < 1 || answer > all.length) {
      throw const CliFailure('No network chosen.', exitCode: 64);
    }
    return all[answer - 1];
  }
}

/// Commands that work on a ready device.
extension SessionReady on Session {
  /// The target, checked to be in the `device` state; otherwise the one fix
  /// for its state.
  Future<DeviceTarget> readyTarget(Adb adb, {String? query}) async {
    final target = await requireTarget(adb, query: query);
    final state = await stateOf(adb, target.adbSerial);
    final issue = switch (state) {
      DeviceState.device => null,
      DeviceState.unauthorized => const Unauthorized(),
      DeviceState.offline => const StillOffline(),
      DeviceState.noPermissions ||
      DeviceState.other => OtherState(state?.name ?? '?'),
      null => null,
    };
    if (state == null) {
      throw CliFailure(
        '${target.label} is not connected.',
        fix:
            'Connect it first: adbwifi connect ${target.saved?.name ?? target.adbSerial}',
      );
    }
    if (issue != null) {
      final text = explain(issue, platform.os);
      throw CliFailure(text.problem, fix: text.fix);
    }
    return target;
  }

  /// The device's API level, or null when it does not say.
  Future<int?> sdkOf(Adb adb, String serial) async {
    final lines = await adb.shellLines(serial, const [
      'getprop',
      'ro.build.version.sdk',
    ]);
    return int.tryParse(lines?.firstOrNull?.trim() ?? '');
  }
}
