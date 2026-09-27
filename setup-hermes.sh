#!/usr/bin/env bash
# agent-pdp1 — setup-hermes
#
# Part 2 of the agent-pdp1 install. Run AFTER install.sh.
# Gets Hermes Agent itself ready, then wires the PDP-1 knowledge into it.
#
#   1. your LLM API key   (script asks — paste it, or name a file)
#   2. install Hermes     (unattended; browser tools skipped by design)
#   3. connect DeepSeek   (provider, model, key — no wizard needed)
#   4. the PDP-1 skills   (symlinks + learnings + SOUL.md)
#   5. reasoning level    (recommended: max — you decide)
#
# Usage:  bash setup-hermes.sh                        # asks for the key
#         bash setup-hermes.sh /path/to/keyfile       # key from that file
#         DEEPSEEK_API_KEY=sk-... bash setup-hermes.sh   # no key prompt
#         DRY_RUN=1 bash setup-hermes.sh              # validate inputs only

set -euo pipefail
shopt -s nullglob

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$SELF_DIR"
HERMES_BIN=""

say()  { echo; echo "== $*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# ------------------------------------------------------------ step 1: the key

say "step 1: your LLM API key"
echo "  Hermes uses an LLM provider as its brains, and that needs an API"
echo "  key. You get the key yourself — this script stores it only in your"
echo "  Hermes .env file and never echoes it."
echo ""
echo "  We use DeepSeek. Why:"
echo "    - very cheap — a few dollars a month even with serious use"
echo "    - you prepay (about \$20) by PayPal or card — no subscription,"
echo "      no risk of surprise bills"
echo "    - not the most powerful model, but excellent for the simple,"
echo "      sparse world of PDP-1 programming"
echo "  How:  go to platform.deepseek.com  ->  API Keys  ->  create a key,"
echo "  then paste it when this script asks (below)."
echo ""

api_key=""; key_source=""
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    api_key="$DEEPSEEK_API_KEY"; key_source="DEEPSEEK_API_KEY environment variable"
elif [ -n "${1:-}" ]; then
    [ -f "$1" ] || fail "no such file: $1"
    api_key="$(tr -d '[:space:]' < "$1")" || fail "could not read the key file: $1"
    key_source="file $1"
else
    echo "  Paste your DeepSeek API key, or the path to a file that contains it."
    printf '  Key or file (input hidden): '
    IFS= read -rs response || true
    printf '\n'
    case "${response:-}" in
        "~/"*) response="$HOME/${response:2}" ;;
    esac
    if [ -f "${response:-}" ]; then
        api_key="$(tr -d '[:space:]' < "$response")" || fail "could not read the key file: $response"
        key_source="file $response"
    else
        case "${response:-}" in
            */*|*\\*) fail "no such file: ${response}" ;;
            *) api_key="${response:-}"; key_source="pasted key" ;;
        esac
    fi
fi
api_key="$(printf '%s' "$api_key" | tr -d '[:space:]')"
[ -n "$api_key" ] || fail "no key given — create one at platform.deepseek.com, then re-run this script"
echo "  ok — key accepted ($key_source, ${#api_key} chars)"

if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "  dry run — inputs validated; nothing installed or changed"
    exit 0
fi

# ------------------------------------------------------- step 2: install hermes

say "step 2: install Hermes"
if command -v hermes >/dev/null 2>&1; then
    HERMES_BIN="$(command -v hermes)"
    echo "  Hermes is already installed: $("$HERMES_BIN" --version 2>/dev/null | head -1)"
elif [ -x "$HOME/.local/bin/hermes" ]; then
    export PATH="$HOME/.local/bin:$PATH"
    HERMES_BIN="$HOME/.local/bin/hermes"
    echo "  Hermes is already installed: $("$HERMES_BIN" --version 2>/dev/null | head -1)"
else
    case "$(uname -m)" in
        aarch64|x86_64) ;;
        *) fail "unsupported CPU: $(uname -m) — Hermes needs a 64-bit OS (aarch64 or x86_64); on a Raspberry Pi, use 64-bit Raspberry Pi OS" ;;
    esac
    for tool in git curl; do
        command -v "$tool" >/dev/null 2>&1 \
            || fail "$tool is required to install Hermes — install it first (Raspberry Pi OS: sudo apt-get install -y $tool), then re-run this script"
    done
    echo "  Installing Hermes — the official installer, unattended."
    echo "  It sets up Python, Node and the 'hermes' command for you —"
    echo "  no sudo needed."
    echo ""
    echo "  Note: the local browser stack (agent-browser + Chromium, ~600 MB"
    echo "  plus extra system libraries) is not installed, to keep this Pi lean."
    echo "  It is only needed for interactive browsing (logins, JS-heavy pages);"
    echo "  web search and page fetching work without it."
    echo "  Enable it later with:  hermes pm install agent-browser"
    echo ""
    printf '  Press Return to continue: '
    read -r _ || true
    printf '\n'
    installer="$(mktemp /tmp/hermes-install.XXXXXX)"
    trap 'rm -f "$installer"' EXIT
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "$installer" \
        || fail "download failed — check your network connection"
    bash "$installer" --non-interactive --skip-browser \
        || fail "the Hermes installer failed — see the output above"
    export PATH="$HOME/.local/bin:$PATH"
    HERMES_BIN="$(command -v hermes || true)"
    [ -n "$HERMES_BIN" ] || fail "hermes not found after install — is ~/.local/bin on your PATH? check and re-run"
    echo "  (New shells will find 'hermes' too: source ~/.bashrc)"
fi

# --------------------------------------------- which home gets all of this?
# Normally none of this matters: no profiles -> the default setup (~/.hermes).
# One profile (a pre-existing install that works in profiles) -> use it.
# Several -> ask.  This script never creates a profile.

mapfile -t PROFILES < <(find "$HOME/.hermes/profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
HERMES_HOME="$HOME/.hermes"
case "${#PROFILES[@]}" in
    0)
        echo "  No Hermes profile found — installing into the default setup"
        echo "  (~/.hermes). PDP-1 work doesn't need a profile; if you create"
        echo "  one later, re-run this script to install into it."
        ;;
    1)
        PROFILE="$(basename "${PROFILES[0]}")"
        HERMES_HOME="$HOME/.hermes/profiles/$PROFILE"
        echo "  Using your profile: $PROFILE"
        ;;
    *)
        echo "  You have several Hermes profiles:"
        for i in "${!PROFILES[@]}"; do
            echo "    $((i+1))) $(basename "${PROFILES[$i]}")"
        done
        read -r -p "  Which one gets the PDP-1 knowledge? [1-${#PROFILES[@]}] " ans || true
        case "${ans:-}" in
            *[!0-9]*|"") fail "pick a number" ;;
            *) [ "$ans" -ge 1 ] && [ "$ans" -le "${#PROFILES[@]}" ] \
                   || fail "pick a number between 1 and ${#PROFILES[@]}"
               PROFILE="$(basename "${PROFILES[$((ans-1))]}")"
               HERMES_HOME="$HOME/.hermes/profiles/$PROFILE" ;;
        esac
        ;;
esac

PROFILE_LABEL="${PROFILE:-default setup}"

# everything below targets the chosen home — plain `hermes` in the normal
# case, `-p <profile>` only when an existing profile is in use
if [ -n "${PROFILE:-}" ]; then
    HERMES_HINT="hermes -p $PROFILE"
    herm() { "$HERMES_BIN" -p "$PROFILE" "$@"; }
else
    HERMES_HINT="hermes"
    herm() { "$HERMES_BIN" "$@"; }
fi

# --------------------------------------------------- step 3: connect DeepSeek

say "step 3: connect DeepSeek"
herm config set model.provider deepseek \
    || fail "could not set model.provider"
herm config set model.default deepseek-flash \
    || fail "could not set model.default"
herm config set model.base_url "https://api.deepseek.com/v1" \
    || fail "could not set model.base_url"
herm config set DEEPSEEK_API_KEY "$api_key" \
    || fail "could not store the API key"
echo "  ok — deepseek + deepseek-flash configured; key stored in $HERMES_HOME/.env"

# --------------------------------------------------- step 4: the PDP-1 skills

say "step 4: the PDP-1 skills"

SKILLS_DIR="$HERMES_HOME/skills"
mkdir -p "$SKILLS_DIR"

echo "  symlinking the frozen skills — a symlink is a pointer, so updates"
echo "  to agent-pdp1 reach your agent automatically"
# drop stale links for renamed/removed skills (pdp1-learnings is a real
# directory — only symlinks are touched)
find "$SKILLS_DIR" -maxdepth 1 -type l -name 'pdp1-*' -delete 2>/dev/null || true
for d in "$PKG_DIR"/skills/*/; do
    ln -sfn "$d" "$SKILLS_DIR/$(basename "$d")"
