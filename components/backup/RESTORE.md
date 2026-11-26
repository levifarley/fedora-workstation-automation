# System restore guide (for Claude Code on a fresh Fedora install)

This file lives in Google Drive at `fedora-backup/RESTORE.md` (plain text) and inside every
backup snapshot at `~/.local/share/system-manifest/RESTORE.md`.

**Machine:** ThinkPad, Fedora (see `system-info.txt`), user `levi`, hostname `fedora`.
**Backup:** restic repository at `gdrive:fedora-backup/restic` (Google Drive via rclone),
encrypted with a password that Levi keeps in a password manager. **Ask Levi for it.**
Nightly snapshots: 7 daily, 4 weekly, 12 monthly.

## What's in each snapshot
- `/home/levi`: the full home folder, *minus* caches, trash, Flatpak runtimes, `node_modules`,
  Claude Code binaries, and Zed's downloaded language servers (these are all reinstallable).
- `/var/lib/system-backup/`:
  - `etc.tar.zst`: the whole `/etc` (with SELinux labels/xattrs)
  - `usr-local.tar.zst`: `/usr/local` (includes `/usr/local/bin/system-backup`)
  - `rpm-modified-files.txt`: package files Levi changed from their RPM defaults (**the /etc files that matter**)
  - `system-services-enabled.txt`, `kernel-cmdline.txt`, `disks.txt`, `docker-images.txt`
- `~/.local/share/system-manifest/`: `dnf-userinstalled.txt`, `dnf-repos-enabled.txt`, `dnf-copr.txt`,
  `flatpak-remotes.txt`, `flatpak-apps.txt`, `user-services-enabled.txt`, `dconf-full.ini` (GNOME settings),
  `zed-extensions.txt`, `nvm-node-versions.txt`, `npm-global.txt`, `pip-user.txt`, `crontab.txt`

## Other copies
- **Movies (Samsung SSD):** separate restic repo `rclone:gdrive:fedora-backup/movies` (same password). Restore to a new drive:
  `RESTIC_REPOSITORY=rclone:gdrive:fedora-backup/movies restic restore latest --target /run/media/levi/<new drive>`
  (files restore under their original path inside the target).
- **Configs + scripts in git:** bare repo `~/.dotfiles` (inside the home backup). If Levi pushed it to a private GitHub repo,
  `git clone --bare <url> ~/.dotfiles && git --git-dir=$HOME/.dotfiles --work-tree=$HOME checkout` restores the setup
  without restic. Secrets are NOT in git: the restic password comes from Levi; the ntfy topic and rclone login come from the restic backup or get re-created.

## Fast path: the restore script (rehearsed in a VM)
After steps 1–3 below (tools, Drive login, restic password at `~/.config/backup/restic-password`), restore the script from
the backup and run it. It automates steps 4–13, skips phases that are already done, and never overwrites /etc. Instead it writes
`~/restore-etc-review.txt` for Levi to go through:
```bash
restic restore latest --include /home/levi/.config/backup/system-restore --target / && ~/.config/backup/system-restore
```
`system-restore --list` shows progress. If a phase fails, fix it and re-run. The manual steps below are the reference.

**Rehearsed 2026-11-25 in a VM** (`rehearsal`): all 12 phases completed. 25 tests passed; the only failures were VM-specific (SSH on).
Expect these manual follow-ups (the script lists them in its notes):
- **Claude Code** itself isn't in the backup: `curl -fsSL https://claude.ai/install.sh | bash`. Install the Claude guard
  (`~/.config/claude-guard/install.sh`) **before** using Claude Code for anything else.
- Apps installed by hand from a download (not in any repo), e.g. elementary-screenshot: reinstall if still wanted.
- GNOME settings: `dconf load / < ~/.local/share/system-manifest/dconf-full.ini` from inside the desktop, then log out/in.
- Go through `~/restore-etc-review.txt` (Wi-Fi, custom /etc changes) with Levi.
- NVIDIA: `sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda` (from RPM Fusion), wait for the module to build, then reboot.
- **Phone access (SSH over Tailscale) stays OFF** until `~/.config/remote/install.sh` is run in a real terminal (Tailscale
  browser login). It applies the SSH hardening and the Tailscale-only firewall zone, then enables sshd. `system-restore`
  deliberately doesn't re-enable sshd itself. Do this **before** re-pairing deadman.
- **deadman must be re-paired with the phone** (phase `deadman` installs the agent and prints the steps): a fresh install
  has a new machine-id and a new order channel, so orders from the old `phone.conf` are rejected. `deadman phone-setup` →
  new `phone.conf` on the phone → `deadman arm '<phone's deadman_ed25519.pub>'` → `deadman-order test` → ACCEPTED in
  `deadman log`. Then at home: `deadman trust-here`. With LUKS in place, `wipe` is now a real crypto-erase.
- **Docker is rootless** (phase `docker`). Never add levi to the `docker` group: that's passwordless root. Volumes from
  `~/docker-export` are restored automatically; images come back with `docker compose up -d --build` per project.

