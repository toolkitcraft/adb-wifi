# Security policy

## Reporting a problem

Please do **not** open a public issue for a security problem. Use GitHub's
private vulnerability reporting ("Report a vulnerability" on the Security tab
of this repository).

Include what you ran, what happened, and the OS and adb version. Do not
include device keys, tokens or other secrets.

## Scope

In scope: anything adbwifi itself does, for example scanning outside the
local private subnet, leaking data it should not store, running commands the
user did not ask for, or unsafe handling of output from a device.

Out of scope: weaknesses of adb itself (for example, adb over Wi-Fi on
Android 4.4–10 is not encrypted) and devices that ship with root adb open.
adbwifi warns about these but cannot fix them.
