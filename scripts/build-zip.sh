#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in cp find sed sha256sum sort touch tr wc xargs zip; do
    need "$tool"
done

require_hash "$INPUTS/echod" "$ECHOD_SHA256"
require_static_aarch64 "echod" "$INPUTS/echod"
require_hash "$INPUTS/busybox" "$BUSYBOX_SHA256"
require_static_aarch64 "BusyBox" "$INPUTS/busybox"
require_hash "$INPUTS/ca-certificates.crt" "$AOSP_CA_BUNDLE_SHA256"
printf '%s\n' "$ECHOLOCAL_MODELS" |
while read -r name expected source; do
    [ -n "$name" ] || continue
    require_hash "$INPUTS/models/$name" "$expected"
done

stage="$WORK/stage"
uninstall_stage="$WORK/uninstall-stage"
rm -rf "$stage" "$uninstall_stage"
mkdir -p "$stage/payload/system/bin" \
    "$stage/payload/system/xbin" \
    "$stage/payload/system/app/echod" \
    "$stage/payload/system/etc/echolocal/models" \
    "$stage/payload/system/etc/ssl/certs" \
    "$stage/META-INF/com/google/android" \
    "$uninstall_stage/META-INF/com/google/android"

cp "$ROOT/payload/system/bin/ledcontroller" "$stage/payload/system/bin/ledcontroller"
cp "$ROOT/payload/system/bin/echolocal" "$stage/payload/system/bin/echolocal"
cp "$INPUTS/busybox" "$stage/payload/system/xbin/busybox"
cp "$INPUTS/echod" "$stage/payload/system/app/echod/echod"
cp "$INPUTS/ca-certificates.crt" "$stage/payload/system/etc/ssl/certs/ca-certificates.crt"
printf 'name=%s\nversion=%s\nbase_ledcontroller_sha256=%s\n' \
    "$ADDON_NAME" "$ECHOLOCAL_VERSION" "$BASE_LEDCONTROLLER_SHA256" \
    > "$stage/payload/system/etc/echolocal/.biscuit-addon"
printf '%s\n' "$ECHOLOCAL_MODELS" |
while read -r name expected source; do
    [ -n "$name" ] || continue
    cp "$INPUTS/models/$name" "$stage/payload/system/etc/echolocal/models/$name"
done

find "$stage" -type d -exec chmod 0755 {} \;
find "$stage/payload" -type f -exec chmod 0644 {} \;
chmod 0755 "$stage/payload/system/bin/ledcontroller" \
    "$stage/payload/system/bin/echolocal" \
    "$stage/payload/system/xbin/busybox" \
    "$stage/payload/system/app/echod/echod"
(
    cd "$stage"
    LC_ALL=C find payload -type f -print | LC_ALL=C sort | xargs sha256sum
) > "$stage/payload-manifest.sha256"
manifest_sha=$(hash_of "$stage/payload-manifest.sha256")
payload_bytes=0
for path in $(LC_ALL=C find "$stage/payload" -type f -print | LC_ALL=C sort); do
    size=$(wc -c < "$path" | tr -d ' ')
    payload_bytes=$((payload_bytes + size))
done

sed -e "s/@ADDON_NAME@/$ADDON_NAME/g" \
    -e "s/@VERSION@/$ECHOLOCAL_VERSION/g" \
    -e "s/@BASE_LEDCONTROLLER_SHA256@/$BASE_LEDCONTROLLER_SHA256/g" \
    -e "s/@MANIFEST_SHA256@/$manifest_sha/g" \
    -e "s/@PAYLOAD_BYTES@/$payload_bytes/g" \
    "$ROOT/installer/META-INF/com/google/android/update-binary.in" \
    > "$stage/META-INF/com/google/android/update-binary"
sed -e "s/@ADDON_NAME@/$ADDON_NAME/g" \
    -e "s/@BASE_LEDCONTROLLER_SHA256@/$BASE_LEDCONTROLLER_SHA256/g" \
    "$ROOT/installer/META-INF/com/google/android/update-binary-uninstall.in" \
    > "$uninstall_stage/META-INF/com/google/android/update-binary"
cp "$ROOT/installer/META-INF/com/google/android/updater-script" \
    "$stage/META-INF/com/google/android/updater-script"
cp "$ROOT/installer/META-INF/com/google/android/updater-script" \
    "$uninstall_stage/META-INF/com/google/android/updater-script"
chmod 0755 "$stage/META-INF/com/google/android/update-binary" \
    "$uninstall_stage/META-INF/com/google/android/update-binary"

find "$stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
find "$uninstall_stage" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
mkdir -p "$OUT"
install_zip="$OUT/$ADDON_NAME-$ECHOLOCAL_VERSION.zip"
uninstall_zip="$OUT/$ADDON_NAME-$ECHOLOCAL_VERSION-uninstall.zip"
rm -f "$install_zip" "$install_zip.sha256" "$uninstall_zip" "$uninstall_zip.sha256"
(
    cd "$stage"
    LC_ALL=C find . -type f -print | sed 's|^./||' | LC_ALL=C sort |
        zip -X -q "$install_zip" -@
)
(
    cd "$uninstall_stage"
    LC_ALL=C find . -type f -print | sed 's|^./||' | LC_ALL=C sort |
        zip -X -q "$uninstall_zip" -@
)
(
    cd "$OUT"
    sha256sum "$(basename "$install_zip")" > "$(basename "$install_zip").sha256"
    sha256sum "$(basename "$uninstall_zip")" > "$(basename "$uninstall_zip").sha256"
)

printf '%s\n' "built $install_zip"
printf '%s\n' "built $uninstall_zip"
