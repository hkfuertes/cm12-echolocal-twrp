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
cat > "$tmp/bin/df" <<'EOF'
#!/bin/sh
cat <<'DF'
Filesystem           1K-blocks      Used Available Use% Mounted on
/dev/block/mmcblk0p13
                        761776     44332    701716   6% /system
DF
EOF
cat > "$tmp/bin/chcon-fails" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod 0755 "$tmp/bin/getprop" "$tmp/bin/chcon" "$tmp/bin/df" "$tmp/bin/chcon-fails"
unzip -q "$INSTALL_ZIP" -d "$tmp/install"
unzip -q "$UNINSTALL_ZIP" -d "$tmp/uninstall"
install_binary="$tmp/install/META-INF/com/google/android/update-binary"
uninstall_binary="$tmp/uninstall/META-INF/com/google/android/update-binary"

setup_system() {
    rm -rf "$1"
    mkdir -p "$1/bin" "$1/xbin" "$1/etc/ssl/certs"
    cp "$FIXTURE" "$1/bin/ledcontroller"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$1/xbin/busybox"
    printf '%s\n' 'base CA bundle' > "$1/etc/ssl/certs/ca-certificates.crt"
    chmod 0755 "$1/bin/ledcontroller" "$1/xbin/busybox"
    chmod 0644 "$1/etc/ssl/certs/ca-certificates.crt"
    case "${2:-managed}" in
        managed)
            printf '%s\n' 'stock start animation' > "$1/bin/start_animation.sh"
            printf '%s\n' 'stock stop animation' > "$1/bin/stop_animation.sh"
            chmod 0755 "$1/bin/start_animation.sh" "$1/bin/stop_animation.sh"
            ;;
        absent) ;;
        *) printf '%s\n' "unknown hook mode: $2" >&2; exit 1 ;;
    esac
}

run_update() {
    TEST_PRODUCT="$4" \
        ECHOLOCAL_SYSTEM="$3" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB="$5" GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" \
        sh "$1" 3 1 "$2" >/dev/null
}

run_update_folded_df() {
    TEST_PRODUCT=biscuit ECHOLOCAL_SYSTEM="$2" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon" DF="$tmp/bin/df" \
        sh "$1" 3 1 "$INSTALL_ZIP" >/dev/null
}

run_update_label_failure() {
    TEST_PRODUCT=biscuit ECHOLOCAL_SYSTEM="$2" ECHOLOCAL_TMPDIR="$tmp/recovery" \
        ECHOLOCAL_FREE_KB=999999 GETPROP="$tmp/bin/getprop" CHCON="$tmp/bin/chcon-fails" \
        sh "$1" 3 1 "$INSTALL_ZIP" >/dev/null
}

system="$tmp/system"
setup_system "$system"
base_busybox_hash=$(sha256sum "$system/xbin/busybox" | awk '{print $1}')
base_ca_hash=$(sha256sum "$system/etc/ssl/certs/ca-certificates.crt" | awk '{print $1}')
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ -f "$system/bin/ledcontroller.orig" ]
[ -L "$system/bin/ledcontroller" ]
[ "$(readlink "$system/bin/ledcontroller")" = "$system/app/echod/echod" ]
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ]
[ -f "$system/etc/echolocal/.biscuit-addon" ]
[ "$(sha256sum "$system/xbin/busybox" | awk '{print $1}')" = "$base_busybox_hash" ]
[ "$(sha256sum "$system/etc/ssl/certs/ca-certificates.crt" | awk '{print $1}')" = "$base_ca_hash" ]
grep -qx 'animation_hooks=managed' "$system/etc/echolocal/.biscuit-addon"
[ "$(cat "$system/bin/start_animation.sh.orig")" = 'stock start animation' ]
[ "$(cat "$system/bin/stop_animation.sh.orig")" = 'stock stop animation' ]
grep -Fq 'echod.prev' "$system/bin/start_animation.sh"
grep -Fq 'exit 0' "$system/bin/stop_animation.sh"
backup_hash=$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')
start_backup_hash=$(sha256sum "$system/bin/start_animation.sh.orig" | awk '{print $1}')
stop_backup_hash=$(sha256sum "$system/bin/stop_animation.sh.orig" | awk '{print $1}')
run_update "$install_binary" "$INSTALL_ZIP" "$system" biscuit 999999
[ "$(sha256sum "$system/bin/ledcontroller.orig" | awk '{print $1}')" = "$backup_hash" ]
[ "$(sha256sum "$system/bin/start_animation.sh.orig" | awk '{print $1}')" = "$start_backup_hash" ]
[ "$(sha256sum "$system/bin/stop_animation.sh.orig" | awk '{print $1}')" = "$stop_backup_hash" ]
[ -L "$system/bin/ledcontroller" ]
[ "$(readlink "$system/bin/ledcontroller")" = "$system/app/echod/echod" ]

