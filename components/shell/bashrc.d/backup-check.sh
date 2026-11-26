# Warn in new terminals if the nightly backup failed or is stale (>36h)
[[ $- != *i* ]] && return
__bk_state="$HOME/.local/state/backup"
if [ -f "$__bk_state/last-result" ]; then
    __bk_last=$(cat "$__bk_state/last-success" 2>/dev/null || echo 0)
    if grep -q FAILED "$__bk_state/last-result" || [ $(( $(date +%s) - __bk_last )) -gt 129600 ]; then
        printf '\e[33m⚠ Backup problem: %s — run `backup status`\e[0m\n' "$(cat "$__bk_state/last-result")"
    fi
fi
unset __bk_state __bk_last
