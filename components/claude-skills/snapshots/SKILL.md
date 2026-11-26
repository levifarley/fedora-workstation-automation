---
name: snapshots
description: Btrfs snapshots on Levi's Fedora (snapper; `snapshots` CLI). System pre/post snapshots around every dnf transaction, hourly /home snapshots. Use for "/snapshots", "undo the last update", "the update broke X", "roll back", "get yesterday's version of a file", "I deleted a file".
---

`snapshots` (`~/.local/bin/snapshots`) wraps snapper configs "root" (/) and "home" (/home). Setup: `~/.config/snapshots/install.sh`.
- System: dnf5 actions plugin (`/etc/dnf/libdnf5-plugins/actions.d/snapper.actions`) takes a pre/post pair on every dnf transaction; keeps 20.
- Home: hourly timeline (24 hourly · 7 daily · 4 weekly); `~/.cache` is a separate subvolume, so it's excluded.
- /boot (kernels) is NOT in snapshots. Rollback picks a kernel whose modules exist in the restored root.

Arguments: `$ARGUMENTS`

- No args: `snapshots` → summarize the newest system pairs and the home snapshot coverage.
- "what changed in the last update": find the newest pre/post pair, `snapshots pkgs <pre#>`.
- A file was lost or overwritten: `snapshots versions <path>`, confirm which version, `snapshots get <path> <#>`
  (it restores into ~/restored/snapshot-N/…, never in place; tell Levi where it is).
- An update broke something but the system boots: confirm the pair with `snapshots pkgs <pre#>`, then have Levi run
  `snapshots undo <pre#>` in a real terminal (sudo). Afterwards, suggest excluding or holding the bad package.
- System badly broken: `snapshots rollback <#>` (dry run, explain it), then Levi runs `snapshots rollback <#> --yes` and reboots.
  The old root is kept as subvolume `root.broken-<date>`; after confirming the rollback works, it can be deleted from the top-level subvolume.
- If the desktop won't start: use a TTY (Ctrl+Alt+F3), log in, and run the same commands. Or pick an older kernel in the GRUB menu.
- GUI: `snapshots gui` (Btrfs Assistant).
Never run undo/rollback without Levi's explicit go-ahead.
