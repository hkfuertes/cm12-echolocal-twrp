#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in git sha256sum find sort xargs wc tr; do
    need "$tool"
done

mkdir -p "$INPUTS" "$SOURCES"
source="$SOURCES/aosp-ca-certificates"
if [ ! -d "$source/.git" ]; then
    rm -rf "$source"
    git init -q "$source"
    git -C "$source" remote add origin "$AOSP_CA_REPOSITORY"
else
    git -C "$source" remote set-url origin "$AOSP_CA_REPOSITORY"
fi
GIT_TERMINAL_PROMPT=0 git -C "$source" fetch -q --depth=1 origin "$AOSP_CA_COMMIT"
git -C "$source" checkout -q --detach --force "$AOSP_CA_COMMIT"
[ "$(git -C "$source" rev-parse HEAD)" = "$AOSP_CA_COMMIT" ] ||
    fail "AOSP CA source did not resolve to $AOSP_CA_COMMIT"

cert_dir="$source/files"
[ -d "$cert_dir" ] || fail "pinned AOSP CA revision has no files directory"
count=$(find "$cert_dir" -type f -name '*.0' | wc -l | tr -d ' ')
[ "$count" = "$AOSP_CA_CERT_COUNT" ] ||
    fail "AOSP CA certificate count changed: expected $AOSP_CA_CERT_COUNT, got $count"

bundle="$INPUTS/ca-certificates.crt"
LC_ALL=C find "$cert_dir" -type f -name '*.0' -print |
    LC_ALL=C sort |
    xargs cat > "$bundle.part"
[ -s "$bundle.part" ] || fail "generated CA bundle is empty"
mv "$bundle.part" "$bundle"
chmod 0644 "$bundle"
require_hash "$bundle" "$AOSP_CA_BUNDLE_SHA256"

printf '%s\n' "generated pinned AOSP CA bundle in $bundle"
