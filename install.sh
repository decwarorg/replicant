#!/usr/bin/env bash
#
# agent-pdp1 — installer
#
# The unified installer: basic PiDP-1 setup AND the Hermes agent, one script.
# DRY_RUN=1 runs the whole flow as a no-op demo — nothing is changed.
#
#   1) Install basic setup   — PiDP-1 package update + full rebuild, agent
#                              tools, 1040 smoke test. Leaves the machine
#                              stopped for a clean start.
#   2) Install Hermes Agent  — unattended Hermes install, connects DeepSeek
#                              (or leaves that for later), wires the PDP-1
#                              skills, SOUL.md and pdp1-learnings into the
#                              agent, verifies with a real round-trip.
#   3) Update/restore Core Skills — pull the latest agent-pdp1 from github;
#                              core-skill edits are replaced, your own files
#                              (pdp1-learnings, SOUL.md) are left alone.
#   4) Exit
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
PIDP1_DIR="${PIDP1_DIR:-/opt/pidp1}"
EMU_DIR="$PIDP1_DIR/src/blincolnlights/pdp1"
BL_DIR="$(dirname "$EMU_DIR")"
PANEL_BIN="$BL_DIR/panel_pidp1/panel_pidp1"
NC=""
EMU_PID=""
STREAM_TMP=""
DL_TMP=""
case "${DRY_RUN:-0}" in 1|yes|true) DRY=1 ;; *) DRY=0 ;; esac
KEY_FILE="${1:-}"
KEY=""
DS=""
HERMES_BIN=""
HERMES_HINT=""
PROFILE=""
HERMES_HOME="$HOME/.hermes"
SKIP_EMU=""
SUDO_OK=0
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
    if [ -n "$EMU_PID" ]; then
        kill "$EMU_PID" 2>/dev/null
        EMU_PID=""
    fi
    [ -n "$STREAM_TMP" ] && rm -f "$STREAM_TMP"
    [ -n "$DL_TMP" ] && rm -f "$DL_TMP"
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
    STREAM_TMP="$(mktemp 2>/dev/null)" || STREAM_TMP="/tmp/agent-pdp1.$$.rc"
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

admin_access_screen() {
    if [ "$PLAIN" = 1 ]; then
        printf '\n== Administrator access ==\n'
        printf '  A few steps need admin rights (package ownership, the PDP-1\n'
        printf '  rebuild, the tool links). sudo will ask for your password ONCE.\n\n'
        printf '  Press Enter, then type your password when sudo asks: '
        read -r _ || true
        printf '\n'
        return 0
    fi
    ui_clear
    printf '\n%s%s%s\n' "$DIM" "$RULE" "$RESET"
    printf '%sAdministrator access%s\n' "$BOLD" "$RESET"
    printf '%s%s%s\n\n' "$DIM" "$RULE" "$RESET"
    printf '  A few steps need admin rights (package ownership, the PDP-1\n'
    printf '  rebuild, the tool links). sudo will ask for your password ONCE.\n\n'
    printf '  Press Enter, then type your password when sudo asks.\n\n'
    read -r _ || true
    printf '\n'
}

ensure_sudo() {  # one password prompt up-front; afterwards sudo -n everywhere
    [ "$SUDO_OK" = 1 ] && return 0
    if [ "$DRY" = 1 ]; then
        emit "${DIM}(dry run — sudo would ask for your password once, at this point)${RESET}"
        SUDO_OK=1
        return 0
    fi
    if sudo -n true 2>/dev/null; then
        SUDO_OK=1
        emit "${DIM}admin rights already available (sudo wants no password)${RESET}"
        return 0
    fi
    admin_access_screen
    if sudo -v; then
        SUDO_OK=1
        repaint
        emit "${GREEN}admin rights ok — password cached for this session${RESET}"
    else
        fail_exit "sudo failed — the next steps need administrator rights"
    fi
}

