#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in file find grep mktemp sha256sum stat unzip; do
    need "$tool"
done

install_zip=${1:-"$OUT/$ADDON_NAME-$ECHOLOCAL_VERSION.zip"}
uninstall_zip=${2:-"$OUT/$ADDON_NAME-$ECHOLOCAL_VERSION-uninstall.zip"}
[ -f "$install_zip" ] || fail "missing ZIP: $install_zip"
[ -f "$uninstall_zip" ] || fail "missing ZIP: $uninstall_zip"

verify_sidecar() {
    zip_path=$1
    sidecar="$zip_path.sha256"
    [ -f "$sidecar" ] || fail "missing checksum: $sidecar"
    (
        cd "$(dirname "$zip_path")"
        sha256sum -c "$(basename "$sidecar")" >/dev/null
    ) || fail "ZIP checksum mismatch: $zip_path"
}

mode_is() {
    [ "$(stat -c '%a' "$1")" = "$2" ] || fail "wrong mode on $1"
}

forbidden_operations() {
    script=$1
    if grep -Eq '/(boot|recovery|userdata|cache|persist)(/|[[:space:]]|$)' "$script"; then
        fail "forbidden partition reference in $script"
    fi
    if grep -Eq '(^|[[:space:]])(dd|flash_image|write_raw_image|format|delete_recursive)([[:space:]]|$)' "$script"; then
        fail "forbidden flash operation in $script"
    fi
}

verify_sidecar "$install_zip"
verify_sidecar "$uninstall_zip"
unzip -t "$install_zip" >/dev/null
unzip -t "$uninstall_zip" >/dev/null

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
unzip -q "$install_zip" -d "$tmp/install"
unzip -q "$uninstall_zip" -d "$tmp/uninstall"

[ -z "$(find "$tmp/install" -type l -print)" ] || fail 'installer ZIP contains a symlink'
[ -z "$(find "$tmp/uninstall" -type l -print)" ] || fail 'uninstaller ZIP contains a symlink'
(
    cd "$tmp/install"
    sha256sum -c payload-manifest.sha256 >/dev/null
) || fail 'payload manifest does not verify'

for relative in \
    system/bin/ledcontroller \
    system/bin/echolocal \
    system/xbin/busybox \
    system/app/echod/echod \
    system/etc/ssl/certs/ca-certificates.crt \
    system/etc/echolocal/.biscuit-addon \
    system/etc/echolocal/models/okay_nabu.json \
    system/etc/echolocal/models/okay_nabu.tflite \
    system/etc/echolocal/models/hey_jarvis.json \
    system/etc/echolocal/models/hey_jarvis.tflite \
    system/etc/echolocal/models/hey_mycroft.json \
    system/etc/echolocal/models/hey_mycroft.tflite; do
    [ -f "$tmp/install/payload/$relative" ] && [ ! -L "$tmp/install/payload/$relative" ] ||
        fail "missing regular payload file: $relative"
done
for relative in system/bin/ledcontroller system/bin/echolocal system/xbin/busybox system/app/echod/echod; do
    mode_is "$tmp/install/payload/$relative" 755
done
for relative in system/etc/ssl/certs/ca-certificates.crt system/etc/echolocal/.biscuit-addon \
    system/etc/echolocal/models/okay_nabu.json system/etc/echolocal/models/okay_nabu.tflite \
    system/etc/echolocal/models/hey_jarvis.json system/etc/echolocal/models/hey_jarvis.tflite \
    system/etc/echolocal/models/hey_mycroft.json system/etc/echolocal/models/hey_mycroft.tflite; do
    mode_is "$tmp/install/payload/$relative" 644
done
file "$tmp/install/payload/system/xbin/busybox" |
    grep -Eq 'ELF 64-bit.*ARM aarch64.*statically linked' || fail 'packaged BusyBox is wrong'
file "$tmp/install/payload/system/app/echod/echod" |
    grep -Eq 'ELF 64-bit.*ARM aarch64.*statically linked' || fail 'packaged echod is wrong'
grep -qx "name=$ADDON_NAME" "$tmp/install/payload/system/etc/echolocal/.biscuit-addon" ||
    fail 'wrong add-on marker'
grep -qx "base_ledcontroller_sha256=$BASE_LEDCONTROLLER_SHA256" \
    "$tmp/install/payload/system/etc/echolocal/.biscuit-addon" || fail 'wrong base marker'

install_binary="$tmp/install/META-INF/com/google/android/update-binary"
uninstall_binary="$tmp/uninstall/META-INF/com/google/android/update-binary"
mode_is "$install_binary" 755
mode_is "$uninstall_binary" 755
sh -n "$install_binary"
sh -n "$uninstall_binary"
forbidden_operations "$install_binary"
forbidden_operations "$uninstall_binary"
grep -Fq 'u:object_r:system_file:s0' "$install_binary" ||
    fail 'installer does not label payload files'
grep -Fq 'BACKUP="$SERVICE.orig"' "$install_binary" || fail 'installer does not preserve fallback'
grep -Fq 'persistent state was preserved' "$uninstall_binary" ||
    fail 'uninstaller does not document state preservation'

printf '%s\n' "verified $install_zip and $uninstall_zip"
