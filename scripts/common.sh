#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/versions.sh"

WORK=${WORK:-"$ROOT/work"}
OUT=${OUT:-"$ROOT/out"}
INPUTS="$WORK/inputs"
SOURCES="$WORK/source"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required host tool: $1"
}

hash_of() {
    sha256sum "$1" | awk '{print $1}'
}

has_hash() {
    [ -f "$1" ] && [ "$(hash_of "$1")" = "$2" ]
}

require_hash() {
    got=$(hash_of "$1")
    [ "$got" = "$2" ] || fail "SHA-256 mismatch: $1"
}

require_static_aarch64() {
    description=$1
    path=$2
    file "$path" | grep -Eq 'ELF 64-bit.*ARM aarch64.*statically linked' ||
        fail "$description is not a static ELF64 AArch64 executable"
}
