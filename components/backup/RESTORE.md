# System restore guide (for Levi, and for Claude Code on a fresh Fedora install)

This file lives in Google Drive at `fedora-backup/RESTORE.md` (plain text, next to `bootstrap.sh`) and inside every
backup snapshot at `~/.local/share/system-manifest/RESTORE.md`. History and lessons: `CHANGELOG.md` (same folder).

**Machine:** ThinkPad P1, Fedora 45, user `levi`, hostname `fedora`, disk encrypted (LUKS).
**Backup:** restic repository `gdrive:fedora-backup/restic` (`/movies` is the movie repo) in the **system** Google
account (not the personal one). Encrypted with a password Levi keeps in a password manager. **Ask Levi for it.**
Credentials live **only** in `/etc/backup` (root 700); every restic job runs as root. Snapshots: 7 daily, 4 weekly, 12 monthly.
**Baseline:** a full restore took 59.5 min on 2026-11-27 (46 min of it the 12 GB download, before the rate limit was raised).

## What's in each snapshot
- `/home/levi`, minus caches, trash, Flatpak runtimes, `node_modules`, Claude Code binaries, Zed's downloads and
  `~/.local/share/docker` (export Docker volumes to `~/docker-export` before a wipe).
- `/var/lib/system-backup/`: `etc.tar.zst` (all of `/etc`), `usr-local.tar.zst`, `tailscale.tar.zst` (the Tailscale node),
  `rpm-modified-files.txt`, `system-services-enabled.txt`, `kernel-cmdline.txt`, `disks.txt`, `docker-images.txt`.
- `~/.local/share/system-manifest/`: package, repo, COPR, Flatpak, service, GNOME (`dconf-full.ini`), Zed, node, npm, pip lists.

## 1. Bootstrap: fresh install → Claude Code (Levi does this; Claude doesn't exist yet)
In a terminal **inside GNOME**:
```bash
curl -fsSLO https://raw.githubusercontent.com/levifarley/fedora-workstation-automation/main/components/backup/bootstrap.sh
bash bootstrap.sh
```
It asks for the OAuth client ID + secret, the **system** account login (a link; a throwaway Firefox profile is the
default, deleted afterwards), and the backup password. It checks each one, restores the guard + backup tools,
installs the guard **first**, then Claude Code. If it stops, fix what it says and run it again: it resumes.
Then: open a new terminal, `cd ~ && claude`, and say *Read ~/.config/backup/RESTORE.md, then help me run system-restore.*

