#!/usr/bin/env bash
# install.sh — one command sets up the command line on one of the owner's machines: the shell prompt
# (starship, in the chevron-band shape agreed on 2 November 2026), fish as the shell typed in, the per-folder palette
# hook, the tmux status bar, the status script, the shared environment file, Claude Code's status line, and the Nerd
# Font on a Mac. The same file serves a Mac (Homebrew) and the VPS (Debian or Ubuntu, apt; starship from its signed
# release tarball into ~/.local/bin, never `curl | sh`). Every payload file is embedded below, so the one file is the
# whole install; the sources are in tools/ops/prompt/payload/ and build-installer.py assembles this file from them.
#
#   bash install.sh [--dry-run] [--no-packages] [--no-font] [--no-chsh] [--no-claude-statusline]
#                   [--project DIR] [--default PALETTE]
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
BEACHHEAD_BUILD='028128027a5c'   # build-installer.py fills this in: a digest of its sources
STARSHIP_VERSION=v1.27.0
STAMP=$(date +%Y%m%d-%H%M%S)
DRY=0; PACKAGES=1; FONT=1; CHSH=1; STATUSLINE=1; PROJECT=''; DEFAULT_PALETTE=''; NOTTY=${BEACHHEAD_NOTTY:-0}
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
soft() { if [ $DRY = 1 ]; then say "  would run: $*"; else say "  running: $*"; "$@" || say "  (that failed; carrying on, the checks below will say what is missing)"; fi; }
OS=$(uname -s); ARCH=$(uname -m)
case "$OS" in Darwin) PLATFORM=mac;; Linux) PLATFORM=linux;; *) echo "unsupported system: $OS" >&2; exit 65;; esac
SUDO=''; [ "$(id -u)" = 0 ] || SUDO=sudo
HOMEBREW=''; for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do [ -x $b ] && HOMEBREW=$b && break; done
say "beachhead prompt: $PLATFORM ($ARCH), user $(id -un), home $HOME$( [ $DRY = 1 ] && echo ', DRY RUN')"

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
install_block() {  # install_block <rc file> <block text> [top]: replaces the marked block, else appends it, or with
  # "top" puts it first: a Debian user's default .bashrc returns early for a non-interactive shell, and Claude Code's
  # tool sources .bashrc non-interactively, so the block must come before that return.
  local dest=$1 block=$2 where=${3:-bottom} begin='# >>> beachhead prompt >>>' end='# <<< beachhead prompt <<<' tmp rest; tmp=$(mktemp); rest=$(mktemp)
  if [ -f "$dest" ] && grep -qF "$begin" "$dest"; then
    awk -v b="$begin" -v e="$end" 'index($0,b)==1{skip=1} !skip{print} index($0,e)==1{skip=0}' "$dest" > "$rest"
  else
    [ -f "$dest" ] && cat "$dest" > "$rest"
  fi
  if [ "$where" = top ]; then
    { printf '%s\n%s\n%s\n' "$begin" "$block" "$end"; [ -s "$rest" ] && { echo; cat "$rest"; }; } > "$tmp"
  else
    { [ -s "$rest" ] && cat "$rest"; [ -s "$rest" ] && echo; printf '%s\n%s\n%s\n' "$begin" "$block" "$end"; } > "$tmp"
  fi
  rm -f "$rest"
  if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then say "  unchanged: $dest"; rm -f "$tmp"; return; fi
  say "  $( [ -f "$dest" ] && echo 'updating: ' || echo 'writing:  ') $dest (its landingham block)"
  if [ $DRY = 1 ]; then rm -f "$tmp"; return; fi
  [ -f "$dest" ] && cp -p "$dest" "$dest.before-$STAMP"; mv "$tmp" "$dest"
}

