#!/bin/bash
# One-time migration: system Flatpaks → native RPMs (2026-11-24).
# Keeps: MakeMKV (user Flatpak, used by ripdvd/ripit). Re-runnable: finished steps are skipped.
# Run in a real terminal:  ~/.config/update/flatpak-to-rpm.sh
set -euo pipefail
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
step() { echo; echo "${B}▶ $*${N}"; }
has_fp() { flatpak info --system "$1" >/dev/null 2>&1; }
# copy Flatpak app data to the native location, only if the native one doesn't exist yet
migrate() {  # $1 = flatpak data dir, $2 = native dir
    if [ -d "$1" ] && [ ! -e "$2" ]; then
        mkdir -p "$(dirname "$2")"; cp -a "$1" "$2"; echo "  copied settings → $2"
    fi
}

if pgrep -f 'com.google.Chrome|/app/extra/chrome' >/dev/null; then
    echo "${R}Close Google Chrome first (its profile is being moved), then re-run.${N}"; exit 1
fi

sudo -v

step "1/7 Remove Déjà Dup"
if has_fp org.gnome.DejaDup; then sudo flatpak uninstall --system -y --delete-data org.gnome.DejaDup; fi
rm -rf ~/.var/app/org.gnome.DejaDup

step "2/7 Google Chrome (Google's RPM repo)"
sudo dnf config-manager setopt google-chrome.enabled=1
sudo dnf install -y google-chrome-stable
migrate ~/.var/app/com.google.Chrome/config/google-chrome ~/.config/google-chrome
rm -rf ~/.config/google-chrome/Singleton* 2>/dev/null || true
if has_fp com.google.Chrome; then sudo flatpak uninstall --system -y --delete-data com.google.Chrome; fi

# (Proton VPN step removed 2026-11-24: Levi uninstalled Proton VPN)

step "4/7 GIMP + Transmission (Fedora RPMs)"
sudo dnf install -y gimp transmission-gtk
migrate ~/.var/app/org.gimp.GIMP/config/GIMP ~/.config/GIMP
migrate ~/.var/app/com.transmissionbt.Transmission/config/transmission ~/.config/transmission
for a in org.gimp.GIMP com.transmissionbt.Transmission; do
    if has_fp $a; then sudo flatpak uninstall --system -y --delete-data $a; fi
done

step "5/7 Extension Manager → GNOME Extensions app + browser connector"
sudo dnf install -y gnome-extensions-app gnome-browser-connector
if has_fp com.mattjakeman.ExtensionManager; then sudo flatpak uninstall --system -y --delete-data com.mattjakeman.ExtensionManager; fi
echo "  (install new extensions from https://extensions.gnome.org in Chrome; manage them in 'Extensions')"

step "6/7 Postman (official tarball → /opt/Postman, self-updating)"
if [ ! -x /opt/Postman/Postman ]; then
    tmp=$(mktemp -d)
    curl -fL --progress-bar -o "$tmp/postman.tar.gz" https://dl.pstmn.io/download/latest/linux_64
    sudo tar -xzf "$tmp/postman.tar.gz" -C /opt
    rm -rf "$tmp"
fi
sudo chown -R "$USER:$USER" /opt/Postman          # lets Postman's in-app updater work
sudo ln -sf /opt/Postman/Postman /usr/local/bin/postman
icon=$(find /opt/Postman -name 'icon_128x128.png' | head -1)
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/postman.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Postman
Comment=API development environment
Exec=/opt/Postman/Postman %U
Icon=${icon:-postman}
Terminal=false
Categories=Development;
StartupWMClass=Postman
EOF
migrate ~/.var/app/com.getpostman.Postman/config/Postman ~/.config/Postman
if has_fp com.getpostman.Postman; then sudo flatpak uninstall --system -y --delete-data com.getpostman.Postman; fi

step "7/7 Clean up system Flatpak (MakeMKV user Flatpak stays)"
sudo flatpak uninstall --system --unused -y || true
if [ -z "$(flatpak list --system --app --columns=application)" ]; then
    for r in fedora flathub; do sudo flatpak remote-delete --system --force "$r" 2>/dev/null || true; done
    echo "  removed system Flatpak remotes (fedora, flathub)"
fi
# GNOME Software: prefer RPMs over Flatpaks when both exist
gsettings set org.gnome.software packaging-format-preference "['rpm', 'flatpak']" 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo
echo "${G}${B}✔ Done.${N} Remaining Flatpaks:"
flatpak list --app --columns=name,installation
echo "Space now used by Flatpak: $(sudo du -sh /var/lib/flatpak 2>/dev/null | cut -f1) system, $(du -sh ~/.local/share/flatpak | cut -f1) user"
