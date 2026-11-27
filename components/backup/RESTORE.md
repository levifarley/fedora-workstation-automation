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

## Bootstrap: fresh install → Claude Code (do this yourself, before Claude exists on the machine)
Copy-paste in order, in a real terminal. Exact paths matter: the Drive folder is `fedora-backup` (**singular**)
and the repo is the `restic` **subfolder** inside it (`fedora-backup/movies` is the movies repo).
```bash
# 1. tools + root-only credentials folder (the backups only ever read credentials from here)
sudo dnf install -y restic rclone
sudo install -d -m 700 -o root -g root /etc/backup /var/cache/restic
# 2. Drive login: made in a temp file, moved into /etc/backup, temp shredded (browser login; client ID/secret: step 2 below)
#    Sign in as the SYSTEM Google account (the backups live there since the 2026-11-27 migration), in a PRIVATE
#    window, then close every private window: that account must never stay signed in to a browser on this laptop.
t=$(mktemp); RCLONE_CONFIG=$t rclone config create gdrive drive scope=drive client_id <ID> client_secret <SECRET> --auth-no-open-browser
#    (it prints a link: open it in the private window)
sudo install -m 600 -o root -g root $t /etc/backup/rclone.conf && shred -u $t
# 3. backup password: paste it, Enter, Ctrl-D (typed straight into the root-only file)
sudo sh -c 'umask 077; cat > /etc/backup/restic-password'
# 4. check + restore just the guard and the backup tools (as root, with the root-only credentials)
R() { sudo env RCLONE_CONFIG=/etc/backup/rclone.conf RESTIC_PASSWORD_FILE=/etc/backup/restic-password \
      RESTIC_REPOSITORY=rclone:gdrive:fedora-backup/restic RESTIC_CACHE_DIR=/var/cache/restic restic "$@"; }
sudo env RCLONE_CONFIG=/etc/backup/rclone.conf rclone lsd gdrive:fedora-backup   # should list: restic, movies
R snapshots                                     # newest = the "Before wiping" backup from the same day
R restore latest --target / --include /home/levi/.config/claude-guard --include /home/levi/.config/backup --include /home/levi/.local/bin
bash ~/.config/claude-guard/install.sh          # guard FIRST, before Claude Code ever runs
curl -fsSL https://claude.ai/install.sh | bash  # then open a new terminal
cd ~ && claude
```
Then tell Claude: *Read ~/.config/backup/RESTORE.md, then help me run system-restore.*
"repository does not exist / config file does not exist" means the path is wrong (usually a missing `/restic`).

