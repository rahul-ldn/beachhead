# prompt — the command line on the household's machines, by one command

    curl -fsSL https://rahul-ldn.github.io/beachhead/prompt/install.sh | bash

| | What it is |
|---|---|
| `install.sh` | The one file that is the whole install: the logic with every payload file embedded. Built from `installer-head.sh`, `payload/` and `installer-tail.sh` by `python3 build-installer.py`. It tells a Mac from a Linux server itself (Homebrew or apt; the font on a Mac only). Its header lists the options and what it never touches. |
| `payload/starship.toml` | The prompt: one line, a rounded cap, cells joined by chevrons (machine › path › git › tmux), the command typed straight after; on the right the failure flag, a slow command's time, the Claude account (A teal, B violet), the clock. Outside tmux a lobby line above it lists the sessions you could join with their controllers; inside tmux the status bar carries that. Palettes: `gruvbox` (the default), `pastel`, `catppuccin`. Assumes FiraCode Nerd Font Mono. |
| `payload/prompt-palette.toml` | A project's own colours, placed at a checkout's root as `.prompt-palette.toml`: inside it, worktrees included, the band wears them. This one is Landingham's (its house style's verdigris, clay, moss and crimson); any project may carry such a file. |
| `payload/beachhead` | The command for afterwards: `beachhead status` (each part's last run), `beachhead check` (is the installed build the served one?), `beachhead update [part] [options]` (fetch the current installer and run it; `--dry-run` passes through). |
| `payload/beachhead-palette` | The hook each shell runs on a directory change: finds the nearest `.prompt-palette.toml` upwards, builds that palette's config once under `~/.cache/starship/`, and prints the path for `STARSHIP_CONFIG`. `--default <name>` changes the default palette. |
| `payload/landingham-status` | One line about the room. On a Mac: the controllers (from the tmux pane titles Claude Code sets), the store's baton (cached 60 s; shown only where the environment file names the store), the heavy lease and the agent slots. On a machine running a Compose stack: every service's state, the last backup, disk, load, memory and the host's own guards (docker, fail2ban, the upgrades, any timer of ours), found through Docker's and systemd's listings. Reads only. For the tmux status bar, the prompt's lobby lines (`--sessions`, `--ops`) and Claude Code's status line (`--claude`). |
| `payload/beachhead.fish` | fish's drop-in (`~/.config/fish/conf.d/`): Homebrew on a Mac, `~/.local/bin`, the shared variables, the hook, starship, and `account`. |
| `payload/tmux.conf` | The status bar: the machine, the session, the controllers' line, the clock. Absolute paths, because a tmux server may be born under `env -i`. |

## Switching the Claude account

`account b` makes a `claude` typed in that shell start under account B (its folder from `CLAUDE_CONFIG_DIR_B` in the
environment file, `~/.claude-b` by default); `account a` goes back; `account` alone says which; the prompt's pill
follows at the next prompt. `account b --save` keeps the choice in the environment file, so every new shell after a
re-login starts that way until the next `--save`. The same words work in fish, zsh and bash.

## What it does, in order

1. **Packages.** A Mac: `brew install starship fish bash` (Apple's bash is the 2007 one), tmux if missing, the font
   cask. Debian or Ubuntu: `apt-get install fish tmux curl`, and starship from its GitHub release tarball into
   `~/.local/bin` with the published sha256 checked, never `curl | sh`.
2. **The files** above, each replaced only when it differs, the old one kept with a dated suffix.
3. **The environment file** `~/.config/beachhead/env`: the one place for variables every shell on the machine
   carries, never a secret, never overwritten. It seeds `CLAUDE_CODE_SHELL` with the modern bash, because Claude Code's
   Bash tool accepts only bash or zsh, fish never, and this pins it whatever the login shell is. It also records the process store and its
   checkout where it finds them (by their shape, never by name), for the baton in the status bar.
4. **zsh and bash**, as marked blocks in `~/.zshrc`, `~/.bashrc` and `~/.bash_profile`, replaced in place on a re-run.
   The bash block's first half runs for every bash, Claude Code's included (it sources `~/.bashrc` at session start):
   the paths and the variables, nothing that prints. The prompt comes after the interactive guard. The block goes at
   the **top** of `.bashrc`, because a Debian user's stock `.bashrc` returns early for a non-interactive shell and the
   block must come before that return.
5. **Palettes**: the default, and the project's file at the checkout's root (`--project DIR`; a Mac's
   `~/Claude/Projects/CRM` when it exists).
6. **Claude Code's status line** in `~/.claude/settings.json`, by a JSON merge, the old file kept.
7. **fish as the login shell** (`/etc/shells`, then `chsh`). On a Mac this asks your password. On a server whose admin
   user has passwordless sudo, which is how the household's is provisioned, `chsh` goes through sudo and asks nothing,
   because `chsh` by itself asks for a password that user does not have. With neither a terminal nor free sudo it is
   skipped and said.
8. **The band printed live**, home and project, and the tally of checks, which is also appended to the part's record
   at `~/.config/beachhead/installed/prompt`: one line a run, with the build's digest.

## What it never touches

`~/.config/landingham/` and `~/.config/landingham-access/`, any Keychain, the controllers' start scripts (which hard-set
their own shell and so are unmoved by the login shell changing), and anything secret.

## Tested, 2 November 2026

On a Mac into a scratch home, piped (every stage but packages and chsh: 12 of 15 checks, the three being the
packages not installed), and end to end in a Debian 13 container (fish 4.0.2 from apt, starship 1.27.0 from the
tarball, chsh, both palettes, Claude's bash environment, `account` in fish and bash, `--save`, a second run changing
nothing: 15 of 15). Not yet run against a real home folder on any machine.
