---
name: watcher
description: Oversight of Levi's whole system — every scheduled/automated job (nightly backup → update, disk-health, snapshots, movielist, weekly tests, anything tagged X-Watcher-Name) plus the end-to-end test suite (`watcher test`). Use for "/watcher", "what's scheduled", "is everything OK/running", "what failed", "test everything", "did the tests pass", "turn off X", and whenever creating NEW automation (it must be registered and get a test).
---

`watcher` (`~/.local/bin/watcher`, Python) discovers jobs from systemd unit files tagged `X-Watcher-Name=` in
`/etc/systemd/system/*.service` (system) and `~/.config/systemd/user/*.service` (user). Run history comes from the journal.

Arguments: `$ARGUMENTS`

- No args / "status": run `watcher` and `watcher check`. Report in a few lines: each job's last result and next run,
  then any problems with the fix. Don't paste the raw dashboard.
- "check": `watcher check` → explain each problem, then investigate failures with `watcher logs <job> -n 80`
  and propose (or make) the fix.
- "test" / "tests": `watcher test` (quick, ~20s). "test full": `watcher test --full` (adds a real restore of 5 random files from
  Drive, a snapshot round-trip and a repo check: minutes, so run it in the background). A group: `watcher test <group> [--full]`
  (system, nvidia, automation, backup, snapshots, disks, configs, dvd, updates). `watcher test report` = the last run.
  Report pass/fail counts, then each failure with its cause and fix (investigate first).
