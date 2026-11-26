#!/bin/bash
# Install/refresh the deadman agent (remote lock/locate/scrub/wipe ordered only by your phone). Real terminal:
#   ~/.config/deadman/install.sh
# Then: deadman phone-setup  (shows the phone steps + your private channel), then: deadman arm '<phone deadman public key>'
set -euo pipefail
S="$HOME/.config/deadman/system"
python3 -I "$S/deadman-agent" --selftest          # refuse to install an agent whose verification logic fails
sudo install -m 755 -o root -g root "$S/deadman-agent" /usr/local/bin/deadman-agent
sudo install -m 644 -o root -g root "$S/deadman-agent.service" "$S/deadman-agent.timer" /etc/systemd/system/
sudo install -d -m 700 -o root -g root /etc/deadman
sudo install -d -m 755 -o root -g root /var/lib/deadman
# private order channel (random); signatures are what make orders valid, the secrecy just keeps the channel quiet
sudo test -s /etc/deadman/topic || openssl rand -hex 16 | sed 's/^/dm-/' | sudo tee /etc/deadman/topic >/dev/null
sudo chmod 600 /etc/deadman/topic
sudo touch /etc/deadman/allowed_signers && sudo chmod 600 /etc/deadman/allowed_signers
sudo restorecon -R /usr/local/bin/deadman-agent /etc/deadman /var/lib/deadman /etc/systemd/system/deadman-agent.* 2>/dev/null || true
sudo systemctl daemon-reload
sudo systemctl enable --now deadman-agent.timer
echo "✔ deadman agent installed and polling every 2 min. Next: deadman phone-setup"
