---
name: backup
description: Run, check, or restore from Levi's nightly encrypted Google Drive system backup (restic + rclone, `backup` CLI). Use for "/backup", "run a backup", "is my backup working", "restore a file from backup", or rebuilding the system after a reinstall.
---

The `backup` command (`~/.local/bin/backup`) fronts the restic repo `rclone:gdrive:fedora-backup/restic`. Since 2026-11-27
**every restic job runs as root** (`/usr/local/bin/system-backup`) and the credentials live **only** in `/etc/backup`
(root 700: restic-password, rclone.conf, env, excludes). Claude can't read them, can't open the repo, and must never ask for or
suggest copying them into `~`. That is Levi's deliberate hardening; don't work around it.
Nightly: `nightly-maintenance.timer` (00:00): backup, then `update` if the backup succeeded. Weekly: `backup-verify.timer`
(Sun 12:00) does real restores from Drive. Settings source: `~/.config/backup/` (env + excludes are TEMPLATES that
`install.sh` copies to /etc/backup after Levi reviews them; system/ = root-installed scripts and units).

Arguments: `$ARGUMENTS`

- No args or "now": `backup now` starts the root job (polkit allows it without a password) and streams its log; it can take
  a while, so use a long timeout or run it in the background. Then summarize the result line.
- "status": `backup status` (no sudo: it reads `~/.local/state/backup/{last-result,verify.json}` written by the root job).
  Flag it if the last success is more than 36h old or any check shows ✘.
- "verify": `backup verify` runs the full verification now (real restores compared with the live files).
- "restore <path>", "ls", "snapshots": these open the repo, so they need **sudo**: give Levi the command for his terminal
  (`backup ls latest <path>`, then `backup restore <path> [snapshot]`, which restores into ~/restored/, never in place).
- After a reinstall: read `~/.config/backup/RESTORE.md` (or `gdrive:fedora-backup/RESTORE.md`) and follow Bootstrap → Fast path.
  Levi types the credentials straight into /etc/backup himself.

`sudo` can't take a password here; give Levi commands to run in a real terminal.