## Fast path: the restore script
After the bootstrap, run the script yourself in a real terminal (it asks for sudo many times; Claude can't type it):
`~/.config/backup/system-restore`. It automates steps 4–13, skips phases that are already done, and never overwrites
/etc. Instead it writes `~/restore-etc-review.txt` for Levi to go through.
`system-restore --list` shows progress. If a phase fails, fix it and re-run. The manual steps below are the reference.
**Run it from a terminal inside GNOME** (not over SSH), so the `dconf` phase can load the GNOME settings.
**Don't reboot until the `nvidia` phase has passed**, or the first boot has no graphics driver.

**Real run 2026-11-27** (the encrypted reinstall): fixed afterwards, so next time these are automatic:
- `dconf load` refuses the whole file if any key is locked by the system (authselect locks 3 `login-screen` keys).
  The script now drops locked keys first. Before, it printed "non-writable keys", loaded **nothing**, and still said ✔.
- akmod-nvidia was installed, but no module got built (akmods only runs at boot). Now phase `nvidia` builds it for every kernel.
- dnf upgraded `libzstd` without the `zstd` binary, so `tar --zstd` broke ("incorrect library version") and `usrlocal`
  failed silently. The script now upgrades the pair and fails the phase on error.
- `kmod-nvidia-<kernel>` packages were listed as "installed by hand". They're built locally and are now left out of the manifest.
- `systemd-vconsole-setup.service` failed on first boot ("Failed to check /dev/tty1 has font support"). That's a harmless
  boot-time race with the GPU framebuffer: `sudo systemctl restart systemd-vconsole-setup` clears it for `watcher check`.

**Rehearsed 2026-11-25 in a VM** (`rehearsal`), then used for real 2026-11-27 (now 16 phases). 25 tests passed; the only failures were VM-specific (SSH on).
Expect these manual follow-ups (the script lists them in its notes):
- **Claude Code** itself isn't in the backup: `curl -fsSL https://claude.ai/install.sh | bash`. Install the Claude guard
  (`~/.config/claude-guard/install.sh`) **before** using Claude Code for anything else.
- Apps installed by hand from a download (not in any repo), e.g. elementary-screenshot: reinstall if still wanted.
- GNOME settings: loaded by phase `dconf` when run inside the desktop. Otherwise run `system-restore --phase dconf` from GNOME
  (not a raw `dconf load` of the manifest: that fails on system-locked keys), then log out/in.
- Go through `~/restore-etc-review.txt` (Wi-Fi, custom /etc changes) with Levi.
- NVIDIA: the packages come back in phase `packages`, and phase `nvidia` builds the module (`sudo akmods --force --kernels <k>`)
  for every installed kernel (installing a missing `kernel-devel-<k>` itself; the installer's own kernel ships without one).
  Only the newest kernel, which is the default boot, must succeed. Reboot only after it passes, then check `nvidia-smi`.
- **The laptop keeps its identity** (phase `identity`, real runs only, never in a rehearsal): machine-id, SSH host keys,
  the Tailscale node (`/var/lib/tailscale`, backed up since 2026-11-27) and the deadman pairing (`/etc/deadman`: phone key,
  order channel, trusted home router, nonce history), plus the hostname deadman orders are signed for. It shows the
  phone key's fingerprint and asks **yes** before trusting it again. Check it against `ssh-keygen -lf ~/.ssh/deadman_ed25519.pub`
  on the phone. **Result: the phone needs no changes at all.** Same `ssh system`, no host-key warning, `deadman-order` just works.
- **Phone access (SSH over Tailscale) stays OFF** until `~/.config/remote/install.sh` is run in a real terminal. With the
  node restored it needs no Tailscale login. It applies the SSH hardening and the Tailscale-only firewall zone, then enables
  sshd. **It must print `name: system`.** Anything else (e.g. `system-1`) means a new device was created; it then prints the fix.
- **Prove deadman:** on the phone `~/bin/deadman-order test` → `deadman log` shows ACCEPTED. One "REJECTED: stale order"
  email right after a restore is normal (the order channel still holds the last order, e.g. the wipe; it's >15 min old).
- **If the identity couldn't be restored** (backup older than 2026-11-27, or you answered no), it's the long way, learned the
  hard way on 2026-11-27:
  1. login.tailscale.com/admin/machines: **remove the old `system`**, rename the new `system-1` → `system`.
  2. Phone: the ssh config pins the IP (`HostName 100.x.y.z` under `Host system`). Put the new IP there:
     `sed -i 's/<old ip>/<new ip>/g' ~/.ssh/config`, then `ssh system hostname` (answer yes to the new host key; if it
     says "HOST IDENTIFICATION HAS CHANGED", `ssh-keygen -R <new ip>` first). `ssh system true` prints nothing when it works.
  3. Laptop: `deadman phone-setup`. Phone: `scp system:.deadman-phone.conf ~/.config/deadman/phone.conf && scp system:.config/deadman/phone/deadman-order ~/bin/`
  4. Phone: `cat ~/.ssh/deadman_ed25519.pub` (the existing key; don't make a new one). Laptop: `deadman arm '<that line>'`.
  5. Phone: `~/bin/deadman-order test` → ACCEPTED. Then, with the laptop at home, phone: `~/bin/deadman-order trust`
     (trusting home is phone-only, so nobody at the keyboard can silence the away alerts).
- **Delete the restore staging** once `~/restore-etc-review.txt` is done: `sudo rm -rf /var/tmp/restore-staging`. It's a
  user-readable copy of the old /etc (password hashes, host keys, Wi-Fi passwords, deadman channel).
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
   Wi-Fi password, Tailscale login, alerts Gmail app password, **the new LUKS passphrase you'll type in the installer**.
   The phone keeps its deadman key; nothing to do there.
5. Phone: `deadman-order test` still works (proves the phone side is fine before wiping), and `deadman` shows
   **✔ network home** (trusted from the phone with `deadman-order trust`: router + public IP).
6. **The backup must contain the identity:** `backup ls latest /var/lib/system-backup`
   lists `etc.tar.zst` and `tailscale.tar.zst`.
7. **The backups are root-only:** `watcher test backup` passes `credentials-root-only`, and `backup verify` passes
   (a real restore from Drive, by root).
8. **The identity restore works on this backup:** in the rehearsal VM, `system-restore --phase stage` then
   `system-restore --phase identity --dry-run` reports **5/5**, with this laptop's machine-id and the trusted router.

### The stolen-laptop test (the whole remote chain, then the wipe)
Play it exactly like a theft, no shortcuts: only the phone acts, nothing is typed on the laptop after step 1.
Every step must produce its email. If one doesn't, **stop**: that's the bug to fix before trusting it in an emergency.
1. Do **all** of the checklist above first (after the wipe, nothing on this disk can be recovered). Then lock the screen
   and leave the laptop awake, like a stolen laptop that's still running.
2. **"Stolen":** move the laptop off home: connect it to the phone's hotspot. Within ~2 min: email **"LAPTOP ONLINE
   AWAY FROM HOME"** (where it is, who's logged in, the phone orders). This proves the alert fires off-home.
3. Phone: `~/bin/deadman-order lost` → email "LOST MODE on", then a location email every 10 min.
4. Phone: `~/bin/deadman-order lock` → email "locked". Check the laptop: desktop session ended, and your password
   is refused at the login screen (that's the point).
5. Phone: `~/bin/deadman-order unlock` → email "unlocked"; your password works again. (Proves lock is reversible.)
   Lock again from the phone before the next step, like you would in a real theft.
6. Phone: `~/bin/deadman-order wipe` → type the confirmation phrase it shows → passphrase for the deadman key.
   Within ~2 min: email **"deadman: WIPE executing"** (it names the LUKS device), then the laptop powers off by itself.
7. Power on: the LUKS prompt appears, but **your passphrase is rejected** ("No key available with this passphrase").
   That's the proof: the keyslots are destroyed and the data is gone. Nothing to fix; boot the USB installer.
8. Reinstall from the USB (encrypt the disk, user `levi`, hostname `fedora`), then Bootstrap → Fast path below.
   After the restore, from the phone at home: `~/bin/deadman-order test`, then `~/bin/deadman-order trust`.
(`scrub` isn't part of the test: wipe already destroys everything, and scrub is the fallback for an unencrypted disk.)

## Restore procedure
Work step by step and confirm with Levi before overwriting anything in `/etc`.
`sudo` needs a real terminal: give Levi the commands to paste.

1. **Tools:** `sudo dnf install -y restic rclone`
2. **Google Drive auth:** use Levi's own OAuth client, not rclone's shared one (that's retired). Get the client ID and
   secret from Google Cloud Console → APIs & Services → Credentials ("Desktop app" client), or from Levi's
   password manager, then run:
   `rclone config create gdrive drive scope=drive client_id <ID> client_secret <SECRET>` (opens a browser login;
   on the "unverified app" warning, click Advanced → continue). Do it into a temp file and move it into
   `/etc/backup/rclone.conf` exactly as in **Bootstrap**. The credentials live **only** in `/etc/backup` (root 700).
3. **Point restic at the repo:** use the `R` wrapper from Bootstrap (root + `/etc/backup`), then `R snapshots`.
   Never put the password or the Drive login in `~`: anything running as levi, Claude included, could read it there.
4. **Pull the latest snapshot into a staging dir** (don't restore straight over `/home` yet):
   `R restore latest --target /var/tmp/restore-staging`
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
   fresh home first. Then load GNOME settings with `system-restore --phase dconf` (it skips system-locked keys) and log out/in.
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