payload_starship_toml() {
cat <<'LANDINGHAM_PAYLOAD_END'
# ~/.config/starship.toml — proposed for the owner's Macs, 2 November 2026 (fourth shape).
# One line. Left: a rounded cap, then cells joined by chevrons (machine › path › git › tmux), the command typed
# straight after. Right: the failure flag, a slow command's duration, the account pill, the clock pill.
# Outside tmux a lobby line sits above: the sessions you could join, with their controllers. Inside tmux that line
# is absent, because the status bar carries the room.
#
# Built the way the Pastel Powerline, Gruvbox Rainbow and Catppuccin Powerline presets are. The last cell of the
# band closes with a chevron drawn by a small module that knows which cell is last, so an absent cell leaves no
# sliver. Assumes FiraCode Nerd Font. Switch the look with `palette`: pastel, gruvbox or catppuccin.
# The glyphs are '\ue0b0' (chevron), '\ue0b6' and '\ue0b4' (the caps), written by codepoint.

"$schema" = 'https://starship.rs/config-schema.json'
add_newline = true
palette = 'gruvbox'

format = """
${custom.tmux_outside}\
[](fg:head)\
${custom.tunhithe}${custom.carrack}${custom.elsewhere}\
$directory\
$git_branch$git_commit$git_state$git_status\
${custom.tmux_after_git}${custom.tmux_after_path}\
${custom.close_after_git}${custom.close_after_path}\
$jobs\
$character"""
right_format = '$status$cmd_duration${custom.account_a}${custom.account_b}$time'

[palettes.pastel]       # Pastel Powerline's colours (M365Princess)
head = '#9A348E'
path = '#DA627D'
git  = '#FCA17D'
tmux = '#86BBD8'
acct = '#06969A'
acctb = '#7B5EA7'
time = '#33658A'
headtext = '#ffffff'
pathtext = '#ffffff'
gittext  = '#1e2127'
tmuxtext = '#1e2127'
accttext = '#ffffff'
timetext = '#ffffff'
dirty    = '#7a1f3d'
lobby    = '#86BBD8'
fail     = '#c0392b'

[palettes.gruvbox]      # Gruvbox Rainbow's colours
head = '#d65d0e'
path = '#d79921'
git  = '#689d6a'
tmux = '#458588'
acct = '#665c54'
acctb = '#b16286'
time = '#3c3836'
headtext = '#fbf1c7'
pathtext = '#fbf1c7'
gittext  = '#fbf1c7'
tmuxtext = '#fbf1c7'
accttext = '#fbf1c7'
timetext = '#fbf1c7'
dirty    = '#fbf1c7'
lobby    = '#83a598'
fail     = '#cc241d'

[palettes.catppuccin]   # Catppuccin Powerline's colours (Mocha)
head = '#fab387'
path = '#f9e2af'
git  = '#a6e3a1'
tmux = '#89b4fa'
acct = '#94e2d5'
acctb = '#cba6f7'
time = '#313244'
headtext = '#1e1e2e'
pathtext = '#1e1e2e'
gittext  = '#1e1e2e'
tmuxtext = '#1e1e2e'
accttext = '#1e1e2e'
timetext = '#cdd6f4'
dirty    = '#1e1e2e'
lobby    = '#89b4fa'
fail     = '#f38ba8'

# ---- the lobby, outside tmux only: its own line above the band ----

[custom.tmux_outside]
shell   = ['/bin/sh']
when    = 'test -z "$TMUX" && tmux list-sessions >/dev/null 2>&1'
command = "$HOME/.local/bin/landingham-status --sessions"
format  = "[  $output]($style)\n"
style   = 'fg:lobby'

# ---- the machine: the head of the band, with its own icon ----

[custom.tunhithe]
shell   = ['/bin/sh']
when    = 'test "$(hostname -s)" = Tunhithe'
command = 'echo Tunhithe'
format  = '[󰍹 $output ]($style)[](fg:head bg:path)'
style   = 'bold fg:headtext bg:head'

[custom.carrack]
shell   = ['/bin/sh']
when    = 'test "$(hostname -s)" = Carrack'
command = 'echo Carrack'
format  = '[󰌢 $output ]($style)[](fg:head bg:path)'
style   = 'bold fg:headtext bg:head'

[custom.elsewhere]
shell   = ['/bin/sh']
when    = 'case "$(hostname -s)" in Tunhithe|Carrack) exit 1;; esac'
command = 'hostname -s'
format  = '[󰒍 $output ]($style)[](fg:head bg:path)'
style   = 'bold fg:headtext bg:head'

# ---- the path: one cell, the repository's root in bold, folders as icons by substitution ----
# $before_root_style does not resolve in starship 1.27.0 (probed 2 November 2026), so the styles are named outright.

[directory]
format                 = '[  $path ]($style)[$read_only]($read_only_style)'
style                  = 'fg:pathtext bg:path'
read_only              = '󰌾 '
read_only_style        = 'fg:pathtext bg:path'
truncation_length      = 3
truncate_to_repo       = false
truncation_symbol      = '…/'
repo_root_style        = 'bold fg:pathtext bg:path'
repo_root_format       = '[  $before_root_path](fg:pathtext bg:path)[$repo_root](bold fg:pathtext bg:path)[$path ](fg:pathtext bg:path)[$read_only](fg:pathtext bg:path)'

[directory.substitutions]
'~/Claude/Projects/CRM' = ' CRM'
'Documents' = '󰈙 '
'Downloads' = ' '
'Music'     = '󰝚 '
'Pictures'  = ' '
'Developer' = '󰲋 '

# ---- git: one cell, entered from the path ----

[git_branch]
format            = '[](fg:path bg:git)[  $branch ]($style)'
style             = 'bold fg:gittext bg:git'
truncation_length = 48

[git_commit]
format        = '[$hash$tag ]($style)'
style         = 'fg:gittext bg:git'
only_detached = false
tag_disabled  = false
tag_symbol    = ' #'

[git_state]
format = '[\($state( $progress_current/$progress_total)\) ]($style)'
style  = 'bold fg:dirty bg:git'

[git_status]
format     = '([$all_status$ahead_behind ]($style))'
style      = 'bold fg:dirty bg:git'
ahead      = '⇡${count}'
behind     = '⇣${count}'
diverged   = '⇕⇡${ahead_count}⇣${behind_count}'
conflicted = '=${count}'
untracked  = '?${count}'
stashed    = '≡${count}'
modified   = '!${count}'
staged     = '+${count}'
renamed    = '»${count}'
deleted    = '✘${count}'

# ---- tmux, inside only: the session and how many others; entered from git or from the path, and closing the band ----

[custom.tmux_after_git]
shell   = ['/bin/sh']
when    = 'test -n "$TMUX" && git rev-parse --is-inside-work-tree >/dev/null 2>&1'
command = 'n=$(tmux list-sessions 2>/dev/null | wc -l | tr -d " "); printf "%s" "$(tmux display-message -p "#S")"; [ "$n" -gt 1 ] && printf " +%s" "$((n-1))"'
format  = '[](fg:git bg:tmux)[  $output ]($style)[](fg:tmux)'
style   = 'fg:tmuxtext bg:tmux'

[custom.tmux_after_path]
shell   = ['/bin/sh']
when    = 'test -n "$TMUX" && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1'
command = 'n=$(tmux list-sessions 2>/dev/null | wc -l | tr -d " "); printf "%s" "$(tmux display-message -p "#S")"; [ "$n" -gt 1 ] && printf " +%s" "$((n-1))"'
format  = '[](fg:path bg:tmux)[  $output ]($style)[](fg:tmux)'
style   = 'fg:tmuxtext bg:tmux'

# ---- outside tmux the band ends at git or at the path: these draw that last chevron ----

[custom.close_after_git]
shell   = ['/bin/sh']
when    = 'test -z "$TMUX" && git rev-parse --is-inside-work-tree >/dev/null 2>&1'
format  = '[](fg:git)'

[custom.close_after_path]
shell   = ['/bin/sh']
when    = 'test -z "$TMUX" && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1'
format  = '[](fg:path)'

# ---- after the band: background jobs, then the prompt ----

[jobs]
symbol           = ''
number_threshold = 1
format           = ' [$symbol $number]($style)'

[character]
success_symbol = ' '
error_symbol   = ' '

# ---- the right-hand side: the failure flag, a slow command, the account a `claude` typed here would use, the clock ----

[status]
disabled = false
format   = '[](fg:fail)[ $status ]($style)[](fg:fail) '
style    = 'bold fg:#ffffff bg:fail'

[cmd_duration]
min_time = 2000
format   = '[$duration]($style) '
style    = 'fg:#999999'

[custom.account_a]
shell   = ['/bin/sh']
when    = 'test -z "${CLAUDE_CONFIG_DIR:-}"'
format  = '[](fg:acct)[󱚝 A]($style)[](fg:acct) '
style   = 'bold fg:accttext bg:acct'

[custom.account_b]
shell   = ['/bin/sh']
when    = 'case "${CLAUDE_CONFIG_DIR:-}" in *claude-b*) exit 0;; *) exit 1;; esac'
format  = '[](fg:acctb)[󱚝 B]($style)[](fg:acctb) '
style   = 'bold fg:accttext bg:acctb'

[time]
disabled    = false
format      = '[](fg:time)[󰥔 $time]($style)[](fg:time)'
time_format = '%H:%M'
style       = 'fg:timetext bg:time'
LANDINGHAM_PAYLOAD_END
}

