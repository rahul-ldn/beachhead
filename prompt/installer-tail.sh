# ---- 1. packages ----
step "packages"
if [ $PACKAGES = 0 ]; then say "  skipped (--no-packages)"
elif [ $PLATFORM = mac ]; then
  [ -n "$HOMEBREW" ] || { echo "Homebrew is not installed; install it first (https://brew.sh), then run this again." >&2; exit 66; }
  for f in starship fish bash tmux; do "$HOMEBREW" list --formula "$f" >/dev/null 2>&1 && say "  present: $f" || run "$HOMEBREW" install "$f"; done
  if [ $FONT = 1 ]; then "$HOMEBREW" list --cask font-fira-code-nerd-font >/dev/null 2>&1 && say "  present: font-fira-code-nerd-font" || run "$HOMEBREW" install --cask font-fira-code-nerd-font; fi
else
  if command -v apt-get >/dev/null; then
    missing=''; for p in fish tmux curl ca-certificates; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    if [ -n "$missing" ]; then run $SUDO apt-get update -qq; run $SUDO apt-get install -y -qq $missing; else say "  present: fish tmux curl"; fi
  else
    say "  no apt-get here: install fish and tmux yourself; starship still comes from its release tarball"
  fi
  say "  no font step: a server has no screen; the Nerd Font belongs on the Mac you connect from, where this script installs it"
  if command -v starship >/dev/null; then say "  present: starship $(starship --version | head -1)"
  else
    case "$ARCH" in x86_64) target=x86_64-unknown-linux-musl;; aarch64|arm64) target=aarch64-unknown-linux-musl;; *) echo "no starship build for $ARCH" >&2; exit 65;; esac
    tarball=starship-$target.tar.gz; base=https://github.com/starship/starship/releases/download/$STARSHIP_VERSION
    say "  fetching starship $STARSHIP_VERSION ($target) from GitHub, checking its sha256, installing to ~/.local/bin"
    if [ $DRY = 0 ]; then
      tmpd=$(mktemp -d); ( cd "$tmpd" && curl -sSfL -o "$tarball" "$base/$tarball" && curl -sSfL -o "$tarball.sha256" "$base/$tarball.sha256" \
        && echo "$(cut -d' ' -f1 "$tarball.sha256")  $tarball" | sha256sum -c --quiet && tar xzf "$tarball" && mkdir -p "$HOME/.local/bin" && install -m 755 starship "$HOME/.local/bin/starship" )
      rm -rf "$tmpd"; say "  installed: $("$HOME/.local/bin/starship" --version | head -1)"
    fi
  fi
fi
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
check "starship runs ($(command -v starship >/dev/null && starship --version | head -1 || echo not found))" command -v starship
check "fish runs ($(command -v fish >/dev/null && fish --version || echo not found))" command -v fish
check "tmux runs ($(command -v tmux >/dev/null && tmux -V || echo not found))" command -v tmux
[ $PLATFORM = mac ] && [ $FONT = 1 ] && check "FiraCode Nerd Font Mono is installed" sh -c 'ls ~/Library/Fonts/FiraCodeNerdFontMono-Regular.ttf /Library/Fonts/FiraCodeNerdFontMono-Regular.ttf 2>/dev/null | grep -q .'

# ---- 2. the files ----
step "the prompt's files"
install_file payload_starship_toml "$HOME/.config/starship/starship.toml"
install_file payload_landingham_status "$HOME/.local/bin/landingham-status" 755
install_file payload_beachhead_palette "$HOME/.local/bin/beachhead-palette" 755
install_file payload_beachhead_fish "$HOME/.config/fish/conf.d/beachhead.fish"
TMUX_BIN=$(command -v tmux 2>/dev/null || echo /opt/homebrew/bin/tmux)
payload_tmux_conf_resolved() { payload_tmux_conf | sed -e "s|__HOME__|$HOME|g" -e "s|__TMUX__|$TMUX_BIN|g"; }
install_file payload_tmux_conf_resolved "$HOME/.tmux.conf"
check "the starship template loads without a warning" sh -c '[ -z "$(STARSHIP_CONFIG=$HOME/.config/starship/starship.toml starship prompt --terminal-width 80 2>&1 >/dev/null | grep WARN)" ]'
check "landingham-status runs" "$HOME/.local/bin/landingham-status" --sessions
check "beachhead-palette answers from home" sh -c 'cd && [ -f "$("$HOME/.local/bin/beachhead-palette")" ]'
check "the tmux conf parses (on a scratch server of its own)" sh -c '"$0" -L landingham-install-check -f "$HOME/.tmux.conf" new-session -d true 2>/dev/null; "$0" -L landingham-install-check kill-server 2>/dev/null; true' "$TMUX_BIN"

