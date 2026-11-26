#!/usr/bin/env bash
# Claude Code status line (silent): caches plan-limit usage for the GNOME top-bar
# extension (claude-usage@levi.local), which reads ~/.cache/claude-usage.json.
set -u

input=$(cat)
dir="${XDG_CACHE_HOME:-$HOME/.cache}"
cache="$dir/claude-usage.json"
mkdir -p "$dir"

prev='{}'
[ -s "$cache" ] && prev=$(cat "$cache" 2>/dev/null || echo '{}')

# rate_limits are account-wide; keep the previous values when this session
# hasn't received them yet (they only appear after its first API response).
printf '%s' "$input" | jq -c \
  --argjson now "$(date +%s)" \
  --argjson prev "$prev" '
  {
    updated_at: $now,
    five_hour: (.rate_limits.five_hour // $prev.five_hour),
    seven_day: (.rate_limits.seven_day // $prev.seven_day),
    session_cost_usd: (.cost.total_cost_usd // 0),
    model: (.model.display_name // null)
  }' >"$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache"

# Prints nothing, so no status line shows in Claude Code terminals; it only
# feeds the 5h/7d limit numbers to the top bar.
