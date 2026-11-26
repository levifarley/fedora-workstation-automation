# Nudge in new terminals: failed/warned nightly update, or reboot pending
[[ $- != *i* ]] && return
__up="$HOME/.local/state/update"
if [ -f "$__up/last-result" ] && ! head -1 "$__up/last-result" | grep -qE ' OK( |$)'; then
    printf "\e[33m⚠ Last update needs attention (run \`update status\`):\n%s\e[0m\n" "$(cat "$__up/last-result")"
fi
# clear the reboot flag once the system has booted after it was written
if [ -f "$__up/reboot-needed" ] && [ "$(stat -c %Y "$__up/reboot-needed")" -lt "$(date -d "$(uptime -s)" +%s)" ]; then
    rm -f "$__up/reboot-needed"
fi
[ -f "$__up/reboot-needed" ] && printf '\e[36m↻ Updates installed — reboot when convenient\e[0m\n'
unset __up