- "fix": run `watcher fix` (no tty here, so it won't prompt). It applies user-level fixes, then tests and checks. Root fixes are written to
  `~/.local/state/watcher/needs-sudo.sh`: show Levi what it does and have him run `bash ~/.local/state/watcher/needs-sudo.sh` in a terminal.
  Then handle whatever is still unresolved yourself: investigate, fix user-level issues, and propose root fixes as commands for Levi.
  Ask before anything risky. Re-run `watcher fix` to confirm. Daily reports: `~/.local/state/watcher/history/<date>.txt`.
- "pause [job|all] [30m|2h|1d|until HH:MM]" / "resume": `watcher pause …` / `watcher resume`. Pausable: all, nightly (= backup → update
  → verify), disk-health, tests, movielist. Paused runs skip cleanly via ExecCondition=/usr/local/bin/watcher-gate. Resume lists skipped runs.
- "logs <job>", "info <job>", "run <job>" (blocks: use the background for long jobs like backup), "enable|disable <job>"
  (system jobs need sudo, so give Levi the command), "commands" (`watcher commands [name]`: every custom command, shell shortcut and Claude skill, grouped; with a name, its full usage).

## Registering new automation (always do this when building any scheduled/triggered job)
In `[Service]` add `ExecCondition=/usr/local/bin/watcher-gate <name>` (makes it pausable). In the job's `.service` `[Unit]` section add:
```
X-Watcher-Name=<short-name>
X-Watcher-State=<file whose first line is "ISO-date OK|WARN|FAILED · summary">   # optional
X-Watcher-MaxAge=<e.g. 26h>                                                      # optional: stale alarm
X-Watcher-Schedule=<text>              # only if it is started by another job instead of its own timer/path
OnFailure=watcher-notify@%n.service    # desktop notification on failure (or X-Watcher-Notify=children)
```
- User units: put them in `~/.config/systemd/user/`, then `systemctl --user daemon-reload`. No sudo needed.
- System units: keep the source in a `~/.config/<project>/system/` folder, add its install lines to
  `~/.config/watcher/install.sh` (which also regenerates the polkit rule that lets `watcher run` work without a password),
  and have Levi run that in a real terminal.
- Keep scripts in `~/.local/bin` (user) or `/usr/local/bin` (system, installed from source).
- **Every new script in ~/.local/bin** needs a header that `watcher commands` reads (the configs/commands-documented test enforces it):
  line 2 `# name — what it does` (or a `"""name — …` docstring), a `# group: <System care|DVD & movies|Claude|…>` line,
  then usage lines indented 2+ spaces: `#   name sub <arg>      what it does`. Also add a `/skill` if Claude should drive it.
- Then run `watcher check` to confirm it shows up and is healthy.

## Adding tests
The engine is `~/.config/watcher/tests.py`. Add a function decorated with `@test("<group>")` (`full=True` if it's slow or network-heavy).
Return a short success message, `raise AssertionError(msg)` on failure, `raise Skip(msg)` when it doesn't apply. Every new automation
gets a test that proves its *result*, not just that it ran. Then run `watcher test <group>`.
The weekly full run is the user unit `systest.timer` (Sun 12:30, watched job "tests"). Its failures show in `watcher check`.

## Nightly verify (step 3) and the fixer
`nightly-maintenance.service` ExecStopPost → `watcher-verify.service` (root, /usr/local/bin/watcher-fix --verify). It always runs, even
after a failed backup/update. Fixes are in `~/.config/watcher/system/watcher-fix`: add new safe fixes there as
`fix(what, action, root=..., cmds=[sudo commands])`. Reinstalling changed root scripts is never automatic (always_ask=True).

## Alerts, report, movies, dots (added 2026-11-25)
- `watcher alerts` shows phone push (ntfy topic in ~/.config/watcher/ntfy-topic, secret, mode 600) + dead-man's switch
  (healthchecks.io URL in ~/.config/watcher/healthchecks-url, pinged by nightly verify). `watcher alerts test` sends a test alert;
  `watcher alerts healthchecks <url>` saves the ping URL. watcher-notify pushes failures to the phone too.
- `watcher report [--notify]` gives the weekly summary (user timer watcher-report.timer, Sun 13:00). Metrics are kept in ~/.local/state/watcher/metrics.jsonl.
- `movies-backup` (user units movies-backup.service/.timer): Samsung SSD → restic repo rclone:gdrive:fedora-backup/movies. Runs on
  SSD mount + daily 01:30. Uses X-Watcher-SuccessFile + X-Watcher-Rerun=no (unplugged ≠ success; fixer won't retry).
- `dots` = bare git repo ~/.dotfiles tracking the paths in ~/.config/dots/paths (secrets excluded + pre-commit secret scan).
  Committing is Levi's call: don't run `dots save` yourself unless he asks in that moment. dots-autosave.timer exists but
  is only enabled if he chooses to.
- Security tests compare against ~/.config/watcher/baseline/ (ports, firewall). After an intended change: `watcher test baseline`.

## Claude guard (oversight of Claude itself — never weaken it)
Root-owned `/usr/local/bin/claude-guard`, wired in by `/etc/claude-code/managed-settings.json` (allowManagedHooksOnly) as a
SessionStart + PreToolUse hook. It blocks git/gh/dots-write commands, secret files and tampering; it asks first for browser
actions, sending data out, network tools, stopping watchdogs, firewall changes and startup/config edits; it logs everything to the
journal (tag claude-audit). `watcher claude [today|week] [--all]` shows the activity. Source + rules: `~/.config/claude-guard/`
(selftest.py must pass; install.sh refuses otherwise). Levi can pause it with `watcher guard pause [dur]` (sudo, his terminal only; still logs; auto-expires ≤1 day) —
Claude must never run or suggest running that itself. Claude must never try to get around a guard decision, edit the installed
guard, or suggest disabling it. If a rule blocks legitimate work, explain it and let Levi decide whether to change the rule.

## Remote access, alerts, deadman (added 2026-11-25)
- **Alerts are email**: everything goes through root-owned `/usr/local/bin/watcher-alert` (ntfy.sh email forwarding to Levi's Gmail;
  config `~/.config/watcher/alerts.conf`; subjects start with `[system]`). `watcher alerts test` sends a test email. No phone push.
- **Phone access** (`remote`, `watcher remote`): Tailscale + key-only SSH (only levi, no forwarding, Tailscale interface only, firewalld
  zone `tailnet`) + mosh. From the Pixel Terminal app: `ssh system`, which shows a status screen; `claude` attaches a persistent tmux Claude session.
  Hardening: `/etc/ssh/sshd_config.d/10-remote-access.conf` (source ~/.config/remote/). The security test fails if it's weakened.
- **Remote wipe/lock/locate** (`deadman`, `watcher deadman`, /deadman skill): phone-signed orders only; Claude is read-only (guard-enforced).

## Architecture doc
Every new feature also goes into `~/Documents/System-Architecture.md` (component table, the "Every watched job" line, diagrams if the
flow changes, roadmap, changelog). `watcher test configs` fails if a watched job or command is missing from it. Never put secrets in it.