# ---- 3. the shared environment file: the one place for variables every shell on this machine must carry ----
step "the environment file"
[ -n "$PROJECT" ] || { [ -d "$HOME/Claude/Projects/CRM" ] && PROJECT=$HOME/Claude/Projects/CRM || true; }
ENV_FILE=$HOME/.config/beachhead/env
if [ $PLATFORM = mac ]; then MODERN_BASH=/opt/homebrew/bin/bash; else MODERN_BASH=$(command -v bash); fi
if [ ! -f "$ENV_FILE" ]; then
  say "  writing:   $ENV_FILE"
  if [ $DRY = 0 ]; then mkdir -p "$(dirname "$ENV_FILE")"; cat > "$ENV_FILE" <<ENVEOF
# ~/.config/beachhead/env — variables every shell on this machine carries, one KEY=value a line, read by fish,
# zsh and bash alike (beachhead's prompt installer wrote it; edit freely; it is never overwritten). Never a secret.
# Claude Code's Bash tool runs bash, not the shell you type in: fish is not supported there, and this pins it.
CLAUDE_CODE_SHELL=$MODERN_BASH
# Where account B's Claude settings live, for the shell function 'account b': the folder need not exist on every machine.
CLAUDE_CONFIG_DIR_B=$HOME/.claude-b
ENVEOF
  fi
else
  say "  present:   $ENV_FILE (left as it is)"
  grep -q '^CLAUDE_CODE_SHELL=' "$ENV_FILE" || { say "  adding CLAUDE_CODE_SHELL=$MODERN_BASH to it"; [ $DRY = 0 ] && echo "CLAUDE_CODE_SHELL=$MODERN_BASH" >> "$ENV_FILE"; }
fi
# The process store and its checkout, for the baton in the status bar: found by their shape on this machine, never
# named here. The checkout is the project folder when it carries the store's CLI; the store is the one corpus.sqlite
# under the Mac's Application Support. Each line is added once, when absent, and never changed afterwards.
env_add() { grep -q "^$1=" "$ENV_FILE" 2>/dev/null && say "  present:   $1" || { say "  adding:    $1=$2"; [ $DRY = 0 ] && printf '%s=%s\n' "$1" "$2" >> "$ENV_FILE"; }; }
if [ -n "$PROJECT" ] && [ -f "$PROJECT/corpus/cli.mjs" ]; then env_add LANDINGHAM_REPOSITORY "$PROJECT"; fi
if [ $PLATFORM = mac ]; then
  stores=$(ls "$HOME/Library/Application Support"/*/process/corpus.sqlite 2>/dev/null | wc -l | tr -d ' ')
  if [ "$stores" = 1 ]; then env_add LANDINGHAM_STORE "$(ls "$HOME/Library/Application Support"/*/process/corpus.sqlite)"; elif [ "$stores" != 0 ]; then say "  $stores process stores found under Application Support: name LANDINGHAM_STORE in $ENV_FILE yourself"; fi
fi
check "the pinned bash exists ($MODERN_BASH)" test -x "$MODERN_BASH"