done

echo "  copying pdp1-learnings — YOUR agent's own file, where it keeps"
echo "  what it learns. A real copy, never a symlink: updates must not"
echo "  overwrite it"
LEARNINGS_DIR="$SKILLS_DIR/pdp1-learnings"
if [ -e "$LEARNINGS_DIR" ]; then
    echo "  You already have one here: $LEARNINGS_DIR"
    read -r -p "  Overwrite it with the fresh template? [y/N] " ans || true
    case "${ans:-n}" in
        [Yy]*)
            rm -rf "$LEARNINGS_DIR"
            cp -r "$PKG_DIR/hermes-specific/pdp1-learnings" "$SKILLS_DIR/"
            ;;
        *)
            echo "  Keeping your existing pdp1-learnings."
            echo "  (If you want the fresh template later: back up that"
            echo "   directory first, then re-run this script and answer y.)"
            ;;
    esac
else
    cp -r "$PKG_DIR/hermes-specific/pdp1-learnings" "$SKILLS_DIR/"
fi

echo "  copying SOUL.md — the rules file. Your agent reads it with every"
echo "  request; it keeps the agent disciplined about the machine"
SOUL_FILE="$HERMES_HOME/SOUL.md"
if [ -e "$SOUL_FILE" ]; then
    echo "  You already have one here: $SOUL_FILE"
    read -r -p "  Overwrite it with the package version? [y/N] " ans || true
    case "${ans:-n}" in
        [Yy]*)
            cp "$PKG_DIR/hermes-specific/SOUL.md" "$SOUL_FILE"
            ;;
        *)
            echo "  Keeping your existing SOUL.md."
            echo "  (If you want the package version later: back that file"
            echo "   up first, then re-run this script and answer y.)"
            ;;
    esac
