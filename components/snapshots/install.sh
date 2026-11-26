#!/bin/bash
# One-time (re-runnable) setup of btrfs snapshots with snapper.
#   root (/)    : pre/post snapshot pair around EVERY dnf transaction (nightly update or manual), keep last 20
#   home (/home): hourly timeline, keep 24 hourly · 7 daily · 4 weekly
#   ~/.cache becomes its own subvolume so it's excluded from home snapshots
# Run in a real terminal:  ~/.config/snapshots/install.sh
set -euo pipefail
B=$'\e[1m'; G=$'\e[32m'; N=$'\e[0m'
step() { echo; echo "${B}▶ $*${N}"; }

sudo true   # (not `sudo -v`: that demands a password even where sudo is NOPASSWD, e.g. during an automated restore)
step "Packages"
sudo dnf install -y snapper btrfs-assistant libdnf5-plugin-actions

step "snapper configs"
sudo snapper -c root list >/dev/null 2>&1 || sudo snapper -c root create-config /
sudo snapper -c home list >/dev/null 2>&1 || sudo snapper -c home create-config /home
sudo snapper -c root set-config TIMELINE_CREATE=no NUMBER_CLEANUP=yes NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10 \
    NUMBER_MIN_AGE=0 SPACE_LIMIT=0.2 FREE_LIMIT=0.2
sudo snapper -c home set-config TIMELINE_CREATE=yes TIMELINE_CLEANUP=yes TIMELINE_MIN_AGE=0 \
    TIMELINE_LIMIT_HOURLY=24 TIMELINE_LIMIT_DAILY=7 TIMELINE_LIMIT_WEEKLY=4 TIMELINE_LIMIT_MONTHLY=0 TIMELINE_LIMIT_YEARLY=0 \
    NUMBER_CLEANUP=yes NUMBER_LIMIT=10 ALLOW_USERS="$USER" SYNC_ACL=yes SPACE_LIMIT=0.2 FREE_LIMIT=0.2
# Listing root snapshots without sudo (snapshots keep each file's own permissions, so nothing new becomes readable)
sudo chmod 755 /.snapshots
# home: `levi` may create/list/read his own snapshots (ALLOW_USERS). The root config is deliberately NOT user-writable.

step "Snapshot every dnf transaction (dnf5 actions plugin)"
sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d
sudo tee /etc/dnf/libdnf5-plugins/actions.d/snapper.actions >/dev/null <<'EOF'
# Pre/post btrfs snapshot (snapper config "root") around every dnf transaction. Managed by ~/.config/snapshots/install.sh
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ -c\ root\ create\ -t\ pre\ -c\ number\ -p\ -d\ dnf)"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ -c\ root\ create\ -t\ post\ -c\ number\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ dnf\ ;\ echo\ tmp.snapper_pre_number
EOF
if [ -f /etc/dnf/libdnf5-plugins/actions.conf ]; then
    sudo sed -i 's/^enabled *=.*/enabled = 1/' /etc/dnf/libdnf5-plugins/actions.conf
fi

step "Exclude ~/.cache from home snapshots (make it its own subvolume)"
if [ "$(stat -f -c %T "$HOME/.cache")" = btrfs ] && ! btrfs subvolume show "$HOME/.cache" >/dev/null 2>&1; then
    mv "$HOME/.cache" "$HOME/.cache.old"
    btrfs subvolume create "$HOME/.cache"
    cp -a --reflink=auto "$HOME/.cache.old/." "$HOME/.cache/"
    rm -rf "$HOME/.cache.old"
    echo "  ~/.cache is now a subvolume"
fi

step "Timers"
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

step "First snapshots"
sudo snapper -c root create -c number -d "baseline after snapshot setup"
snapper -c home create -c number -d "baseline after snapshot setup"

echo
echo "${G}${B}✔ Snapshots ready.${N} Next: ~/.config/watcher/install.sh (adds them + disk-health to the watcher). Try: snapshots"
