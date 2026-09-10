# cm12-echolocal-twrp

A reproducible, TWRP-flashable EchoLocal add-on for the framework-free Biscuit
`cm12-minimal` base. Its payload lives in `/system`; it owns runtime state under `/data/misc/echolocal`.

## What it does

- verifies the Biscuit device and the exact reserved generic
  `/system/bin/ledcontroller` fallback before installing;
- preserves that fallback once as `ledcontroller.orig`;
- replaces it with a symlink to `/system/app/echod/echod`; when a base has
  animation hooks, preserves them as `.orig` and restores them on uninstall;
- compiles `echod` from the pinned EchoLocal tag and packages it with verified
  wake-word models while using the BusyBox and TLS trust store already
  supplied by the base;
- initializes a missing ESPHome key and missing wake-word models on first install,
  without overwriting existing runtime state; and
- provides `echolocal repair` to recreate missing state after a `/data` wipe,
  without restoring Wi-Fi credentials; and
- builds a matching uninstaller that restores the generic fallback and leaves
  `/data/misc/echolocal` intact.

It deliberately does **not** modify boot, ramdisk, recovery, cache, persist,
or partition tables. A full system OTA removes this add-on; reflash the install
ZIP afterwards.

## Base requirements

- `/system/xbin/busybox` must be a regular executable supplied by `cm12-minimal`.
- `/system/bin/wpa_passphrase` must be supplied by CM12 to provision protected Wi-Fi.
- CM12 owns the TLS trust roots. This ZIP never packages, overwrites, or
  removes certificates.

## Wi-Fi

```sh
adb shell echolocal wifi connect '<ssid>' '<passphrase>'
adb shell echolocal wifi open '<ssid>'
adb shell echolocal wifi status
```

`wifi connect` takes an 8–63 character WPA passphrase and derives the raw
WPA key with the base `wpa_passphrase`; a 64-character hexadecimal key is also
accepted directly. The ZIP never contains Wi-Fi credentials.

## ESPHome key

```sh
adb shell echolocal key show
adb shell echolocal key rotate
```

`key show` prints the current ESPHome key. Treat it as a secret. `key rotate`
generates a new key, restarts `ledcontroller`, and prints the replacement; update
Home Assistant with it before pairing again.

## Build

Requires Docker and git. `echod` is compiled from the pinned EchoLocal tag
inside a toolchain image pulled by digest — never downloaded as a release
binary:

```sh
make package          # arm64 and armv7 ZIPs
make package-arm64    # one target only
make package-armv7
make verify
make test
```

Toolchain caches, source checkouts, staging trees, and ZIPs stay under
ignored `work/` and `out/`. Pins (tag, commit, image digest, per-target binary
and model hashes) live in [`scripts/versions.sh`](scripts/versions.sh);
credentials never enter the repository or ZIP.

Flash `out/cm12-echolocal-biscuit-0.0.6-arm64.zip` in TWRP only on the
supported generic Biscuit base. Its adjacent `-arm64-uninstall.zip` restores
the base fallback. The armv7 ZIP validates the 32-bit build, but retains the
CM12 base pin and will reject a CM14/Fire OS base until that integration exists.
After a `/data` wipe, run `adb root`, then `adb shell echolocal repair`; obtain
the new key with `adb shell echolocal key show` and reconfigure Wi-Fi. Test on
hardware before relying on it.

## Credits

This add-on packages and integrates [EchoLocal](https://github.com/ygelfand/echolocal)
by [ygelfand](https://github.com/ygelfand). This repository supplies only the Biscuit
CM12 TWRP integration.
