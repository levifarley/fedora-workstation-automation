#!/bin/bash
# sync.sh: refresh this public showcase from the LIVE system files, swap personal details for placeholders,
# then run the leak check. Nothing is copied unless it's listed below (allow-list, never "copy the folder").
#
#   tools/sync.sh            copy + redact + leak-check (exit 1 if anything personal is left)
#
# Personal values are discovered on this machine at run time (alert email, machine-id, router MACs, saved Wi-Fi
# names, Tailscale IPs) plus any extra lines in ~/.config/showcase/private (one literal per line). Those values
# are never written into this repo, not even into this script.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
C="$REPO/components"
H="$HOME"

rm -rf "$C"; mkdir -p "$C"
put() {  # put <source under ~> <dest under components/>
    local src="$H/$1" dst="$C/$2"
    [ -e "$src" ] || { echo "  (missing, skipped) ~/$1"; return 0; }
    mkdir -p "$(dirname "$dst")"; cp -p "$src" "$dst"
}

# --- watcher: the overseer + tests + alert sender
put .local/bin/watcher                          watcher/bin/watcher
put .config/watcher/install.sh                  watcher/install.sh
put .config/watcher/tests.py                    watcher/tests.py
put .config/watcher/firewall-laptop-zone.sh     watcher/firewall-laptop-zone.sh
for f in watcher-notify watcher-gate watcher-fix watcher-alert watcher-notify@.service watcher-verify.service; do
    put ".config/watcher/system/$f"             "watcher/system/$f"
done
for f in watcher-report.service watcher-report.timer systest.service systest.timer; do
    put ".config/systemd/user/$f"               "watcher/systemd-user/$f"
done

# --- claude-guard: the AI guardrail
for f in claude-guard selftest.py install.sh managed-settings.json; do put ".config/claude-guard/$f" "claude-guard/$f"; done

# --- deadman: remote lock / locate / wipe, phone-signed orders, away-from-home alert
put .local/bin/deadman                          deadman/bin/deadman
put .config/deadman/install.sh                  deadman/install.sh
for f in deadman-agent deadman-agent.service deadman-agent.timer; do put ".config/deadman/system/$f" "deadman/system/$f"; done
put .config/deadman/phone/deadman-order         deadman/phone/deadman-order

# --- backup + restore
put .local/bin/backup                           backup/bin/backup
for f in env excludes install.sh system-restore RESTORE.md migrate-drive-account.sh bootstrap.sh CHANGELOG.md; do put ".config/backup/$f" "backup/$f"; done
for f in system-backup system-backup.service 50-system-backup.rules movies-backup.service movies-backup.timer \
         backup-verify.service backup-verify.timer; do put ".config/backup/system/$f" "backup/system/$f"; done
put .local/bin/rehearsal                        backup/bin/rehearsal

# --- update (NVIDIA-safe nightly chain)
put .local/bin/update                           update/bin/update
for f in install.sh flatpak-to-rpm.sh; do put ".config/update/$f" "update/$f"; done
for f in system-update system-update.service nightly-maintenance.service nightly-maintenance.timer 50-system-update.rules; do
    put ".config/update/system/$f"              "update/system/$f"
done

# --- snapshots, disk health
put .local/bin/snapshots                        snapshots/bin/snapshots
put .config/snapshots/install.sh                snapshots/install.sh
for f in snapper-timeline-watcher.conf snapper-cleanup-watcher.conf; do put ".config/snapshots/system/$f" "snapshots/system/$f"; done
for f in disk-health disk-health.service disk-health.timer; do put ".config/disk-health/system/$f" "disk-health/system/$f"; done

# --- remote access (Tailscale-only SSH)
put .local/bin/remote                           remote/bin/remote
put .config/remote/install.sh                   remote/install.sh
put .config/remote/system/10-remote-access.conf remote/system/10-remote-access.conf

# --- dots (config history)
put .local/bin/dots                             dots/bin/dots
for f in exclude paths pre-commit; do put ".config/dots/$f" "dots/$f"; done
for f in dots-autosave.service dots-autosave.timer; do put ".config/systemd/user/$f" "dots/systemd-user/$f"; done

# --- shell hooks + Claude Code skills that drive the tools
for f in backup-check.sh update-check.sh remote.sh colors.sh; do put ".bashrc.d/$f" "shell/bashrc.d/$f"; done
for s in watcher backup update snapshots dots deadman; do put ".claude/skills/$s/SKILL.md" "claude-skills/$s/SKILL.md"; done

# --- the architecture document
cp "$H/Documents/System-Architecture.md" "$REPO/docs/architecture.md"

# --- example config instead of the real one
cat >"$C/watcher/alerts.conf.example" <<'EOF'
# Where watcher alerts go (read by /usr/local/bin/watcher-alert). Copy to ~/.config/watcher/alerts.conf.
METHOD=ntfy-email
EMAIL=you@example.com
EOF

# --- redact: personal literals → placeholders (values discovered here, never stored in the repo)
"$REPO/tools/private-values.sh" > "${TMPDIR:-/tmp}/showcase-private.$$"
trap 'rm -f "${TMPDIR:-/tmp}/showcase-private.$$"' EXIT
python3 -I - "$REPO" "${TMPDIR:-/tmp}/showcase-private.$$" <<'PY'
import pathlib, re, sys
repo, privf = pathlib.Path(sys.argv[1]), sys.argv[2]
pairs = [l.rstrip("\n").split("\t", 1) for l in open(privf) if "\t" in l]
pairs.sort(key=lambda p: -len(p[0]))                       # longest first
targets = [p for p in (repo / "components").rglob("*") if p.is_file()] + [repo / "docs" / "architecture.md"]
for p in targets:
    try: s = p.read_text()
    except UnicodeDecodeError: continue
    t = s
    for lit, rep in pairs:
        t = re.sub(re.escape(lit), rep, t, flags=re.I)
    t = re.sub(r"[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|yahoo|icloud|proton)\.(com|me)", "you@example.com", t)
    if t != s: p.write_text(t)
PY
find "$C" -name '__pycache__' -prune -exec rm -rf {} +

echo "✔ copied $(find "$C" -type f | wc -l) files into components/ + docs/architecture.md"
exec "$REPO/tools/leakcheck.sh"
