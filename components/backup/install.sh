#!/bin/bash
# One-time (and re-runnable) setup for the nightly backup + terminal color tools.
# Run in a real terminal:  ~/.config/backup/install.sh
set -euo pipefail
SRC="$HOME/.config/backup/system"
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'

echo "${B}1/4 Installing packages (sudo)${N}"
sudo dnf install -y restic rclone eza git-delta fzf

echo "${B}2/4 Installing system service, timer, polkit rule${N}"
sudo install -m 755 -o root -g root "$SRC/system-backup" /usr/local/bin/system-backup
sudo install -m 644 "$SRC/system-backup.service" /etc/systemd/system/
sudo install -m 644 "$SRC/50-system-backup.rules" /etc/polkit-1/rules.d/
sudo restorecon -v /usr/local/bin/system-backup /etc/systemd/system/system-backup.* /etc/polkit-1/rules.d/50-system-backup.rules
sudo systemctl daemon-reload
# midnight scheduling lives in ~/.config/update/install.sh (nightly-maintenance.timer: backup → update)

source "$HOME/.config/backup/env"

echo "${B}3/4 Google Drive connection (rclone)${N}"
if rclone listremotes 2>/dev/null | grep -q '^gdrive:$'; then
    echo "gdrive remote already configured"
else
    echo "A browser window will open: sign in to Google and allow rclone."
    rclone config create gdrive drive scope=drive
fi
rclone mkdir "$RCLONE_REMOTE_DIR"

echo "${B}4/4 Encryption password + repository${N}"
if [ ! -f "$RESTIC_PASSWORD_FILE" ]; then
    ( umask 077; openssl rand -base64 33 | tr -d '\n' >"$RESTIC_PASSWORD_FILE" )
    echo
    echo "${Y}${B}══════════ SAVE THIS PASSWORD SOMEWHERE OFF THIS COMPUTER ══════════${N}"
    echo "${Y}  (password manager / printed paper). Without it the backup CANNOT be restored.${N}"
    echo
    echo "    ${B}$(cat "$RESTIC_PASSWORD_FILE")${N}"
    echo
    read -rp "Press Enter once you've saved it... "
fi
if restic cat config >/dev/null 2>&1; then
    echo "Repository already initialized"
else
    restic init
fi

echo
echo "${G}${B}✔ Done.${N} Now run ~/.config/update/install.sh to schedule midnight backup → update. Run ${B}backup${N} now for the first (big) upload, ${B}backup status${N} anytime."

