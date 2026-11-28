# Backup / restore changelog

History and lessons moved out of RESTORE.md so the guide is only steps. Full story of 2026-11-27:
`~/Desktop/2026-11-27-backup-restore-postmortem.md`.

## 2026-11-27 (post-mortem fixes, after reinstall #2)
- **`bootstrap.sh`** replaces the Bootstrap copy-paste block: prompts one value at a time (secrets hidden), checks the
  client ID/secret format (rejects `<ID>`/`<SECRET>` placeholders), logs in with `rclone authorize` (prints the link;
  never opens the wrong browser), offers a throwaway Firefox profile that is deleted afterwards, checks the account is
  the one that holds `fedora-backup/restic`, verifies the backup password opens the repo, resumes where it stopped.
  Copies: public showcase repo (`components/backup/bootstrap.sh`) and Drive `fedora-backup/bootstrap.sh` (uploaded nightly).
- `system-restore`: the stage download uses twice the nightly rate limit (`RCLONE_TPSLIMIT` 16, 8 connections).
  Baseline at the old limit: 46 min download, 59.5 min total.
- `deadman log` uses `journalctl --merge` (after phase identity restores the old machine-id, new journal entries land
  in a differently named folder until reboot, and the log looked empty).
- RESTORE.md: after a deadman wipe the boot can stop at "root account is locked" (no LUKS prompt): that's the wipe
  working. After a restore, expect one "REJECTED: stale" email per order still on the channel (5 after the test).

## 2026-11-27 (refactor, before reinstall #2)
- Credentials root-only in `/etc/backup`; every restic job runs as root (`system-backup`); movies + weekly
  `backup-verify` are system units. Backups moved to the separate system Google account (`migrate-drive-account.sh`).
- `/var/lib/tailscale` archived nightly; new phase `identity` restores machine-id, SSH host keys, the Tailscale node,
  the deadman pairing and the hostname, so the phone needs no changes. Proven in reinstall #2.
- Phase `docker` (rootless + volumes from `~/docker-export`), phase `deadman`; sshd/tailscaled only come back through
  `~/.config/remote/install.sh`.

## 2026-11-27 (reinstall #1, the first real run)
- `dconf load` refused the whole file when a key is locked by the system (authselect locks 3 `login-screen` keys):
  the script now drops locked keys first. Before, it loaded nothing and still said ✔.
- akmod-nvidia installed but no module built (akmods only runs at boot): phase `nvidia` builds it for every kernel.
- dnf upgraded `libzstd` without `zstd`, breaking `tar --zstd`: the script upgrades the pair and fails on error.
- `kmod-nvidia-<kernel>` packages showed as "installed by hand": left out of the manifest now.
- `systemd-vconsole-setup.service` can fail on first boot (race with the GPU framebuffer): harmless;
  `sudo systemctl restart systemd-vconsole-setup` clears it for `watcher check`.

## 2026-11-25
- Restore rehearsed in a VM (`rehearsal`): 12 phases, 25 tests passed (failures VM-specific).
