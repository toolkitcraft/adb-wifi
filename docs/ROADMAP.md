# Roadmap

Every item comes from a real problem in `lessons.md`.

## Version 1: CLI

Build order. Each step is small and tested before the next.

| Step | Feature | Command | Status |
|---|---|---|---|
| 0 | Project setup, `version`, CI | `adbwifi version` | ✅ done |
| 1 | Find adb (SDK paths, `ANDROID_HOME`, Homebrew, PATH; Mac/Windows/Linux) | `adbwifi version` shows adb | ⏳ |
| 2 | Run adb with a timeout (kill on hang) | — | ⏳ |
| 3 | Doctor: my IP → same subnet (warning) → port 5555 (open / refused / no answer) → `adb connect` → state → device info | `adbwifi doctor [device]` | ⏳ |
| 4 | Find devices on the local /24 (asks first) | `adbwifi find` | ⏳ |
| 5 | Remember devices by serial | `adbwifi name`, `forget`, `info` | ⏳ |
| 6 | Smart reconnect (rescan when the IP changed) + offline wait | `adbwifi connect <device> [--wait]` | ⏳ |
| 7 | Clean device list (merge by serial, drop stale offline) | `adbwifi devices` | ⏳ |
| 8 | App logs by PID (`pidof`/`--pid` on Android 7+, `ps` + computer-side filter on 4.4–6, follow restarts, keep crash/ANR lines) | `adbwifi logs --app <pkg>` | ⏳ |
| 9 | Install with progress | `adbwifi install <apk>` | ⏳ |
| 10 | Shell (root warning), pull, push, disconnect | `adbwifi shell`, `pull`, `push`, `disconnect` | ⏳ |
| 11 | App info (version, PID, memory) | `adbwifi app info <pkg>` | ⏳ |

Options for every command: `-d/--device`, `--timeout`, `--json`, `-v/--verbose`.

## Version 2: GUI (Flutter desktop)

Device list with states, find button, doctor panel, drag-and-drop install with
progress, logcat viewer, file browser, network-change alert.

## Version 3: later

Android 11+ pairing (`adb pair`, mDNS), "turn off network adb" helper, open in
scrcpy, doctor report export (no secrets), multi-device install.

## Release

GitHub Actions builds `adbwifi` for macOS (arm64, x64), Windows x64 and Linux
x64, with SHA-256 checksums. Signing (Apple notarization, Windows
Authenticode) comes later.

## Not planned

- Reimplementing the adb protocol (revisit only on real demand).
- Native C/C++ code.
- Any access over the internet without a VPN.
