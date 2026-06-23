# tms (tmux-session-manager)

A lightweight session manager for tmux in pure bash.

Workspace layout is declared in `tms.env`: project sessions (code, debg, logs windows), a shared
ssh session, a shared llm session for local model serving and agents, and a unified logs session for
system-level streams. Running `tms` compares that declaration against live tmux state and only
creates or rebuilds what has drifted — existing windows are left alone. Requires tmux >= 3.2.

Each attach creates a grouped-session clone so multiple terminals can track different windows without
clobbering each other's view. If `fzf` is available, `tms [session]` drops into a fuzzy window
picker; without it, `choose-tree` is used as a fallback.

## Usage

```bash
# First run — build the workspace from tms.env
tms init

# Preview what would change without touching tmux
tms init --dry-run

# Tear down and rebuild all sessions from scratch
tms init --reset

# Attach to a session (fuzzy picker if fzf is present)
tms
tms <session>
tms <session> <window>
```

## Setup

```bash
# 1. Copy and edit the environment file
cp tms.env ~/.tms.env

# 2. Put tms somewhere on your PATH
ln -s /path/to/tms ~/.local/bin/tms

# 3. (Optional) install tab completion
source tms-completion.bash   # or drop it in your bash-completion dir
```

`TMS_ENV_PATH` overrides the config location if you keep it somewhere other than `~/.tms.env`.


