#!/bin/sh
set -eu

. "$(dirname "$0")/common.sh"

for tool in curl file git sha256sum; do
    need "$tool"
done

mkdir -p "$INPUTS/downloads" "$INPUTS/models" "$SOURCES"

echod="$INPUTS/echod"
fetch "$ECHOD_URL" "$echod" "$ECHOD_SHA256"
require_static_aarch64 "echod" "$echod"
chmod 0755 "$echod"

model_source="$SOURCES/echolocal"
if [ ! -d "$model_source/.git" ]; then
    rm -rf "$model_source"
    git init -q "$model_source"
    git -C "$model_source" remote add origin "$ECHOLOCAL_REPOSITORY"
else
    git -C "$model_source" remote set-url origin "$ECHOLOCAL_REPOSITORY"
fi
GIT_TERMINAL_PROMPT=0 git -C "$model_source" fetch -q --depth=1 origin "$ECHOLOCAL_COMMIT"
git -C "$model_source" checkout -q --detach --force "$ECHOLOCAL_COMMIT"
[ "$(git -C "$model_source" rev-parse HEAD)" = "$ECHOLOCAL_COMMIT" ] ||
    fail "EchoLocal source did not resolve to $ECHOLOCAL_COMMIT"

printf '%s\n' "$ECHOLOCAL_MODELS" |
while read -r name expected source; do
    [ -n "$name" ] || continue
    source_path="$model_source/$source"
    target="$INPUTS/models/$name"
    [ -f "$source_path" ] || fail "missing pinned model: $source"
    cp "$source_path" "$target"
    chmod 0644 "$target"
    require_hash "$target" "$expected"
done


printf '%s\n' "prepared pinned EchoLocal inputs in $INPUTS"
