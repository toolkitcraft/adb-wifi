import 'dart:convert';
import 'dart:io';

import '../adb/text.dart';
import '../network/ipv4.dart';
import '../platform/host_platform.dart';

/// A device adbwifi remembers. Only these fields are ever stored: no keys,
/// no tokens, nothing typed into a shell.
final class SavedDevice {
  const SavedDevice({
    required this.serial,
    this.name,
    this.model,
    this.lastIp,
    this.lastPort = NetworkAddress.defaultAdbPort,
    this.lastSeen,
  });

  /// The hardware serial: the key, because the IP changes with DHCP.
  final String serial;

  /// The user's name for it, such as `tablet`.
  final String? name;
  final String? model;
  final Ipv4? lastIp;
  final int lastPort;
  final DateTime? lastSeen;

  NetworkAddress? get lastAddress => switch (lastIp) {
    null => null,
    final ip => NetworkAddress(ip, lastPort),
  };

  /// The name if it has one, else the model, else the serial.
  String get label => name ?? model ?? serial;

  SavedDevice copyWith({
    String? name,
    bool clearName = false,
    String? model,
    NetworkAddress? address,
    DateTime? lastSeen,
  }) => SavedDevice(
    serial: serial,
    name: clearName ? null : (name ?? this.name),
    model: model ?? this.model,
    lastIp: address?.ip ?? lastIp,
    lastPort: address?.port ?? lastPort,
    lastSeen: lastSeen ?? this.lastSeen,
  );

  Map<String, Object?> toJson() => {
    'serial': serial,
    'name': name,
    'model': model,
    'lastIp': lastIp?.toString(),
    'lastPort': lastPort,
    'lastSeen': lastSeen?.toUtc().toIso8601String(),
  };

  /// Reads one stored device. Null when the entry is not valid, so a hand
  /// edit cannot smuggle odd values into commands.
  static SavedDevice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final serial = json['serial'];
    if (serial is! String || !isValidSerial(serial)) return null;
    final name = json['name'];
    final model = json['model'];
    final ip = json['lastIp'];
    final port = json['lastPort'];
    final seen = json['lastSeen'];
    return SavedDevice(
      serial: serial,
      name: name is String && isValidName(name) ? name : null,
      model: model is String ? cleanDeviceText(model) : null,
      lastIp: ip is String ? Ipv4.tryParse(ip) : null,
      lastPort: port is int && port > 0 && port < 65536
          ? port
          : NetworkAddress.defaultAdbPort,
      lastSeen: seen is String ? DateTime.tryParse(seen) : null,
    );
  }
}

/// A serial as adb prints it: letters, digits and `._:-`, up to 64.
bool isValidSerial(String serial) => _serial.hasMatch(serial);
final _serial = RegExp(r'^[A-Za-z0-9._:-]{1,64}$');

/// A device name: starts with a letter, then letters, digits, `._-`, up to
/// 32. It cannot look like an IP, so `-d <x>` is never ambiguous.
bool isValidName(String name) => _name.hasMatch(name);
final _name = RegExp(r'^[A-Za-z][A-Za-z0-9._-]{0,31}$');

/// All saved devices, keyed by serial. Immutable: changes return a copy.
final class DeviceBook {
  DeviceBook([Iterable<SavedDevice> devices = const []])
    : _bySerial = Map.unmodifiable({for (final d in devices) d.serial: d});

  final Map<String, SavedDevice> _bySerial;

  /// Sorted by label, for display.
  List<SavedDevice> get devices =>
      _bySerial.values.toList()..sort((a, b) => a.label.compareTo(b.label));

  bool get isEmpty => _bySerial.isEmpty;

  SavedDevice? bySerial(String serial) => _bySerial[serial];

  /// Names are matched without case: `Tablet` finds `tablet`.
  SavedDevice? byName(String name) {
    final wanted = name.toLowerCase();
    return _bySerial.values
        .where((d) => d.name?.toLowerCase() == wanted)
        .firstOrNull;
  }

  /// The device last seen at [address], if any.
  SavedDevice? byAddress(NetworkAddress address) =>
      _bySerial.values.where((d) => d.lastAddress == address).firstOrNull;

