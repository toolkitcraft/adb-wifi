# AI prompt: build adbwifi

How to use:

1. `cd ~/Documents/DSA/adb-wifi` and start a new Claude Code session there.
2. Say: `Read docs/AI_PROMPT.md and follow the prompt in it.`
3. When a session gets long, start a fresh one the same way. Update
   **Current state** below first (the AI tells you what to write there), so
   the new session knows where the build is.

---

````text
You are helping me build `adbwifi`, a cross-platform (macOS, Windows, Linux) Dart CLI
that connects a computer to Android devices with adb over Wi-Fi and explains
WHY a connection fails. It wraps Google's official adb program; it does not
reimplement the adb protocol.

## Read these first, before writing code

1. CLAUDE.md                          (project rules, toolchain, commands)
2. .claude/skills/senior-dev/SKILL.md (how to write code in this repo)
3. docs/lessons.md                    (the real problems this tool solves)
4. docs/ROADMAP.md                    (features and build order)
5. The "Design notes" section below   (decisions from planning)
Then read the existing code in packages/core and apps/cli.

## Current state

- Step 0 (project setup) is done: Dart 3.9 pub workspace, packages
  `adb_wifi_core` (packages/core, empty) and `adb_wifi_cli` (apps/cli, only
  the `version` command, 3 tests passing), CI workflow, README, SECURITY.md.
- Nothing is committed yet.
- Next is ROADMAP step 1: find adb.

## Your job: give me the source code for ALL of version 1; I TYPE IT

Goal: finish ROADMAP version 1 (steps 1 to 11) completely, to production
quality. You provide all the source code; I write it into the files myself,
because I am learning.

- Do NOT create or edit files in this repo yourself, unless I clearly say
  "you write it". Show me the code; I type it.
- Work through the steps in order. Split a big step into parts of about
  150 lines of new code or less.
- For each step (or part), give me:
  1. Goal: what it does and which lesson/problem it solves (2-3 lines).
  2. File list in order: path + "create" or "modify".
  3. For each file: the COMPLETE file content in a code block. For a modified
     file, show the full new file, or the exact lines to change with enough
     surrounding lines that I can find the spot.
  4. Short "why" notes for the important lines (not every line), and the key
     adb idea in simple English when the step depends on adb.
  5. The tests for it (I type those too).
  6. The commands to run to check it.
- Then STOP and wait until I say "done".
- When I say "done": read my files, run `dart format --output=none
  --set-exit-if-changed .`, `dart analyze --fatal-infos`, and `dart test` in
  packages/core and apps/cli. Compare my code with what you gave me. Tell me
  about typos, bugs or differences and how to fix them. Never skip or weaken
  a test to make it pass.
- When everything passes: give a short report (what works now, checks run
  and results, what needs a real device), tell me what to change in
  docs/ROADMAP.md (⏳ → ✅) and in "Current state" of this file, and then
  give me the next step. Keep going like this until step 11 is done.
- Stop and ask me when a decision is really mine (a new dependency, a change
  to the plan, a security trade-off) or a step needs the real tablet.

Git: ask me before any commit. Never push. Never commit secrets.

After step 11: report the whole of version 1 and give me the README.md
update (real usage examples, install notes, platform status) to type. Do not
start version 2 (the Flutter desktop GUI) until I say so.

## Decisions already made (do not reopen them)

- Dart 3.9 for core + CLI; Flutter desktop GUI in version 2 on the same core.
  The vending app's Flutter 3.13.9 pin does not apply here.
- No C/C++. Wrap the official adb. No shell scripts as the tool.
- Version 1 supports the same Wi-Fi / LAN only.
- Command `adbwifi`; logic in `adb_wifi_core`, CLI in `adb_wifi_cli`.
- Only dependency so far: `args`. `package:path` is OK to add for paths.
  Ask me before adding anything else.

## Design notes (from planning)

### Architecture
- Core returns typed results (sealed classes); it never prints. The CLI turns
  results into text (✅ ⚠️ ❌ 👉) or JSON (`--json`). The GUI will reuse them.
- Small interfaces at real boundaries, with fakes in tests: ProcessRunner,
  PortProbe, NetworkInterfaces, DeviceStore (file), Platform/Env, Clock.
- Exit codes: 0 ok, 1 failure, 64 usage error.

### Global options (every command)
`-d/--device <ip|name>`, `--timeout <seconds>` (default 10), `--json`,
`-v/--verbose` (prints every adb command and its raw output).

Device selection: a saved name → its last IP and serial; an IP → use it;
nothing given → the only connected device, or ask which one if there are
several, or say "run adbwifi find" if none.

### Step 1: find adb
Order: ANDROID_HOME, ANDROID_SDK_ROOT, the default Android SDK path for the
OS (macOS ~/Library/Android/sdk, Windows %LOCALAPPDATA%\Android\Sdk, Linux
~/Android/Sdk), Homebrew (/opt/homebrew/bin, /usr/local/bin), then PATH
(`;` and `adb.exe` on Windows). Prefer the SDK's adb (Android Studio uses
it). Show the adb version in `adbwifi version`. If adb is missing, print how
to install it per OS. Doctor detects "adb server version (X) doesn't match
this client (Y)" and explains that two adb versions are fighting.

### Step 2: run adb with a timeout
Process.start with an argument list (never a shell), UTF-8, LineSplitter +
trim (Windows `\r\n`). On timeout: kill the process, return a typed
TimedOut result. `adb connect` is known to hang.