else
    cp "$PKG_DIR/hermes-specific/SOUL.md" "$SOUL_FILE"
fi

# --------------------------------------------------- step 5: reasoning level

say "step 5: reasoning level"
echo "  For PDP-1 work we strongly recommend 'max' reasoning for your"
echo "  agent. The work is careful machine-level stuff — octal"
echo "  arithmetic, protocol framing, stop-reason diagnosis — and 'max'"
echo "  gives the agent the depth to get the details right. On DeepSeek"
echo "  the extra cost stays small."
read -r -p "  Set reasoning to max for '$PROFILE_LABEL'? [Y/n] " ans || true
case "${ans:-y}" in
    [Yy]*)
        # --force skips a false "not a recognized config key" notice: the
        # runtime *does* read agent.reasoning_effort (as does the web UI).
        herm config set --force agent.reasoning_effort max \
            && echo "  ok — reasoning_effort: max set" \
            || fail "could not set reasoning_effort"
        ;;
    *)
        echo "  Fine — set it later yourself:  $HERMES_HINT config set agent.reasoning_effort max"
        ;;
esac

# ------------------------------------------------------------------ verify

say "verify"
echo "  installed for '$PROFILE_LABEL':"
ls "$SKILLS_DIR" | grep 'pdp1' | sed 's/^/    /' || true
for s in pdp1-assembly pdp1-code-review pdp1-debugging \
         pdp1-plumbing pdp1-tutor pdp1-type30-vision; do
    [ -d "$PKG_DIR/skills/$s" ] || fail "package is missing skills/$s — re-run skills/update.sh"
    [ -d "$SKILLS_DIR/$s" ]     || fail "'$s' missing or broken in $SKILLS_DIR — re-run this script"
done
[ -d "$SKILLS_DIR/pdp1-learnings" ] || fail "pdp1-learnings missing in $SKILLS_DIR — re-run this script"

echo "  quick health check (advisory — anything it flags is worth a look):"
herm doctor || true

echo "  checking DeepSeek — one real round-trip to the model"
if ! reply="$(herm -z 'Reply with exactly: OK')"; then
    fail "the round-trip failed — check the key, then run '$HERMES_HINT doctor'"
fi
echo "  model replied: $reply"

say "next steps"
echo "  - start chatting:  $HERMES_HINT"
echo "  - try:             'load the pdp1-debugging skill'"
echo "  - package updates: /opt/agent-pdp1/skills/update.sh"

say "done"
