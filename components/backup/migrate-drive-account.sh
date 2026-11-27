#!/bin/bash
# migrate-drive-account.sh — move the backups from your PERSONAL Google account to the separate SYSTEM account
# (the one that is never signed in to a browser on this laptop), so your everyday browser session can't reach them.
# Run it yourself in a real terminal, AFTER ~/.config/backup/install.sh (credentials already root-only in /etc/backup):
#   ~/.config/backup/migrate-drive-account.sh            steps 1–5: log in the system account, copy, verify, switch
#   ~/.config/backup/migrate-drive-account.sh finish     step 6 (after `backup` + `backup verify` pass on the system account): delete the personal copy
#                                                       and remove the personal account's login from this laptop
# Before step 1: the system account is in your Google One family (it shares the 5 TB), and in Drive (as your PERSONAL
# account, any browser) you've shared the folder "fedora-backup" with the system account as Viewer.
set -euo pipefail
C=/etc/backup; RC="$C/rclone.conf"
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
[ -t 0 ] || { echo "Run this yourself in a terminal."; exit 1; }
r() { sudo rclone --config "$RC" "$@"; }                     # rclone as root, with the root-only logins
rs() { sudo env RCLONE_CONFIG="$RC" RESTIC_PASSWORD_FILE="$C/restic-password" RESTIC_CACHE_DIR=/var/cache/restic restic "$@"; }
sudo test -s "$RC" || { echo "${R}No $RC — run ~/.config/backup/install.sh first.${N}"; exit 1; }

if [ "${1:-}" = finish ]; then
    r listremotes | grep -qx 'personal-old:' || { echo "Nothing to finish (no personal-old remote)."; exit 0; }
    echo "${B}Step 6: delete the backup copy in your PERSONAL Drive, and its login from this laptop${N}"
    echo "Only do this after 'backup' AND 'backup verify' succeeded since the switch (shown below):"
    cat ~/.local/state/backup/last-result 2>/dev/null; jq -r '.full.time // empty | strflocaltime("verify full: %F %H:%M")' ~/.local/state/backup/verify.json 2>/dev/null
    read -rp "Type DELETE to permanently remove personal-old:fedora-backup: " a; [ "$a" = DELETE ] || { echo "nothing changed"; exit 0; }
    r purge personal-old:fedora-backup --drive-use-trash=false
    r config delete personal-old
    echo "${G}✔ Done. The laptop holds no login for your personal Google account any more (only the system account, root-only).${N}"
    echo "  In Drive (personal account): the share of 'fedora-backup' is gone with the folder; nothing else to undo."
    exit 0
fi

r listremotes | grep -qx 'personal-old:' && { echo "${Y}Already switched (personal-old exists). Next, days later: $0 finish${N}"; exit 0; }
id=$(r config dump | jq -r '.gdrive.client_id // empty'); sec=$(r config dump | jq -r '.gdrive.client_secret // empty')
[ -n "$id" ] && [ -n "$sec" ] || { echo "${R}Couldn't read your OAuth client from the current gdrive login.${N}"; exit 1; }

echo "${B}Step 1/5: log in the SYSTEM account (private window, so it never stays signed in)${N}"
echo "  If your Google Cloud OAuth app is in 'Testing', add the system account as a test user first (or publish the app)."
echo "  A URL follows: open it in a ${B}private/incognito window${N}, sign in as the SYSTEM account, allow, then close every"
echo "  private window. Nothing of that account stays in your browser."
tok=$(rclone authorize drive "$id" "$sec" --auth-no-open-browser 2>/dev/tty | grep -o '{.*}' | tail -1)
[ -n "$tok" ] || { echo "${R}No token received.${N}"; exit 1; }
r config create gsys drive scope=drive client_id "$id" client_secret "$sec" token "$tok" >/dev/null; unset tok
who=$(r about gsys: --json | jq -r '"\(.total / 1099511627776 * 10 | floor / 10) TiB total, \(.used / 1073741824 | floor) GiB used"')
echo "  system account Drive: $who"

echo "${B}Step 2/5: does the system account see your shared folder?${N}"
r lsf gsys: --drive-shared-with-me --max-depth 1 | grep -qx 'fedora-backup/' || {
    echo "${R}Not shared yet. In Drive as your PERSONAL account: right-click 'fedora-backup' → Share → the system account (Viewer). Then re-run.${N}"; exit 1; }
need=$(r size gdrive:fedora-backup --json | jq -r '.bytes'); free=$(r about gsys: --json | jq -r '.free // (.total - .used)')
[ "$free" -gt "$need" ] || { echo "${R}Not enough space on the system account ($((free/2**30)) GiB free, need $((need/2**30))). Add it to your Google One family.${N}"; exit 1; }

echo "${B}Step 3/5: server-side copy (Drive → Drive, nothing re-uploaded from here; can take a few hours)${N}"
systemctl is-active -q system-backup.service movies-backup.service && { echo "${R}A backup is running; wait for it to finish.${N}"; exit 1; }
r copy gdrive:fedora-backup gsys:fedora-backup --server-side-across-configs \
    --transfers 8 --checkers 16 -P

echo "${B}Step 4/5: prove the copy${N}"
a=$(r size gdrive:fedora-backup --json | jq -c '{count, bytes}'); b=$(r size gsys:fedora-backup --json | jq -c '{count, bytes}')
echo "  personal: $a   system: $b"; [ "$a" = "$b" ] || { echo "${R}Copies differ. Re-run to resume the copy.${N}"; exit 1; }
for repo in restic movies; do
    echo "  restic check ($repo) on the system account…"
    rs -r "rclone:gsys:fedora-backup/$repo" check --no-lock >/dev/null || { echo "${R}restic check failed on the copy of $repo.${N}"; exit 1; }
done
echo "${G}  ✔ identical, and restic reads both repositories on the system account${N}"

echo "${B}Step 5/5: switch the laptop to the system account${N}"
# the name "gdrive" stays (every script uses it); it now means the system account. The personal login is kept as
# "personal-old" only until `finish`.
sudo sed -i 's/^\[gdrive\]$/[personal-old]/; s/^\[gsys\]$/[gdrive]/' "$RC"
r lsf gdrive:fedora-backup --max-depth 1 | grep -qx 'restic/' && r about gdrive: --json | jq -e '.total > 1e12' >/dev/null ||
    { echo "${R}Switch check failed — restoring the old config.${N}"; sudo sed -i 's/^\[gdrive\]$/[gsys]/; s/^\[personal-old\]$/[gdrive]/' "$RC"; exit 1; }
echo "${G}${B}✔ Backups now live on the system account.${N}"
echo "  Next: ${B}backup${N}, then ${B}backup verify${N}; when both pass: ${B}$0 finish${N}"