# ---- 4. zsh and bash, for the times they are the shell: the same prompt, the same variables ----
step "zsh and bash"
read -r -d '' ZSH_BLOCK <<'ZEOF' || true
# installed by beachhead's prompt installer; interactive shells only, and nothing here prints
[[ -o interactive ]] || return
[[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"
HISTSIZE=50000; SAVEHIST=50000; setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE
[[ -r ~/.config/beachhead/env ]] && while IFS= read -r l; do [[ $l == [A-Za-z_]*=* ]] && export "$l"; done < ~/.config/beachhead/env
# `account a` / `account b` [--save]: the Claude account a `claude` typed in THIS shell uses; the prompt's pill follows.
# --save keeps the choice in ~/.config/beachhead/env, so every new shell after a re-login starts that way.
account() {
  local env="$HOME/.config/beachhead/env" which="${1:-}" save=''
  case " $* " in *" --save "*) save=yes;; esac
  case "$which" in
    a|A) unset CLAUDE_CONFIG_DIR; echo 'claude: A (the default folder)';;
    b|B) local d="${CLAUDE_CONFIG_DIR_B:-$HOME/.claude-b}"; [ -d "$d" ] || { echo "account b: no folder at $d on this machine" >&2; return 66; }; export CLAUDE_CONFIG_DIR="$d"; echo "claude: B ($d)";;
    '') if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then echo "claude: B ($CLAUDE_CONFIG_DIR)"; else echo 'claude: A (the default folder)'; fi; return 0;;
    *) echo 'usage: account a|b [--save]' >&2; return 64;;
  esac
  if [ -n "$save" ] && [ -w "$env" ]; then
    grep -v '^CLAUDE_CONFIG_DIR=' "$env" > "$env.new"; [ -n "${CLAUDE_CONFIG_DIR:-}" ] && echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> "$env.new"
    mv "$env.new" "$env" && echo "  saved: new shells start on $which"
  fi
}
if command -v starship >/dev/null; then
  beachhead_palette() { export STARSHIP_CONFIG="$(beachhead-palette)"; }
  autoload -Uz add-zsh-hook && add-zsh-hook chpwd beachhead_palette
  beachhead_palette
  eval "$(starship init zsh)"
fi
ZEOF
read -r -d '' BASH_BLOCK <<'BEOF' || true
# installed by beachhead's prompt installer. The part above the guard is for EVERY bash, Claude Code's Bash tool
# included (it sources this file at session start): the paths and the shared variables, and nothing that prints.
[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH";; esac
[ -r ~/.config/beachhead/env ] && while IFS= read -r l; do case "$l" in [A-Za-z_]*=*) export "$l";; esac; done < ~/.config/beachhead/env
case $- in *i*) ;; *) return 0 2>/dev/null || true;; esac
# from here on, the shell you type in
export BASH_SILENCE_DEPRECATION_WARNING=1   # Apple's 3.2 bash nags about zsh otherwise
HISTSIZE=50000; HISTFILESIZE=50000; HISTCONTROL=ignoreboth; shopt -s histappend checkwinsize
# `account a` / `account b` [--save]: the Claude account a `claude` typed in THIS shell uses; the prompt's pill follows.
# --save keeps the choice in ~/.config/beachhead/env, so every new shell after a re-login starts that way.
account() {
  local env="$HOME/.config/beachhead/env" which="${1:-}" save=''
  case " $* " in *" --save "*) save=yes;; esac
  case "$which" in
    a|A) unset CLAUDE_CONFIG_DIR; echo 'claude: A (the default folder)';;
    b|B) local d="${CLAUDE_CONFIG_DIR_B:-$HOME/.claude-b}"; [ -d "$d" ] || { echo "account b: no folder at $d on this machine" >&2; return 66; }; export CLAUDE_CONFIG_DIR="$d"; echo "claude: B ($d)";;
    '') if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then echo "claude: B ($CLAUDE_CONFIG_DIR)"; else echo 'claude: A (the default folder)'; fi; return 0;;
    *) echo 'usage: account a|b [--save]' >&2; return 64;;
  esac
  if [ -n "$save" ] && [ -w "$env" ]; then
    grep -v '^CLAUDE_CONFIG_DIR=' "$env" > "$env.new"; [ -n "${CLAUDE_CONFIG_DIR:-}" ] && echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> "$env.new"
    mv "$env.new" "$env" && echo "  saved: new shells start on $which"
  fi
}
if command -v starship >/dev/null; then
  beachhead_palette() { [ "${PWD}" = "${_LANDINGHAM_PWD:-}" ] || { export STARSHIP_CONFIG="$(beachhead-palette)"; _LANDINGHAM_PWD=$PWD; }; }
  PROMPT_COMMAND="beachhead_palette${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
  eval "$(starship init bash)"
