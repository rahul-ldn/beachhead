# beachhead

The scripts that take a new machine and make it one of the household's: each part is one command, re-runnable
without harm, that sets up one aspect of the environment on a Mac or a Debian/Ubuntu server. GitHub Pages serves
the built files, so a part is installed by one line wherever `curl` runs. Nothing here is secret: the parts name
machines and a project, and read anything private from files that stay on each machine.

| Part | What it sets up | The one command |
|---|---|---|
| [`prompt/`](prompt/) | The shell prompt (starship, a chevron band with a palette per project), fish as the shell typed in, bash for Claude Code's tool, the tmux status bar, Claude Code's status line, the shared environment file | `curl -fsSL https://rahul-ldn.github.io/beachhead/prompt/install.sh \| bash` |

The same line on a Mac or a server: each part tells the platform apart itself (a server, having no screen, gets no font).
To see what a part would do first: `… | bash -s -- --dry-run`.
Every part ends each stage with its checks (✓/✗), and its exit status is the number of checks that failed.

Parts to come: absorbing a new VPS (users, keys, the firewall, Docker, the backup's alarm), and whatever else a new
machine needs before it can carry Landingham or another project.

## On each machine

`~/.config/beachhead/` is the parts' common ground: `env`, one file of the variables every shell on the machine
carries, which every part reads and may add a line to but never rewrites; and `installed/<part>`, one line a run
from each part, with the build it was (a digest of the sources) and how its checks went. One file for what must agree, one record per part.

Afterwards, on the machine: `beachhead status`, `beachhead check`, and `beachhead update [part]` to fetch and re-run
the current installer.

Each part's `install.sh` is **built, never edited**: its sources are beside it, and `python3 build-installer.py`
in the part's folder assembles the one file. The workflow refuses a push where a built file is stale.