act_sudo() {  # like act, for commands that already carry 'sudo -n'
    ensure_sudo
    act "$@"
    local rc=$?
    if [ "$DRY" = 0 ] && [ "$rc" = 0 ]; then sudo -n -v 2>/dev/null || true; fi
    return "$rc"
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

pdp1_running() {  # names of still-running PiDP-1 processes (space separated)
    local p out=""
    for p in pdp1 pdp1_periph panel_pidp1 panel_pdp1; do
        pgrep -x "$p" >/dev/null 2>&1 && out="$out $p"
    done
    printf '%s' "${out# }"
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
        printf '%s│%s│\n' "$ind" "$(boxrow 'AGENT-PDP1 INSTALLER' c)"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  This program will install and configure the Agent-pdp1')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  package in the /opt directory.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Please see github.com/obsolescence/agent-pdp1 for details.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Required: a Pi with 4GB (2GB might work, untested though)')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  and sufficient free space on the SD card (~4GB).')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Alternatively, this will install on Linux laptops as well.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Before continuing, make sure the Pi is connected to the')"
        printf '%s│%s│\n' "$ind" "$(boxrow '  Internet and that the pidp1 package is already installed.')"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s│%s│\n' "$ind" "$(boxrow '[ Enter ] to continue' c)"
        printf '%s│%s│\n' "$ind" "$(boxrow '')"
        printf '%s└%s┘\n' "$ind" "$hl"
    else
        printf '\n\nAGENT-PDP1 INSTALLER\n\n'
        printf 'This program will install and configure the Agent-pdp1\n'
        printf 'package in the /opt directory.\n\n'
        printf 'Please see github.com/obsolescence/agent-pdp1 for details.\n\n'
        printf 'Required: a Pi with 4GB (2GB might work, untested though)\n'
        printf 'and sufficient free space on the SD card (~4GB).\n'
        printf 'Alternatively, this will install on Linux laptops as well.\n\n'
        printf 'Before continuing, make sure the Pi is connected to the\n'
        printf 'Internet and that the pidp1 package is already installed.\n\n'
        printf '[ Enter ] to continue\n'
    fi
    if [ "$DRY" = 1 ]; then
        printf '\n%s  *** DRY RUN — nothing will be installed or changed. ***%s\n' "$YELLOW" "$RESET"
    fi
    printf '\n  Press Enter to continue... '
    read -r _ || exit 0
    printf '\n'
}

# --- option 1: install basic setup -------------------------------------------

