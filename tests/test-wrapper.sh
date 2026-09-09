#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WRAPPER="$ROOT/payload/system/bin/ledcontroller"
HELPER="$ROOT/payload/system/bin/echolocal"
HOST_BUSYBOX=$(command -v busybox)
[ -n "$HOST_BUSYBOX" ] || { printf '%s\n' 'missing host BusyBox' >&2; exit 1; }
sh -n "$WRAPPER"
sh -n "$HELPER"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
sys="$tmp/system"
state="$tmp/data/misc/echolocal"
props="$tmp/properties"
started="$tmp/started"
mkdir -p "$sys/bin" "$sys/xbin" "$sys/app/echod" "$sys/etc/echolocal/models"
cp "$WRAPPER" "$sys/bin/ledcontroller"
sed '1c#!/bin/sh' "$HELPER" > "$sys/bin/echolocal"
chmod 0755 "$sys/bin/ledcontroller" "$sys/bin/echolocal"

cat > "$sys/xbin/busybox" <<EOF
#!/bin/sh
case "\${1:-}" in
    chown|mount) exit 0 ;;
    id) printf '%s\\n' 'uid=0(root) gid=0(root)' ;;
    *) exec "$HOST_BUSYBOX" "\$@" ;;
esac
EOF
chmod 0755 "$sys/xbin/busybox"
cat > "$sys/bin/setprop" <<'EOF'
#!/bin/sh
printf '%s=%s\n' "$1" "$2" >> "$TEST_PROPS"
EOF
chmod 0755 "$sys/bin/setprop"

for model in okay_nabu hey_jarvis hey_mycroft; do
    printf '{"name":"%s"}\n' "$model" > "$sys/etc/echolocal/models/$model.json"
    printf 'model-%s\n' "$model" > "$sys/etc/echolocal/models/$model.tflite"
done

write_daemon() {
    cat > "$sys/app/echod/echod" <<EOF
#!/bin/sh
printf '%s\\n' '$1' > "\$TEST_STARTED"
EOF
    chmod 0755 "$sys/app/echod/echod"
}

run_wrapper() {
    ECHOLOCAL_SYSTEM="$sys" ECHOLOCAL_STATE="$state" \
        TEST_PROPS="$props" TEST_STARTED="$started" \
        sh "$sys/bin/ledcontroller"
}

write_daemon new
run_wrapper
[ "$(cat "$started")" = new ]
[ -s "$state/psk" ]
for model in okay_nabu hey_jarvis hey_mycroft; do
    [ -f "$state/models/$model.json" ]
    [ -f "$state/models/$model.tflite" ]
done
key_hash=$(sha256sum "$state/psk" | awk '{print $1}')
printf 'custom\n' > "$state/models/okay_nabu.json"
run_wrapper
[ "$(cat "$state/models/okay_nabu.json")" = custom ]
[ "$(sha256sum "$state/psk" | awk '{print $1}')" = "$key_hash" ]

rm -rf "$state"
run_wrapper
[ -s "$state/psk" ]
[ -f "$state/models/hey_mycroft.tflite" ]

write_daemon new
cat > "$sys/app/echod/echod.prev" <<'EOF'
#!/bin/sh
printf '%s\n' old > "$TEST_STARTED"
EOF
chmod 0755 "$sys/app/echod/echod.prev"
printf 'trial-version\n' > "$state/updating"
run_wrapper
[ "$(cat "$started")" = old ]
[ ! -e "$sys/app/echod/echod.prev" ]
[ ! -e "$state/updating" ]
grep -qx 'echolocal.rolledback=trial-version' "$props"

printf '%s\n' 'wrapper first boot, data wipe, and rollback checks passed'