payload_landingham_status() {
cat <<'LANDINGHAM_PAYLOAD_END'
#!/usr/bin/env bash
# landingham-status — one line about the controllers and the store, for the tmux status bar (every 30 s), for a
# shell by hand, with --sessions for the prompt's lobby line outside tmux, and with --claude for Claude Code's own
# status line. It reads only: tmux's pane titles and activity times, the lease files, and the store's baton
# (`corpus baton`, a reading verb, cached for 60 s because Node takes half a second). On a machine without the
# controllers, the leases or the store, those parts are simply absent.
#
#   A20 4m · B12+ 2h · baton B12 · heavy: B-12 records push · slots 1/4
set -u
# The machine's own particulars live in ~/.config/beachhead/env, read here too because the tmux server's
# environment is bare: LANDINGHAM_REPOSITORY (the checkout with the store's CLI) and LANDINGHAM_STORE (the store file).
# Without them the baton is simply not shown.
if [ -r "$HOME/.config/beachhead/env" ]; then
  while IFS= read -r l; do case "$l" in LANDINGHAM_*=*|PROCESS_*=*) export "$l";; esac; done < "$HOME/.config/beachhead/env"
fi
tmux=$(command -v tmux 2>/dev/null || true)
repo=${LANDINGHAM_REPOSITORY:-}
store=${LANDINGHAM_STORE:-}
cache=${TMPDIR:-/tmp}/landingham-baton-$(id -u)
now=$(date +%s)
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
ago() { local s=$(( now - $1 )); if [ "$s" -lt 60 ]; then echo "${s}s"; elif [ "$s" -lt 3600 ]; then echo "$(( s / 60 ))m"; elif [ "$s" -lt 86400 ]; then echo "$(( s / 3600 ))h"; else echo "$(( s / 86400 ))d"; fi; }
short() {  # "✳ CRM Controller Tunhithe-A 20" -> A20
  local l=$1; l=${l#✳ }; l=${l#CRM }; l=${l#Controller }; l=${l#Tunhithe-}; l=${l#Carrack-}; echo "${l// /}"
}
join() { local IFS='|'; local out="$*"; echo "${out//|/ · }"; }

if [ "${1:-}" = --sessions ]; then
  # The lobby: every tmux session you could join, who is in it (by the pane title Claude Code sets), and its last activity.
  [ -n "$tmux" ] || exit 0
  rooms=()
  while IFS=$'\t' read -r s act att title; do
    who=''; case "$title" in *Controller*) who="$(short "$title") ";; esac
    mark=''; [ "${att:-0}" -gt 0 ] && mark='+'
    rooms+=("${s}${mark}=${who}$(ago "$act")")
  done < <("$tmux" list-panes -a -F $'#{session_name}\t#{session_activity}\t#{session_attached}\t#{pane_title}' 2>/dev/null)
  [ ${#rooms[@]} -gt 0 ] && join "${rooms[@]}"
  exit 0
fi

parts=()
if [ -n "$tmux" ]; then
  while IFS=$'\t' read -r s act att title; do
    case "$title" in *Controller*) ;; *) continue;; esac
    mark=''; [ "${att:-0}" -gt 0 ] && mark='+'
    parts+=("$(short "$title")${mark} $(ago "$act")")
  done < <("$tmux" list-panes -a -F $'#{session_name}\t#{session_activity}\t#{session_attached}\t#{pane_title}' 2>/dev/null)
