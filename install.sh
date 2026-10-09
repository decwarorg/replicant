#!/usr/bin/env bash
#
# DECWAR Replicant — installer
#
# Installs the Hermes agent with the DECWAR companion, one script.
# DRY_RUN=1 runs the whole flow as a no-op demo — nothing is changed.
#
#   1) Install Hermes Agent  — unattended Hermes install, connects DeepSeek
#                              (or leaves that for later), wires the decwar
#                              skill and SOUL.md into the agent, verifies
#                              with a real round-trip.
#   2) Update/restore Core Skills — pull the latest replicant from github;
#                              core-skill edits are replaced, your own files
#                              (SOUL.md) are left alone.
#   3) Exit
#
# Usage:  bash install.sh              normal interactive run
#         bash install.sh keyfile      read the DeepSeek key from that file
#         DRY_RUN=1 bash install.sh    simulate everything; change NOTHING
#         DEEPSEEK_API_KEY=sk-… bash install.sh    key from the environment
#         PLAIN=1 bash install.sh      plain line-based output (small/dumb
#                                      terminals; also automatic when the
#                                      output is not a terminal)
#
# UI: two-zone VT-100 layout — the step's progress at the top (checkmarks,
# notes, input markers), the detailed output in a ~20-line log zone at the
# bottom. All real command output is streamed there.
#
# Security: the DeepSeek key is only ever read and stored; it is never
# echoed, and only its length is reported. It ends up in the agent's .env
# (chmod 600) via `hermes config set`.
#
# A failed step ends the script with the error visible (terminal restored,
# screen content kept, exit 1). Re-running is safe — every step is written
# to be idempotent.

set -u

SELF_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PKG_DIR="$SELF_DIR"
STREAM_TMP=""
DL_TMP=""
CURLH=""
case "${DRY_RUN:-0}" in 1|yes|true) DRY=1 ;; *) DRY=0 ;; esac
KEY_FILE="${1:-}"
KEY=""
DS=""
HERMES_BIN=""
HERMES_HINT=""
PROFILE=""
HERMES_HOME="$HOME/.hermes"
CLEANED=0

# --- colours (used sparingly) ------------------------------------------------
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
if [ ! -t 1 ]; then
    GREEN=  YELLOW=  RED=  BOLD=  DIM=  RESET=
fi

# --- terminal geometry -------------------------------------------------------
ROWS=24
COLS=80
case "${PLAIN:-0}" in 1|yes|true) PLAIN=1 ;; *) PLAIN=0 ;; esac
[ -t 1 ] || PLAIN=1
if command -v tput >/dev/null 2>&1; then
    _r="$(tput lines 2>/dev/null)" || _r=""
    _c="$(tput cols  2>/dev/null)" || _c=""
    case "$_r" in ''|*[!0-9]*) ;; *) ROWS="$_r" ;; esac
    case "$_c" in ''|*[!0-9]*) ;; *) COLS="$_c" ;; esac
fi
[ "$ROWS" -lt 20 ] && PLAIN=1
[ "$COLS" -lt 64 ] && PLAIN=1

BOTTOM_H=20                       # wanted height of the log zone
_max_bottom=$((ROWS - 14))        # keep at least 14 rows for progress
[ "$BOTTOM_H" -gt "$_max_bottom" ] && BOTTOM_H="$_max_bottom"
[ "$BOTTOM_H" -lt 6 ] && PLAIN=1
SEP=$((ROWS - BOTTOM_H))          # separator row
LOG_TOP=$((SEP + 1))              # first row of the log zone

RULE="$(printf '%*s' 60 '')"
RULE="${RULE// /-}"

# --- low level screen helpers ------------------------------------------------
at()       { printf '\033[%s;%sH' "$1" "$2"; }      # cursor position
clr_line() { printf '\033[2K'; }
ui_clear() { [ "$PLAIN" = 1 ] && return; printf '\033[r\033[2J\033[H'; }
ui_region() { [ "$PLAIN" = 1 ] && return; printf '\033[%s;%sr' "$1" "$2"; }

clip_line() {  # $1 = text; cut painted rows to the terminal width (with '…')
    local s="$1" w=$((COLS - 1)) i=0 n ch out vis
    [ "$PLAIN" = 1 ] && { printf '%s' "$s"; return; }
    n=${#s}; [ "$n" -le "$w" ] && { printf '%s' "$s"; return; }   # cheap fast path
    vis=0
    while [ "$i" -lt "$n" ]; do
        ch="${s:$i:1}"
        if [ "$ch" = $'\e' ]; then
            i=$((i+1))
            while [ "$i" -lt "$n" ]; do ch="${s:$i:1}"; i=$((i+1)); case "$ch" in [a-zA-Z]) break ;; esac; done
        else vis=$((vis+1)); i=$((i+1)); fi
    done
    [ "$vis" -le "$w" ] && { printf '%s' "$s"; return; }
    out=''; vis=0; i=0
    while [ "$i" -lt "$n" ] && [ "$vis" -lt $((w - 1)) ]; do
        ch="${s:$i:1}"
        if [ "$ch" = $'\e' ]; then
            out+="$ch"; i=$((i+1))
            while [ "$i" -lt "$n" ]; do ch="${s:$i:1}"; out+="$ch"; i=$((i+1)); case "$ch" in [a-zA-Z]) break ;; esac; done
            continue
        fi
        out+="$ch"; vis=$((vis+1)); i=$((i+1))
    done
    printf '%s%s…' "$out" "$RESET"
}

