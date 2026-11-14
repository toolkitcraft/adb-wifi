import 'package:adb_wifi_core/adb_wifi_core.dart';

/// How to install adb on [os]. Shown when adb is not found.
String installAdbHelp(HostOs os) {
  const download =
      'download "SDK Platform-Tools" from\n'
      '  https://developer.android.com/tools/releases/platform-tools';
  return switch (os) {
    HostOs.macos =>
      'Install Android platform-tools, then run this again. Either:\n'
          '• Android Studio → Settings → Android SDK → SDK Tools →\n'
          '  Android SDK Platform-Tools (best: Android Studio uses this adb)\n'
          '• brew install --cask android-platform-tools\n'
          '• $download,\n'
          '  unzip it and set ANDROID_HOME to the folder above platform-tools',
    HostOs.windows =>
      'Install Android platform-tools, then open a new terminal. Either:\n'
          '• Android Studio → Settings → Android SDK → SDK Tools →\n'
          '  Android SDK Platform-Tools (best: Android Studio uses this adb)\n'
          '• $download,\n'
          r'  unzip it to C:\Android and set ANDROID_HOME=C:\Android',
    HostOs.linux =>
      'Install Android platform-tools, then run this again. Either:\n'
          '• Android Studio → Settings → Android SDK → SDK Tools →\n'
          '  Android SDK Platform-Tools (best: Android Studio uses this adb)\n'
          '• $download,\n'
          '  unzip it and set ANDROID_HOME to the folder above platform-tools\n'
          '• sudo apt install adb   (Debian/Ubuntu; may be an older adb)\n'
          '• sudo dnf install android-tools   (Fedora)',
  };
}

/// One problem line and one fix for each doctor issue.
({String problem, String fix}) explain(DoctorIssue issue, HostOs os) =>
    switch (issue) {
      AdbMissing() => (problem: 'adb not found.', fix: installAdbHelp(os)),
      AdbServerStuck() => (
        problem: 'The adb server does not answer.',
        fix:
            'Run "adb kill-server", then try again. Still stuck? Restart '
            'the computer.',
      ),
      AdbVersionsFight(:final server, :final client) => (
        problem:
            'Two different adb versions are fighting over the adb server '
            '(server $server, this adb $client). Devices will drop.',
        fix:
            'Use one adb: point Android Studio and PATH at the same '
            'platform-tools, or remove the extra one ("adbwifi version" '
            'lists them).',
      ),
      NoNetwork() => (
        problem: 'This computer is not on a network (no Wi-Fi or LAN address).',
        fix: 'Connect it to the same Wi-Fi as the device.',
      ),
      NoDeviceGiven() => (
        problem: 'No device given, so only this computer was checked.',
        fix:
            'Run: adbwifi doctor <device-ip>  (on the device: Settings → '
            'About → Status → IP address), or adbwifi find.',
      ),
      NotLocalAddress(:final ip) => (
        problem:
            '$ip is not a local network address. adbwifi only works with '
            'devices on your own Wi-Fi or LAN.',
        fix:
            'Use the device\'s local IP (192.168.x.x, 10.x.x.x or '
            '172.16–31.x.x). Never open adb to the internet.',
      ),
      DifferentSubnet(:final computer, :final device) => (
        problem:
            'This computer ($computer) and the device ($device) are on '
            'different networks.',
        fix:
            'This works only if your router connects both networks. If the '
            'next steps fail, put both on the same Wi-Fi.',
      ),
      PortClosed(:final address) => (
        problem:
            'The device answered at ${address.ip}, but adb is not listening '
            'on port ${address.port}.',
        fix:
            'On the device: Settings → Developer options → turn on USB '
            'debugging (and "ADB over network" if it has it). Some devices '
            'need a USB cable once and "adb tcpip 5555".',
      ),
      NoAnswer(:final address, :final unreachable) => (
        problem: unreachable
            ? 'No route to ${address.ip}.'
            : 'No answer from $address.',
        fix:
            'Check that:\n'
            '• the device and this computer are on the same Wi-Fi (a guest '
            'Wi-Fi often stops devices from seeing each other)\n'
            '• the IP is right: on the device, Settings → About → Status\n'
            '• the device has an IP at all (after a power cut some devices '
            'get none until Wi-Fi is turned off and on)',
      ),
      NetworkError(:final address, :final message) => (
        problem: 'Network error for $address: $message',
        fix: 'Check the IP and the Wi-Fi, then try again.',
      ),
      ConnectHung(:final after) => (
        problem:
            'adb connect did not answer in ${after.inSeconds} s and was '
            'stopped.',
        fix:
            'This usually means the networks differ. Check the Wi-Fi on '
            'both sides, or try a longer --timeout.',
      ),
      ConnectError(:final message) => (
        problem: 'adb connect failed: $message',
        fix:
            'Try again. If it keeps failing, turn USB debugging off and on, '
            'on the device.',
      ),
      Unauthorized() => (
        problem: 'The device has not allowed this computer yet.',
        fix:
            'On the device, tap Allow on "Allow USB debugging?" and tick '
            '"Always allow from this computer". Then run this again. No '
            'prompt? Turn USB debugging off and on.',
      ),
      StillOffline() => (
        problem:
            'The device stays offline, even after a reconnect. The port is '
            'open, so the problem is on the device.',
        fix:
            'On the device: Developer options → USB debugging OFF, then ON. '
            'Restarting adb on the computer does not fix this. '
            '"adbwifi connect --wait" retries until it works.',
      ),
      OtherState(:final state) => (
        problem: 'The device is in the "$state" state.',
        fix: 'Wait until it has fully started, then try again.',
      ),
      InfoUnavailable() => (
        problem: 'Connected, but the device did not answer getprop.',
        fix: 'Try again. If it repeats, reconnect the device.',
      ),
      RootOverNetwork() => (problem: rootWarning, fix: rootFix),
    };

