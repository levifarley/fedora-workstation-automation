---
name: dots
description: Review Levi's config/script history (`dots` = bare git repo ~/.dotfiles, pushed to private GitHub levifarley/fedora-setup). Use for "/dots", "what changed in my configs", "what's unsaved", "write a commit message", "when did X change", "get an old version of a file". Read-only for Claude: Levi runs every save/restore himself.
---

`dots` (`~/.local/bin/dots`) wraps a bare git repo `~/.dotfiles` (work tree `~`). It tracks only the paths listed in `~/.config/dots/paths`.
Secrets are excluded (`~/.config/dots/exclude`), and a pre-commit hook scans for keys/tokens. `dots-autosave.timer` commits and pushes
nightly at 23:30 with an automatic message.

**Claude is read-only here.** The Claude guard blocks `dots save/git/remote/restore/track` and raw git for Claude, on purpose:
committing is Levi's call. Never try to get around that (no git via other tools or scripts). Hand Levi the exact command instead.

Arguments: `$ARGUMENTS`

- No args / "status" / "review": run `dots status` and `dots diff` (run them from `~`; paths are relative to the cwd).
  Summarize the changes in plain words, grouped by area (backup, update, watcher, restore, guard, skills, shell, Zed…), not file by file.
  Flag anything suspicious: a file that shouldn't be tracked, something that looks like a secret, a big accidental deletion.
  Then propose a one-line commit message and give Levi the command: `dots save "<message>"`.
- "log" / "history" / "when did X change": `dots log [N]`. For one file, `dots log` won't filter, so read the history from
  `dots diff`/the log messages and explain. Point to `dots restore <file> <commit>` (Levi runs it; it shows the diff and asks first).
- "track <path>": check the path holds no secrets, then give Levi `dots track <path>` + `dots save`.
- Before big events (e.g. the planned reinstall), suggest a clearly named save point: `dots save "State before reinstall"`.