fi
if [ -n "$store" ] && [ -f "$store" ] && [ -n "$repo" ] && [ -d "$repo" ] && command -v node >/dev/null; then
  if [ ! -f "$cache" ] || [ $(( now - $(mtime "$cache") )) -gt 60 ]; then
    ( cd "$repo" && node corpus/cli.mjs baton 2>/dev/null | sed -n 's/^  Holder: \(.*\) — session.*/\1/p' | head -1 > "$cache.new" )
    if [ -s "$cache.new" ]; then mv "$cache.new" "$cache"; else rm -f "$cache.new" "$cache"; fi   # an empty answer is never cached
  fi
  holder=$(cat "$cache" 2>/dev/null); [ -n "$holder" ] && parts+=("baton $(short "$holder")")
fi
heavy=$HOME/satellite/leases/heavy
if [ -f "$heavy" ]; then label=$(sed -n 's/.*"label":"\([^"]*\)".*/\1/p' "$heavy"); [ -n "$label" ] && parts+=("heavy: $label"); fi
slots=$HOME/satellite/leases/agent-slots
if [ -d "$slots" ]; then held=$(ls "$slots" 2>/dev/null | wc -l | tr -d ' '); parts+=("slots $held/${PROCESS_AGENT_SLOTS:-4}"); fi
line=''; [ ${#parts[@]} -gt 0 ] && line=$(join "${parts[@]}")
if [ "${1:-}" = --claude ]; then
  head=$(python3 -c 'import json,sys,os
d=json.load(sys.stdin); m=d.get("model",{}).get("display_name",""); w=d.get("workspace",{}).get("current_dir","")
print(" · ".join(x for x in (m, os.path.basename(w)) if x))' 2>/dev/null)
  echo "${head:+$head · }$line"
else
  echo "$line"
fi
LANDINGHAM_PAYLOAD_END
}

payload_beachhead_palette() {
cat <<'LANDINGHAM_PAYLOAD_END'
#!/usr/bin/env bash
# beachhead-palette — which starship config a shell in this folder should use. Called by the shell on every
# directory change (fish --on-variable PWD, zsh chpwd, bash PROMPT_COMMAND); its one line of output is STARSHIP_CONFIG.
#
#   The template is ~/.config/starship/starship.toml; its `palette = '…'` line is the DEFAULT, used wherever no project
#   says otherwise. Change the default by editing that line, or: beachhead-palette --default gruvbox
#   A project claims its colours with a `.prompt-palette.toml` at its root: a `palette = '<name>'` line and, if the
#   template does not already define that name, a `[palettes.<name>]` table. The hook walks up from the current folder
#   to the first such file, so a worktree inside the project inherits it, and builds the project's config once as
#   ~/.cache/starship/<name>.toml (the template with its palette line changed and the project's table appended),
#   rebuilding only when the template or the project's file is newer.
set -u
template=${PROMPT_TEMPLATE:-$HOME/.config/starship/starship.toml}
cache=${PROMPT_CACHE:-$HOME/.cache/starship}
if [ "${1:-}" = --default ]; then
  [ -n "${2:-}" ] || { echo 'usage: beachhead-palette --default <palette>' >&2; exit 64; }
  grep -q "^\[palettes\.$2\]" "$template" || { echo "the template defines no palette named $2" >&2; exit 65; }
  sed "s|^palette = .*|palette = '$2'|" "$template" > "$template.new" && mv "$template.new" "$template" && echo "default palette: $2"; exit
fi
dir=$PWD; project=''
while [ "$dir" != / ] && [ -n "$dir" ]; do
  if [ -f "$dir/.prompt-palette.toml" ]; then project=$dir/.prompt-palette.toml; break; fi
  dir=$(dirname "$dir")
done
[ -n "$project" ] || { echo "$template"; exit 0; }
name=$(sed -n "s/^palette *= *'\([^']*\)'.*/\1/p" "$project" | head -1)
[ -n "$name" ] || { echo "$template"; exit 0; }
built=$cache/$name.toml
if [ ! -f "$built" ] || [ "$template" -nt "$built" ] || [ "$project" -nt "$built" ]; then
  mkdir -p "$cache"
  { sed "s|^palette = .*|palette = '$name'|" "$template"; echo; echo "# ---- from $project ----"; grep -v "^palette *=" "$project"; } > "$built.new" && mv "$built.new" "$built"
fi
echo "$built"
LANDINGHAM_PAYLOAD_END
}

payload_beachhead_fish() {
cat <<'LANDINGHAM_PAYLOAD_END'
# ~/.config/fish/conf.d/beachhead.fish — installed by beachhead's prompt installer. Nothing here prints.
# Homebrew on a Mac, ~/.local/bin on every machine, the shared variables, then the prompt with its per-folder palette.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv | source
end
fish_add_path --global --move ~/.local/bin
if test -r ~/.config/beachhead/env
    for line in (string match -r '^[A-Za-z_][A-Za-z0-9_]*=.*' < ~/.config/beachhead/env)
        set -l kv (string split -m1 = -- $line)
        set -gx $kv[1] (string trim -c '"' -- $kv[2])
    end
end
if status is-interactive; and command -q starship
    function __beachhead_palette --on-variable PWD
        set -gx STARSHIP_CONFIG (beachhead-palette)
    end
    __beachhead_palette
    starship init fish | source
end

# `account a` or `account b`: the Claude account a `claude` typed in THIS shell uses (the prompt's pill follows at the
# next prompt). With --save the choice is kept in ~/.config/beachhead/env, so every new shell after a re-login
# starts that way until the next --save. `account` alone says which. B's folder is CLAUDE_CONFIG_DIR_B, else ~/.claude-b.
function account --description 'the Claude account a `claude` typed here uses: account a|b [--save]'
    set -l env ~/.config/beachhead/env
    set -l which $argv[1]; set -l save (contains -- --save $argv; and echo yes)
    switch "$which"
        case a A
            set -e CLAUDE_CONFIG_DIR; set -eg CLAUDE_CONFIG_DIR
            echo 'claude: A (the default folder)'
        case b B
            set -l dir (set -q CLAUDE_CONFIG_DIR_B; and echo $CLAUDE_CONFIG_DIR_B; or echo ~/.claude-b)
            test -d $dir; or begin; echo "account b: no folder at $dir on this machine" >&2; return 66; end
            set -gx CLAUDE_CONFIG_DIR $dir
            echo "claude: B ($dir)"
        case ''
            if set -q CLAUDE_CONFIG_DIR; echo "claude: B ($CLAUDE_CONFIG_DIR)"; else; echo 'claude: A (the default folder)'; end
            return 0
        case '*'
            echo 'usage: account a|b [--save]' >&2; return 64
    end
    if test -n "$save"; and test -w $env
        grep -v '^CLAUDE_CONFIG_DIR=' $env > $env.new
        if set -q CLAUDE_CONFIG_DIR; echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> $env.new; end
        mv $env.new $env; and echo "  saved: new shells start on $which"
    end
end
complete -c account -f -a 'a b'
complete -c account -l save -d 'keep the choice for every new shell'
LANDINGHAM_PAYLOAD_END
}

payload_tmux_conf() {
cat <<'LANDINGHAM_PAYLOAD_END'
# ~/.tmux.conf — installed by beachhead's prompt installer. The status bar is the one line always on screen, so it
# carries the room: this machine, this session, the controllers' activity, the baton and the leases (where they exist).
# Every command is an absolute path, because the tmux server on Tunhithe is born under env -i.
set -g default-terminal 'tmux-256color'
set -g history-limit 20000
set -g status-interval 30
set -g status-position bottom
set -g status-left-length 40
set -g status-right-length 180
set -g status-style 'bg=#3a3f4b,fg=#e6e6e6'
set -g @machine_bg '#c0392b'
if-shell 'test "$(hostname -s)" = Tunhithe' 'set -g @machine_bg "#2f6fdb"'
if-shell 'test "$(hostname -s)" = Carrack'  'set -g @machine_bg "#2e9e5b"'
set -g status-left '#[bg=#{@machine_bg},fg=#ffffff,bold] #h #[bg=#555b69,fg=#{@machine_bg}]#[bg=#555b69,fg=#ffffff] #S #[bg=#3a3f4b,fg=#555b69]#[default] '
set -g status-right '#[fg=#e6e6e6]#(__HOME__/.local/bin/landingham-status) #[fg=#555b69]#[bg=#555b69,fg=#ffffff,bold] %H:%M '
set -g window-status-current-style 'bg=#555b69,fg=#ffffff,bold'
bind S display-message '#(__TMUX__ list-sessions -F "#{session_name}#{?session_attached,+,}" | tr "\n" " ")'
LANDINGHAM_PAYLOAD_END
}

payload_prompt_palette_toml() {
cat <<'LANDINGHAM_PAYLOAD_END'
# .prompt-palette.toml — Landingham's colours for the shell prompt, picked up by the prompt hook whenever a shell
# is inside this folder (worktrees included). The names follow docs/design/HOUSE-STYLE.md and the iOS colour sets:
# verdigris and clay on parchment, moss for good news, crimson for trouble. Keep the table's keys as they are:
# the prompt's cells are named by them.
palette = 'landingham'

[palettes.landingham]
head  = '#1F6F63'   # verdigris: the machine
path  = '#B4651C'   # clay: the path
git   = '#4F7A43'   # moss: git
tmux  = '#52A294'   # verdigris, dark appearance: the tmux room
acct  = '#6E6960'   # muted: account A
acctb = '#8C2B2B'   # crimson: account B
time  = '#1F1B15'   # ink: the clock
headtext = '#F1EDE4'
pathtext = '#F1EDE4'
gittext  = '#F1EDE4'
tmuxtext = '#15120E'
accttext = '#F1EDE4'
timetext = '#F1EDE4'
dirty    = '#F7EADC'
lobby    = '#52A294'
fail     = '#8C2B2B'
LANDINGHAM_PAYLOAD_END
}

# ---- 1. packages ----
step "packages"
if [ $PACKAGES = 0 ]; then say "  skipped (--no-packages)"
elif [ $PLATFORM = mac ]; then
  [ -n "$HOMEBREW" ] || { echo "Homebrew is not installed; install it first (https://brew.sh), then run this again." >&2; exit 66; }
  for f in starship fish bash tmux; do "$HOMEBREW" list --formula "$f" >/dev/null 2>&1 && say "  present: $f" || soft "$HOMEBREW" install "$f"; done
  if [ $FONT = 1 ]; then
    if [ -f "$HOME/Library/Fonts/FiraCodeNerdFontMono-Regular.ttf" ] || [ -f /Library/Fonts/FiraCodeNerdFontMono-Regular.ttf ]; then say "  present: FiraCode Nerd Font Mono (the font files are in place; the cask is not needed)"
    elif "$HOMEBREW" list --cask font-fira-code-nerd-font >/dev/null 2>&1; then say "  present: font-fira-code-nerd-font"
    else soft "$HOMEBREW" install --cask font-fira-code-nerd-font; fi
  fi
else
  if command -v apt-get >/dev/null; then
    missing=''; for p in fish tmux curl ca-certificates; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    if [ -n "$missing" ]; then soft $SUDO apt-get update -qq; soft $SUDO apt-get install -y -qq $missing; else say "  present: fish tmux curl"; fi
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
  found=''; n=0
  for f in "$HOME/Library/Application Support"/*/process/corpus.sqlite; do [ -f "$f" ] && { found=$f; n=$((n+1)); }; done
  if [ $n = 1 ]; then env_add LANDINGHAM_STORE "$found"; elif [ $n = 0 ]; then say "  no process store on this Mac: LANDINGHAM_STORE not set (the baton shows only where the store is)"; else say "  $n process stores found under Application Support: name LANDINGHAM_STORE in $ENV_FILE yourself"; fi
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
install_block "$HOME/.bashrc" "$BASH_BLOCK" top
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
  if [ $PLATFORM = linux ] && [ -n "$SUDO" ] && sudo -n true 2>/dev/null; then
    say "  sudo asks nothing here, so chsh goes through it (chsh by itself would ask for a password this user may not have):"
    run sudo chsh -s "$FISH" "$(id -un)"
  elif [ $NOTTY = 1 ]; then
    say "  skipped: no terminal to take a password; afterwards: chsh -s $FISH"; CHSH=0
  else
    say "  this asks for your password:"; run chsh -s "$FISH"
  fi
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
else BEACHHEAD_NOTTY=1 main "$@"
fi