folded_df="$tmp/folded-df"
setup_system "$folded_df"
run_update_folded_df "$install_binary" "$folded_df"
[ -L "$folded_df/bin/ledcontroller" ]

label_failure="$tmp/label-failure"
setup_system "$label_failure"
run_update_label_failure "$install_binary" "$label_failure"
[ -L "$label_failure/bin/ledcontroller" ]

minimal="$tmp/minimal"
setup_system "$minimal" absent
run_update "$install_binary" "$INSTALL_ZIP" "$minimal" biscuit 999999
[ -L "$minimal/bin/ledcontroller" ]
grep -qx 'animation_hooks=absent' "$minimal/etc/echolocal/.biscuit-addon"
[ ! -e "$minimal/bin/start_animation.sh" ]
[ ! -e "$minimal/bin/stop_animation.sh" ]
cp "$tmp/install/payload/system/bin/start_animation.sh" "$minimal/bin/start_animation.sh"
cp "$tmp/install/payload/system/bin/stop_animation.sh" "$minimal/bin/stop_animation.sh"
run_update "$uninstall_binary" "$UNINSTALL_ZIP" "$minimal" biscuit 999999
[ ! -e "$minimal/bin/start_animation.sh" ]
[ ! -e "$minimal/bin/stop_animation.sh" ]
[ "$(sha256sum "$minimal/bin/ledcontroller" | awk '{print $1}')" = "$BASE_LEDCONTROLLER_SHA256" ]

wrong_device="$tmp/wrong-device"
setup_system "$wrong_device"
if run_update "$install_binary" "$INSTALL_ZIP" "$wrong_device" not-biscuit 999999; then
    printf '%s\n' 'wrong device was accepted' >&2
    exit 1
fi
[ ! -e "$wrong_device/bin/ledcontroller.orig" ]
[ ! -e "$wrong_device/bin/start_animation.sh.orig" ]

missing_busybox="$tmp/missing-busybox"
setup_system "$missing_busybox"
rm "$missing_busybox/xbin/busybox"
if run_update "$install_binary" "$INSTALL_ZIP" "$missing_busybox" biscuit 999999; then
    printf '%s\n' 'missing base BusyBox was accepted' >&2
    exit 1
fi

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
[ ! -L "$system/bin/ledcontroller" ]
[ ! -e "$system/bin/ledcontroller.orig" ]
[ "$(cat "$system/bin/start_animation.sh")" = 'stock start animation' ]
[ "$(cat "$system/bin/stop_animation.sh")" = 'stock stop animation' ]
[ ! -e "$system/bin/start_animation.sh.orig" ]
[ ! -e "$system/bin/stop_animation.sh.orig" ]
[ ! -e "$system/bin/echolocal" ]
[ "$(sha256sum "$system/xbin/busybox" | awk '{print $1}')" = "$base_busybox_hash" ]
[ "$(sha256sum "$system/etc/ssl/certs/ca-certificates.crt" | awk '{print $1}')" = "$base_ca_hash" ]
[ ! -e "$system/app/echod/echod" ]
[ ! -e "$system/etc/echolocal/.biscuit-addon" ]
[ "$(cat "$persistent/state")" = keep ]

printf '%s\n' 'installer refusal, base BusyBox/CA preservation, symlink takeover, managed/absent hook, and persistent-state checks passed'
