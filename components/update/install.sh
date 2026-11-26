#!/bin/bash
# Install/refresh the nightly backup → update chain. Run in a real terminal:  ~/.config/update/install.sh
set -euo pipefail
SRC="$HOME/.config/update/system"

sudo install -m 755 -o root -g root "$SRC/system-update" /usr/local/bin/system-update
sudo install -m 644 "$SRC/system-update.service" "$SRC/nightly-maintenance.service" "$SRC/nightly-maintenance.timer" /etc/systemd/system/
sudo install -m 644 "$SRC/50-system-update.rules" /etc/polkit-1/rules.d/
sudo restorecon -v /usr/local/bin/system-update /etc/systemd/system/system-update.service \
    /etc/systemd/system/nightly-maintenance.* /etc/polkit-1/rules.d/50-system-update.rules
sudo systemctl daemon-reload
# the midnight trigger moves from system-backup.timer to nightly-maintenance.timer (backup → update)
sudo systemctl disable --now system-backup.timer 2>/dev/null || true
sudo systemctl enable --now nightly-maintenance.timer
systemctl list-timers nightly-maintenance.timer --no-pager | head -2
echo "✔ Installed. Midnight: backup → update (only if backup succeeded). Try: update check"
