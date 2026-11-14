# Test fixtures

Real adb and device output, used by the parser tests. Keep one file per
format and per version seen. Paths with a user name are replaced by
`/Users/me`.

| File | Source |
| --- | --- |
| `adb/version_36.0.0_macos.txt` | Captured: `adb version`, platform-tools 36.0.0, macOS arm64 |
| `adb/devices_mixed.txt` | Typed from the formats in `docs/lessons.md` (network, USB, offline, unauthorized, Linux "no permissions"). Replace with a capture |
| `device/getprop_yc119r.txt` | Shortened, typed from the YC119R facts in `docs/lessons.md`. Replace with a capture |
| `device/ps_android44.txt` | Typed: toolbox `ps`, Android 4.4 (dg3188 class). Replace with a capture |
| `device/ps_android71.txt` | Typed: toolbox `ps`, Android 7.1 (YC119R class). Replace with a capture |
| `device/ps_android9_toybox.txt` | Typed: toybox `ps -A`, Android 8+ |
| `logs/threadtime_crash.txt` | Typed: `logcat -v threadtime` with a Java crash, a native crash report, "has died" and an ANR |
| `apps/dumpsys_package.txt` | Typed: `dumpsys package <pkg>`, shortened, with a "Hidden system packages" section |
| `apps/meminfo_android71.txt` | Typed: `dumpsys meminfo <pid>`, Android 7 layout |
| `apps/ls_fd_android71.txt` | Typed: toolbox `ls -l /proc/<pid>/fd` (as root) |
| `device/id_root.txt`, `device/id_shell_kitkat.txt` | Typed: `id` on a root adbd and on Android 4.4 |

"Typed" fixtures follow the documented format but were not captured from a
device. `adb connect` messages are inline in `test/connect_test.dart`.
Capture real ones (with the owner's OK) and replace them.