walk_basic() {
    step_begin 1 5 "Checking your system"
    ARCH="$(uname -m)"
    act "uname -m" "$ARCH"
    case "$ARCH" in
        aarch64|x86_64) step_item "64-bit system ($ARCH)" ;;
        *) step_item "System: $ARCH" ;;
    esac
    OS_NAME="unknown"
    if [ -r /etc/os-release ]; then
        OS_NAME="$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}")"
    fi
    act "grep PRETTY_NAME /etc/os-release" "PRETTY_NAME=\"$OS_NAME\""
    step_note "${DIM}$OS_NAME — information only, no consequences.${RESET}"
    if [ "$DRY" = 1 ]; then
        act "curl -sI --max-time 5 https://github.com | head -1" "HTTP/2 200"
        step_item "Internet connection available"
    elif curl -sI --max-time 5 https://github.com >/dev/null 2>&1; then
        say_cmd "curl -sI --max-time 5 https://github.com | head -1"
        emit "HTTP/2 200"
        step_item "Internet connection available"
    else
        step_item "No internet connection" bad
        fail_exit "no internet — connect the Pi to the network, then re-run"
    fi
    if [ "$DRY" = 1 ]; then
        act "df -h / | tail -1" "/dev/root  59G  52G  4.8G  92% /"
        step_item "Free space on the SD card (4.8 GB free)"
    else
        AV_FREE="$(df -Pk / | awk 'NR==2 {print $4}')"
        say_cmd "df -h / | tail -1"
        emit "$(df -h / | tail -1)"
        if [ -n "$AV_FREE" ] && [ "$AV_FREE" -lt 2097152 ] 2>/dev/null; then
            step_item "Low disk space" bad
            step_note "${YELLOW}Less than 2 GB free — the Hermes install later wants ~4 GB.${RESET}"
        else
            step_item "Free space on the SD card ($(df -h / | awk 'NR==2 {print $4}') free)"
        fi
    fi
    step_hint

    step_begin 2 5 "Preparing the package"
    owner="$(stat -c '%U' "$SELF_DIR" 2>/dev/null || echo unknown)"
    if [ "$owner" = "$(id -un)" ]; then
        act "stat -c '%U' $SELF_DIR" "$(id -un)"
        step_item "Package ownership OK ($(id -un))"
    else
        step_ask
        if ui_confirm "This package is owned by '$owner'. Take ownership now (needs sudo)?" y; then
            ensure_sudo
            if act_sudo "sudo -n chown -R $(id -un):$(id -gn) '$SELF_DIR'"; then
                step_item "Ownership taken — now owned by $(id -un)"
            else
                fail_exit "could not take ownership of $SELF_DIR (sudo failed?)"
            fi
        else
            step_note "${YELLOW}Ownership not changed — package updates will fail.${RESET}"
            step_note "${DIM}You can do it later:  sudo chown -R $(id -un) $SELF_DIR${RESET}"
        fi
    fi
    missing=""
    for t in git make gcc python3; do have "$t" || missing="$missing $t"; done
    act "command -v git make gcc python3" "/usr/bin/git" "/usr/bin/make" "/usr/bin/gcc" "/usr/bin/python3"
    if [ "$DRY" = 1 ] || [ -z "$missing" ]; then
        step_item "Build tools present (git, make, gcc, python3)"
    else
        fail_exit "missing:$missing — install them first:  sudo apt-get install -y${missing}  then re-run"
    fi
    NC="$(command -v nc || command -v ncat || true)"
    if [ "$DRY" = 1 ]; then
        act "command -v nc" "/usr/bin/nc"
        step_item "nc available"
        NC="nc"
    elif [ -n "$NC" ]; then
        say_cmd "command -v nc"
        emit "$NC"
        step_item "nc available ($NC)"
    else
        fail_exit "missing: nc (or ncat) — install it first:  sudo apt-get install -y netcat-openbsd  then re-run"
    fi
    if [ "$DRY" = 0 ] && ! git -C "$EMU_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
        fail_exit "$EMU_DIR is not a valid git repository — install the PiDP-1 package first (see its docs)"
    fi
    act "git -C $PIDP1_DIR rev-parse --short HEAD" "$(git -C "$PIDP1_DIR" rev-parse --short HEAD 2>/dev/null || echo ad4c56a)"
    step_item "pidp1 package repository found"
    step_hint

    step_begin 3 5 "Updating PiDP-1 and rebuilding"
    step_ask
    if ui_confirm "This will stop the PDP-1, update the pidp1 package to the latest main, and rebuild all binaries." y; then
        ensure_sudo
        act "pdp1control stop" "stopping pdp1 ..." || true
        if ! have pdp1control; then
            emit "${DIM}(pdp1control not found — relying on the process check below)${RESET}"
        fi
        [ "$DRY" = 0 ] && sleep 2
        still=""
        [ "$DRY" = 0 ] && still="$(pdp1_running)"
        if [ -n "$still" ]; then
            fail_exit "PDP-1 processes still running:$still — stop them manually (pdp1control stop), then re-run"
        fi
        step_item "PDP-1 machine stopped"
        step_note "${DIM}Maintenance window: the machine is left stopped — restart later with 'pdp1control start'.${RESET}"
        BR="$(git -C "$PIDP1_DIR" branch --show-current 2>/dev/null || true)"
        UPD_OK=""
        if [ "$DRY" = 1 ]; then
            act "git -C $PIDP1_DIR pull --ff-only" "Already up to date."
            UPD_OK=1
        elif [ "$BR" = "main" ] && act "git -C $PIDP1_DIR pull --ff-only" "Already up to date."; then
            UPD_OK=1
        fi
        if [ -n "$UPD_OK" ]; then
            step_item "PiDP-1 package updated to the latest main"
        else
            step_ask
            if ui_confirm "Force the PiDP-1 package to the most up to date version? This is OK to do." y; then
                if act "git -C $PIDP1_DIR fetch origin" "From origin" " * branch            main       -> FETCH_HEAD" \
                   && act "git -C $PIDP1_DIR checkout -f -B main" "Switched to branch 'main'" \
                   && act "git -C $PIDP1_DIR reset --hard origin/main" "HEAD is now at the newest main"; then
                    step_item "PiDP-1 package forced to the most up to date version"
                else
                    fail_exit "the forced update failed — check the internet connection, then re-run"
                fi
            else
                stop_exit "Stopped — PiDP-1 was left unchanged. 'pdp1control start' brings the machine back; re-run and answer y to force the update later."
            fi
        fi
        if ! act "git -C $PIDP1_DIR submodule update --init --recursive"; then
            step_note "${YELLOW}Submodule update failed — check 'git -C $PIDP1_DIR status' when convenient.${RESET}"
        fi
        if [ "$DRY" = 1 ] || grep -q -- '--recompile' "$PIDP1_DIR/install/install.sh" 2>/dev/null; then
            step_note "${YELLOW}This takes a couple of minutes, don't abort.${RESET}"
            if act "bash $PIDP1_DIR/install/install.sh --recompile" \
                   "Recompiling all required PiDP-1 binaries..." \
                   "make: Entering directory '$EMU_DIR'" \
                   "make: Nothing to be done for 'all'." \
                   "  ... 12 more build targets ..." \
                   "Setting required access privileges to pidp1 simulator" \
                   "Done."; then
                if [ "$DRY" = 0 ]; then
                    [ -x "$EMU_DIR/pdp1" ] || fail_exit "the build did not produce $EMU_DIR/pdp1"
                    [ -x "$PANEL_BIN" ] || step_note "${YELLOW}WARNING: panel driver missing ($PANEL_BIN) — run:  bash $PIDP1_DIR/install/install.sh --recompile${RESET}"
                    if have getcap && ! getcap "$PANEL_BIN" 2>/dev/null | grep -q cap_sys_nice; then
                        step_note "${YELLOW}WARNING: panel RT privilege missing — run:  sudo setcap cap_sys_nice+ep $PANEL_BIN${RESET}"
                    fi
                fi
                step_item "All binaries rebuilt, panel privileges re-applied"
            else
                fail_exit "the PiDP-1 rebuild failed — see the output above"
            fi
        else
            step_note "${YELLOW}This pidp1 checkout has no --recompile helper — building the emulator only.${RESET}"
            if act "( cd $EMU_DIR && make )" "make: Nothing to be done for 'all'."; then
                [ "$DRY" = 0 ] && [ -x "$EMU_DIR/pdp1" ] || [ "$DRY" = 1 ] || fail_exit "make did not produce $EMU_DIR/pdp1"
                emit "for the full rebuild later:  bash $PIDP1_DIR/install/install.sh"
                emit "(answer n to everything except 'Make required PiDP-1 binaries?')"
                step_item "Emulator built"
            else
                fail_exit "make failed — see the output above"
            fi
        fi
    else
        step_note "${YELLOW}PiDP-1 update skipped — you can do it later:${RESET}"
        step_note "${DIM}    bash $PIDP1_DIR/install/install.sh --recompile${RESET}"
        SKIP_EMU=1
    fi
    step_hint

    step_begin 4 5 "Installing the agent tools"
    step_ask
    if ui_confirm "This will install pdp1dbg.py and pdp1_dpy into /usr/local/bin (sudo)." y; then
        DBG_TOOL="$SELF_DIR/skills/pdp1-debugging/scripts/pdp1dbg.py"
        DPY_TOOL="$SELF_DIR/skills/pdp1-type30-vision/scripts/pdp1_dpy"
        ensure_sudo
        if [ "$DRY" = 0 ]; then
            [ -f "$DBG_TOOL" ] || fail_exit "package incomplete — missing $DBG_TOOL"
            [ -f "$DPY_TOOL" ] || fail_exit "package incomplete — missing $DPY_TOOL"
        fi
        if act_sudo "sudo -n ln -sfn '$DBG_TOOL' /usr/local/bin/pdp1dbg.py"; then
            step_item "pdp1dbg.py installed"
        else
            fail_exit "could not install pdp1dbg.py (sudo failed?)"
        fi
        if act_sudo "sudo -n ln -sfn '$DPY_TOOL' /usr/local/bin/pdp1_dpy"; then
            step_item "pdp1_dpy installed"
        else
            fail_exit "could not install pdp1_dpy (sudo failed?)"
        fi
        if [ "$DRY" = 0 ]; then
            [ -x "$(readlink -f /usr/local/bin/pdp1dbg.py 2>/dev/null)" ] || fail_exit "the pdp1dbg.py link is broken"
            [ -x "$(readlink -f /usr/local/bin/pdp1_dpy 2>/dev/null)" ] || fail_exit "the pdp1_dpy link is broken"
            have pdp1dbg.py && have pdp1_dpy || fail_exit "installed, but /usr/local/bin is not on your PATH"
        fi
        act "command -v pdp1dbg.py pdp1_dpy" "/usr/local/bin/pdp1dbg.py" "/usr/local/bin/pdp1_dpy"
        step_item "Both tools available on PATH"
    else
        step_note "${YELLOW}Tools not installed — you can link them manually later.${RESET}"
    fi
    step_hint

    step_begin 5 5 "Testing the installation"
    if [ -n "$SKIP_EMU" ]; then
        step_note "${YELLOW}Smoke test skipped — the PiDP-1 update was skipped.${RESET}"
    else
        if [ "$DRY" = 1 ]; then
            act "$NC -w 1 127.0.0.1 1040 <<< hello" "hello — proto=1"
            step_item "Port 1040 answered (emulator OK)"
        else
            need=""
            if ! "$NC" -z 127.0.0.1 1040 2>/dev/null; then
                emit "starting a headless emulator for the test"
                ( cd "$EMU_DIR" && exec ./pdp1 -t ) & EMU_PID=$!
                need=1
            fi
            OUT=""; i=0
            while [ "$i" -lt 10 ]; do
                OUT="$("$NC" -w 1 127.0.0.1 1040 <<< 'hello' 2>/dev/null || true)"
                case "$OUT" in *proto=1*) break ;; esac
                i=$((i+1)); sleep 1
            done
            say_cmd "$NC -w 1 127.0.0.1 1040 <<< hello"
            emit "$OUT"
            case "$OUT" in
                *proto=1*) step_item "Port 1040 answered (emulator OK)" ;;
                *) fail_exit "no hello from port 1040: $OUT — check the build output above" ;;
            esac
            if [ -n "$need" ]; then
                kill "$EMU_PID" 2>/dev/null || true
                wait "$EMU_PID" 2>/dev/null || true
                EMU_PID=""
                emit "${DIM}test instance stopped${RESET}"
            fi
        fi
        still=""
        [ "$DRY" = 0 ] && still="$(pdp1_running)"
        if [ -n "$still" ]; then
            fail_exit "processes still running:$still — stop them manually (pdp1control stop)"
        fi
        act "pgrep -x pdp1" "(no output — nothing running)"
        step_item "Machine left in a clean state"
        step_item "Basic setup complete"
    fi
    step_hint

    finish_screen \
        "${GREEN}✓${RESET} Basic setup is complete." \
        "" \
        "Start the machine with:  pdp1control start" \
        "To add the Hermes agent, run 'Install Hermes Agent' next." \
        "" \
        "${DIM}Other agents: point yours at $SELF_DIR/skills — see README.md.${RESET}"
}

