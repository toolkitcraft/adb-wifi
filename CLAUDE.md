# adb-wifi: engineering context

`adbwifi` helps developers connect a computer to Android devices with adb over
Wi-Fi, and explains **why** a connection fails. It wraps Google's official
`adb` program; it does not reimplement the adb protocol.

The problems it solves are recorded in `docs/lessons.md`. The feature plan and
build order are in `docs/ROADMAP.md`. Read both before adding a feature.

Use the `senior-dev` skill (`.claude/skills/senior-dev/SKILL.md`) for all work
in this repo.

## Toolchain

- Dart **3.9** (the normal `dart` / `flutter` on PATH, Flutter 3.35).
  This is *not* the vending app: the Flutter 3.13.9 / Dart 3.1.5 pin does not
  apply here.
- Pub workspace: run `dart pub get` once at the repo root. One shared
  `pubspec.lock`, committed.
- Must run on **macOS, Windows and Linux**. Development and real-device testing
  happen on macOS; Windows and Linux are covered by CI until tested by hand.

## Layout

| Path | Package | Responsibility |
| --- | --- | --- |
| `packages/core` | `adb_wifi_core` | All logic: find adb, run it with timeouts, network checks, scan, doctor, device store. Pure Dart, no printing, no Flutter |
| `apps/cli` | `adb_wifi_cli` | The `adbwifi` command: parse arguments, call core, format output (text or `--json`) |
| `apps/gui` | (version 2) | Flutter desktop UI on top of the same core |

## Non-negotiable rules

- Every process and network call has a timeout. `adb connect` can hang.
- Run only simple commands on the device (`getprop`, `id -u`, `pidof`, `ps`,
  `logcat`). Parse output on the computer: device shells lack `awk` and use
  busybox/toybox flags.
- Start processes with an argument list, never one command string, and never
  through a shell.
- Scan only private IPv4 ranges on the computer's own subnet, and only after
  the user agrees.
- No internet access, telemetry, auto-update, or admin rights.
- Never read `~/.android/adbkey`. Never log, store or print secrets. Saved
  device data is limited to serial, model, name, last IP and last-seen time.
- Never add a feature that exposes adb port 5555 to the internet.

## Commands

| Command | Purpose |
| --- | --- |
| `dart pub get` | Resolve all packages (run at the root) |
| `dart format .` | Format |
| `dart analyze --fatal-infos` | Static analysis |
| `cd packages/core && dart test` | Core tests |
| `cd apps/cli && dart test` | CLI tests |
| `dart run apps/cli/bin/adbwifi.dart <command>` | Run the CLI from source |
| `dart compile exe apps/cli/bin/adbwifi.dart -o build/adbwifi` | Native executable for this OS |

Report the checks you actually ran. Passing tests with fakes do not prove the
tool works against a real device; say what was and was not tried on one.
