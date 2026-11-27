#!/bin/bash
# One-time (and re-runnable) setup for the backups. Run in a real terminal:  ~/.config/backup/install.sh
# Since 2026-11-27 every restic job runs as ROOT and the credentials live ONLY in /etc/backup (root 700):
#   /etc/backup/restic-password  /etc/backup/rclone.conf  /etc/backup/env  /etc/backup/excludes
# Nothing running as levi (Claude included) can read them or delete the backups. Re-run after editing
# ~/.config/backup/{env,excludes,system/*}; review the diff first: sudo diff /etc/backup/env ~/.config/backup/env
set -euo pipefail
SRC="$HOME/.config/backup/system"
C=/etc/backup
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
SB=/usr/local/bin/system-backup

echo "${B}1/5 Packages${N}"
sudo dnf install -y restic rclone jq eza git-delta fzf

echo "${B}2/5 Root-only settings (${C})${N}"
sudo install -d -m 700 -o root -g root "$C" /var/cache/restic
sudo install -m 600 -o root -g root "$HOME/.config/backup/env" "$C/env"
sudo install -m 600 -o root -g root "$HOME/.config/backup/excludes" "$C/excludes"
sudo install -m 755 -o root -g root "$SRC/system-backup" "$SB"

echo "${B}3/5 Credentials → root-only${N}"
old_pw="$HOME/.config/backup/restic-password"; old_rc="$HOME/.config/rclone/rclone.conf"
# one-time move from the old per-user locations
[ -s "$old_pw" ] && ! sudo test -s "$C/restic-password" && sudo install -m 600 -o root -g root "$old_pw" "$C/restic-password"
[ -s "$old_rc" ] && ! sudo test -s "$C/rclone.conf"     && sudo install -m 600 -o root -g root "$old_rc" "$C/rclone.conf"
if ! sudo test -s "$C/rclone.conf"; then
    [ -t 0 ] || { echo "${R}No Drive login in $C and no terminal to create one. Run this installer yourself.${N}"; exit 1; }
    echo "A link follows: open it in a PRIVATE window, sign in as the SYSTEM Google account (the backups live there),"
    echo "allow rclone, then close every private window. (Your own OAuth client: RESTORE.md step 2.)"
    read -rp "OAuth client ID: " cid; read -rp "OAuth client secret: " csec
    tmp=$(mktemp); RCLONE_CONFIG="$tmp" rclone config create gdrive drive scope=drive client_id "$cid" client_secret "$csec" --auth-no-open-browser
    sudo install -m 600 -o root -g root "$tmp" "$C/rclone.conf"; shred -u "$tmp"
fi
if ! sudo test -s "$C/restic-password"; then
    sudo sh -c "umask 077; openssl rand -base64 33 | tr -d '\n' > $C/restic-password"
    echo; echo "${Y}${B}══════════ SAVE THIS PASSWORD SOMEWHERE OFF THIS COMPUTER ══════════${N}"
    echo "${Y}  (password manager / printed paper). Without it the backup CANNOT be restored.${N}"; echo
    echo "    ${B}$(sudo cat "$C/restic-password")${N}"; echo
    [ -t 0 ] && read -rp "Press Enter once you've saved it... "
fi
sudo env -C / "$SB" restic cat config >/dev/null 2>&1 || {
    if sudo env -C / bash -c "source $C/env && rclone lsf --max-depth 1 \"\$RCLONE_REMOTE_DIR\"" 2>/dev/null | grep -qx 'restic/'; then
        echo "${R}The Drive repository exists but won't open with $C/restic-password. Nothing deleted; fix the password first.${N}"; exit 1
    fi
    echo "Initializing the repository"; sudo env -C / bash -c "source $C/env && rclone mkdir \"\$RCLONE_REMOTE_DIR\" && restic init"
}
echo "${G}  ✔ root opens the repository with the credentials in $C${N}"
# only now that root's copies are proven to work: remove the user-readable copies
for f in "$old_pw" "$old_rc"; do [ -e "$f" ] && shred -u "$f" && echo "  removed the user copy: ${f/#$HOME/~}"; done
rmdir "$HOME/.config/rclone" 2>/dev/null || true
rm -rf "$HOME/.cache/restic"

echo "${B}4/5 Root jobs: nightly backup, movies, weekly verify${N}"
sudo install -m 644 "$SRC/system-backup.service" "$SRC/movies-backup.service" "$SRC/movies-backup.timer" \
    "$SRC/backup-verify.service" "$SRC/backup-verify.timer" /etc/systemd/system/
sudo install -m 644 "$SRC/50-system-backup.rules" /etc/polkit-1/rules.d/
sudo restorecon -R "$SB" "$C" /var/cache/restic /etc/systemd/system/system-backup.service /etc/systemd/system/movies-backup.* \
    /etc/systemd/system/backup-verify.* /etc/polkit-1/rules.d/50-system-backup.rules 2>/dev/null || true
# the movie backup used to be a user unit: retire it
if [ -e "$HOME/.config/systemd/user/movies-backup.service" ]; then
    systemctl --user disable --now movies-backup.timer movies-backup.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/movies-backup.service" "$HOME/.config/systemd/user/movies-backup.timer"
    systemctl --user daemon-reload; echo "  retired the old user movies-backup units"
fi
sudo systemctl daemon-reload
sudo systemctl enable movies-backup.service movies-backup.timer backup-verify.timer >/dev/null
sudo systemctl start movies-backup.timer backup-verify.timer
# midnight scheduling lives in ~/.config/update/install.sh (nightly-maintenance.timer: backup → update)

echo "${B}5/5 Check${N}"
sudo env -C / "$SB" restic snapshots --latest 1 --compact | tail -3
echo
echo "${G}${B}✔ Done.${N} Backups run as root now. ${B}backup${N} runs one, ${B}backup status${N} anytime; ls/restore ask for sudo."
