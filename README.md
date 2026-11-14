# adbwifi

Connect your computer to Android devices with **adb over Wi-Fi**, and find out
**why** it fails when it does.

> **Status: early development.** Only `adbwifi version` works today. See
> [docs/ROADMAP.md](docs/ROADMAP.md).

```text
$ adbwifi doctor 192.168.1.202
 ✅ adb found       ~/Library/Android/sdk/platform-tools/adb
 ✅ Your computer   192.168.1.50 (Wi-Fi)
 ✅ Port 5555       open
 ❌ adb state       offline
 👉 Fix: On the device, turn USB debugging OFF, then ON.
```

## Platforms

| OS | Status |
|---|---|
| macOS | Developed and tested here |
| Windows | Built and tested in CI, not yet with a real device |
| Linux | Built and tested in CI, not yet with a real device |

## Requirements

- Google's `adb` (Android SDK Platform-Tools). adbwifi finds it by itself.
- The computer and the Android device on the **same Wi-Fi / LAN**.

## What this tool does and does not do

- It runs the official `adb` program; it does not replace it.
- It talks only to your local network and to adb on your computer. **No
  internet, no telemetry, no auto-update, no admin rights.**
- It scans your network only when you ask, and only your own private subnet.
- It never reads your adb keys (`~/.android/adbkey`) and never saves secrets.
  It saves only device serial, model, name, last IP and last-seen time.
- `--verbose` shows every adb command it runs.

Use it only on networks you own or are allowed to test. Never forward adb
port 5555 to the internet.

## Development

Requires Dart 3.9.

```bash
dart pub get                                   # at the repo root
dart analyze --fatal-infos
(cd packages/core && dart test)
(cd apps/cli && dart test)
dart run apps/cli/bin/adbwifi.dart version     # run from source
```

Layout: `packages/core` (`adb_wifi_core`, all logic) and `apps/cli`
(`adb_wifi_cli`, the `adbwifi` command). A Flutter desktop GUI comes in
version 2.

Background: [docs/lessons.md](docs/lessons.md) records the real problems this
tool is built to solve.
