---
name: update
description: Update Levi's Fedora system (dnf + flatpak, NVIDIA-safe) with the `update` CLI, check pending updates, or report the nightly update result. Use for "/update", "update my system", "any updates?", "did the nightly update work", "do I need to reboot".
---

`update` (`~/.local/bin/update`) starts `system-update.service` (root worker `/usr/local/bin/system-update`).
Nightly, `nightly-maintenance.timer` (00:00, wakes from suspend) runs `nightly-maintenance.service`: backup, then update only if the backup succeeded. A manual `backup` does NOT trigger an update.
Config source: `~/.config/update/` (system/ = files installed by install.sh).
State: `~/.local/state/update/last-result`, `reboot-needed`.

Arguments: `$ARGUMENTS`

- No args or "now": run `update now` (blocks; use a long timeout or run in the background), then summarize which packages and Flatpaks
  were updated, any warnings (especially an NVIDIA kmod warning), firmware available, and whether a reboot is recommended.
- "full" / "--backup": `update --backup` (backup first, then update).
- "check": `update check`, then summarize what's pending (call out kernel, nvidia, mesa, zed).
- "status": `update status`.

Never reboot or apply firmware (`fwupdmgr update`) on your own; recommend it and let Levi decide.
If the worker reports that the NVIDIA module was not built for a new kernel, see the memory note on Fedora/NVIDIA history before advising.
`sudo` can't take a password here; give Levi commands to run in a real terminal.