<details><summary>Manual fallback (only if bootstrap.sh can't be downloaded or fails)</summary>

Type the values when asked; nothing to replace in the commands.
```bash
sudo dnf install -y restic rclone jq && sudo install -d -m 700 /etc/backup /var/cache/restic
read -rp 'client ID: ' CID; read -rsp 'client secret: ' CSEC; echo
rclone authorize drive "$CID" "$CSEC" --auth-no-open-browser     # open the printed link, sign in as the SYSTEM account
read -rp 'paste the {"access_token"...} line it printed: ' TOK
sudo rclone --config /etc/backup/rclone.conf config create gdrive drive scope=drive client_id "$CID" client_secret "$CSEC" token "$TOK"
unset CSEC TOK; sudo rclone --config /etc/backup/rclone.conf lsd gdrive:fedora-backup          # lists: restic, movies
read -rsp 'backup password: ' P; echo; printf '%s' "$P" | sudo sh -c 'umask 077; cat > /etc/backup/restic-password'; unset P
R() { sudo env RCLONE_CONFIG=/etc/backup/rclone.conf RESTIC_PASSWORD_FILE=/etc/backup/restic-password \
      RESTIC_REPOSITORY=rclone:gdrive:fedora-backup/restic RESTIC_CACHE_DIR=/var/cache/restic restic "$@"; }
R snapshots --latest 1
R restore latest --target / --include /home/levi/.config/claude-guard --include /home/levi/.config/backup --include /home/levi/.local/bin
bash ~/.config/claude-guard/install.sh && curl -fsSL https://claude.ai/install.sh | bash
```
Afterwards sign the system account out of that browser. "repository does not exist" = wrong path (missing `/restic`)
or wrong Google account (the backups are in the **system** account).
</details>

## 2. The restore script
Levi runs it in a terminal **inside GNOME** (sudo prompts; `dconf` needs the desktop): `~/.config/backup/system-restore`.
`--list` shows progress; a failed phase can be fixed and re-run (finished phases are skipped). It never overwrites
`/etc` blindly: it writes `~/restore-etc-review.txt`. **Don't reboot until the `nvidia` phase has passed.**

What needs Levi during or after it:
1. **Phase `identity` asks yes/no.** It shows the deadman phone key's fingerprint: it must match
   `ssh-keygen -lf ~/.ssh/deadman_ed25519.pub` on the phone (`SHA256:cfPX7r/7…`). Type `yes`. This brings back the
   machine-id, SSH host keys, Tailscale node, deadman pairing and hostname, so **the phone needs no changes.**
2. **Phone access:** `~/.config/remote/install.sh` (SSH hardening, Tailscale-only firewall, then sshd on). With the node
   restored it needs no login. **It must print `name: system`.** Anything else: see "If the identity didn't come back".
3. **Prove deadman** from the phone: `~/bin/deadman-order test` → email "test OK", `deadman log` shows ACCEPTED.
   Expect one **"REJECTED: stale order" email per order still on the channel** (5 after the stolen-laptop test). That's
   the replay protection working. Until the first reboot, journal tools need `--merge` (`deadman log` does it).
4. **Reboot**, then `nvidia-smi` and `watcher check`.
5. Go through `~/restore-etc-review.txt`, then `sudo rm -rf /var/tmp/restore-staging` (a user-readable copy of the old
   `/etc`: password hashes, host keys, Wi-Fi passwords). The watcher test fails if it's still there after 3 days.
6. Docker projects: `cd ~/Projects/<project> && docker compose up -d --build`, then `rm -rf ~/docker-export`.
   Docker is rootless; never add levi to the `docker` group (that's passwordless root).
7. Hand-installed apps aren't in any repo: Postman (`/opt/Postman`, from https://dl.pstmn.io/download/latest/linux_64,
   chown to levi), elementary-screenshot.
8. `backup` then `backup verify`, then `watcher test --full`.

### If the identity didn't come back
(backup older than 2026-11-27, or `identity` answered no)
1. login.tailscale.com/admin/machines: remove the old `system`, rename the new `system-1` → `system`.
2. Phone: `~/.ssh/config` pins the IP (`HostName 100.x.y.z` under `Host system`): `sed -i 's/<old ip>/<new ip>/g' ~/.ssh/config`,
   then `ssh system hostname` (yes to the new host key; on "HOST IDENTIFICATION HAS CHANGED": `ssh-keygen -R <ip>` first).
   `ssh system true` prints nothing when it works.
3. Laptop: `deadman phone-setup`. Phone: `scp system:.deadman-phone.conf ~/.config/deadman/phone.conf && scp system:.config/deadman/phone/deadman-order ~/bin/`
4. Phone: `cat ~/.ssh/deadman_ed25519.pub` (the existing key). Laptop: `deadman arm '<that line>'`.
5. Phone: `~/bin/deadman-order test` → ACCEPTED; at home: `~/bin/deadman-order trust` (phone-only by design).

## 3. Before wiping
Claude runs a full systems check and gives the go-ahead first. Then:
1. **Export Docker volumes:**
   `mkdir -p ~/docker-export && for v in $(docker volume ls -q); do docker run --rm -v "$v":/v -v ~/docker-export:/out alpine tar -C /v -cf "/out/$v.tar" .; done`
2. **Final backup:** `backup`, then `backup verify` (all ✔). Movies too if the SSD changed (`movies-backup`).
3. `dots save`, and push the showcase repo (that's where `bootstrap.sh` is downloaded from).
4. **Off the laptop** (password manager / paper): backup password, OAuth client ID + **current** secret, the **system**
   account's password (2-step on the phone), GitHub, Wi-Fi, Tailscale logins, **the new LUKS passphrase**.
5. **The OAuth app is "In production"** (Google Cloud Console → OAuth consent screen). In "Testing", Google expires the
   login after 7 days and the nightly backup silently loses Drive.
6. Phone: `deadman-order test` works, and `deadman` shows **✔ network home**.
7. The backup carries the identity: in the rehearsal VM, `system-restore --rehearsal --phase stage`, then
   `system-restore --phase identity --dry-run` → **5/5**, this laptop's machine-id, 1 trusted router.
   (The VM needs current credentials first: `rehearsal secrets`.)

### The stolen-laptop test
Only the phone acts after step 1. Every step must produce its email; if one doesn't, **stop** and fix that first.
1. Checklist above done. Lock the screen, leave the laptop awake.
2. Connect it to the phone's hotspot → **"LAPTOP ONLINE AWAY FROM HOME"** within ~2 min.
3. `~/bin/deadman-order lost` → "LOST MODE on", then a location email every 10 min.
4. `~/bin/deadman-order lock` → "locked"; the password is refused at the login screen.
5. `~/bin/deadman-order unlock` → "unlocked" (proves it's reversible); then `lock` again.
6. `~/bin/deadman-order wipe` → type the phrase, then the deadman key passphrase → **"deadman: WIPE executing"**, power off.
7. Power on. Either the LUKS prompt **rejects your passphrase**, or (as on 2026-11-27) the boot stops earlier at
   **"root account is locked"** (emergency mode, no prompt at all). **Both mean the wipe worked:** the keyslots are gone.
8. Boot the USB installer: encrypt the disk, user `levi`, hostname `fedora`. Then section 1.
(`scrub` isn't part of the test: it logs Tailscale out, which would spoil the identity restore; wipe covers it anyway.)

## 4. Manual reference (what system-restore automates)
Confirm with Levi before overwriting anything in `/etc`. `sudo` needs a real terminal: give Levi the commands.
1. Stage: `R restore latest --target /var/tmp/restore-staging` (R from the manual fallback above).
2. Repos first (`dnf-repos-enabled.txt`, `dnf-copr.txt`): RPM Fusion free + nonfree, COPRs (`che/zed`), Docker CE,
   negativo17 Spotify, hardware:razer. Repo files are in `etc.tar.zst` under `etc/yum.repos.d/`.
3. Packages: `sudo dnf install $(cat dnf-userinstalled.txt)` (report names that no longer exist). NVIDIA: akmod-nvidia
   from RPM Fusion, then `sudo akmods --force --kernels <k>` for every kernel (needs `kernel-devel-<k>`).
4. Apps: Levi prefers RPMs over Flatpak. The only Flatpak is MakeMKV (user install):
   `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak install --user -y flathub com.makemkv.MakeMKV`
5. Home: `rsync -aHAX /var/tmp/restore-staging/home/levi/ ~/`, then `system-restore --phase dconf` from GNOME, log out/in.
6. `/etc`: for each file in `rpm-modified-files.txt` + custom units/polkit rules/NM connections/repos, **diff and show
   Levi before copying.** Never copy `fstab`, `crypttab`, `default/grub`, `hostname`. Then `sudo restorecon -Rv /etc`.
7. Installers, in order: `backup`, `update`, `snapshots`, `watcher`, `claude-guard` (`~/.config/<x>/install.sh`), the
   firewall zone (`bash ~/.config/watcher/firewall-laptop-zone.sh`), then `deadman/install.sh`, `remote/install.sh`.
8. Zed (the editor; no VS Code): `sudo dnf copr enable che/zed && sudo dnf install zed`; settings come back with home.
9. Check: `backup status`, `watcher test --full`, `watcher check`.