### Step 3: doctor (the heart of the tool)
An ordered ladder; stop at the first hard failure; each failure maps to ONE
fix:
1. adb found?                → no: install instructions.
2. Computer's IP?            → none: "computer is not on a network".
   Skip virtual adapters (VPN, Docker, Hyper-V, utun, awdl, bridge,
   vEthernet, vboxnet, vmnet, tailscale, zt). Ask if several real ones.
3. Same subnet (assume /24; Dart does not give the netmask)?
   → different: WARNING only ("works only if your router connects both
   networks"), then keep testing.
4. TCP 5555: open / refused / no answer. Classify by OS error code
   (ECONNREFUSED: macOS 61, Linux 111, Windows 10061) and timeout.
   - refused   → "device reached, but adb is not listening: turn on USB
                  debugging / ADB over network".
   - no answer → "cannot reach the device: different Wi-Fi, wrong IP, or the
                  device has no IP (e.g. after a power cut)". If nothing on
                  the subnet answers at all, hint at guest Wi-Fi / AP
                  isolation.
5. `adb connect` (with timeout).
6. State: device → OK; unauthorized → "tap Allow on the device, tick Always
   allow"; offline → "turn USB debugging OFF then ON on the device"
   (restarting adb on the computer does NOT fix it).
7. Device info: model, Android version, SDK, build type, serial, root
   (`id -u` = 0). Root + network → red warning.

### Step 4: find
Ask before scanning (show the subnet). Scan .1-.254 of the computer's /24,
skip its own IP, 64 sockets at a time, ~400 ms timeout each (~2-3 s total).
For each open port: adb connect, read serial/model/Android/build type/root.
Show a table; save new devices. `--yes` skips the question. Typing an IP
always works without a scan.

### Step 5: device store
JSON file in the OS config dir (macOS ~/Library/Application Support/adbwifi,
Windows %APPDATA%\adbwifi, Linux $XDG_CONFIG_HOME or ~/.config/adbwifi).
Keyed by serial (Map). Fields only: serial, name, model, last IP, last port,
last seen. Commands: `name`, `forget`, `info`.

### Step 6: connect
Try the saved IP. If port 5555 does not answer: rescan the subnet, find the
same serial at a new IP, save it, tip "give it a fixed IP in the router".
If offline: disconnect the stale entry, connect once more; still offline →
print the fix; with `--wait`, retry every 2 s for up to 2 minutes (Ctrl+C
stops).

### Step 7: devices
Parse `adb devices -l`. Merge entries by serial (USB + network duplicates),
drop stale `offline` duplicates, show 🟢 device / 🟡 offline /
🔴 unauthorized, plus saved names.

### Step 8: logs --app <package>  (very important)
- SDK >= 24 (Android 7+): `pidof <pkg>`, then `logcat -v threadtime
  --pid=<pid>`.
- SDK < 24 (Android 4.4-6, e.g. the dg3188): pidof and --pid do not exist.
  Use `ps`, find the PID on the computer, run `logcat -v threadtime`, and
  filter by the PID column on the computer.
- Every 2 s check the PID: gone → "💥 app stopped/crashed, waiting for it to
  start"; new PID → switch to it and keep streaming.
- Also keep lines that mention the package name (ActivityManager "has died",
  "ANR in"), and DEBUG lines (native crash) right after a crash.
- Options: --tag, --level, --grep, --save <file>, --clear (logcat -c),
  --dump (print and exit). Stream line by line; never hold the whole log.
- --save redacts `Bearer …`, `token=…`, `key=…`, `password=…` as ***.

### Step 9: install <apk>
Show the target device (name, model) first. Use `install -r`. Show progress.
Map INSTALL_FAILED_VERSION_DOWNGRADE / UPDATE_INCOMPATIBLE etc. to simple
messages ("the build number must be higher than the installed one").

### Step 10: shell, pull, push, disconnect
`shell`: inherit stdin/stdout so it is interactive; red warning first if
root. `pull`/`push`: show progress (Wi-Fi is ~1.8 MB/s). `disconnect
[device] | --all`; after disconnect from a root device, remind "turn off
USB debugging on production devices".

### Step 11: app info <package>
Version (from `dumpsys package`), running + PID, memory (`dumpsys meminfo`),
open serial ports (`ls -l /proc/<pid>/fd`, only if allowed). Parse on the
computer.

## Rules (short version of the senior-dev skill)

- Clean, small, reusable code; immutable types; sealed results and errors;
  no `dynamic`; no `!` without a proven invariant.
- Every process and network call has a timeout. Process args as a list,
  never through a shell.
- Run only simple commands on the device; parse on the computer, with tests
  using real captured output in test/fixtures/ (keep a fixture for each
  format: Android 4.4 `ps`, Android 7 `ps`, `adb devices -l`, connect
  messages, install errors).
- Inject the platform so Windows and Linux paths are tested on my Mac.
- Security: local private subnet only, ask before scanning, no internet, no
  telemetry, never read ~/.android/adbkey, never log or store secrets,
  never change a device without an explicit command. Never add a way to
  expose port 5555 to the internet.

## Real device testing

- My computer: Mac (Apple Silicon); adb at
  ~/Library/Android/sdk/platform-tools/adb (not on PATH).
- Test device: YC119R tablet (Android 7.1.2, root adb), usually
  192.168.1.202:5555 (the IP can change). The Mac and tablet must be on the
  same Wi-Fi. Ask me before testing on it.
- In every report, say clearly which results came from fakes and which from
  the real device. Windows and Linux are tested only by CI until I test them.

## How to talk to me

Simple English, short sentences, tables and small diagrams.

## Start now

1. Confirm you read the files, and summarize the plan in 5 lines.
2. Give me ROADMAP step 1 (find adb) in the format above.
````
