# Handoff: standalone EchoLocal TWRP add-on for Biscuit

## Mission

Create a **separate** project that builds a TWRP-flashable, system-only EchoLocal add-on for the framework-free Biscuit base.

The parent repository, `../amazon_device_biscuit`, must not retain tracked EchoLocal source, binaries, models, scripts, product definitions, or build artifacts for this feature. The add-on project must recover every external input during its own reproducible build and verify every pinned input before packaging.

Do not modify the Biscuit boot image or ramdisk. Do not reuse the Fire OS-oriented `echoctl install` flow unchanged.

## Current base contract

The generic base is `cm12-minimal` at merge commit `8c1c348` (PR #6):

- `device/amazon/biscuit/biscuit_bootstrap_device.mk` installs the marked fallback `/system/bin/ledcontroller`.
- `device/amazon/biscuit/rootdir/init.biscuit.bootstrap.rc` starts and supervises `ledcontroller` as root after `post-fs-data`.
- The fallback source documents that it is reserved for a system-only TWRP add-on.
- The generic base was built, installed, and boot-checked successfully. Runtime validation showed root ADB, `init.svc.ledcontroller=running`, `/sys/bus/i2c/devices/0-003f/boot_animation` equal to `0`, and a black 72-character LED frame.

A compatible ZIP can therefore replace **only** `/system/bin/ledcontroller`; init will execute the replacement next boot. Require this base contract and fail closed on any other system image.

## Inputs to recover during the add-on build

Do not commit downloaded/generated inputs to this project.

- EchoLocal release daemon:
  - version: `0.0.6`
  - URL: `https://github.com/ygelfand/echolocal/releases/download/0.0.6/echod`
  - SHA-256: `155a9d1330879de6f889a3990f2e82d1ecf5ddf97c7e6d1b4d85babe6f192181`
  - validate: static ELF64 AArch64 executable.
- EchoLocal source/model assets:
  - repository: `https://github.com/ygelfand/echolocal`
  - commit: `567d9440f48509457cf1c7131745e385fabf83c1`
  - models: `okay_nabu`, `hey_jarvis`, `hey_mycroft`, each JSON plus TFLite.
- CA bundle:
  - generate it from a pinned public AOSP CA revision during the add-on build; do not copy a generated bundle from the Biscuit repository.
  - install it at `/system/etc/ssl/certs/ca-certificates.crt`: static Linux Go looks at the conventional Linux path, not `/system/etc/security/cacerts.pem`.
- BusyBox and all other add-on runtime tools must be pinned, verified, and packaged by this project. Do not assume the generic base includes BusyBox.

Never embed Wi-Fi credentials or an ESPHome key in the ZIP, repository, logs, or test fixtures.

## Recommended runtime design

Do not install a direct `ledcontroller -> echod` symlink. Install a small POSIX wrapper at `/system/bin/ledcontroller`; generic init starts that wrapper after `/data` is available.

The wrapper should:

1. Run only the safe EchoLocal rollback compatibility needed for `/system/app/echod/echod.prev`.
2. Create and permission `/data/misc/echolocal` and `/data/misc/echolocal/models`.
3. Ensure a persistent, recoverable ESPHome key using the add-on's `echolocal key ensure` command.
4. Copy each model from `/system/etc/echolocal/models` only if absent from `/data/misc/echolocal/models`.
5. `exec` the installed EchoLocal daemon through its expected compatibility path.

This design makes first boot and a later `/data` wipe self-healing without a boot-image change or installer writes to `/data`. After a wipe, Wi-Fi must be provisioned again through the device controller; never restore credentials automatically.

Install compatibility paths required by unmodified EchoLocal, including `/system/app/echod/echod`, and retain its hard-coded `ledcontroller` init-service lifecycle contract.

## ZIP installer and uninstaller requirements

The TWRP installer must:

- mount and modify only `/system`;
- reject non-Biscuit devices and unsupported generic-base versions;
- verify the existing `/system/bin/ledcontroller` marker or approved hash before replacing it;
- verify payload hashes, modes, free space, and symlink targets before completion;
- preserve the original generic fallback once, for example as `/system/bin/ledcontroller.orig` plus an explicit add-on marker;
- install executable modes and the correct `u:object_r:system_file:s0` context;
- never modify boot, recovery, userdata, cache, persist, GPT, or other partitions.

The uninstaller must require the add-on marker, restore the preserved generic fallback, and delete only add-on-owned `/system` files. Preserve `/data/misc/echolocal` by default.

A full system OTA will overwrite or remove the add-on; reflash the ZIP afterward. Do not promise OTA survival. Preserved `/data` should retain the key and models.

## Suggested project shape

Keep it small:

```text
cm12-echolocal-twrp/
  Makefile                 # prepare, package, verify, clean
  scripts/
    fetch-inputs.sh         # pinned downloads/checks
    build-ca-bundle.sh      # pinned CA materialization
    build-zip.sh
    verify-zip.sh
  payload/
    system/bin/ledcontroller
    system/bin/echolocal
    system/etc/...          # populated only into build output
  installer/
    META-INF/com/google/android/updater-script
    updater-binary
  tests/
    test-zip.sh
    test-wrapper.sh
  README.md
```

Use ignored `work/` and `out/` directories for clones, downloads, generated models, CA material, staging, and ZIPs. Add a strict `.gitignore` in this separate project. Commit only scripts, source templates, pinned checksums/revisions, tests, and documentation.

## Test and acceptance plan

Before hardware use, add deterministic host tests for:

- release/model/CA hash and revision validation;
- ZIP file list, modes, contexts, symlinks, and no unintended partition operations;
- refusal on wrong device, wrong base, missing marker, insufficient space, and bad hashes;
- wrapper idempotence, first boot, and simulated `/data` wipe;
- upgrade preserving the original fallback exactly once;
- uninstaller restoration and preservation of persistent state.

Then perform one explicit TWRP smoke test on a supported `cm12-minimal` image:

1. install ZIP without wiping data;
2. boot and confirm root ADB, `ledcontroller`, `echod`, key recovery, model seed, Wi-Fi preservation, and mDNS after IP;
3. test uninstall restores the generic fallback;
4. test reinstall and a controlled data wipe.

Do not use `adb wait-for-device`; use `adb devices -l` and short explicit checks.

## Useful references

- Base PR: https://github.com/hkfuertes/amazon_device_biscuit/pull/6
- EchoLocal integration PR: https://github.com/hkfuertes/amazon_device_biscuit/pull/4
- Direct-product reference branch: `echolocal-integration` at `3a0209a`
- Generic base source: `../amazon_device_biscuit/device/amazon/biscuit/`
- Existing EchoLocal installer/source: `../echolocal/` (reference only; do not copy Fire OS boot flashing or service takeover behavior).

## Current state

No standalone ZIP, installer, uninstaller, or ZIP tests exist yet. A clean `biscuit_echolocal-userdebug` Docker OTA build was launched separately in `cm12-biscuit-build`; it is not part of this add-on project and must not be flashed without an explicit request.

Suggested next skills: `diagnose` for any build/install/runtime failure; otherwise use the normal minimal implementation workflow and retain the fail-closed updater checks.
