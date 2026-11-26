#!/bin/bash
# Install/refresh the Claude guard (root-owned so Claude can't change or remove it). Run in a real terminal:
#   ~/.config/claude-guard/install.sh
# Review what changed first:  diff -u /usr/local/bin/claude-guard ~/.config/claude-guard/claude-guard
# Emergency off-switch:       sudo rm /etc/claude-code/managed-settings.json   (then restart Claude Code)
set -euo pipefail
S="$HOME/.config/claude-guard"
python3 -I "$S/selftest.py" "$S/claude-guard"                 # refuse to install a guard that fails its own tests
jq -e '.allowManagedHooksOnly == true and (.hooks.PreToolUse | length > 0)' "$S/managed-settings.json" >/dev/null
sudo install -m 755 -o root -g root "$S/claude-guard" /usr/local/bin/claude-guard
sudo install -d -m 755 -o root -g root /etc/claude-code
sudo install -m 644 -o root -g root "$S/managed-settings.json" /etc/claude-code/managed-settings.json
sudo restorecon -v /usr/local/bin/claude-guard /etc/claude-code/managed-settings.json >/dev/null 2>&1 || true
python3 -I "$S/selftest.py"                                    # the installed copy
echo "✔ Claude guard installed. Restart Claude Code so it loads the managed settings, then: watcher claude"
