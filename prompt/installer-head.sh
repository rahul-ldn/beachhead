#!/usr/bin/env bash
# landingham-prompt-install.sh — one command sets up the command line on one of the owner's machines: the shell prompt
# (starship, in the chevron-band shape agreed on 2 November 2026), fish as the shell typed in, the per-folder palette
# hook, the tmux status bar, the status script, the shared environment file, Claude Code's status line, and the Nerd
# Font on a Mac. The same file serves a Mac (Homebrew) and the VPS (Debian or Ubuntu, apt; starship from its signed
# release tarball into ~/.local/bin, never `curl | sh`). Every payload file is embedded below, so the one file is the
# whole install; the sources are in tools/ops/prompt/payload/ and build-installer.py assembles this file from them.
#
#   bash landingham-prompt-install.sh [--dry-run] [--no-packages] [--no-font] [--no-chsh] [--no-claude-statusline]
#                                     [--project DIR] [--default PALETTE]
#   … or piped, the one command on any machine, from where GitHub Pages serves this file:
#   curl -fsSL https://rahul-ldn.github.io/beachhead/prompt/install.sh | bash            (any option: … | bash -s -- --dry-run)
#   Piped, the script has no keyboard, so it reads sudo's and chsh's prompts from /dev/tty; with no terminal at all
#   (a container, a remote command) it skips the login-shell step and says so. Every stage ends with its checks (✓/✗),
#   the last stage prints the band as it will look, and the exit status is the number of checks that failed.
#
#   --dry-run              say everything, change nothing
#   --no-packages          skip the package step (brew or apt, and the starship tarball)
#   --no-font              on a Mac, skip the Nerd Font (a server never gets one: its screen is the Mac's)
#   --no-chsh              do not make fish the login shell (the one step that asks for your password)
#   --no-claude-statusline leave ~/.claude/settings.json alone
#   --project DIR          the checkout that gets its .prompt-palette.toml (default: ~/Claude/Projects/CRM when it exists)
#   --default PALETTE      the default palette for folders that are no project's: gruvbox (default), pastel, catppuccin
#
# What it never touches: ~/.config/landingham/ and ~/.config/landingham-access/ (the access words), any Keychain,
# the controllers' start scripts, and anything secret. Existing files it must replace are kept beside the new one
# with a dated suffix. Re-running is safe: it replaces its own files and its own marked blocks and nothing else.
set -euo pipefail

main() {
STARSHIP_VERSION=v1.27.0
STAMP=$(date +%Y%m%d-%H%M%S)
DRY=0; PACKAGES=1; FONT=1; CHSH=1; STATUSLINE=1; PROJECT=''; DEFAULT_PALETTE=''
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1;; --no-packages) PACKAGES=0;; --no-font) FONT=0;; --no-chsh) CHSH=0;; --no-claude-statusline) STATUSLINE=0;;
    --project) PROJECT=$2; shift;; --default) DEFAULT_PALETTE=$2; shift;;
    -h|--help) if [ -f "$0" ]; then sed -n '2,26p' "$0"; else echo 'options: --dry-run --no-packages --no-font --no-chsh --no-claude-statusline --project DIR --default PALETTE'; fi; exit 0;;
    *) echo "unknown option: $1" >&2; exit 64;;
  esac; shift
done
say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }
PASS=0; FAIL=0
check() {  # check "<what>" <command…>: runs the command quietly and reports ✓ or ✗
  local what=$1; shift
  if [ $DRY = 1 ]; then say "  · would check: $what"; return 0; fi
  if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); printf '  \033[32m✓\033[0m %s\n' "$what"; else FAIL=$((FAIL+1)); printf '  \033[31m✗\033[0m %s\n' "$what"; fi
}
run()  { if [ $DRY = 1 ]; then say "  would run: $*"; else say "  running: $*"; "$@"; fi; }
OS=$(uname -s); ARCH=$(uname -m)
case "$OS" in Darwin) PLATFORM=mac;; Linux) PLATFORM=linux;; *) echo "unsupported system: $OS" >&2; exit 65;; esac
SUDO=''; [ "$(id -u)" = 0 ] || SUDO=sudo
HOMEBREW=''; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x $b ] && HOMEBREW=$b && break; done
say "landingham-prompt-install: $PLATFORM ($ARCH), user $(id -un), home $HOME$( [ $DRY = 1 ] && echo ', DRY RUN')"

# ---- writing files: never silently over something that is not ours ----
install_file() {  # install_file <payload function> <destination> [mode]
  local fn=$1 dest=$2 mode=${3:-644} tmp; tmp=$(mktemp)
  "$fn" > "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then say "  unchanged: $dest"; rm -f "$tmp"; return; fi
  if [ -f "$dest" ]; then say "  replacing: $dest (the old one kept as $dest.before-$STAMP)"; else say "  writing:   $dest"; fi
  if [ $DRY = 1 ]; then rm -f "$tmp"; return; fi
  mkdir -p "$(dirname "$dest")"; [ -f "$dest" ] && cp -p "$dest" "$dest.before-$STAMP"
  mv "$tmp" "$dest"; chmod "$mode" "$dest"
}
install_block() {  # install_block <rc file> <block text>: replaces the marked block, or appends it
  local dest=$1 block=$2 begin='# >>> landingham prompt >>>' end='# <<< landingham prompt <<<' tmp; tmp=$(mktemp)
  if [ -f "$dest" ] && grep -qF "$begin" "$dest"; then
    awk -v b="$begin" -v e="$end" 'index($0,b)==1{skip=1} !skip{print} index($0,e)==1{skip=0}' "$dest" > "$tmp"
  else
    [ -f "$dest" ] && cat "$dest" > "$tmp"
  fi
  { [ -s "$tmp" ] && echo; printf '%s\n%s\n%s\n' "$begin" "$block" "$end"; } >> "$tmp"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then say "  unchanged: $dest"; rm -f "$tmp"; return; fi
  say "  $( [ -f "$dest" ] && echo 'updating: ' || echo 'writing:  ') $dest (its landingham block)"
  if [ $DRY = 1 ]; then rm -f "$tmp"; return; fi
  [ -f "$dest" ] && cp -p "$dest" "$dest.before-$STAMP"; mv "$tmp" "$dest"
}

