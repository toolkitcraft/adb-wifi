# adbwifi

Connect your computer to Android devices with **adb over Wi-Fi**, and find out
**why** it fails when it does.

> **Status: version 1 is written and tested with fakes; not yet checked on a
> real device.** See [docs/ROADMAP.md](docs/ROADMAP.md).

```text
$ adbwifi doctor 192.168.1.202
Checking 192.168.1.202:5555

✅ adb 36.0.0-13206524 (1.0.41): ~/Library/Android/sdk/platform-tools/adb
✅ This computer: 192.168.1.50 on en0
✅ Same network: 192.168.1.0/24
✅ Port open: 192.168.1.202:5555
✅ adb connect: already connected
❌ The device stays offline, even after a reconnect. The port is open, so
   the problem is on the device.
👉 On the device: Developer options → USB debugging OFF, then ON.
```

## Usage

| Command | What it does |
|---|---|
| `adbwifi version` | Tool version, and which adb it found (and any other adb) |
| `adbwifi doctor [device]` | Checks step by step: adb → this computer's network → same subnet → port 5555 → `adb connect` → state → device. Stops at the first problem with one fix |
| `adbwifi find` | Asks, then scans your own /24 for port 5555 (about 3 s), shows and saves what it finds |
| `adbwifi connect [device] [--wait]` | Connects; if the saved IP is gone, offers to rescan and finds the device by serial. `--wait` retries while it is offline or waits for Allow |
| `adbwifi devices` | One line per device (USB + Wi-Fi merged), stale offline entries hidden, saved names |
| `adbwifi name <device> <name>` | Names a device, e.g. `tablet` |
| `adbwifi info [device]` / `forget <device>` | Saved devices / delete one |
| `adbwifi logs --app <pkg>` | That app's log only; follows restarts; keeps crash, ANR and "has died" lines. `--tag --level --grep --save --clear --dump` |
| `adbwifi install <apk>` | `install -r`, with plain words for errors like a lower build number |
| `adbwifi shell [cmd]`, `pull`, `push` | As adb, with a red warning when adb is root on the network |
| `adbwifi disconnect [device] \| --all` | Disconnects, reminds you to turn off debugging on root devices |
| `adbwifi app info <pkg>` | Version, PID, memory, open serial ports |

A device is an IP (`192.168.1.202`, port 5555 by default), a saved name or
a serial. Every command takes `-d <device>`, `--timeout <s>` (default 10),
`--json` and `-v` (shows every adb command). Exit codes: 0 ok, 1 failed,
64 usage error.

```bash
adbwifi find                          # once: find and save the tablet
adbwifi name 192.168.1.202 tablet
adbwifi -d tablet logs --app com.example.app --level w
adbwifi -d tablet install app-release.apk
```

## Install

You need Google's adb (Android SDK Platform-Tools) too; adbwifi finds it by
itself and tells you how to install it if it is missing.

