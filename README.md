# Edwin Editor

A small, portable editing setup for Ghostty, Herdr, Vim, Neovim, and
VSCodeVim. The local checkout is the source of truth; `bootstrap.sh` can deploy
that exact working tree to a long-lived machine over SSH.

## Local setup

```sh
./install.sh --ghostty
```

The first run:

- installs stable editor tools with [mise](https://mise.jdx.dev/),
- links `nvim/` to `~/.config/nvim`,
- copies an existing `~/.vimrc` to `~/.vimrc.bak`, then links the tracked
  `nvim/vimrc` in its place, and
- optionally links the tracked Ghostty configuration on macOS.

An existing `~/.vimrc.bak` is never overwritten. If it differs from the
current Vimrc, installation stops for manual resolution.

VSCodeVim should keep using the shared file:

```jsonc
"vim.vimrc.enable": true,
"vim.vimrc.path": "$HOME/.vimrc"
```

## Remote setup

Deploy the current local checkout, including modified and untracked
non-ignored files:

```sh
./bootstrap.sh workbox
```

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
terminal keys unchanged; navigation belongs to Vim's Normal mode. The
shared Vimrc provides the same Colemak motions in Vim, Neovim, and VSCodeVim:

| Keys | Movement |
| --- | --- |
| `n` / `e` | One line down / up |
| `N` / `E` | Next / previous paragraph |
| `Ctrl+N` / `Ctrl+E` | Half-page down / up |
| `k` / `K` | Continue / reverse the last search |

Counts work with line movement (`5n`, `3e`). Insert mode keeps native editor
and completion bindings; use `dh`, `Esc`, or `Ctrl+[` to return to Normal
mode. Neovim also retains LazyVim's `s` Flash jump for visible targets.

## Updating

Tools intentionally follow their latest stable releases. Plugins are pinned
by `nvim/lazy-lock.json`; update them deliberately with `:Lazy update` and
commit the resulting lockfile.

Run the checks with:

```sh
./test.sh
```
