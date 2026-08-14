# Edwin Editor

A small, portable editing setup for Ghostty, Herdr, Vim, Neovim, and
VSCodeVim. The local checkout is the source of truth; `bootstrap.sh` can deploy
that exact working tree to a long-lived machine over SSH.

## Local setup

```sh
./install.sh
```

The first run:

- installs stable editor tools, including chezmoi, with
  [mise](https://mise.jdx.dev/), and
- applies the dotfiles in `home/` with chezmoi. This includes the Herdr user
  configuration; Ghostty is included only on macOS.

The checkout stays the chezmoi source directory. Preview and apply later edits
from the repository root:

```sh
chezmoi --source "$PWD" diff
chezmoi --source "$PWD" apply
```

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
`../2026-08-12-herdrdev-herdr/target`:

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