Download from [Releases](https://github.com/toolkitcraft/adb-wifi/releases) (0.1.0 is a pre-release):

| OS | File |
|---|---|
| macOS, Apple Silicon (M1 and newer) | `adbwifi-macos-arm64.tar.gz` |
| macOS, Intel | `adbwifi-macos-x64.tar.gz` |
| Windows 10/11, x64 | `adbwifi-windows-x64.zip` |
| Linux, x64 | `adbwifi-linux-x64.tar.gz` |

`SHA256SUMS.txt` has a checksum for each file.

### macOS

```bash
cd ~/Downloads
version=v0.1.0                             # newest version on the Releases page
base=https://github.com/toolkitcraft/adb-wifi/releases/download/$version
file=adbwifi-macos-arm64.tar.gz            # Intel Mac: adbwifi-macos-x64.tar.gz
curl -fLO "$base/$file" -fLO "$base/SHA256SUMS.txt"
grep "$file" SHA256SUMS.txt | shasum -a 256 -c -   # must say OK
mkdir -p ~/.local/bin
tar -xzf "$file" -C ~/.local/bin adbwifi
adbwifi version
```

If `adbwifi` is not found, add `export PATH="$HOME/.local/bin:$PATH"` to
`~/.zshrc` and open a new terminal.

The build is not signed yet. Downloaded with `curl` it runs as it is. If you
downloaded it with a browser and macOS says "cannot be opened because the
developer cannot be verified", run once:
`xattr -d com.apple.quarantine ~/.local/bin/adbwifi`.

### Linux

```bash
cd ~/Downloads
version=v0.1.0                             # newest version on the Releases page
base=https://github.com/toolkitcraft/adb-wifi/releases/download/$version
file=adbwifi-linux-x64.tar.gz
curl -fLO "$base/$file" -fLO "$base/SHA256SUMS.txt"
grep "$file" SHA256SUMS.txt | sha256sum -c -      # must say OK
mkdir -p ~/.local/bin
tar -xzf "$file" -C ~/.local/bin adbwifi
adbwifi version
```

For USB devices on Linux, adb also needs udev rules (`android-sdk-platform-tools-common`
on Debian/Ubuntu); network devices do not.

### Windows (PowerShell)

```powershell
cd $env:USERPROFILE\Downloads
$version = "v0.1.0"   # newest version on the Releases page
$base = "https://github.com/toolkitcraft/adb-wifi/releases/download/$version"
Invoke-WebRequest "$base/adbwifi-windows-x64.zip" -OutFile adbwifi-windows-x64.zip
Invoke-WebRequest "$base/SHA256SUMS.txt" -OutFile SHA256SUMS.txt
(Get-FileHash adbwifi-windows-x64.zip -Algorithm SHA256).Hash   # compare with SHA256SUMS.txt
Expand-Archive adbwifi-windows-x64.zip -DestinationPath "$env:LOCALAPPDATA\adbwifi" -Force
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
[Environment]::SetEnvironmentVariable("Path", "$userPath;$env:LOCALAPPDATA\adbwifi", "User")
```

Open a new terminal, then run `adbwifi version`. The build is not signed
yet: if Windows SmartScreen warns, choose "More info" → "Run anyway", or run
`Unblock-File "$env:LOCALAPPDATA\adbwifi\adbwifi.exe"`.

No admin rights are needed on any OS.

### Uninstall

Delete the `adbwifi` file (`~/.local/bin/adbwifi`, or
`%LOCALAPPDATA%\adbwifi` on Windows). Saved devices are in
`~/Library/Application Support/adbwifi` (macOS), `%APPDATA%\adbwifi`
(Windows) or `~/.config/adbwifi` (Linux).

### Build from source

With Dart 3.9: `dart pub get`, then
`dart compile exe apps/cli/bin/adbwifi.dart -o build/adbwifi` (create
`build/` first).

## Platforms

| OS | Status |
|---|---|
| macOS | Developed here. Checked without a device; real-device checks to do |
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
dart run apps/cli/bin/adbwifi.dart doctor      # run from source
```

Layout: `packages/core` (`adb_wifi_core`, all logic) and `apps/cli`
(`adb_wifi_cli`, the `adbwifi` command). A Flutter desktop GUI comes in
version 2.

Background: [docs/lessons.md](docs/lessons.md) records the real problems this
tool is built to solve.

## Releasing (maintainers)

1. Set the same version in `apps/cli/pubspec.yaml` and
   `apps/cli/lib/src/version.dart`, and move it from "unreleased" in
   `CHANGELOG.md`.
2. `git tag v0.1.0 && git push origin v0.1.0`
3. The `release` workflow tests and builds all four files, adds
   `SHA256SUMS.txt`, and makes a **draft** release. A tag that does not
   match the code version fails the build.
4. Download one file per OS, try `adbwifi version`, then publish the draft.

## License

[Apache License 2.0](LICENSE).