# --- option 2: install Hermes agent ------------------------------------------

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
        fail_exit "no internet — connect the Pi to the network, then re-run"
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
    step_note "${DIM}    - excellent for the simple, sparse world of PDP-1 programming${RESET}"
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
    step_note "${YELLOW}Note: the browser stack (Chromium, ~600 MB) is skipped to keep your Pi lean.${RESET}"
    step_note "${YELLOW}Enable it later with:  hermes pm install agent-browser${RESET}"
    if have hermes || [ -x "$HOME/.local/bin/hermes" ]; then
        if have hermes; then HERMES_BIN="$(command -v hermes)"
        else HERMES_BIN="$HOME/.local/bin/hermes"; export PATH="$HOME/.local/bin:$PATH"; fi
        HVER="$("$HERMES_BIN" --version 2>/dev/null | head -1)"
        say_cmd "$HERMES_BIN --version"
        emit "$HVER"
        step_item "Hermes is already installed — skipping the download"
    else
        emit "Downloading the official installer ..."
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
        emit "Running the installer (unattended) — several minutes on a Pi"
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
            local pmsg="  Which one gets the PDP-1 knowledge? [1-${#PROFILES[@]}]: "
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
        emit "For PDP-1 work, 'max' reasoning is strongly recommended — careful"
        emit "machine-level work, and only a small extra cost on DeepSeek."
        step_ask "answer the reasoning question at the bottom"
        if ui_confirm "Set reasoning to max for this agent?" y; then
            if act "$(hcmd config set --force agent.reasoning_effort max)" "✓ Set agent.reasoning_effort = max"; then
                step_item "Reasoning effort set to max"
                step_note "${DIM}(you might want to change that to 'high' later on)${RESET}"
            else
                fail_exit "could not set agent.reasoning_effort — see the output above"
            fi
        else
            step_note "${YELLOW}Reasoning not changed — set it later:${RESET}"
            step_note "${DIM}    $HERMES_HINT config set --force agent.reasoning_effort max${RESET}"
        fi
    else
        step_note "${YELLOW}DeepSeek connection skipped — connect your preferred model later.${RESET}"
    fi
    step_hint

    step_begin 5 6 "Wiring the PDP-1 skills"
    SKILLS_DIR="$HERMES_HOME/skills"
    if [ "$DRY" = 0 ]; then mkdir -p "$SKILLS_DIR"; fi
    emit "Linking the frozen skills (a symlink means package updates reach them):"
    if [ "$DRY" = 0 ]; then
        find "$SKILLS_DIR" -maxdepth 1 -type l -name 'pdp1-*' -delete 2>/dev/null || true
    fi
    local n=0 d b
    for d in "$PKG_DIR"/skills/*/; do
        b="$(basename "$d")"
        if [ "$DRY" = 0 ]; then ln -sfn "$d" "$SKILLS_DIR/$b"; fi
        emit "  $b"
        n=$((n+1))
    done
    step_item "$n PDP-1 skills linked"
    local LD="$SKILLS_DIR/pdp1-learnings"
    if [ -e "$LD" ]; then
        step_ask "answer the y/n question at the bottom"
        if ui_confirm "You already have pdp1-learnings. Overwrite it with the fresh template?" n; then
            if [ "$DRY" = 0 ]; then
                rm -rf "$LD"
                cp -r "$PKG_DIR/hermes-specific/pdp1-learnings" "$SKILLS_DIR/"
            fi
            step_item "pdp1-learnings replaced with the fresh template"
        else
            step_item "pdp1-learnings kept (your existing one)"
            step_note "${DIM}(back it up, then re-run and answer y, if you want the fresh template)${RESET}"
        fi
    else
        if [ "$DRY" = 0 ]; then cp -r "$PKG_DIR/hermes-specific/pdp1-learnings" "$SKILLS_DIR/"; fi
        step_item "pdp1-learnings copied"
    fi
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
        for s in pdp1-assembly pdp1-code-review pdp1-debugging \
                 pdp1-plumbing pdp1-tutor pdp1-type30-vision; do
            [ -d "$SKILLS_DIR/$s" ] || ok=0
        done
        [ -d "$SKILLS_DIR/pdp1-learnings" ] || ok=0
        [ "$ok" = 1 ] && step_item "Skills verified" || fail_exit "skills missing or broken in $SKILLS_DIR — re-run this installer"
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
            "Try: give a guided tour of assembly process" \
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

# --- option 3: update/restore core skills ------------------------------------

walk_skills() {
    step_begin 1 3 "Checking the package"
    step_ask
    if ! ui_confirm "This will update the agent-pdp1 package from GitHub (core-skill edits are replaced)." y; then
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
    act "ls $SELF_DIR/skills" "pdp1-assembly  pdp1-code-review  pdp1-debugging  ..."
    step_item "$n core skills verified"
    step_hint

    finish_screen \
        "${GREEN}✓${RESET} Core skills are up to date." \
        "" \
        "Your own files (pdp1-learnings, SOUL.md) were left alone."
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
        printf '\n%sAGENT-PDP1 INSTALLER%s\n' "$BOLD" "$RESET"
        if [ "$DRY" = 1 ]; then
            printf '%s(dry run — nothing will be installed or changed)%s\n' "$DIM" "$RESET"
        fi
        printf '\nWhat would you like to do?\n\n'
        printf '  1) Install basic setup\n'
        printf '  2) Install Hermes Agent\n'
        printf '  3) Update/restore Core Skills from github\n'
        printf '  4) Exit\n\n'
        printf 'Choice [1-4]: '
        read -r choice || exit 0
        printf '\n'
        case "$choice" in
            1) walk_basic ;;
            2) walk_hermes ;;
            3) walk_skills ;;
            4) ui_clear
               printf '\n  Exiting — nothing else was changed.\n\n'
               exit 0 ;;
            *) printf '%s  Please enter 1, 2, 3 or 4.%s\n' "$YELLOW" "$RESET"
               sleep 1 ;;
        esac
    done
}

main "$@"
