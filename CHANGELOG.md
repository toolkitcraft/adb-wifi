# Changelog

All notable changes to adbwifi. Versions follow [Semantic Versioning](https://semver.org).

## 0.1.0 (2026-11-14), preview

First version of the `adbwifi` command for macOS, Windows and Linux.

- `version`: finds adb by itself (ANDROID_HOME, ANDROID_SDK_ROOT, the
  Android SDK folder, Homebrew, PATH) and lists other adb copies.
- `doctor`: checks adb, this computer's network, the subnet, port 5555,
  `adb connect`, the device state and the device, and gives one fix for the
  first problem. Warns when adb runs as root on the network.
- `find`: scans the computer's own private /24 for port 5555 after asking.
- `name`, `forget`, `info`: remembers devices by serial.
- `connect [--wait]`: finds a device again when its IP changed; waits while
  it is offline or waits for Allow.
- `devices`: one line per device (USB and Wi-Fi merged, stale offline
  entries hidden).
- `logs --app`: one app's log on Android 4.4 and newer, following restarts
  and keeping crash, ANR and "has died" lines; `--save` hides secrets.
- `install`, `shell`, `pull`, `push`, `disconnect`, `app info`.
- `--json`, `--verbose`, `--timeout` and `-d` on every command.

Known limits: real-device testing is still in progress; release builds are
not signed (see the README for the macOS and Windows warnings).