const rootWarning =
    'adb runs as ROOT on this device, and anyone on this network can '
    'connect to it and take full control.';
const rootFix =
    'Turn off USB debugging (and ADB over network) when you are done, '
    'especially on production devices.';

/// One line about a device: `YC119R · Android 7.1.2 (SDK 25) · userdebug`.
String describeDevice(DeviceInfo info) => [
  info.model ?? 'Unknown model',
  if (info.androidVersion != null)
    'Android ${info.androidVersion}${info.sdk == null ? '' : ' (SDK ${info.sdk})'}',
  ?info.buildType,
  if (info.serialNumber != null) 'serial ${info.serialNumber}',
  if (info.isRoot == true) 'ROOT',
].join(' · ');

/// A stable name for each issue, for `--json` (class names can change).
String issueCode(DoctorIssue issue) => switch (issue) {
  AdbMissing() => 'adb_missing',
  AdbServerStuck() => 'adb_server_stuck',
  AdbVersionsFight() => 'adb_versions_fight',
  NoNetwork() => 'no_network',
  NoDeviceGiven() => 'no_device_given',
  NotLocalAddress() => 'not_local_address',
  DifferentSubnet() => 'different_subnet',
  PortClosed() => 'port_closed',
  NoAnswer() => 'no_answer',
  NetworkError() => 'network_error',
  ConnectHung() => 'connect_hung',
  ConnectError() => 'connect_error',
  Unauthorized() => 'unauthorized',
  StillOffline() => 'still_offline',
  OtherState() => 'other_state',
  InfoUnavailable() => 'info_unavailable',
  RootOverNetwork() => 'root_over_network',
};

/// Plain words for Android's install error codes.
({String problem, String fix}) explainInstall(String code, String? detail) {
  final (problem, fix) = switch (code) {
    'INSTALL_FAILED_VERSION_DOWNGRADE' => (
      'The installed app has a higher build number than this APK.',
      'The build number (versionCode) must be higher than the installed '
          'one. Raise it and build again, or uninstall the app first (this '
          'deletes its data).',
    ),
    'INSTALL_FAILED_UPDATE_INCOMPATIBLE' ||
    'INSTALL_FAILED_INCONSISTENT_CERTIFICATES' => (
      'This APK is signed with a different key than the installed app.',
      'Sign it with the same key (debug vs release?), or uninstall the app '
          'first (this deletes its data).',
    ),
    'INSTALL_FAILED_ALREADY_EXISTS' => (
      'The app is already installed.',
      'adbwifi uses "install -r" to replace it; this old adb or device '
          'refused. Uninstall it first.',
    ),
    'INSTALL_FAILED_INSUFFICIENT_STORAGE' => (
      'The device is out of storage.',
      'Free some space on the device, then try again.',
    ),
    'INSTALL_FAILED_OLDER_SDK' => (
      'The device\'s Android is too old for this APK (minSdk).',
      'Lower minSdk in the build, or use a newer device.',
    ),
    'INSTALL_FAILED_NO_MATCHING_ABIS' => (
      'The APK has no native code for this device\'s CPU.',
      'Build it for this CPU (for example armeabi-v7a for RK3288 boards).',
    ),
    'INSTALL_FAILED_TEST_ONLY' => (
      'The APK is marked test-only.',
      'Build a normal APK (not from "Run" in Android Studio), or use '
          '"adb install -t" by hand.',
    ),
    'INSTALL_FAILED_DUPLICATE_PERMISSION' ||
    'INSTALL_FAILED_CONFLICTING_PROVIDER' => (
      'Another installed app already uses a permission or provider name '
          'from this APK.',
      'Uninstall the other app, or rename the permission/provider.',
    ),
    'INSTALL_FAILED_USER_RESTRICTED' => (
      'The device blocked the install.',
      'Allow installs over USB/adb in Developer options, or tap Allow on '
          'the device.',
    ),
    'INSTALL_FAILED_VERIFICATION_FAILURE' => (
      'Package verification rejected the APK.',
      'Turn off "Verify apps over USB" in Developer options.',
    ),
    'INSTALL_PARSE_FAILED_NO_CERTIFICATES' => (
      'The APK is not signed.',
      'Sign the APK (a debug build is signed automatically).',
    ),
    'INSTALL_FAILED_INVALID_APK' || 'INSTALL_PARSE_FAILED_NOT_APK' => (
      'The file is not a valid APK.',
      'Check the file; build it again.',
    ),
    _ when code.startsWith('INSTALL_PARSE_FAILED') => (
      'Android could not read the APK ($code).',
      'Build the APK again and check its manifest.',
    ),
    _ => (
      'Android refused the APK: $code.',
      'Search the code online, or try again with -v to see adb\'s output.',
    ),
  };
  return (
    problem: problem,
    fix: detail == null ? fix : '$fix\n(Android said: $detail)',
  );
}

/// `7.9 MB`, `512 KB`.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}
