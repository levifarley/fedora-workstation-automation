#!/bin/bash
# Set up phone access: Tailscale + key-only SSH reachable ONLY over Tailscale + mosh. Run in a real terminal:
#   ~/.config/remote/install.sh
# Undo: sudo systemctl disable --now sshd; sudo tailscale down
set -euo pipefail
R="$HOME/.config/remote"
B=$'\e[1m'; G=$'\e[32m'; N=$'\e[0m'
step() { echo; echo "${B}▶ $*${N}"; }

step "Packages (Tailscale, mosh, tmux — all from Fedora's repos)"
sudo dnf install -y tailscale mosh tmux

step "SSH: keys only, levi only, no forwarding"
sudo install -m 644 -o root -g root "$R/system/10-remote-access.conf" /etc/ssh/sshd_config.d/10-remote-access.conf
sudo ssh-keygen -A >/dev/null   # this laptop's SSH host keys (first-time only; normally made on sshd's first start)
sudo sshd -t   # refuse to continue on a bad config
install -d -m 700 "$HOME/.ssh"
grep -qF "$(awk '{print $NF}' "$R/phone-key.pub")" "$HOME/.ssh/authorized_keys" 2>/dev/null || cat "$R/phone-key.pub" >>"$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"; restorecon -R "$HOME/.ssh" 2>/dev/null || true

step "Firewall: SSH + mosh allowed on the Tailscale interface only (Wi-Fi zone stays closed)"
if ! sudo firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -qx tailnet; then
    sudo firewall-cmd --permanent --new-zone=tailnet
fi
sudo firewall-cmd --permanent --zone=tailnet --set-description="Tailscale only: SSH + mosh from Levi's devices"
sudo firewall-cmd --permanent --zone=tailnet --add-interface=tailscale0 >/dev/null
sudo firewall-cmd --permanent --zone=tailnet --add-service=ssh >/dev/null
sudo firewall-cmd --permanent --zone=tailnet --add-service=mosh >/dev/null
sudo firewall-cmd --permanent --zone=laptop --remove-service=ssh >/dev/null 2>&1 || true
sudo firewall-cmd --reload

step "Tailscale"
sudo systemctl enable --now tailscaled
if ! tailscale status >/dev/null 2>&1; then
    echo "A login link follows — open it and sign in with the same account as on your phone."
    sudo tailscale up --hostname=system --ssh=false
fi
sudo systemctl enable --now sshd
# readable snapshot of what sshd ACTUALLY enforces (its config dir is root-only), for `remote` and the security tests
sudo install -d -m 755 /var/lib/remote-access
sudo sshd -T 2>/dev/null | sudo tee /var/lib/remote-access/sshd-effective >/dev/null

echo
echo "${G}${B}✔ Remote access ready.${N} This laptop on your tailnet: $(tailscale ip -4 2>/dev/null | head -1)  (name: system)"
echo "On the phone (Terminal app): see  remote phone-setup"
"$HOME/.local/bin/watcher" test baseline >/dev/null 2>&1 || true
