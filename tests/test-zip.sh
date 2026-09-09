#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
. "$ROOT/scripts/versions.sh"
INSTALL_ZIP="$ROOT/out/$ADDON_NAME-$ECHOLOCAL_VERSION.zip"
UNINSTALL_ZIP="$ROOT/out/$ADDON_NAME-$ECHOLOCAL_VERSION-uninstall.zip"
FIXTURE="$ROOT/tests/fixtures/ledcontroller"
[ "$(sha256sum "$FIXTURE" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ] || {
    printf '%s\n' 'generic fallback fixture hash changed' >&2
    exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/recovery"
cat > "$tmp/bin/getprop" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_PRODUCT:-biscuit}"
EOF
cat > "$tmp/bin/chcon" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$tmp/bin/getprop" "$tmp/bin/chcon"
unzip -q "$INSTALL_ZIP" -d "$tmp/install"
unzip -q "$UNINSTALL_ZIP" -d "$tmp/uninstall"
install_binary="$tmp/install/META-INF/com/google/android/update-binary"
uninstall_binary="$tmp/uninstall/META-INF/com/google/android/update-binary"

setup_system() {
    rm -rf "$1"
    mkdir -p "$1/bin"
    cp "$FIXTURE" "$1/bin/ledcontroller"
    chmod 0755 "$1/bin/ledcontroller"
}

run_update() {
    TEST_PRODUCT="$4" \
        ECHOLOCAL_SYSTEM="$3" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB="$5" GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" \
        sh "$1" 3 1 "$2" >/dev/null
}

system="$tmp/system"
setup_system "$system"
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ -f "$system/bin/ledcontroller.orig" ]
[ ! -L "$system/bin/ledcontroller" ]
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ]
[ -f "$system/etc/echolocal/.biscuit-addon" ]
backup_hash=$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$backup_hash" ]

wrong_device="$tmp/wrong-device"
setup_system "$wrong_device"
if run_update "$install_binary" "$INSTALL_ZIP" "$wrong_device" not-biscuit 999999; then
    printf '%s\n' 'wrong device was accepted' >&2
    exit 1
fi
[ ! -e "$wrong_device/bin/ledcontroller.orig" ]

wrong_base="$tmp/wrong-base"
setup_system "$wrong_base"
printf 'not the generic fallback\n' > "$wrong_base/bin/ledcontroller"
if run_update "$install_binary" "$INSTALL_ZIP" "$wrong_base" biscuit 999999; then
    printf '%s\n' 'wrong base was accepted' >&2
    exit 1
fi

no_space="$tmp/no-space"
setup_system "$no_space"
if run_update "$install_binary" "$INSTALL_ZIP" "$no_space" biscuit 0; then
    printf '%s\n' 'insufficient space was accepted' >&2
    exit 1
fi

bad_tree="$tmp/bad-tree"
bad_zip="$tmp/bad.zip"
unzip -q "$INSTALL_ZIP" -d "$bad_tree"
printf 'broken\n' >> "$bad_tree/payload-manifest.sha256"
(
    cd "$bad_tree"
    zip -X -q -r "$bad_zip" .
)
bad_hash="$tmp/bad-hash"
setup_system "$bad_hash"
if run_update "$install_binary" "$bad_zip" "$bad_hash" biscuit 999999; then
    printf '%s\n' 'bad payload manifest was accepted' >&2
    exit 1
fi

persistent="$tmp/persistent"
mkdir -p "$persistent"
printf 'keep\n' > "$persistent/state"
run_update "$uninstall_binary" "$UNINSTALL_ZIP" "$system" biscuit 999999
[ "$(sha256sum "$system/bin/ledcontroller" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ]
[ ! -e "$system/bin/ledcontroller.orig" ]
[ ! -e "$system/bin/echolocal" ]
[ ! -e "$system/app/echod/echod" ]
[ ! -e "$system/etc/echolocal/.biscuit-addon" ]
[ "$(cat "$persistent/state")" = keep ]

printf '%s\n' 'installer refusal, upgrade, uninstall, and persistent-state checks passed'
