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

Caps Lock remains mapped to Control in macOS Keyboard Settings. Ghostty turns
Ctrl+H/N/E/I into left/down/up/right throughout the terminal. The shared
Vimrc provides the same motions in Vim and VSCodeVim, including Insert mode.

Trade-off: Ctrl+I replaces Vim's jump-forward binding and may also be
indistinguishable from Tab in terminals using legacy key encoding.

## Updating

Tools intentionally follow their latest stable releases. Plugins are pinned
by `nvim/lazy-lock.json`; update them deliberately with `:Lazy update` and
commit the resulting lockfile.

Run the checks with:

```sh
./test.sh
```