wrap_into() {  # $1 = text; fills CHUNKS=() with pieces no wider than the screen
    local s="$1" w=$((COLS - 1)) i=0 vis=0 ch out='' sgr='' esc n
    n=${#s}
    CHUNKS=()
    [ "$w" -lt 8 ] && w=8
    while [ "$i" -lt "$n" ]; do
        ch="${s:$i:1}"
        if [ "$ch" = $'\e' ]; then
            esc="$ch"; i=$((i+1))
            while [ "$i" -lt "$n" ]; do ch="${s:$i:1}"; esc+="$ch"; i=$((i+1)); case "$ch" in [a-zA-Z]) break ;; esac; done
            out+="$esc"; sgr="$esc"; continue
        fi
        if [ "$vis" -ge "$w" ]; then CHUNKS+=("$out$RESET"); out="$sgr"; vis=0; fi
        out+="$ch"; vis=$((vis+1)); i=$((i+1))
    done
    CHUNKS+=("$out")
}

cleanup() {
    [ "$CLEANED" = 1 ] && return 0
    CLEANED=1
    [ -n "$STREAM_TMP" ] && rm -f "$STREAM_TMP"
    [ -n "$DL_TMP" ] && rm -f "$DL_TMP"
    [ -n "$CURLH" ] && rm -rf "$CURLH"
    if [ "$PLAIN" = 0 ]; then printf '\033[r\033[?7h%s\n' "$RESET"; fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM
[ "$PLAIN" = 0 ] && printf '\033[?7l'              # no autowrap while painting

# --- bottom log zone (last ~20 lines, refreshed as output arrives) -----------
BUF=()
emit() {  # $1 = line (may contain colour; long lines wrap, never mangle)
    if [ "$PLAIN" = 1 ]; then
        printf '%s\n' "$1"
    else
        if [ "${#1}" -le $((COLS - 2)) ]; then
            BUF+=("$1")
        else
            wrap_into "$1"
            BUF+=("${CHUNKS[@]}")
        fi
        while [ "${#BUF[@]}" -gt "$BOTTOM_H" ]; do BUF=("${BUF[@]:1}"); done
        redraw_log
    fi
}

redraw_log() {
    [ "$PLAIN" = 1 ] && return
    local n=${#BUF[@]} r idx
    for ((r = LOG_TOP; r <= ROWS; r++)); do
        at "$r" 1; clr_line
        idx=$(( r - (ROWS - n + 1) ))
        if [ "$n" -gt 0 ] && [ "$idx" -ge 0 ] && [ "$idx" -lt "$n" ]; then
            printf '%s' "${BUF[$idx]}"
        fi
    done
    at "$ROWS" 1
}

# --- step screens ------------------------------------------------------------
NEXT_ITEM=0
STEP_CUR=0
STEP_TOT=0
STEP_TITLE=""
declare -A STEP_AT=()             # row -> rendered line (for repaint)

paint_header() {
    at 1 1; printf '%s%s%s' "$DIM" "$RULE" "$RESET"
    at 2 1; printf '%sStep %s of %s — %s%s' "$BOLD" "$STEP_CUR" "$STEP_TOT" "$STEP_TITLE" "$RESET"
    at 3 1; printf '%s%s%s' "$DIM" "$RULE" "$RESET"
    at "$SEP" 1; printf '%s%s%s' "$DIM" "$RULE" "$RESET"
}

step_begin() {  # $1 = current step, $2 = total, $3 = title
    STEP_CUR=$1; STEP_TOT=$2; STEP_TITLE=$3
    STEP_AT=()
    NEXT_ITEM=5
    ui_clear
    if [ "$PLAIN" = 1 ]; then
        printf '\n%s\nStep %s of %s — %s\n%s\n\n' "$RULE" "$1" "$2" "$3" "$RULE"
    else
        paint_header
        ui_region "$LOG_TOP" "$ROWS"
        BUF=()
        at "$ROWS" 1
    fi
}

paint_line() {  # $1 = row, $2 = full line text (clipped to the screen width)
    local t
    t="$(clip_line "$2")"
    at "$1" 1; clr_line; printf '%s' "$t"
    STEP_AT[$1]="$t"
}

step_item() {  # $1 = text; green checkmark (or red cross with a 2nd arg 'bad')
    local mark="${GREEN}✓${RESET}"
    [ "${2:-ok}" = bad ] && mark="${RED}✗${RESET}"
    if [ "$PLAIN" = 1 ]; then
        printf '  %s %s\n' "$mark" "$1"
    else
        paint_line "$NEXT_ITEM" "  $mark $1"
    fi
    NEXT_ITEM=$((NEXT_ITEM + 1))
}

step_note() {  # $1 = text (no icon)
    if [ "$PLAIN" = 1 ]; then
        printf '  %s\n' "$1"
    else
        paint_line "$NEXT_ITEM" "  $1"
    fi
    NEXT_ITEM=$((NEXT_ITEM + 1))
}

step_ask() {  # top-area marker: input is expected at the bottom ($1 = optional text)
    [ "$PLAIN" = 1 ] && return
    local msg="${1:-answer the y/n question at the bottom}"
    paint_line "$NEXT_ITEM" "${YELLOW}  -> Needs your input: $msg${RESET}"
}

step_hint() {  # $1 = optional message
    local msg="${1:-Press Enter to continue...}"
    if [ "$PLAIN" = 1 ]; then
        printf '\n%s ' "$msg"
        read -r _ || true
        printf '\n'
        return
    fi
    local row=$((NEXT_ITEM + 1)) cm
    [ "$row" -gt $((SEP - 1)) ] && row=$((SEP - 1))
    cm="$(clip_line "$msg")"
    at "$row" 1; clr_line; printf '%s%s%s' "$DIM" "$cm" "$RESET"
    at "$row" $(( ${#cm} + 1 ))
    read -r _ || true
}

repaint() {  # re-render the current step screen (after a full-screen detour)
    [ "$PLAIN" = 1 ] && return
    ui_clear
    paint_header
    ui_region "$LOG_TOP" "$ROWS"
    local r
    for ((r = 5; r < SEP; r++)); do
        if [ -n "${STEP_AT[$r]:-}" ]; then
            at "$r" 1; clr_line; printf '%s' "${STEP_AT[$r]}"
        fi
    done
    redraw_log
    at "$ROWS" 1
}

ui_confirm() {  # $1 = question, $2 = default answer (y|n).  0 = yes
    local text="$1" d="${2:-n}" prompt ans
    if [ "$d" = y ]; then prompt='  Are you sure? [Y/n]: '; else prompt='  Are you sure? [y/N]: '; fi
    if [ "$PLAIN" = 1 ]; then
        printf '  %s%s%s\n' "$YELLOW" "$text" "$RESET"
        printf '%s' "$prompt"
        read -r ans || true
        printf '\n'
    else
        emit "  ${YELLOW}$text${RESET}"
        emit "$prompt"
        at "$ROWS" $(( ${#prompt} + 1 ))
        read -r ans || true
    fi
    ans="${ans:-$d}"
    case "$ans" in
        [Yy]*)
            [ "$PLAIN" = 0 ] && emit "${DIM}  -> confirmed${RESET}"
            return 0 ;;
        *)
            [ "$PLAIN" = 0 ] && emit "${YELLOW}  -> skipped${RESET}"
            return 1 ;;
    esac
}

ask_key() {  # collect + validate the DeepSeek key into $KEY ('' = nothing given)
    KEY=''
    local msg='  Key: ' input key file
    while :; do
        input=''
        if [ "$PLAIN" = 1 ]; then
            printf '  Paste your DeepSeek API key, or type the filename containing it.\n'
            printf '%s' "$msg"
            read -r input || true
            printf '\n'
        else
            emit "  Paste your DeepSeek API key, or type the filename containing it."
            emit "$msg"
            at "$ROWS" $(( ${#msg} + 1 ))
            read -r input || true
            emit ''
        fi
        [ -z "$input" ] && return 0                    # nothing entered
        input="${input#"${input%%[![:space:]]*}"}"     # trim surrounding whitespace
        input="${input%"${input##*[![:space:]]}"}"
        case "$input" in
            \"*\"|\'*\') input="${input:1:${#input}-2}" ;;
        esac
        input="${input/#\~/$HOME}"
        if [[ "$input" =~ ^sk-[A-Za-z0-9]{16,}$ ]]; then
            KEY="$input"; return 0                     # the key itself
        fi
        file="$input"
        if [ ! -r "$file" ] && [ -r "$HOME/$input" ]; then
            file="$HOME/$input"            # no path given: assume ~/
        fi
        if [ -f "$file" ] && [ -r "$file" ]; then
            key="$(grep -oE 'sk-[A-Za-z0-9]{16,}' "$file" 2>/dev/null | head -n1)"
            if [ -n "$key" ]; then
                KEY="$key"; return 0                   # a file that holds the key
            fi
            emit "${YELLOW}  That file contains no DeepSeek key (sk-...) — try again.${RESET}"
        else
            emit "${YELLOW}  Not a DeepSeek key, and no readable file — try again (a plain filename is looked up in ~/).${RESET}"
        fi
    done
}

finish_screen() {  # $@ = message lines
    ui_clear
    printf '\n%s\n\n' "$RULE"
    local ln
    for ln in "$@"; do printf '  %s\n' "$ln"; done
    printf '\n%s\n' "$RULE"
    printf '\nPress Enter to return to the menu... '
    read -r _ || true
    printf '\n'
}

# --- action layer ------------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

say_cmd() {  # show the (possibly redacted) command line
    if [ "$PLAIN" = 1 ]; then
        printf '%s$ %s%s\n' "$DIM" "$1" "$RESET"
    else
        emit "${DIM}\$ $1${RESET}"
    fi
}

stream() {  # run via bash -c; output line-by-line into the log zone; rc kept
    local rc=0 line
    if [ "$PLAIN" = 1 ]; then
        bash -c "$1" 2>&1
        return $?
    fi
    STREAM_TMP="$(mktemp 2>/dev/null)" || STREAM_TMP="/tmp/hermes-replicant.$$.rc"
    while IFS= read -r line; do
        emit "${line%$'\r'}"
    done < <( { if have stdbuf; then stdbuf -oL -eL bash -c "$1" 2>&1
                else bash -c "$1" 2>&1; fi
              printf '%s' "$?" >"$STREAM_TMP"; } )
    rc="$(cat "$STREAM_TMP" 2>/dev/null)"
    rm -f "$STREAM_TMP"; STREAM_TMP=""
    case "$rc" in ''|*[!0-9]*) rc=1 ;; esac
    return "$rc"
}

act() {  # $1 = command; $2.. = dry-run simulated output lines. REAL: run it.
    local cmd="$1" l; shift
    say_cmd "$cmd"
    if [ "$DRY" = 1 ]; then
        for l in "$@"; do emit "$l"; done
        return 0
    fi
    stream "$cmd"
}

act_hide() {  # $1 = real command; $2 = redacted display; $3.. = dry lines
    local cmd="$1" disp="$2" l; shift 2
    say_cmd "$disp"
    if [ "$DRY" = 1 ]; then
        for l in "$@"; do emit "$l"; done
        return 0
    fi
    stream "$cmd"
}

fail_exit() {  # $1 = message. Ends the script with the error visible.
    if [ "$NEXT_ITEM" -ge 5 ] && [ "$NEXT_ITEM" -lt $((SEP - 1)) ]; then
        step_item "$1" bad
    fi
    cleanup
    printf '\n%s✗ ERROR: %s%s\n\n' "$RED" "$1" "$RESET"
    printf '%sThe installer stopped here. Fix the above, then re-run — it is safe to re-run.%s\n\n' "$DIM" "$RESET"
    exit 1
}

stop_exit() {  # $1 = message. Graceful stop (not an installation error).
    cleanup
    printf '\n%s%s%s\n\n' "$YELLOW" "$1" "$RESET"
    exit 1
}

hcmd() {  # build a Hermes command string (quoted for bash -c AND display)
    if [ -n "$PROFILE" ]; then printf 'hermes -p %q' "$PROFILE"
    else printf 'hermes'; fi
    local a; for a in "$@"; do printf ' %q' "$a"; done
}

# --- intro screen ------------------------------------------------------------

intro_screen() {
    ui_clear
    local w=62 hl pad ind=''
    hl="$(printf '%*s' "$w" '')"
    hl="${hl// /─}"
    if [ "$COLS" -ge 70 ] && [ "$PLAIN" = 0 ]; then
        pad=$(( (COLS - w - 2) / 2 ))
        ind="$(printf '%*s' "$pad" '')"
    fi
    boxrow() {  # $1 = content, $2 = 'c' to centre
        local s="$1" pl pr
        if [ "${2:-l}" = c ]; then
            pl=$(( (w - ${#s}) / 2 )); pr=$(( w - pl - ${#s} ))
            printf '%*s%s%*s' "$pl" '' "$s" "$pr" ''
        else
            printf '%s%*s' "$s" "$(( w - ${#s} ))" ''
        fi
    }
    if [ -n "$ind" ]; then
        printf '\n\n%s┌%s┐\n' "$ind" "$hl"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow 'DECWAR REPLICANT INSTALLER' c)"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  This program will install and configure the DECWAR')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  companion for Hermes Agent.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Please see github.com/decwarorg/replicant for details.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Required: git and curl, plus an internet connection')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  for the unattended install.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  It also installs the DECWAR skill and SOUL.md.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Make sure this machine is online before continuing.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  ')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '[ Enter ] to continue' c)"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s└%s┘\n' "$ind" "$hl"
    else
        printf '\n\nDECWAR REPLICANT INSTALLER\n\n'
        printf 'This program will install and configure the DECWAR\n'
        printf 'companion for Hermes Agent.\n\n'
        printf 'Please see github.com/decwarorg/replicant for details.\n\n'
        printf 'Required: git and curl, plus an internet connection\n'
        printf 'for the unattended install.\n'
        printf 'It also installs the DECWAR skill and SOUL.md.\n\n'
        printf 'Make sure this machine is online before continuing.\n'
        printf '\n\n'
        printf '[ Enter ] to continue\n'
    fi
    if [ "$DRY" = 1 ]; then
        printf '\n%s  *** DRY RUN — nothing will be installed or changed. ***%s\n' "$YELLOW" "$RESET"
    fi
    printf '\n  Press Enter to continue... '
    read -r _ || exit 0
    printf '\n'
}

# --- install Hermes Agent ------------------------------------------

walk_hermes() {
    local DS='' KEY=''
    step_begin 1 6 "Checking your system"
    ARCH="$(uname -m)"
    act "uname -m" "$ARCH"
    case "$ARCH" in
        aarch64|x86_64) step_item "64-bit system ($ARCH)" ;;
        *)
            step_item "64-bit OS required (found: $ARCH)" bad
            fail_exit "unsupported CPU: $ARCH — Hermes needs a 64-bit OS (on a Raspberry Pi, use 64-bit Raspberry Pi OS)"
            ;;
    esac
    if [ "$DRY" = 1 ]; then
        act "curl -sI --max-time 5 https://hermes-agent.nousresearch.com | head -1" "HTTP/2 200"
        step_item "Internet connection available"
    elif curl -sI --max-time 5 https://hermes-agent.nousresearch.com >/dev/null 2>&1; then
        say_cmd "curl -sI --max-time 5 https://hermes-agent.nousresearch.com | head -1"
        emit "HTTP/2 200"
        step_item "Internet connection available"
    else
        step_item "No internet connection" bad
        fail_exit "no internet — connect this machine to the network, then re-run"
    fi
    missing=""
    for t in git curl; do have "$t" || missing="$missing $t"; done
    act "command -v git curl" "/usr/bin/git" "/usr/bin/curl"
    if [ "$DRY" = 0 ] && [ -n "$missing" ]; then
        step_item "Missing:${missing}" bad
        fail_exit "install them first:  sudo apt-get install -y${missing}  then re-run"
    fi
    step_item "git and curl present"
    step_hint

    step_begin 2 6 "Your DeepSeek API key"
    step_note "Hermes uses a large language model as its brains — that needs an API key."
    step_note "We recommend DeepSeek if you have no preference"
    step_note "${DIM}    - very cheap — a few dollars a month even with serious use${RESET}"
    step_note "${DIM}    - \$10 prepaid by PayPal or card will last months,${RESET}"
    step_note "${DIM}        No subscription needed, no surprise bills${RESET}"
    step_note "${DIM}    - more than enough for the simple world of DECWAR play${RESET}"
    step_note "Get one at:  platform.deepseek.com -> API Keys -> create a key"
    step_ask
    if ui_confirm "Will you use DeepSeek?" y; then
        DS=1
        if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
            KEY="$(printf '%s' "$DEEPSEEK_API_KEY" | tr -d '[:space:]')"
            if [[ ! "$KEY" =~ ^sk-[A-Za-z0-9]{16,}$ ]]; then
                step_item "DEEPSEEK_API_KEY does not look like a key" bad
                fail_exit "the DEEPSEEK_API_KEY value should look like 'sk-…'"
            fi
            emit "${DIM}(using the key from the DEEPSEEK_API_KEY environment variable)${RESET}"
        elif [ -n "$KEY_FILE" ]; then
            KEY="$(grep -oE 'sk-[A-Za-z0-9]{16,}' "$KEY_FILE" 2>/dev/null | head -n1)"
            if [ -z "$KEY" ]; then
                KEY="$(head -n1 "$KEY_FILE" 2>/dev/null | tr -d '[:space:]')"
            fi
            if [[ ! "$KEY" =~ ^sk-[A-Za-z0-9]{16,}$ ]]; then
                step_item "No DeepSeek key found in that file" bad
                fail_exit "$KEY_FILE contains no DeepSeek key (sk-…)"
            fi
            emit "${DIM}(using the key from $KEY_FILE)${RESET}"
        else
            step_ask "paste your key (or key file) at the bottom"
            ask_key
            if [ -z "$KEY" ]; then
                stop_exit "No key given — the installer stops here. Create one at platform.deepseek.com, then run it again."
            fi
        fi
        local len=${#KEY}
        step_item "API key received ($len characters)"
        if [ "$DRY" = 1 ]; then
            emit "${DIM}(dry run — the key is not stored anywhere)${RESET}"
        else
            emit "${DIM}(the key is stored in step 4 — it is never shown)${RESET}"
        fi
    else
        DS=0
        step_note "No problem — you can connect your preferred model after the install is complete:"
        step_note "${DIM}    hermes config set model.provider <provider>${RESET}"
        step_note "${DIM}    hermes config set model.default <model>${RESET}"
        step_note "${DIM}    hermes config set <PROVIDER>_API_KEY ********${RESET}"
    fi
    step_hint

    step_begin 3 6 "Installing Hermes Agent"
    step_note "${YELLOW}Note: the browser stack (Chromium, ~600 MB) is skipped to keep the install lean.${RESET}"
    step_note "${YELLOW}Enable it later with:  hermes pm install agent-browser${RESET}"
    if have hermes || [ -x "$HOME/.local/bin/hermes" ]; then
        if have hermes; then HERMES_BIN="$(command -v hermes)"
        else HERMES_BIN="$HOME/.local/bin/hermes"; export PATH="$HOME/.local/bin:$PATH"; fi
        HVER="$("$HERMES_BIN" --version 2>/dev/null | head -1)"
        say_cmd "$HERMES_BIN --version"
        emit "$HVER"
        step_item "Hermes is already installed — skipping the download"
    else
        step_note "${DIM}Network note: this step fetches over HTTP/1.1 — avoids a known curl HTTP/2 failure on some networks.${RESET}"
        emit "Downloading the official installer ..."
        # Some networks break libcurl's HTTP/2 transfers to GitHub's release
        # CDN (curl exit 16, "Error in the HTTP2 framing layer"), and the
        # upstream installer's pinned-uv download has no fallback for that
        # error. Give this step's curl traffic HTTP/1.1 via a throwaway
        # config dir — CURL_HOME — so no file of the user's is touched.
        if [ "$DRY" = 0 ]; then
            CURLH="$(mktemp -d 2>/dev/null)" || CURLH="/tmp/hermes-replicant-curl.$$"
            mkdir -p "$CURLH"
            if [ -f "$HOME/.curlrc" ]; then
                cat "$HOME/.curlrc" > "$CURLH/.curlrc" 2>/dev/null || :
            fi
            printf '\n--http1.1\n' >> "$CURLH/.curlrc"
            export CURL_HOME="$CURLH"
        fi
        if [ "$DRY" = 1 ]; then
            DL_TMP="/tmp/hermes-install.sh"
        else
            DL_TMP="$(mktemp 2>/dev/null)" || DL_TMP="/tmp/hermes-install.$$.sh"
        fi
        if act "curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o $DL_TMP"; then
            step_item "Installer downloaded"
        else
            fail_exit "the download failed — check your network connection"
        fi
        emit "Running the installer (unattended) — several minutes"
        step_note "${YELLOW}This takes a few minutes, don't abort.${RESET}"
        if act "bash $DL_TMP --non-interactive --skip-browser" \
               "==> Fetching Python runtime ..." \
               "==> Fetching Node.js ..." \
               "==> Installing dependencies ..." \
               "==> Building Hermes components ..." \
               "==> Installing the 'hermes' command ..." \
               "Installer finished."; then
            :
        else
            fail_exit "the Hermes installer failed — see the output above"
        fi
        if [ "$DRY" = 0 ]; then
            # undo this step's temporary resources (curl workaround, installer script)
            unset CURL_HOME
            [ -n "$CURLH" ] && rm -rf "$CURLH"
            CURLH=""
            rm -f "$DL_TMP"; DL_TMP=""
            export PATH="$HOME/.local/bin:$PATH"
            HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
            [ -n "$HERMES_BIN" ] || fail_exit "hermes was not found after the install — check ~/.local/bin, then re-run"
        else
            HERMES_BIN="hermes"
        fi
        step_item "Hermes runtime installed"
        step_item "'hermes' command ready"
        emit "${DIM}New shells will find 'hermes' too:  source ~/.bashrc${RESET}"
    fi
    # which home gets all of this?  (0 profiles -> default ~/.hermes; 1 -> use
    # it; several -> ask.  never creates a profile.)
    PROFILES=()
    if [ -d "$HOME/.hermes/profiles" ]; then
        while IFS= read -r _pr; do
            [ -n "$_pr" ] && PROFILES+=("$_pr")
        done < <(find "$HOME/.hermes/profiles" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | sort)
    fi
    case "${#PROFILES[@]}" in
        0)
            emit "No Hermes profile found — installing into the default setup (~/.hermes)"
            ;;
        1)
            PROFILE="$(basename "${PROFILES[0]}")"
            HERMES_HOME="$HOME/.hermes/profiles/$PROFILE"
            emit "Using your profile: $PROFILE"
            step_item "Agent home: profile '$PROFILE'"
            ;;
        *)
            emit "You have several Hermes profiles:"
            local i
            for i in "${!PROFILES[@]}"; do
                emit "  $((i+1))) $(basename "${PROFILES[$i]}")"
            done
            step_ask "answer the profile question at the bottom"
            local pmsg="  Which one gets the DECWAR companion? [1-${#PROFILES[@]}]: "
            while :; do
                local ans
                if [ "$PLAIN" = 1 ]; then
                    printf '%s' "$pmsg"
                    read -r ans || true
                    printf '\n'
                else
                    emit "$pmsg"
                    at "$ROWS" $(( ${#pmsg} + 1 ))
                    read -r ans || true
                fi
                case "$ans" in
                    ''|*[!0-9]*)
                        fail_exit "pick a number between 1 and ${#PROFILES[@]}" ;;
                    *)
                        if [ "$ans" -ge 1 ] && [ "$ans" -le "${#PROFILES[@]}" ]; then
                            PROFILE="$(basename "${PROFILES[$((ans-1))]}")"
                            HERMES_HOME="$HOME/.hermes/profiles/$PROFILE"
                            break
                        fi
                        fail_exit "pick a number between 1 and ${#PROFILES[@]}" ;;
                esac
            done
            emit "Using your profile: $PROFILE"
            step_item "Agent home: profile '$PROFILE'"
            ;;
    esac
    if [ -n "$PROFILE" ]; then HERMES_HINT="hermes -p $PROFILE"; else HERMES_HINT="hermes"; fi
    step_hint

    step_begin 4 6 "Connecting DeepSeek"
    if [ "$DS" = 1 ]; then
        local hh="${HERMES_HOME/#$HOME/\~}"
        if act "$(hcmd config set model.provider deepseek)" "✓ Set model.provider = deepseek"; then
            step_item "Provider set: deepseek"
        else
            fail_exit "could not set model.provider — see the output above"
        fi
        if act "$(hcmd config set model.default deepseek-flash)" "✓ Set model.default = deepseek-flash"; then
            step_item "Model set: deepseek-flash"
        else
            fail_exit "could not set model.default — see the output above"
        fi
        if act "$(hcmd config set model.base_url https://api.deepseek.com/v1)" "✓ Set model.base_url"; then
            :
        else
            fail_exit "could not set model.base_url — see the output above"
        fi
        if act_hide "$(hcmd config set DEEPSEEK_API_KEY "$KEY")" \
                    "hermes config set DEEPSEEK_API_KEY ********" \
                    "✓ Set DEEPSEEK_API_KEY (stored in $hh/.env)"; then
            step_item "API key stored ($hh/.env)"
        else
            fail_exit "could not store the API key — see the output above"
        fi
        emit "For DECWAR play, 'medium' reasoning is the default — good for regular"
        emit "sessions; raise it to 'max' if you want deeper analysis."
        step_ask "answer the reasoning question at the bottom"
        if ui_confirm "Set reasoning to medium for this agent?" y; then
            if act "$(hcmd config set --force agent.reasoning_effort medium)" "✓ Set agent.reasoning_effort = medium"; then
                step_item "Reasoning effort set to medium"
                step_note "${DIM}(you can raise it to 'max' later on)${RESET}"
            else
                fail_exit "could not set agent.reasoning_effort — see the output above"
            fi
        else
            step_note "${YELLOW}Reasoning not changed — set it later:${RESET}"
            step_note "${DIM}    $HERMES_HINT config set --force agent.reasoning_effort medium${RESET}"
        fi
    else
        step_note "${YELLOW}DeepSeek connection skipped — connect your preferred model later.${RESET}"
    fi
    step_hint

    step_begin 5 6 "Wiring the skills"
    SKILLS_DIR="$HERMES_HOME/skills"
    if [ "$DRY" = 0 ]; then mkdir -p "$SKILLS_DIR"; fi
    emit "Linking the package skills (a symlink means package updates reach them):"
    local n=0 d b
    for d in "$PKG_DIR"/skills/*/; do
        b="$(basename "$d")"
        if [ "$DRY" = 0 ]; then ln -sfn "$d" "$SKILLS_DIR/$b"; fi
        emit "  $b"
        n=$((n+1))
    done
    step_item "$n skill(s) linked"
    local SF="$HERMES_HOME/SOUL.md"
    if [ -e "$SF" ]; then
        step_ask "answer the y/n question at the bottom"
        if ui_confirm "You already have a SOUL.md. Overwrite it with the package version?" y; then
            if [ "$DRY" = 0 ]; then cp "$PKG_DIR/hermes-specific/SOUL.md" "$SF"; fi
            step_item "SOUL.md replaced with the package version"
        else
            step_item "SOUL.md kept (your existing one)"
            step_note "${DIM}(back it up, then re-run and answer y, if you want the package version)${RESET}"
        fi
    else
        if [ "$DRY" = 0 ]; then cp "$PKG_DIR/hermes-specific/SOUL.md" "$SF"; fi
        step_item "SOUL.md installed"
    fi
    step_hint

    step_begin 6 6 "Final check"
    step_note "${YELLOW}Ignore small error messages below.${RESET}"
    step_note "${DIM}They will generally not impact Hermes use${RESET}"
    act "$(hcmd doctor)" "core checks passed — advisory notes only" || true
    if [ "$DRY" = 1 ]; then
        step_item "Skills verified"
    else
        local ok=1 s
        for s in decwar; do
            [ -d "$SKILLS_DIR/$s" ] || ok=0
        done
        [ "$ok" = 1 ] && step_item "Skills verified" || fail_exit "skill missing or broken in $SKILLS_DIR — re-run this installer"
    fi
    if [ "$DS" = 1 ]; then
        if [ "$DRY" = 1 ]; then
            act_hide "$(hcmd -z 'Reply with exactly: OK')" \
                     "$HERMES_HINT -z 'Reply with exactly: OK'" \
                     "model replied: OK"
            step_item "DeepSeek round-trip OK"
            step_item "Hermes Agent is ready"
        else
            say_cmd "$HERMES_HINT -z 'Reply with exactly: OK'"
            if ! reply="$(bash -c "$(hcmd -z 'Reply with exactly: OK')" 2>&1)"; then
                emit "${reply//$'\n'/ }"
                fail_exit "the round-trip failed — check the key; then run 'hermes doctor'"
            fi
            emit "${reply//$'\n'/ }"
            case "$reply" in
                *OK*)
                    step_item "DeepSeek round-trip OK"
                    step_item "Hermes Agent is ready" ;;
                *)
                    fail_exit "the model replied unexpectedly — check the key and the model settings" ;;
            esac
        fi
    else
        step_note "${YELLOW}Round-trip test skipped — no model configured yet.${RESET}"
        step_item "Hermes Agent is installed"
    fi
    step_hint

    if [ "$DS" = 1 ]; then
        finish_screen \
            "${GREEN}✓${RESET} Hermes Agent is ready." \
            "" \
            "Start by typing \`hermes\` on the command line" \
            "Try: help me play DECWAR" \
            "" \
            "${DIM}Updates later: $SELF_DIR/skills/update.sh — or run this installer again.${RESET}"
    else
        finish_screen \
            "${GREEN}✓${RESET} Hermes Agent is installed." \
            "" \
            "Connect your preferred model first (commands in step 2)," \
            "then start by typing \`hermes\` on the command line." \
            "" \
            "${DIM}Updates later: $SELF_DIR/skills/update.sh — or run this installer again.${RESET}"
    fi
}

# --- update/restore core skills ------------------------------------

walk_skills() {
    step_begin 1 3 "Checking the package"
    step_ask
    if ! ui_confirm "This will update the replicant package from GitHub (core-skill edits are replaced)." y; then
        finish_screen "${YELLOW}Nothing was changed.${RESET}"
        return
    fi
    if [ "$DRY" = 0 ] && ! git -C "$SELF_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        fail_exit "$SELF_DIR is not a git repository — reinstall the package first"
    fi
    act "git -C $SELF_DIR rev-parse --short HEAD" "$(git -C "$SELF_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    step_item "Package repository found"
    if [ "$DRY" = 1 ]; then
        act "curl -sI --max-time 5 https://github.com | head -1" "HTTP/2 200"
        step_item "Internet connection available"
    elif curl -sI --max-time 5 https://github.com >/dev/null 2>&1; then
        say_cmd "curl -sI --max-time 5 https://github.com | head -1"
        emit "HTTP/2 200"
        step_item "Internet connection available"
    else
        step_item "No internet connection" bad
        fail_exit "no internet — connect and re-run"
    fi
    step_hint

    step_begin 2 3 "Fetching updates from GitHub"
    if [ "$DRY" = 1 ]; then
        act "chmod -R +w $SELF_DIR/skills"
        act "git -C $SELF_DIR checkout -- skills"
        act "git -C $SELF_DIR pull --ff-only" "Fast-forward — 2 files changed"
        act "chmod -R -w $SELF_DIR/skills"
        step_item "Package updated"
        step_item "Core skills restored and write-protected"
    else
        if ! act "chmod -R +w '$SELF_DIR/skills'"; then
            fail_exit "could not unlock the skills directory — check its permissions"
        fi
        emit "Restoring the core skills (any local edits to them are replaced)"
        if ! act "git -C $SELF_DIR checkout -- skills"; then
            fail_exit "could not restore the skills directory — see the output above"
        fi
        if act "git -C $SELF_DIR pull --ff-only"; then
            step_item "Package updated"
        else
            fail_exit "the update failed — see the output above (offline, or local changes outside skills/?)"
        fi
        if ! act "chmod -R -w '$SELF_DIR/skills'"; then
            step_note "${YELLOW}Note: could not re-lock the skills directory (harmless).${RESET}"
        fi
        step_item "Core skills restored and write-protected"
    fi
    step_hint

    step_begin 3 3 "Verifying the skills"
    n=0
    for d in "$SELF_DIR"/skills/*/; do [ -d "$d" ] && n=$((n+1)); done
    act "ls $SELF_DIR/skills" "decwar  README.txt  curate.sh  protect.sh  update.sh"
    step_item "$n core skills verified"
    step_hint

    finish_screen \
        "${GREEN}✓${RESET} Core skills are up to date." \
        "" \
        "Your own files (SOUL.md) were left alone."
}

# --- main --------------------------------------------------------------------

main() {
    if [ -n "$KEY_FILE" ] && [ ! -f "$KEY_FILE" ]; then
        fail_exit "no such file: $KEY_FILE"
    fi
    intro_screen
    local choice
    while :; do
        ui_clear
        printf '\n%sDECWAR REPLICANT INSTALLER%s\n' "$BOLD" "$RESET"
        if [ "$DRY" = 1 ]; then
            printf '%s(dry run — nothing will be installed or changed)%s\n' "$DIM" "$RESET"
        fi
        printf '\nWhat would you like to do?\n\n'
        printf '  1) Install Hermes Agent\n'
        printf '  2) Update/restore Core Skills from github\n'
        printf '  3) Exit\n\n'
        printf 'Choice [1-3]: '
        read -r choice || exit 0
        printf '\n'
        case "$choice" in
            1) walk_hermes ;;
            2) walk_skills ;;
            3) ui_clear
               printf '\n  Exiting — nothing else was changed.\n\n'
               exit 0 ;;
            *) printf '%s  Please enter 1, 2 or 3.%s\n' "$YELLOW" "$RESET"
               sleep 1 ;;
        esac
    done
}

main "$@"
