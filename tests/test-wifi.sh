#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/payload/system/bin/echolocal"
HOST_BUSYBOX=$(command -v busybox)
[ -n "$HOST_BUSYBOX" ] || { printf '%s\n' 'missing host BusyBox' >&2; exit 1; }
sh -n "$HELPER"
grep -Fq 'ready=$(wifi_cli status 2>/dev/null)' "$HELPER"
grep -Fq 'response=$(wifi_cli "$@" 2>/dev/null)' "$HELPER"
! grep -Fq 'wifi_cli status >/dev/null 2>&1' "$HELPER"
! grep -Fq 'wifi_cli "$@" >/dev/null' "$HELPER"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
sys="$tmp/system"
wpa_log="$tmp/wpa.log"
wpa_passphrase_log="$tmp/wpa-passphrase.log"
mkdir -p "$sys/bin" "$sys/xbin"
sed '1c#!/bin/sh' "$HELPER" > "$sys/bin/echolocal"
chmod 0755 "$sys/bin/echolocal"

cat > "$sys/xbin/busybox" <<EOF
#!/bin/sh
case "\${1:-}" in
    chown) exit 0 ;;
    id) printf '%s\\n' 'uid=0(root) gid=0(root)' ;;
    od) printf '%s\\n' 'BusyBox 1.22 does not support od -An' >&2; exit 1 ;;
    *) exec "$HOST_BUSYBOX" "\$@" ;;
esac
EOF
chmod 0755 "$sys/xbin/busybox"

cat > "$sys/bin/wpa_cli" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        -i*|-p*) shift ;;
        *) command=$1; shift; break ;;
    esac
done
printf '%s' "$command" >> "$TEST_WPA_LOG"
for argument in "$@"; do printf ' %s' "$argument" >> "$TEST_WPA_LOG"; done
printf '\n' >> "$TEST_WPA_LOG"
ready_state=
[ -z "${TEST_WPA_READY_STATE:-}" ] ||
    ready_state=$(cat "$TEST_WPA_READY_STATE" 2>/dev/null || true)
case "$command" in
    list_networks)
        [ -z "${TEST_WPA_READY_STATE:-}" ] || [ "$ready_state" = ready ] || {
            printf '%s\n' FAIL
            exit 0
        }
        printf 'network id / ssid / bssid / flags\n'
        ;;
    add_network) printf '0\n' ;;
    status)
        if [ -n "${TEST_WPA_READY_STATE:-}" ]; then
            case "$ready_state" in
                '') printf '%s\n' starting > "$TEST_WPA_READY_STATE"; printf '%s\n' FAIL; exit 0 ;;
                starting) printf '%s\n' ready > "$TEST_WPA_READY_STATE" ;;
            esac
        fi
        printf '%s\n' 'wpa_state=COMPLETED' 'ssid=Strongs' 'ip_address=192.0.2.1'
        ;;
    set_network|enable_network|select_network|save_config|remove_network) printf 'OK\n' ;;
    *) exit 1 ;;
esac
EOF
chmod 0755 "$sys/bin/wpa_cli"

cat > "$sys/bin/wpa_passphrase" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 1 ]
[ "$1" = Strongs ]
IFS= read -r passphrase
[ "${#passphrase}" -ge 8 ]
printf '%s\n' "$1" > "$TEST_WPA_PASSPHRASE_LOG"
printf '%s\n' 'network={' '    psk=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' '}'
EOF
chmod 0755 "$sys/bin/wpa_passphrase"

cat > "$sys/bin/setprop" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 0755 "$sys/bin/setprop"

: > "$wpa_log"
output=$(ECHOLOCAL_SYSTEM="$sys" TEST_WPA_LOG="$wpa_log" TEST_WPA_PASSPHRASE_LOG="$wpa_passphrase_log" sh "$sys/bin/echolocal" wifi open Strongs)
[ "$output" = 'connected: Strongs (192.0.2.1)' ]
grep -Fxq 'set_network 0 ssid 5374726f6e6773' "$wpa_log"
grep -Fxq 'set_network 0 key_mgmt NONE' "$wpa_log"

: > "$wpa_log"
passphrase=$(printf '%08d' 0)
ready_state="$tmp/wpa-ready"
output=$(ECHOLOCAL_SYSTEM="$sys" TEST_WPA_LOG="$wpa_log" TEST_WPA_PASSPHRASE_LOG="$wpa_passphrase_log" TEST_WPA_READY_STATE="$ready_state" sh "$sys/bin/echolocal" wifi connect Strongs "$passphrase")
[ "$output" = 'connected: Strongs (192.0.2.1)' ]
[ "$(cat "$ready_state")" = ready ]
grep -Fxq 'Strongs' "$wpa_passphrase_log"
grep -Fxq 'set_network 0 key_mgmt WPA-PSK' "$wpa_log"
grep -Fxq 'set_network 0 psk 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef' "$wpa_log"
! grep -Fq "$passphrase" "$wpa_log"
printf '%s\n' 'Wi-Fi passphrase and BusyBox 1.22 paths work'
