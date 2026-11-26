#!/bin/bash
# private-values.sh: print "<private literal>\t<placeholder>" lines discovered on THIS machine.
# Used by sync.sh (to redact) and leakcheck.sh (to prove nothing is left). Output is never written into the repo.
set -uo pipefail
emit() { [ -n "$1" ] && [ "${#1}" -ge 4 ] && printf '%s\t%s\n' "$1" "$2"; }

# alert email address(es)
for f in "$HOME/.config/watcher/alerts.conf"; do
    [ -r "$f" ] && grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" | while read -r e; do emit "$e" "you@example.com"; done
done
# this machine's id (deadman orders name it)
emit "$(cat /etc/machine-id 2>/dev/null)" "0123456789abcdef0123456789abcdef"
# router + Wi-Fi hardware addresses currently known (home router MAC is the away-alert trust anchor)
ip -j neigh 2>/dev/null | jq -r '.[].lladdr // empty' 2>/dev/null | sort -u | while read -r m; do emit "$m" "aa:bb:cc:dd:ee:ff"; done
# saved Wi-Fi network names
nmcli -t -f NAME,TYPE connection show 2>/dev/null | awk -F: '$2 ~ /wireless/ {print $1}' | while read -r n; do emit "$n" "HomeWiFi"; done
# Tailscale addresses
command -v tailscale >/dev/null && tailscale ip 2>/dev/null | while read -r a; do emit "$a" "100.64.0.1"; done
# public key fingerprints/comment of the phone (not secret, but identifying)
[ -r "$HOME/.config/remote/phone-key.pub" ] && emit "$(grep -oE 'AAAA[A-Za-z0-9+/=]{40,}' "$HOME/.config/remote/phone-key.pub" | head -1)" "AAAA...phone-key..."
# anything else you never want published: one literal per line
[ -r "$HOME/.config/showcase/private" ] && grep -v '^\s*#' "$HOME/.config/showcase/private" | while IFS= read -r l; do emit "$l" "REDACTED"; done
exit 0
