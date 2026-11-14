---
name: senior-dev
description: Implement, debug, refactor, or review adb-wifi (the adbwifi Dart CLI, its pure-Dart core, and the later Flutter desktop GUI) to production quality, with attention to clean reusable code, security, cross-platform behavior on macOS/Windows/Linux, performance, and data structures/algorithms. Use for any code task in the adb-wifi repo.
---

# Senior developer: adb-wifi

Deliver the requested behavior as a small, reviewable, production-quality
change. Correctness, security and cross-platform behavior are design
constraints, not polish. Keep the solution proportional to the problem.

Project context is in the repo's `CLAUDE.md`; the problems the tool exists to
solve are in `docs/lessons.md`; the plan is in `docs/ROADMAP.md`.

## Establish the contract

1. Read the relevant code, tests and `pubspec.yaml` files before editing.
2. Find the lesson or roadmap item the change serves. If it serves neither,
   say so before building it.
3. State what will change, what will not, and every assumption, especially
   about adb output formats and per-OS behavior.
4. Toolchain: Dart 3.9 in a pub workspace (`dart pub get` at the root). Use
   only APIs that exist in that SDK; check the SDK source when unsure.

## Architecture

- `packages/core` (`adb_wifi_core`) holds all logic. No Flutter imports, no
  `print`, no `stdout`. It returns typed results; callers decide how to show
  them.
- `apps/cli` (`adb_wifi_cli`) parses arguments, calls core and formats output.
  No business logic in commands beyond wiring.
- `apps/gui` (version 2) is a Flutter desktop app on the same core.
- Put small interfaces only at real boundaries: process runner, port probe,
  network interfaces, file store, clock, environment/platform. Tests replace
  them with fakes. Do not add generic layers or frameworks beyond that.
- Inject the platform (OS, env vars, path separator) instead of reading
  `Platform` deep in the logic, so Windows and Linux paths are unit-testable
  on a Mac.

## Clean, reusable code

- Small functions with one job. Names say what, comments say why.
- Immutable value types (`final` fields, `const` constructors). Use records
  for small multi-value returns and `sealed` classes for results and errors,
  then `switch` exhaustively.
- Strict null safety: no `!` without a proven invariant, no `dynamic`, no
  `late` that can be read before it is set.
- Parsers are pure functions from `String` to typed values, tested against
  real captured adb output in `test/fixtures/`.
- Extract shared code around shared behavior, not similar-looking lines.
  Three similar lines are better than a premature abstraction.
- Keep `dart format` and `dart analyze --fatal-infos` clean. Match the
  surrounding style.

## Processes and adb

- Every `Process` call has a timeout. On timeout, kill the process and return
  a typed "timed out" result. Never `await` a process without a bound.
- Always pass arguments as a list; never `runInShell`, never build one command
  string. Paths may contain spaces (Windows `Program Files`).
- Decode output as UTF-8, split lines with `LineSplitter`, and trim, because
  Windows adb output ends lines with `\r\n`.
- Always address a device with `-s <serial>` once there can be more than one.
- Expect adb output to change between versions: match on stable tokens,
  keep fixtures for each version seen, and fail with a clear message on
  unknown output instead of guessing.
- Run only minimal commands on the device; parse on the computer.
- Prefer the Android SDK's adb over others, and detect two different adb
  versions fighting over the server on port 5037.

## Cross-platform (macOS, Windows, Linux)

- No OS-specific shell tools (`nc`, `ipconfig`, `timeout`, `grep`, `awk`).
  Use `dart:io`: `Socket.connect(timeout:)`, `NetworkInterface.list()`,
  `Process.start`.
- Build paths with `package:path` style joining for the target OS, and store
  config in the OS's normal location (Application Support, `%APPDATA%`,
  `~/.config`).
- Skip virtual network adapters (VPN, Docker, Hyper-V, `utun`, `awdl`) when
  choosing the computer's network; ask when more than one real one remains.
- Classify socket errors by meaning (refused vs. no answer), and map OS
  error codes for all three systems.
- CI runs analyze and tests on all three OSes. Say clearly when a behavior
  was verified only on macOS.

## Security

- Network: only private IPv4 ranges, only the computer's own subnet, only
  after the user agrees. No internet calls, telemetry or auto-update. Never
  build a feature that exposes port 5555 beyond the LAN.
- Never read `~/.android/adbkey`. Never log, store or print tokens, keys,
  passwords or `.env` values. Redact `Bearer …`, `token=…`, `key=…` in saved
  logs.
- Treat everything from a device (getprop values, logcat lines, file names)
  as untrusted: bound its length, never build shell commands, file paths or
  code from it without validation.
- Warn clearly when adb is root on a network-reachable device.
- Never change a device without an explicit user action (install, push,
  shell). Show which device will be changed first.
- Add a dependency only when it removes real work and is maintained; pin it
  and explain why. Prefer packages published by the Dart team.

## Performance

- The work is I/O-bound. Bound concurrency (for example 64 sockets at a time
  for a /24 scan) and use short timeouts; do not spawn unbounded futures.
- Stream large output (logcat, file transfers) line by line or chunk by chunk;
  never buffer a whole log in memory.
- Cancel subscriptions, close sockets and sinks, and kill child processes on
  Ctrl+C or when a command ends.
- Measure before optimizing, and report the numbers.

## Data structures and algorithms

- Choose deliberately: `Map<String, Device>` keyed by serial for lookup and
  de-duplication, `Set` for membership (seen IPs, skipped adapters), `List`
  for ordered display. State complexity when it matters.
- Identify devices by serial, not IP; IPs change with DHCP.
- Keep the doctor a pure ordered ladder over injected probe results: it
  stops at the first failing step and maps each failure to one fix.
- Merge `adb devices` entries by serial; drop stale `offline` duplicates.
- Retries use a bounded count or deadline with a fixed or capped backoff.

## Flutter desktop (version 2)

- Widgets call state holders; state holders call core. No process or socket
  code in widgets.
- One state approach (`ChangeNotifier`/`ValueNotifier` unless a real need
  appears). Dispose controllers, timers and subscriptions.
- Long lists (devices, log lines) use `ListView.builder` with a bounded
  buffer.
- The GUI must show the same doctor results and fixes as the CLI, from the
  same core types.

## Verification

Choose checks proportional to risk:

1. `dart format .` and `dart analyze --fatal-infos` at the root.
2. `dart test` in each changed package: unit tests with fakes, parser tests
   with captured fixtures, CLI tests through `runCli` with string sinks.
3. `dart run apps/cli/bin/adbwifi.dart …` against a real device when the
   change touches adb, sockets or the network.
4. `dart compile exe` when the change touches startup, executables or
   packaging.

## Completion report

Report what changed, the behavior implemented, the checks actually run with
their results, which OSes and devices it was really tried on, and remaining
limits. Passing tests with fakes do not prove it works with a real device.

Report unrelated findings separately instead of fixing them silently.
