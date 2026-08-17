# Edwin Editor

A small, portable editing and coding-agent setup for Ghostty, Herdr, Vim,
Neovim, VSCodeVim, and Pi. The local checkout is the source of truth;
`bootstrap.sh` can deploy that exact working tree to a long-lived machine over
SSH.

## Local setup

```sh
./install.sh
```

Requires `git`, `curl`, `cc`, and `make`.

The first run:

- installs stable tools, including Node 24, Pi 0.84.2, and chezmoi, with
  [mise](https://mise.jdx.dev/),
- clones and synchronizes the private `ocyedwin/skills` repository,
- installs `git:github.com/ocyedwin/pi-langfuse` globally with Pi, and
- applies the dotfiles in `home/` with chezmoi. This includes the Herdr user
  configuration; Ghostty is included only on macOS.

The checkout stays the chezmoi source directory. Preview and apply later edits
from the repository root:

```sh
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

Chezmoi links both `~/.codex/AGENTS.md` and `~/.pi/agent/AGENTS.md` directly
to `home/.chezmoitemplates/AGENTS.md` in this checkout. The shared file starts
empty; edit it here, then start a new Codex session or run `/reload` in Pi.
Rerun `chezmoi apply` if this checkout moves. Remote changes take effect after
the next `bootstrap.sh` deployment.

Personal skills live in a separate checkout at
`~/.local/share/edwin-skills`. Its synchronizer exposes each managed skill
under `~/.agents/skills`, which both
[Codex](https://learn.chatgpt.com/docs/build-skills) and
[Pi](https://pi.dev/docs/latest/skills) discover natively, and keeps the
existing Claude Code links under `~/.claude/skills`. It preserves unrelated
entries such as `~/.agents/.skill-lock.json` and refuses to replace a real
skill directory.

The private checkout requires non-interactive GitHub SSH access on every
machine. Verify it before installing:

```sh
git ls-remote git@github.com:ocyedwin/skills.git HEAD
```

If the standard GitHub host uses a work identity, the installer also supports
`git@github-ocyedwin:ocyedwin/skills.git`. It selects an accessible allowed
URL and updates an existing skills checkout between those two URLs when needed.

The first successful sync installs a five-minute LaunchAgent on macOS or
systemd user timer on Linux. Validated fast-forward commits to `skills/main`
are therefore production deployments. Codex normally detects changes
automatically; use `/reload` in Pi after a skill changes.

Each `install.sh` run reconciles `pi-langfuse` with its `main` branch. Between
installs, update it from this checkout with `mise exec -- pi update
--extensions`. Langfuse credentials stay outside this repository; tracing
remains disabled until Pi inherits all three:

```sh
LANGFUSE_PUBLIC_KEY=pk-lf-...
LANGFUSE_SECRET_KEY=sk-lf-...
LANGFUSE_BASE_URL=https://langfuse.example.com
```

When enabled, the extension sends raw prompts, system prompts, messages,
images, tool arguments and results, and context metadata without redaction.

VSCodeVim should keep using the shared file:

```jsonc
"vim.vimrc.enable": true,
"vim.vimrc.path": "$HOME/.vimrc",
"vim.leader": "<space>",
"vim.normalModeKeyBindingsNonRecursive": [
  {
    "before": ["<leader>", "<leader>"],
    "commands": ["workbench.action.quickOpen"]
  }
]
```

`Space Space` then opens the project file picker in both VSCodeVim and
Neovim.

## Remote setup

Deploy the current local checkout's tracked files, including working-tree
modifications and staged additions, plus the matching custom Herdr binary from
the newest sibling checkout matching `../????-??-??-ocyedwin-herdr/target`:

```sh
./bootstrap.sh workbox
```

Bootstrap detects the remote OS and architecture before changing it. If the
sibling checkout has no matching release build, bootstrap stops with the build
path it expects. Override discovery with `HERDR_BINARY=/path/to/herdr`.

Bootstrap refuses to run while non-ignored untracked files exist, before it
contacts the remote. Review each new file and either stage it deliberately or
add it to `.gitignore` first.

`workbox` can be any SSH config alias or `user@host`. SSH configuration owns
ports, keys, and jump hosts. The snapshot is installed at
`~/.local/share/edwin-editor`, with the prior snapshot retained as
`~/.local/share/edwin-editor.previous`.

The remote copy is a deployment artifact, not a Git checkout. Make changes
locally and rerun `bootstrap.sh`.

If remote installation fails, inspect the retained snapshot and restore it
with:

```sh
ssh workbox 'data=$HOME/.local/share; previous=$data/edwin-editor.previous; current=$data/edwin-editor; failed=$data/edwin-editor.failed.$(date +%Y%m%d%H%M%S).$$; test -x "$previous/install.sh" && test ! -e "$failed" && mv "$current" "$failed" && mv "$previous" "$current"'
```

## Workflow

```sh
# local persistence
herdr

# attach to a persistent Herdr session on a remote machine
herdr --remote workbox

# conventional SSH path
ssh workbox
herdr
```

Caps Lock remains mapped to Control in macOS Keyboard Settings. Ghostty leaves
terminal keys unchanged; navigation belongs to Vim's Normal and Visual modes.
The shared Vimrc provides the same Colemak motions in Vim, Neovim, and VSCodeVim:

| Keys | Movement |
| --- | --- |
| `n` / `e` | One line down / up |
| `N` / `E` | Half-page down / up |
| `Ctrl+N` / `Ctrl+E` | Next / previous paragraph |
| `k` / `K` | Continue / reverse the last search |

Counts work with line movement (`5n`, `3e`), and Visual mode extends the
selection with the same keys. Insert mode keeps native editor and completion
bindings; use `dh`, `Esc`, or `Ctrl+[` to return to Normal mode. Neovim also
retains LazyVim's `s` Flash jump for visible targets.

Hunk 0.18 or newer uses the same navigation direction: `n` / `e` move down / up,
`Ctrl+N` / `Ctrl+E` select the next / previous hunk, and `N` / `E` page down
/ up. Arrow, Page Up/Down, and Space bindings remain available.

## Updating

Tools intentionally follow their latest stable releases. Plugins are pinned
by `home/dot_config/nvim/lazy-lock.json`; update them deliberately with
`:Lazy update`, then import and commit the resulting lockfile:

```sh
chezmoi --source "$PWD" re-add ~/.config/nvim/lazy-lock.json
```

Run the checks with:

```sh
./test.sh
```
