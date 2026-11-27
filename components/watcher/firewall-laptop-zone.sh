#!/bin/bash
# firewall-laptop-zone — replace Fedora's wide-open default zone (all ports 1025-65535 open to the LAN) with a tight one.
# Allows in: DHCPv6, mDNS (printers/Spotify discovery), samba-client (browse shares), Spotify Connect (57621).
# Outgoing traffic and Docker (its own "docker" zone) are unaffected.
#   bash ~/.config/watcher/firewall-laptop-zone.sh            apply
#   bash ~/.config/watcher/firewall-laptop-zone.sh --undo     go back to FedoraWorkstation
set -euo pipefail
if [ "${1:-}" = --undo ]; then
    sudo firewall-cmd --set-default-zone=FedoraWorkstation
    echo "✔ back to FedoraWorkstation. Re-record the baseline: watcher test baseline"; exit 0
fi
if ! sudo firewall-cmd --permanent --get-zones | tr ' ' '\n' | grep -qx laptop; then
    sudo firewall-cmd --permanent --new-zone=laptop
fi
sudo firewall-cmd --permanent --zone=laptop --set-description="Laptop: only DHCPv6, mDNS, samba-client, Spotify Connect inbound"
for s in dhcpv6-client mdns samba-client; do sudo firewall-cmd --permanent --zone=laptop --add-service=$s >/dev/null; done
for p in 57621/tcp 57621/udp; do sudo firewall-cmd --permanent --zone=laptop --add-port=$p >/dev/null; done
sudo firewall-cmd --reload
sudo firewall-cmd --set-default-zone=laptop
echo; sudo firewall-cmd --get-active-zones; echo; sudo firewall-cmd --zone=laptop --list-all
echo
echo "✔ Wi-Fi is now in the 'laptop' zone. Undo anytime: bash $0 --undo"
"$HOME/.local/bin/watcher" test baseline
