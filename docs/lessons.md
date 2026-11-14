# adb over Wi-Fi: lessons from the eRoxii vending app

Context for building a tool that connects a computer to Android devices with
adb over the local network. Everything here was seen while developing the
eRoxii vending app (2026-11-05 to 2026-11-14), mostly on 2026-11-12. Items
marked **unverified** were suspected but not proven. The step-by-step user
guide is `docs/networkADB.md`.

## Why network adb was needed

- The station tablets are kiosk Android boards. USB to the Mac failed
  repeatedly: the Mac saw **no USB device at all**, neither the tablet nor a
  USB-serial cable that had worked an hour earlier. The cause was never
  found (**unverified**: macOS "Allow accessories to connect", a
  charge-only cable, the wrong board port, or the USB-C adapter).
- Network adb worked with no cable and became the main way to install,
  read logs, open a shell, copy files, and inspect serial ports.

## Devices seen

| Device | Android | Network adb result |
|---|---|---|
| YC119R (RK3288 board `RK3288_BOX_REF_V4.54D`, build `CP-DC-rk3288-userdebug ... test-keys`) | 7.1.2 (API 25) | Listened on 5555 with no extra setup. **adbd ran as root** (`id` gave `uid=0`, SELinux context `u:r:su:s0`) |
| K518 (RK3288, `RK3288-K518-V7.5.30`) | 7.1.2 | Port 5555 **refused** (network adb not on) |
| dg3188 (production) | 4.4.4 (API 19) | After a power cut it has **no IP** (Android stops DHCP), so network adb is impossible until its network is fixed |

- Computer: Mac (Apple Silicon), shell **zsh**, adb at
  `~/Library/Android/sdk/platform-tools/adb`, **not on PATH**.
- Android 7 has **no mDNS / "Wireless debugging" pairing**, which only
  arrived in Android 11. Devices must be found by IP: read from the tablet's
  Settings → About → Status, or found by checking port 5555 on the subnet.

## Problems hit, in order, and what fixed them

1. **`command not found: adb`.** Not on PATH. Fix: call it by full path.
2. **Mac switched Wi-Fi** (to download a tool faster). Every adb session
   dropped silently. Fix: switch back and reconnect.
3. **`adb connect` hung with no output** for a long time when the networks
   differed. macOS has no `timeout` command (`gtimeout` wasn't installed
   either). Fix: run it in the background and kill it after ~10 s.
4. **`offline` state.** `adb devices` showed `192.168.1.202:5555 offline`,
   and `adb connect` printed `failed to connect`, **while ping worked and
   TCP 5555 was open** (`nc -z -G 3 IP 5555` succeeded).
   - `adb disconnect` + `adb connect`: still offline.
   - `adb kill-server` + `start-server` + `connect`: still offline.
   - **Fix: on the tablet, Developer options → USB debugging off, then
     on.** The next `adb connect` printed `connected` and the state was
     `device`.
   - Lesson: "offline with the port open" is a tablet-side adbd problem;
     nothing on the computer fixes it.
5. **USB cable not detected** (see above). Avoided by using the network.

## Things that behave differently than expected

- **zsh doesn't split variables:** `DEV="-s 1.2.3.4:5555"; adb $DEV shell`
  passes one argument. Keep the variable to one word (`DEV=1.2.3.4:5555`)
  and write `-s $DEV`.
- **The tablet's shell is minimal (toybox + busybox):** no `awk`. `ps` has
  the old format (no `-A` on some ROMs), and `timeout` is
  `busybox timeout -t SECS` on some builds. Do text processing on the
  computer, not the device.
- **`logcat --pid=PID`** works on Android 7. Logs are full of other noise;
  filter on the computer.
- **Transfer speed** over Wi-Fi was about 1.8 MB/s (a 7.9 MB APK pull took
  4.3 s). Show progress for large files.
- **Stale entries:** after a failure, `adb devices` keeps an `offline` line
  with a new `transport_id` on each retry.
- **Same device twice:** a device on both USB and network appears as two
  entries, so every command needs `-s`.

## What root network adb made possible (and why it's dangerous)

On the userdebug YC119R the adb shell was root, which let us:
- list apps (`pm list packages -3`) and find an app's process (`pidof`),
- see which serial port an app holds (`ls -l /proc/PID/fd`),
- read port settings (`busybox stty -F /dev/ttyS1 -a`),
- copy an installed APK (`adb pull /data/app/<pkg>-1/base.apk`),
- attach `strace` to another app's process and record its serial writes,
- write temp files to `/data/local/tmp` (remember to delete them).

**The same access is open to anyone on that Wi-Fi.** It gives full control
of the tablet and of the vending machine's motors.

## Requirements this suggests for the tool

1. **Find adb** by itself: `ANDROID_HOME`, `~/Library/Android/sdk`,
   Homebrew, PATH, with the Windows and Linux paths from `networkADB.md`.
2. **A timeout on every network and adb call.** `adb connect` can hang.
3. **A health check ladder** that stops at the first failure and says what
   to do:
   computer IP and subnet → ping → TCP 5555 → `adb connect` → state
   (`device` / `offline` / `unauthorized`).
   - Port closed → "Turn on ADB over network / USB debugging".
   - `unauthorized` → "Tap Allow on the tablet, tick Always allow".
   - `offline` with the port open → "Turn USB debugging off and on, on the
     tablet", then retry by itself.
   - Different subnet → "The computer and tablet are on different Wi-Fi".
4. **Discovery:** scan only the computer's own subnet (e.g. its /24) for
   TCP 5555, with short timeouts. Let users also type an IP and remember
   devices by name and serial, because DHCP may change the IP.
5. **Always use `-s <serial>`**, and clean up stale `offline` entries.
6. **Show the device:** model, Android version, build type
   (`getprop ro.build.type`), and whether adb is root (`id -u` = 0). Show a
   clear **warning when root adb is open on the network**, and offer
   "turn off when done".
7. **Common actions:** install APK (`install -r`, and say that the build
   number must be higher), logcat with a filter, shell, pull/push with
   progress, disconnect.
8. **Do the parsing on the computer side**, because the device shell lacks
   `awk` and has busybox-specific flags.
9. **Never log or store secrets** typed into shells or seen in device
   files.

## Not proven / open questions

- Why the Mac saw no USB devices.
- Whether the YC119R keeps network adb after a reboot (it already listened
  on 5555 when first checked).
- Whether toggling "ADB over network" alone (without USB debugging) also
  fixes the `offline` state.
