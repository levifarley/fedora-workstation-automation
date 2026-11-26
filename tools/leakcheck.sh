#!/bin/bash
# leakcheck.sh: fail (exit 1) if anything personal or secret is in the repo's files. Run before every commit/push.
# Checks: this machine's private values (tools/private-values.sh) + generic secret/PII patterns.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
files=$(find . -type f -not -path './.git/*' -not -path './tools/*' -not -name '*.png')
bad=0

while IFS=$'\t' read -r lit _; do
    [ -n "$lit" ] || continue
    hits=$(grep -rlIiF -- "$lit" $files 2>/dev/null)
    if [ -n "$hits" ]; then
        bad=1; echo "✘ private value (${#lit} chars, starts '${lit:0:3}…') found in:"; sed 's/^/     /' <<<"$hits"
    fi
done < <("$REPO/tools/private-values.sh")

declare -A PATTERNS=(
    [personal email]='[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|yahoo|icloud|proton)\.(com|me)'
    [private key]='-----BEGIN [A-Z ]*PRIVATE KEY-----'
    [GitHub token]='(ghp|gho|ghs|github_pat)_[A-Za-z0-9_]{20,}'
    [Anthropic key]='sk-ant-[A-Za-z0-9_-]{20,}'
    [Google OAuth secret]='GOCSPX-[A-Za-z0-9_-]{10,}'
    [ntfy topic value]='dm-[0-9a-f]{32}'
    [Tailscale IP]='\b100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}\b'
    [Tailscale name]='[a-z0-9-]+\.ts\.net'
)
for name in "${!PATTERNS[@]}"; do
    hits=$(grep -rlIE -- "${PATTERNS[$name]}" $files 2>/dev/null | while read -r f; do
        # placeholders are fine
        grep -IoE -- "${PATTERNS[$name]}" "$f" | grep -qvE '^(you@example\.com|100\.64\.0\.1)$' && echo "$f"; done)
    if [ -n "$hits" ]; then bad=1; echo "✘ $name in:"; sed 's/^/     /' <<<"$hits"; fi
done

for f in alerts.conf ntfy-topic restic-password healthchecks-url rclone.conf phone-key.pub; do
    found=$(find . -name "$f" -not -path './.git/*')
    [ -n "$found" ] && { bad=1; echo "✘ file that must never be published: $found"; }
done

if [ $bad = 0 ]; then echo "✔ leak check passed: no private values or secrets found"; else echo "✘ leak check FAILED: fix the above before committing"; fi
exit $bad