## Before wiping (the day of the reinstall)
Claude runs a full systems check and gives the go-ahead first. Then:
1. **Export Docker volumes** (`~/.local/share/docker` is excluded from the backup, so they'd be lost):
   ```bash
   mkdir -p ~/docker-export && for v in $(docker volume ls -q); do
     docker run --rm -v "$v":/v -v ~/docker-export:/out alpine tar -C /v -cf "/out/$v.tar" .; done; ls -lh ~/docker-export
   ```
2. **Fresh backups:** `backup` (runs one now), plus the movies backup if the SSD changed; then `backup status` shows today.
3. **Config history pushed:** `dots save`.
4. **Off the laptop** (password manager / paper): restic password, Google OAuth client ID + secret, GitHub login,
   Wi-Fi password, Tailscale login, alerts Gmail app password. The phone keeps its deadman key; nothing to do there.
5. Phone: `deadman-order test` still works (proves the phone side is fine before re-pairing).

## Restore procedure
Work step by step and confirm with Levi before overwriting anything in `/etc`.
`sudo` needs a real terminal: give Levi the commands to paste.

1. **Tools:** `sudo dnf install -y restic rclone`
2. **Google Drive auth:** use Levi's own OAuth client, not rclone's shared one (that's retired). Get the client ID and
   secret from Google Cloud Console → APIs & Services → Credentials ("Desktop app" client), or from Levi's
   password manager, then run:
   `rclone config create gdrive drive scope=drive client_id <ID> client_secret <SECRET>` (opens a browser login;
   on the "unverified app" warning, click Advanced → continue)
3. **Point restic at the repo:**
   ```bash
   export RESTIC_REPOSITORY=rclone:gdrive:fedora-backup/restic
   export RESTIC_PASSWORD_FILE=~/restic-password   # Levi pastes the password into this file (chmod 600)
   restic snapshots
   ```
4. **Pull the latest snapshot into a staging dir** (don't restore straight over `/home` yet):
   `restic restore latest --target ~/restore-staging`
5. **Repositories first:** look in `dnf-repos-enabled.txt` and `dnf-copr.txt`. Re-enable RPM Fusion
   (free + nonfree), the COPRs (e.g. `che/zed`), Docker CE, negativo17 Spotify, and hardware:razer.
   The repo files are also in `etc.tar.zst` under `etc/yum.repos.d/`.
6. **Packages:** `sudo dnf install $(cat dnf-userinstalled.txt)`. Skip names that no longer exist and report them.
   NVIDIA: see the notes in Claude's memory or `rpm-modified-files.txt`; install akmod-nvidia from RPM Fusion.
7. **Apps (Levi dislikes Flatpak/Snap: prefer RPMs):** Google Chrome (`google-chrome` repo, `google-chrome-stable`),
   GIMP, Transmission
   (`transmission-gtk`), `gnome-extensions-app` and `gnome-browser-connector` are native RPMs and come back via step 6. Postman lives in
   `/opt/Postman` (not in the backup): re-download https://dl.pstmn.io/download/latest/linux_64, extract it to /opt, and chown it to levi.
   `~/.local/share/applications/postman.desktop` is restored with home. The **only** Flatpak is MakeMKV (user install, used by
   ripdvd/ripit): `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo &&
   flatpak install --user -y flathub com.makemkv.MakeMKV`. Don't add system Flatpak remotes.
8. **Home folder:** `rsync -aHAX ~/restore-staging/home/levi/ ~/`. Back up anything that's already in the
   fresh home first. Then `dconf load / < ~/.local/share/system-manifest/dconf-full.ini` and log out/in.
9. **/etc:** extract `etc.tar.zst` to a temp dir. For each file in `rpm-modified-files.txt`, plus custom
   additions (`/etc/systemd/system/*`, `/etc/polkit-1/rules.d/*`, `/etc/NetworkManager/system-connections/*`,
   `/etc/yum.repos.d/*`), **diff against the fresh file and show Levi before copying.** Don't blindly
   restore `fstab`, `crypttab`, `default/grub`, or `machine-id`, because disk UUIDs will differ.
   Afterwards, run `sudo restorecon -Rv /etc`.
9a. **Claude guard (install BEFORE using Claude Code for the rest of the restore, if Levi agrees):**
    `~/.config/claude-guard/install.sh` puts the root-owned audit/guard hook in /etc/claude-code. Claude must not skip or weaken it.
9b. **Firewall:** Levi uses a tight custom zone, not Fedora's default: run `bash ~/.config/watcher/firewall-laptop-zone.sh`
    (it allows only DHCPv6, mDNS, samba-client and Spotify 57621 inbound).
10. **Services:** re-enable the units from `system-services-enabled.txt` / `user-services-enabled.txt` that
    aren't Fedora defaults.
11. **Dev tooling:** install the nvm Node versions listed, then `npm i -g` the packages from `npm-global.txt`,
    and pull the `docker-images.txt` images if needed.
12. **Zed (the main editor; Levi does not use VS Code, so don't install it):**
    `sudo dnf copr enable che/zed && sudo dnf install zed`. Settings, keymap and themes come back with the
    home restore (`~/.config/zed/`), along with installed extensions, workspace history, agent threads and prompts
    (`~/.local/share/zed/`). Zed re-downloads its language servers on first launch.
13. **Re-arm backups:** extract `usr-local.tar.zst` (for `/usr/local/bin/system-backup`), then run
    `~/.config/backup/install.sh` and then `~/.config/update/install.sh` in a real terminal (the second
    schedules the midnight backup → update chain and installs `/usr/local/bin/system-update`), then
    `~/.config/snapshots/install.sh` (btrfs snapshots), then `~/.config/watcher/install.sh` (failure notifications,
    disk-health, `watcher run` permissions). Then run `watcher test --full`; everything should pass. Check everything with `watcher check`. Afterwards, run `backup status` to confirm the old repo is visible.
