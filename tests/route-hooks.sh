#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

cat > "$tmp/bin/logger" <<'EOF'
#!/bin/sh
cat >> "$LOGGER_LOG"
EOF
chmod +x "$tmp/bin/logger"

cat > "$tmp/bin/ip" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$IP_LOG"
[ "${IP_EXIT:-0}" -eq 0 ]
EOF
chmod +x "$tmp/bin/ip"

PATH="$tmp/bin:$PATH" IP_LOG="$tmp/ip.log" LOGGER_LOG="$tmp/logger.log" \
  "$repo/sbin/dhcpy6d-add-route" 2001:db8:1::/64 fe80::2 eth0
grep -Fqx -- '-6 route replace 2001:db8:1::/64 via fe80::2 dev eth0' "$tmp/ip.log"
grep -Fqx 'dhcpy6d-add-route: called with "2001:db8:1::/64" "fe80::2" "eth0"' "$tmp/logger.log"

PATH="$tmp/bin:$PATH" IP_LOG="$tmp/ip.log" LOGGER_LOG="$tmp/logger.log" IP_EXIT=2 \
  "$repo/sbin/dhcpy6d-del-route" 2001:db8:1::/64 fe80::2 eth0
grep -Fqx -- '-6 route del 2001:db8:1::/64 via fe80::2 dev eth0' "$tmp/ip.log"
grep -Fqx 'dhcpy6d-del-route: called with "2001:db8:1::/64" "fe80::2" "eth0"' "$tmp/logger.log"
