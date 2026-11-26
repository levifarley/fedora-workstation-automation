---
name: backup
description: Run, check, or restore from Levi's nightly encrypted Google Drive system backup (restic + rclone, `backup` CLI). Use for "/backup", "run a backup", "is my backup working", "restore a file from backup", or rebuilding the system after a reinstall.
---

The system has a `backup` command (`~/.local/bin/backup`) that wraps the restic repo at
`rclone:gdrive:fedora-backup/restic`. The nightly job is `nightly-maintenance.timer` (00:00, wakes from suspend): backup, then `update` if the backup succeeded.
Config: `~/.config/backup/` (env, excludes, RESTORE.md, install.sh, system/ = root-installed files).

Arguments: `$ARGUMENTS`

- No args or "now": run `backup now` (it blocks until done; can take a while; use a long timeout or
  run in background), then summarize: files new/changed, data added, snapshot id, errors.
- "status": run `backup status` and report the last result, next run, and the latest snapshots. Flag it if the
  last success is more than 36h old.
- "restore <path>": find it with `backup ls latest <path>`, confirm with the user, then `backup restore <path> [snapshot]`
  (it restores into ~/restored/, never in place).
- After a system reinstall / disaster recovery: read `~/.config/backup/RESTORE.md` (or `gdrive:fedora-backup/RESTORE.md`
  via `rclone cat`) and follow it step by step, asking the user for the restic password.

`sudo` can't take a password here; give the user commands to run in a real terminal.
