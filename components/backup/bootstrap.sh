#!/bin/bash
# bootstrap.sh — fresh Fedora install → backups reachable → Claude guard → Claude Code.  Run it yourself, in a terminal
# inside GNOME, as levi. Safe to re-run: every step checks whether it's already done and resumes from there.
# Get it on a fresh install (no secrets in it; it's the same file as in the public showcase repo):
#   curl -fsSLO https://raw.githubusercontent.com/levifarley/fedora-workstation-automation/main/components/backup/bootstrap.sh
#   bash bootstrap.sh
# (Also stored next to RESTORE.md in Drive: fedora-backup/bootstrap.sh.)
# You need: the OAuth client ID + secret, the SYSTEM Google account's login (phone has its 2-step), the backup password.
# Written after reinstall #2 (2026-11-27): placeholders in a paste block broke bash, rclone opened the wrong browser,
# and nothing checked the inputs. This script prompts, checks, and offers a fallback at the browser step.
set -uo pipefail
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'
C=/etc/backup; RC="$C/rclone.conf"; PW="$C/restic-password"
REPO="rclone:gdrive:fedora-backup/restic"
step() { echo; echo "${B}━━ $* ${N}"; }
ok()   { echo "${G}  ✔ $*${N}"; }
die()  { echo "${R}  ✘ $*${N}"; echo "  Fix that, then run this script again: it resumes where it stopped."; exit 1; }
r()    { sudo rclone --config "$RC" "$@"; }
R()    { sudo env RCLONE_CONFIG="$RC" RESTIC_PASSWORD_FILE="$PW" RESTIC_REPOSITORY="$REPO" RESTIC_CACHE_DIR=/var/cache/restic \
             RCLONE_TPSLIMIT=16 RCLONE_TPSLIMIT_BURST=16 restic "$@"; }
[ "$(id -un)" = levi ] || die "run this as levi, not $(id -un)"
[ -t 0 ] || die "run this in a terminal (it asks questions)"

step "1/6 Tools and the root-only credentials folder"
sudo dnf install -y -q restic rclone jq >/dev/null || die "dnf install failed (network?)"
sudo install -d -m 700 -o root -g root "$C" /var/cache/restic
ok "restic, rclone, jq; $C (root only)"

step "2/6 Google Drive login (SYSTEM account)"
if sudo test -s "$RC" && r lsf --max-depth 1 gdrive:fedora-backup 2>/dev/null | grep -qx 'restic/'; then
    ok "already logged in, and fedora-backup/restic is there"
