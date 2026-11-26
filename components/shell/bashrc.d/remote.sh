# Phone/remote sessions (SSH over Tailscale): status on login, and `claude` runs in a persistent tmux session
[[ $- != *i* ]] && return
[ -n "${SSH_CONNECTION:-}" ] || return

if [ -z "${TMUX:-}" ]; then
    # `claude` → attach to (or start) one long-lived Claude Code session that survives the phone disconnecting
    claude() { command tmux new-session -A -s claude "command claude $*"; }
    # status screen, once per login (not inside tmux)
    if [ -z "${REMOTE_GREETED:-}" ]; then
        export REMOTE_GREETED=1
        printf '\e[1m%s\e[0m  %s · up %s\n\n' "$(hostname)" "$(date '+%a %b %d %H:%M')" "$(uptime -p | sed 's/up //')"
        timeout 20 "$HOME/.local/bin/watcher" 2>/dev/null | sed -n '3,200p' | grep -E '^ [^ ]|↳|healthy|problem' | head -30
        timeout 20 "$HOME/.local/bin/watcher" check 2>/dev/null | grep -v 'ℹ' | head -8
        printf '\n\e[2m%s\e[0m\n' "claude · watcher · watcher check · watcher fix · backup status · deadman status · watcher commands"
    fi
fi
