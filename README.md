# cm12-echolocal-twrp

A reproducible, TWRP-flashable EchoLocal add-on for the framework-free Biscuit
`cm12-minimal` base. Its payload lives in `/system`; it owns runtime state under `/data/misc/echolocal`.

## What it does

- verifies the Biscuit device and the exact reserved generic
  `/system/bin/ledcontroller` fallback before installing;
- preserves that fallback once as `ledcontroller.orig`;
- replaces it with a regular wrapper (never an `echod` symlink);
- packages verified `echod`, wake-word models, a Linux CA bundle, and static
  AArch64 BusyBox;
- recreates the ESPHome key and missing models after a `/data` wipe without
  restoring Wi-Fi credentials; and
- builds a matching uninstaller that restores the generic fallback and leaves
  `/data/misc/echolocal` intact.

It deliberately does **not** modify boot, ramdisk, recovery, cache, persist,
or partition tables. A full system OTA removes this add-on; reflash the install
ZIP afterwards.

## Build

```sh
make package
make verify
make test
```

Generated downloads, source checkouts, CA material, staging trees, and ZIPs
stay under ignored `work/` and `out/`. Inputs and their hashes live in
[`scripts/versions.sh`](scripts/versions.sh); credentials never enter the
repository or ZIP.

Flash `out/cm12-echolocal-biscuit-0.0.6.zip` in TWRP only on the supported
generic Biscuit base. Flash the adjacent `-uninstall.zip` to restore the base
fallback. Test on hardware before relying on it.
