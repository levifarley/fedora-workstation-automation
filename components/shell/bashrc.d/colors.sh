# ~/.bashrc.d/colors.sh — colorful, readable terminal (loaded by ~/.bashrc)
[[ $- != *i* ]] && return   # interactive shells only

# ---------- Prompt ----------
# Layout:  ✔ 23:59 levi@fedora ~/Projects/foo (main *)
#          ❯
# Green ✔ / red ✘<code> for last command's exit status; git branch + dirty marker.
if [ -f /usr/share/git-core/contrib/completion/git-prompt.sh ]; then
    . /usr/share/git-core/contrib/completion/git-prompt.sh
    GIT_PS1_SHOWDIRTYSTATE=1
    GIT_PS1_SHOWUNTRACKEDFILES=1
    GIT_PS1_SHOWUPSTREAM=auto
    GIT_PS1_SHOWCOLORHINTS=1
fi

__prompt() {
    local ec=$?
    local R='\[\e[0m\]' B='\[\e[1m\]' DIM='\[\e[2m\]'
    local RED='\[\e[38;5;203m\]' GRN='\[\e[38;5;114m\]' YEL='\[\e[38;5;221m\]'
    local BLU='\[\e[38;5;75m\]'  MAG='\[\e[38;5;176m\]' CYN='\[\e[38;5;80m\]'
    local status
    if [ $ec -eq 0 ]; then status="${GRN}✔${R}"; else status="${RED}✘ ${ec}${R}"; fi
    local git=""
    if declare -F __git_ps1 >/dev/null; then git="$(__git_ps1 ' (%s)')"; fi
    local host_color=$CYN
    [ -n "$SSH_CONNECTION" ] && host_color=$YEL
    PS1="\n${status} ${DIM}\A${R} ${GRN}${B}\u${R}${DIM}@${R}${host_color}\h${R} ${BLU}${B}\w${R}${MAG}${git}${R}\n${MAG}❯${R} "
    # keep window title + history in sync across terminals
    history -a
}
PROMPT_COMMAND="__prompt${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# ---------- History (bigger, deduped, shared) ----------
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT='%F %T  '
shopt -s histappend

# ---------- ls → eza (icons, git status, colors) ----------
if command -v eza >/dev/null; then
    alias ls='eza --group-directories-first --color=auto'
    alias ll='eza -l --group-directories-first --git --time-style=relative'
    alias la='eza -la --group-directories-first --git --time-style=relative'
    alias lt='eza --tree --level=2'
else
    alias ll='ls -lh --color=auto --group-directories-first'
    alias la='ls -lAh --color=auto --group-directories-first'
fi

# ---------- grep / diff / ip ----------
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias ip='ip -color=auto'
export GREP_COLORS='ms=01;38;5;203:mc=01;31:sl=:cx=:fn=38;5;176:ln=38;5;114:bn=32:se=38;5;244'

# ---------- bat: syntax-highlighted cat, man pages, --help ----------
if command -v bat >/dev/null; then
    export BAT_THEME="${BAT_THEME:-TwoDark}"
    alias cat='bat --paging=never --style=plain'   # plain `cat` still behaves when piped
    alias catn='bat --paging=never'                # with line numbers + header
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export MANROFFOPT="-c"
    # colorized --help:   h git   /   h rsync
    h() { "$@" --help 2>&1 | bat --plain --language=help; }
    # tail a log with highlighting:  tailf /var/log/foo.log
    tailf() { tail -f "$@" | bat --paging=never --style=plain -l log; }
fi

# ---------- less: colors + keep raw color codes ----------
export LESS='-R --use-color -Dd+r$Du+b$'

# ---------- git: colorful side-by-side diffs via delta ----------
if command -v delta >/dev/null && ! git config --global --get core.pager >/dev/null; then
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.line-numbers true
    git config --global merge.conflictStyle zdiff3
fi

# ---------- zoxide: `z proj` jumps to frequent dirs, `zi` picks interactively ----------
command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# ---------- fzf: Ctrl-R fuzzy history, Ctrl-T file picker ----------
[ -f /usr/share/fzf/shell/key-bindings.bash ] && . /usr/share/fzf/shell/key-bindings.bash
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border --color=hl:203,hl+:203,pointer:176,prompt:75'