  /// A saved name, else a serial.
  SavedDevice? find(String nameOrSerial) =>
      byName(nameOrSerial) ?? bySerial(nameOrSerial);

  DeviceBook put(SavedDevice device) => DeviceBook([
    ..._bySerial.values.where((d) => d.serial != device.serial),
    device,
  ]);

  DeviceBook remove(String serial) =>
      DeviceBook(_bySerial.values.where((d) => d.serial != serial));

  Map<String, Object?> toJson() => {
    'version': 1,
    'devices': {for (final d in devices) d.serial: d.toJson()},
  };
}

/// The result of reading the store.
sealed class StoreLoad {
  const StoreLoad();
}

final class StoreLoaded extends StoreLoad {
  const StoreLoaded(this.book);

  final DeviceBook book;
}

/// The file exists but cannot be read. It is left alone, never replaced,
/// so the user can fix it or delete it.
final class StoreBroken extends StoreLoad {
  const StoreBroken(this.path, this.reason);

  final String path;
  final String reason;
}

/// Saves the [DeviceBook]. A boundary interface for fakes.
abstract interface class DeviceStore {
  /// Where the data lives, to show the user.
  String get location;

  Future<StoreLoad> load();
  Future<void> save(DeviceBook book);
}

/// Stores devices as JSON in the OS's normal config folder.
final class JsonFileDeviceStore implements DeviceStore {
  const JsonFileDeviceStore(this.path);

  /// `devices.json` in [configDirectory].
  factory JsonFileDeviceStore.forPlatform(HostPlatform platform) {
    final dir = configDirectory(platform);
    if (dir == null) {
      throw StateError('No home folder: cannot find where to save devices.');
    }
    return JsonFileDeviceStore(platform.paths.join(dir, 'devices.json'));
  }

  final String path;

  /// A bigger file is not ours; reading it could use a lot of memory.
  static const maxBytes = 1024 * 1024;

  @override
  String get location => path;

  @override
  Future<StoreLoad> load() async {
    final file = File(path);
    if (!await file.exists()) return StoreLoaded(DeviceBook());
    try {
      if (await file.length() > maxBytes) {
        return StoreBroken(path, 'it is larger than 1 MB');
      }
      return parseStore(path, await file.readAsString());
    } on FileSystemException catch (e) {
      return StoreBroken(path, e.message);
    }
  }

  /// Writes a temporary file, then renames it over the old one, so a crash
  /// mid-write never leaves half a file.
  @override
  Future<void> save(DeviceBook book) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(book.toJson()),
      flush: true,
    );
    await temp.rename(path);
  }
}

/// Reads the store's JSON text.
StoreLoad parseStore(String path, String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    return StoreBroken(path, 'it is not valid JSON (${e.message})');
  }
  if (json is! Map<String, Object?> || json['devices'] is! Map) {
    return StoreBroken(path, 'it has no "devices" map');
  }
  final entries = (json['devices'] as Map).values;
  return StoreLoaded(
    DeviceBook([for (final entry in entries) ?SavedDevice.fromJson(entry)]),
  );
}

/// The folder for adbwifi's settings: `~/Library/Application Support` on
/// macOS, `%APPDATA%` on Windows, `$XDG_CONFIG_HOME` or `~/.config` on
/// Linux. Null without a home folder.
String? configDirectory(HostPlatform platform) {
  final paths = platform.paths;
  final home = platform.homeDirectory;
  final base = switch (platform.os) {
    HostOs.macos =>
      home == null ? null : paths.join(home, 'Library', 'Application Support'),
    HostOs.windows => platform.variable('APPDATA'),
    HostOs.linux =>
      _absolute(platform, platform.variable('XDG_CONFIG_HOME')) ??
          (home == null ? null : paths.join(home, '.config')),
  };
  return base == null ? null : paths.join(base, 'adbwifi');
}

/// The XDG spec says to ignore a relative XDG_CONFIG_HOME.
String? _absolute(HostPlatform platform, String? dir) =>
    dir != null && platform.paths.isAbsolute(dir) ? dir : null;