else
    echo "  From your password manager: the OAuth client of your own Google Cloud app (\"Desktop app\" client)."
    while :; do
        read -rp "  Client ID (ends in .apps.googleusercontent.com): " cid
        [[ "$cid" =~ ^[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com$ ]] && break
        echo "${Y}  That doesn't look like a client ID. Paste the whole thing.${N}"
    done
    while :; do
        read -rsp "  Client secret (hidden; starts with GOCSPX-): " csec; echo
        [[ "$csec" =~ ^GOCSPX-[A-Za-z0-9_-]{20,}$ ]] && break
        echo "${Y}  That doesn't look like a client secret (GOCSPX-…). If it keeps failing, make a new secret in${N}"
        echo "${Y}  Google Cloud Console → APIs & Services → Credentials, and save it in your password manager.${N}"
    done
    echo
    echo "  Next: a login link. Sign in as the ${B}SYSTEM${N} account and allow access."
    echo "  Goal: ${B}no system-account session stays in a browser afterwards.${N} Choose how:"
    echo "    1) throwaway Firefox profile, deleted right after  ${D}(recommended: nothing can stay behind)${N}"
    echo "    2) just print the link; I'll use a browser myself and sign out of the system account afterwards"
    read -rp "  1 or 2 [1]: " how
    log=$(mktemp); prof=""
    rclone authorize drive "$cid" "$csec" --auth-no-open-browser >"$log" 2>&1 &
    apid=$!
    for _ in $(seq 1 30); do grep -qo 'http://127.0.0.1:53682/auth[^ ]*' "$log" && break; sleep 0.5; done
    url=$(grep -o 'http://127.0.0.1:53682/auth[^ ]*' "$log" | head -1)
    [ -n "$url" ] || { kill $apid 2>/dev/null; cat "$log"; die "rclone didn't print a login link"; }
    if [ "${how:-1}" = 1 ] && command -v firefox >/dev/null; then
        prof=$(mktemp -d); firefox --no-remote --profile "$prof" "$url" >/dev/null 2>&1 &
        echo "  A separate Firefox window opened (empty profile). Sign in there; close it when it says Success."
    else
        echo "  Open this link in a browser:"; echo "    ${B}$url${N}"
        echo "  If Google warns the app is unverified: Advanced → continue (it's your own app)."
    fi
    wait $apid; tok=$(grep -o '{.*}' "$log" | tail -1); err=$(grep -iE 'error|invalid' "$log" | tail -2)
    rm -f "$log"; [ -n "$prof" ] && { pkill -f -- "--profile $prof" 2>/dev/null; sleep 1; rm -rf "$prof"; ok "throwaway browser profile deleted"; }
    if [ -z "$tok" ]; then
        echo "$err"
        [[ "$err" =~ client.secret|invalid_client ]] && die "Google rejected the client ID/secret (see above): re-check them"
        die "no login token came back (closed too early? try option 2)"
    fi
    sudo rclone --config "$RC" config create gdrive drive scope=drive client_id "$cid" client_secret "$csec" token "$tok" >/dev/null &&
        sudo chmod 600 "$RC" || die "couldn't save the login"
    unset tok csec
    r lsf --max-depth 1 gdrive:fedora-backup 2>/dev/null | grep -qx 'restic/' ||
        die "logged in, but fedora-backup/restic isn't there: wrong Google account? (must be the SYSTEM account) — remove $RC and re-run"
    ok "logged in; fedora-backup has restic + movies"
    [ "${how:-1}" = 2 ] && echo "${Y}  Now sign the system account out of that browser (and clear its Google cookies).${N}"
fi

step "3/6 Backup password"
if sudo test -s "$PW" && R cat config >/dev/null 2>&1; then
    ok "already set, and it opens the repository"
else
    for try in 1 2 3; do
        read -rsp "  Backup (restic) password from your password manager (hidden): " pw; echo
        printf '%s' "$pw" | sudo sh -c "umask 077; cat > $PW"; unset pw
        R cat config >/dev/null 2>&1 && { ok "the password opens the repository"; break; }
        echo "${Y}  That password doesn't open the repository.${N}"; sudo rm -f "$PW"
        [ $try = 3 ] && die "3 wrong tries"
    done
fi

step "4/6 Which snapshot will be restored"
R snapshots --latest 1 --compact --no-lock 2>/dev/null | sed -n '3,4p'
read -rp "  This newest snapshot should be your 'Before wiping' backup. Continue? [Y/n] " a
[ "${a:-y}" != n ] || die "stopped before restoring anything"

step "5/6 Restore the guard + backup tools, then install the guard FIRST"
if [ -x /usr/local/bin/claude-guard ] && sudo test -s /etc/claude-code/managed-settings.json; then
    ok "Claude guard already installed"
else
    R restore latest --target / --no-lock --include /home/levi/.config/claude-guard --include /home/levi/.config/backup \
        --include /home/levi/.local/bin || die "restore of the tools failed"
    bash "$HOME/.config/claude-guard/install.sh" || die "guard install failed"
    ok "guard installed (before Claude Code exists on this machine)"
fi

step "6/6 Claude Code"
if command -v claude >/dev/null || [ -x "$HOME/.local/bin/claude" ]; then ok "already installed"
else curl -fsSL https://claude.ai/install.sh | bash || die "Claude Code install failed"; fi
echo
echo "${G}${B}✔ Bootstrap done.${N} Open a ${B}new terminal${N} (inside GNOME), then:"
echo "    cd ~ && claude"
echo "  and tell Claude: ${B}Read ~/.config/backup/RESTORE.md, then help me run system-restore.${N}"