fi
BEOF
install_block "$HOME/.zshrc" "$ZSH_BLOCK"
install_block "$HOME/.bashrc" "$BASH_BLOCK"
install_block "$HOME/.bash_profile" '[ -r ~/.bashrc ] && . ~/.bashrc'
check "bash, sourced the way Claude Code sources it, carries CLAUDE_CODE_SHELL and finds the scripts" bash -c 'source ~/.bashrc; [ -n "$CLAUDE_CODE_SHELL" ] && command -v landingham-status >/dev/null'
check "an interactive bash gets starship's prompt" bash -ic '[[ $PROMPT_COMMAND == *starship* ]]'
command -v zsh >/dev/null && check "an interactive zsh gets starship's prompt and the palette" zsh -ic '[[ -n $STARSHIP_CONFIG ]] && typeset -f prompt_starship_precmd >/dev/null'
command -v fish >/dev/null && check "an interactive fish gets starship's prompt and the palette" fish -ic 'test -n "$STARSHIP_CONFIG"; and functions fish_prompt | grep -q starship'
ACCT_CHECK=$(mktemp -d)
cat > "$ACCT_CHECK/check.fish" <<'FEOF'
set -gx CLAUDE_CONFIG_DIR_B $HOME/.claude-b-check
account b >/dev/null; or exit 1
test "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-b-check"; or exit 2
account a >/dev/null; or exit 3
set -q CLAUDE_CONFIG_DIR; and exit 4
exit 0
FEOF
cat > "$ACCT_CHECK/check.bash" <<'BEOF2'
CLAUDE_CONFIG_DIR_B=$HOME/.claude-b-check
account b >/dev/null || exit 1; [ "$CLAUDE_CONFIG_DIR" = "$HOME/.claude-b-check" ] || exit 2
account a >/dev/null || exit 3; [ -z "${CLAUDE_CONFIG_DIR:-}" ] || exit 4
exit 0
BEOF2
mkdir -p "$HOME/.claude-b-check"
command -v fish >/dev/null && check "\`account b\` and \`account a\` switch the Claude account in a fish shell" fish "$ACCT_CHECK/check.fish"
check "\`account b\` and \`account a\` switch the Claude account in a bash shell" bash -i "$ACCT_CHECK/check.bash"
rmdir "$HOME/.claude-b-check" 2>/dev/null; rm -rf "$ACCT_CHECK"

# ---- 5. the default palette, and the project's own ----
step "palettes"
if [ -n "$DEFAULT_PALETTE" ]; then
  if [ $DRY = 1 ]; then say "  would set the default palette to $DEFAULT_PALETTE"; else "$HOME/.local/bin/beachhead-palette" --default "$DEFAULT_PALETTE" | sed 's/^/  /'; fi
else say "  default palette: $(sed -n "s/^palette = '\(.*\)'/\1/p" "$HOME/.config/starship/starship.toml" 2>/dev/null || echo gruvbox) (change it: beachhead-palette --default <name>)"; fi
if [ -n "$PROJECT" ]; then
  [ -d "$PROJECT" ] || { echo "no such project folder: $PROJECT" >&2; exit 66; }
  install_file payload_prompt_palette_toml "$PROJECT/.prompt-palette.toml"
  check "inside $PROJECT the palette hook picks the project's own colours" sh -c 'cd "$0" && "$HOME/.local/bin/beachhead-palette" | grep -q "/landingham.toml$"' "$PROJECT"
else say "  no project folder found or named (--project DIR): no project palette placed"; fi

# ---- 6. Claude Code's status line ----
step "Claude Code's status line"
SETTINGS=$HOME/.claude/settings.json
if [ $STATUSLINE = 0 ]; then say "  skipped (--no-claude-statusline)"
elif ! command -v python3 >/dev/null; then say "  skipped: no python3 here to edit JSON safely; add to $SETTINGS by hand: \"statusLine\": {\"type\": \"command\", \"command\": \"$HOME/.local/bin/landingham-status --claude\"}"
else
  want="$HOME/.local/bin/landingham-status --claude"
  if [ -f "$SETTINGS" ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('statusLine',{}).get('command')==sys.argv[2] else 1)" "$SETTINGS" "$want" 2>/dev/null; then say "  present: statusLine in $SETTINGS"
  else
    say "  setting statusLine in $SETTINGS$( [ -f "$SETTINGS" ] && echo " (the old file kept as $SETTINGS.before-$STAMP)")"
    if [ $DRY = 0 ]; then
      mkdir -p "$(dirname "$SETTINGS")"; [ -f "$SETTINGS" ] && cp -p "$SETTINGS" "$SETTINGS.before-$STAMP"
      python3 - "$SETTINGS" "$want" <<'PYEOF'
import json,sys,os
p,cmd=sys.argv[1:3]; d=json.load(open(p)) if os.path.exists(p) else {}
d['statusLine']={'type':'command','command':cmd}
json.dump(d,open(p,'w'),indent=2); open(p,'a').write('\n')
PYEOF
    fi
  fi
  check "settings.json is still valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS"
fi

# ---- 7. fish as the shell you type in ----
step "the login shell"
FISH=$(command -v fish 2>/dev/null || { [ $PLATFORM = mac ] && echo /opt/homebrew/bin/fish || echo /usr/bin/fish; })
if [ $CHSH = 0 ]; then say "  skipped (--no-chsh); to do it later: chsh -s $FISH"
elif [ "$(basename "${SHELL:-}")" = fish ] || { [ $PLATFORM = mac ] && dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | grep -q fish; }; then say "  present: fish is already the login shell"
else
  grep -qx "$FISH" /etc/shells 2>/dev/null || run $SUDO sh -c "echo '$FISH' >> /etc/shells"
  say "  this asks for your password:"; run chsh -s "$FISH"
fi
[ $CHSH = 1 ] && check "fish is the login shell" sh -c 'if [ "$(uname -s)" = Darwin ]; then dscl . -read "/Users/$(id -un)" UserShell | grep -q fish; else getent passwd "$(id -un)" | grep -q fish; fi'

# ---- 8. what is live now ----
step "finishing"
if [ -n "$TMUX_BIN" ] && "$TMUX_BIN" list-sessions >/dev/null 2>&1; then run "$TMUX_BIN" source-file "$HOME/.tmux.conf"; fi
if [ $DRY = 0 ] && command -v starship >/dev/null; then
  say "  the band, as it will look (home, then the project if there is one):"
  ( cd && STARSHIP_CONFIG=$("$HOME/.local/bin/beachhead-palette") starship prompt --terminal-width 120 2>/dev/null | sed 's/^/    /'; echo )
  [ -n "$PROJECT" ] && ( cd "$PROJECT" && STARSHIP_CONFIG=$("$HOME/.local/bin/beachhead-palette") starship prompt --terminal-width 120 2>/dev/null | sed 's/^/    /'; echo )
fi
# The part's record, beside the shared environment file: what ran, when, which build, and how its checks went.
# One line a run, newest last, so a later `beachhead doctor` can read every part's state from one folder.
if [ $DRY = 0 ]; then mkdir -p "$HOME/.config/beachhead/installed"; printf '%s build %s on %s: %s checks passed, %s failed\n' "$(date '+%Y-%m-%d %H:%M')" "$BEACHHEAD_BUILD" "$PLATFORM" "$PASS" "$FAIL" >> "$HOME/.config/beachhead/installed/prompt"; fi
say "  done: $PASS checks passed, $FAIL failed. Open a new terminal window$( [ $PLATFORM = mac ] && [ $FONT = 1 ] && echo ', set its font to FiraCode Nerd Font Mono,') and the band is there."
say "  the default palette: beachhead-palette --default <gruvbox|pastel|catppuccin>; a project's own: .prompt-palette.toml at its root."
return $FAIL
}

# Piped from curl or gh, the script has no keyboard: hand the prompts /dev/tty; with no terminal at all, skip chsh.
if [ -t 0 ]; then main "$@"
elif ( : < /dev/tty ) 2>/dev/null; then main "$@" < /dev/tty
else echo "no terminal: the login-shell step (chsh) will be skipped; run it yourself afterwards" >&2; main --no-chsh "$@"
fi
