#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 && -z ${EDWIN_EDITOR_TEST_PTY:-} ]]; then
  command -v script >/dev/null 2>&1 || {
    printf 'FAIL: a PTY or the script command is required\n' >&2
    exit 1
  }
  export EDWIN_EDITOR_TEST_PTY=1
  case $(uname -s) in
    Darwin) exec script -q /dev/null "$0" "$@" ;;
    Linux)
      printf -v quoted_script '%q' "$0"
      exec script -qec "$quoted_script" /dev/null
      ;;
    *)
      printf 'FAIL: unsupported test platform\n' >&2
      exit 1
      ;;
  esac
fi
[[ -t 0 ]] || {
  printf 'FAIL: unable to create a test PTY\n' >&2
  exit 1
}

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/edwin-editor-test.XXXXXX")

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f $1 ]] || fail "expected file: $1"
}

assert_absent() {
  [[ ! -e $1 && ! -L $1 ]] || fail "expected absent path: $1"
}

sh -n "$ROOT/install.sh"
bash -n "$ROOT/bootstrap.sh"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/install.sh" "$ROOT/bootstrap.sh" "$ROOT/test.sh"
fi

ghostty=
if command -v ghostty >/dev/null 2>&1; then
  ghostty=$(command -v ghostty)
elif [[ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]]; then
  ghostty=/Applications/Ghostty.app/Contents/MacOS/ghostty
fi
if [[ -n $ghostty ]]; then
  "$ghostty" +validate-config --config-file="$ROOT/home/Library/Application Support/com.mitchellh.ghostty/config"
fi

chezmoi=
if command -v chezmoi >/dev/null 2>&1; then
  chezmoi=$(command -v chezmoi)
elif [[ -x $HOME/.local/bin/chezmoi ]]; then
  chezmoi=$HOME/.local/bin/chezmoi
fi
if [[ -n $chezmoi ]]; then
  CHEZMOI_HOME=$TEMP_DIR/chezmoi-home
  mkdir -p "$CHEZMOI_HOME"
  "$chezmoi" --source "$ROOT" --destination "$CHEZMOI_HOME" apply
  "$chezmoi" --source "$ROOT" --destination "$CHEZMOI_HOME" verify
  assert_file "$CHEZMOI_HOME/.config/nvim/init.lua"
  assert_file "$CHEZMOI_HOME/.config/hunk/config.toml"
  assert_file "$CHEZMOI_HOME/.config/herdr/config.toml"
  [[ -L $CHEZMOI_HOME/.vimrc ]] || fail "chezmoi did not create the Vimrc symlink"
fi

nvim=
if command -v nvim >/dev/null 2>&1; then
  nvim=$(command -v nvim)
elif [[ -x $HOME/.local/bin/nvim ]]; then
  nvim=$HOME/.local/bin/nvim
fi
if [[ -n $nvim && -s $ROOT/home/dot_config/nvim/lazy-lock.json ]]; then
  env -u SSH_CONNECTION -u SSH_TTY "$nvim" --headless \
    "+lua vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy' })" \
    "+lua local ok = vim.opt.number:get() and not vim.opt.relativenumber:get() and vim.g.autoformat == false and vim.g.snacks_animate == false; if not ok then os.exit(1) end" \
    "+lua local expected = { n = 'j', e = 'k', N = '<C-D>', E = '<C-U>', k = 'n', K = 'N', ['<C-n>'] = '}', ['<C-e>'] = '{' }; for _, mode in ipairs({ 'n', 'x' }) do for lhs, rhs in pairs(expected) do if vim.fn.maparg(lhs, mode) ~= rhs then os.exit(1) end end end; for _, lhs in ipairs({ '<C-h>', '<C-n>', '<C-e>', '<C-i>' }) do if vim.fn.maparg(lhs, 'i') ~= '' then os.exit(1) end end; if vim.fn.maparg('dh', 'i') ~= '<Esc>' or vim.fn.maparg('<C-h>', 'n') ~= '<C-W>h' or vim.fn.maparg('<C-i>', 'n') ~= '' or vim.fn.maparg('e', 'o') ~= '' or vim.fn.maparg('n', 'o') == 'j' or vim.fn.maparg('k', 'o') ~= '' then os.exit(1) end" \
    "+lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'target', 'two', '', 'target', 'four', '', 'target' }); local function press(keys) vim.fn.feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), 'xt') end; vim.api.nvim_win_set_cursor(0, { 1, 0 }); press('n'); if vim.api.nvim_win_get_cursor(0)[1] ~= 2 then os.exit(1) end; vim.api.nvim_win_set_cursor(0, { 1, 0 }); press('vn'); if vim.fn.mode() ~= 'v' or vim.api.nvim_win_get_cursor(0)[1] ~= 2 or vim.fn.line('v') ~= 1 then os.exit(1) end; press('<Esc>'); press('2n'); if vim.api.nvim_win_get_cursor(0)[1] ~= 4 then os.exit(1) end; press('<C-n>'); if vim.api.nvim_win_get_cursor(0)[1] ~= 6 then os.exit(1) end; press('<C-e>'); if vim.api.nvim_win_get_cursor(0)[1] ~= 3 then os.exit(1) end; vim.fn.setreg('/', 'target'); vim.v.searchforward = 1; vim.api.nvim_win_set_cursor(0, { 1, 0 }); press('k'); if vim.api.nvim_win_get_cursor(0)[1] ~= 4 then os.exit(1) end; press('K'); if vim.api.nvim_win_get_cursor(0)[1] ~= 1 then os.exit(1) end; local lines = {}; for i = 1, 100 do lines[i] = tostring(i) end; vim.api.nvim_buf_set_lines(0, 0, -1, false, lines); vim.api.nvim_win_set_cursor(0, { 50, 0 }); press('N'); local down = vim.api.nvim_win_get_cursor(0)[1]; press('E'); if down <= 50 or vim.api.nvim_win_get_cursor(0)[1] >= down then os.exit(1) end" \
    "+lua local config = require('lazy.core.config'); local plugin = require('lazy.core.plugin'); if not config.plugins['neo-tree.nvim'] then os.exit(1) end; if plugin.values(config.plugins['snacks.nvim'], 'opts', false).scroll.enabled ~= false then os.exit(1) end; local blink = plugin.values(config.plugins['blink.cmp'], 'opts', false).keymap; if blink.preset ~= 'enter' or blink['<C-e>'] == false or blink['<C-n>'] == false or blink['<Tab>'] == false then os.exit(1) end" \
    "+lua if not vim.tbl_contains(vim.opt.clipboard:get(), 'unnamedplus') then os.exit(1) end" \
    +qa! >/dev/null 2>&1

  SSH_CONNECTION='127.0.0.1 1 127.0.0.1 2' "$nvim" --headless \
    "+lua vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy' })" \
    "+lua if vim.g.clipboard ~= 'osc52' or #vim.opt.clipboard:get() ~= 0 then os.exit(1) end" \
    +qa >/dev/null 2>&1
fi

grep -Fx 'nnoremap n j' "$ROOT/home/dot_config/nvim/vimrc" >/dev/null
grep -Fx 'nnoremap <C-n> }' "$ROOT/home/dot_config/nvim/vimrc" >/dev/null
grep -Fx '"hunk.review.stepDown" = ["n", "down"]' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
grep -Fx '"hunk.review.stepUp" = ["e", "up"]' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
grep -Fx '"hunk.review.nextHunk" = "ctrl+n"' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
grep -Fx '"hunk.review.previousHunk" = "ctrl+e"' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
grep -Fx '"hunk.review.pageDown" = ["E", "pagedown", "space"]' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
grep -Fx '"hunk.review.pageUp" = ["N", "pageup", "shift+space"]' "$ROOT/home/dot_config/hunk/config.toml" >/dev/null
if grep -Eq '^(i|n|x|o)?noremap .*<C-[hi]>' "$ROOT/home/dot_config/nvim/vimrc"; then
  fail "horizontal Ctrl navigation mapping remains"
fi
if grep -Eq '^keybind = ctrl\+(h|n|e|i)=' "$ROOT/home/Library/Application Support/com.mitchellh.ghostty/config"; then
  fail "Ghostty navigation interception remains"
fi

SOURCE=$TEMP_DIR/source
mkdir -p "$SOURCE"
COPYFILE_DISABLE=1 tar -C "$ROOT" --exclude .git -cf - . | tar -C "$SOURCE" -xf -
chmod +x "$SOURCE/install.sh" "$SOURCE/bootstrap.sh" "$SOURCE/test.sh"

git -C "$SOURCE" init -q
git -C "$SOURCE" config user.name test
git -C "$SOURCE" config user.email test@example.invalid
printf 'this tracked file will be deleted\n' >"$SOURCE/delete-me"
printf 'version 1\n' >"$SOURCE/deployment-version"
git -C "$SOURCE" add -A
git -C "$SOURCE" commit -qm fixture

printf '\ndirty working-tree marker\n' >>"$SOURCE/README.md"
printf 'untracked\n' >"$SOURCE/untracked file"
printf 'leading dash\n' >"$SOURCE/-leading-name"
newline_name=$'line\nbreak'
printf 'newline\n' >"$SOURCE/$newline_name"
ln -s missing-target "$SOURCE/broken-link"
printf '\nignored-smoke\n' >>"$SOURCE/.gitignore"
printf 'ignored\n' >"$SOURCE/ignored-smoke"
rm -f "$SOURCE/delete-me"

REMOTE_HOME=$TEMP_DIR/remote-home
REMOTE_BIN=$TEMP_DIR/remote-bin
TOOL_ROOT=$TEMP_DIR/tools
LOCAL_BIN=$TEMP_DIR/local-bin
SSH_LOG=$TEMP_DIR/ssh.log
mkdir -p "$REMOTE_HOME" "$REMOTE_BIN" "$TOOL_ROOT" "$LOCAL_BIN"

for command_name in git curl cc make; do
  printf '#!/bin/sh\nexit 0\n' >"$REMOTE_BIN/$command_name"
  chmod +x "$REMOTE_BIN/$command_name"
done

for binary_name in rg fd fzf lazygit tree-sitter hunk; do
  printf '#!/bin/sh\nexit 0\n' >"$TOOL_ROOT/$binary_name"
  chmod +x "$TOOL_ROOT/$binary_name"
done
cat >"$TOOL_ROOT/nvim" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
  printf 'NVIM vtest\n'
fi
exit 0
EOF
chmod +x "$TOOL_ROOT/nvim"

cat >"$TOOL_ROOT/chezmoi" <<'EOF'
#!/bin/sh
set -eu
source_dir=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -S|--source) source_dir=$2; shift 2 ;;
    apply) shift; break ;;
    *) shift ;;
  esac
done
[ -n "$source_dir" ]
rm -rf "$HOME/.config/nvim" "$HOME/.config/hunk" "$HOME/.config/herdr"
mkdir -p "$HOME/.config"
cp -R "$source_dir/home/dot_config/nvim" "$HOME/.config/nvim"
cp -R "$source_dir/home/dot_config/hunk" "$HOME/.config/hunk"
cp -R "$source_dir/home/dot_config/herdr" "$HOME/.config/herdr"
rm -f "$HOME/.vimrc"
ln -s .config/nvim/vimrc "$HOME/.vimrc"
EOF
chmod +x "$TOOL_ROOT/chezmoi"

cat >"$TOOL_ROOT/herdr-build" <<'EOF'
#!/bin/sh
case "${1:-}" in
  --version) printf 'herdr test\n' ;;
  config) [ "${2:-}" = check ] ;;
esac
EOF
chmod +x "$TOOL_ROOT/herdr-build"

cat >"$REMOTE_BIN/mise" <<'EOF'
#!/bin/sh
case "${1:-}" in
  trust|install) exit 0 ;;
  which)
    last=
    for argument in "$@"; do
      last=$argument
    done
    printf '%s/%s\n' "$FAKE_TOOL_ROOT" "$last"
    ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$REMOTE_BIN/mise"

cat >"$REMOTE_BIN/mv" <<'EOF'
#!/bin/sh
if [ "${FAKE_PROMOTION_FAIL:-0}" -eq 1 ]; then
  case ${1:-}:${2:-} in
    */.edwin-editor.deploy.lock/stage:*/edwin-editor) exit 55 ;;
  esac
fi
exec /bin/mv "$@"
EOF
chmod +x "$REMOTE_BIN/mv"

cat >"$LOCAL_BIN/ssh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mode=none
if [[ ${1:-} == -T || ${1:-} == -t ]]; then
  mode=$1
  shift
fi
[[ $# -eq 2 ]] || exit 64
target=$1
command_text=$2
printf '%s %s\n' "$mode" "$target" >>"$FAKE_SSH_LOG"
if [[ $mode == -T && ${FAKE_TRANSFER_STATUS:-0} -ne 0 ]]; then
  exit "$FAKE_TRANSFER_STATUS"
fi
if [[ $mode == -t && ${FAKE_INSTALL_STATUS:-0} -ne 0 ]]; then
  exit "$FAKE_INSTALL_STATUS"
fi
unset XDG_DATA_HOME
HOME=$FAKE_REMOTE_HOME \
PATH="$FAKE_REMOTE_BIN:/usr/bin:/bin" \
FAKE_TOOL_ROOT=$FAKE_TOOL_ROOT \
  /bin/sh -c "$command_text"
EOF
chmod +x "$LOCAL_BIN/ssh"

export FAKE_REMOTE_HOME=$REMOTE_HOME
export FAKE_REMOTE_BIN=$REMOTE_BIN
export FAKE_TOOL_ROOT=$TOOL_ROOT
export FAKE_SSH_LOG=$SSH_LOG
export HERDR_BINARY=$TOOL_ROOT/herdr-build

PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host

DEPLOY=$REMOTE_HOME/.local/share/edwin-editor
assert_file "$DEPLOY/install.sh"
[[ -x $DEPLOY/herdr ]] || fail "custom Herdr binary was not deployed"
assert_file "$DEPLOY/untracked file"
assert_file "$DEPLOY/-leading-name"
assert_file "$DEPLOY/$newline_name"
[[ -L $DEPLOY/broken-link ]] || fail "broken symlink was not deployed"
assert_absent "$DEPLOY/ignored-smoke"
assert_absent "$DEPLOY/delete-me"
grep -F 'dirty working-tree marker' "$DEPLOY/README.md" >/dev/null
grep -Fx 'version 1' "$DEPLOY/deployment-version" >/dev/null
[[ -d $REMOTE_HOME/.config/nvim && ! -L $REMOTE_HOME/.config/nvim ]] ||
  fail "Neovim config was not applied"
[[ -L $REMOTE_HOME/.vimrc ]] || fail "Vimrc was not linked"
assert_file "$REMOTE_HOME/.config/hunk/config.toml"
assert_file "$REMOTE_HOME/.config/herdr/config.toml"
[[ -x $REMOTE_HOME/.local/bin/herdr ]] || fail "custom Herdr binary was not installed"
[[ -L $REMOTE_HOME/.local/bin/nvim ]] || fail "Neovim binary was not linked"
[[ -L $REMOTE_HOME/.local/bin/chezmoi ]] || fail "chezmoi binary was not linked"
[[ -L $REMOTE_HOME/.local/bin/hunk ]] || fail "Hunk binary was not linked"
[[ $(sed -n '1p' "$SSH_LOG") == 'none fake-host' ]] || fail "target platform was not inspected"
[[ $(sed -n '2p' "$SSH_LOG") == '-T fake-host' ]] || fail "archive SSH did not disable TTY"
[[ $(sed -n '3p' "$SSH_LOG") == '-t fake-host' ]] || fail "installer SSH did not request TTY"

printf 'version 2\n' >"$SOURCE/deployment-version"
PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host
PREVIOUS=$REMOTE_HOME/.local/share/edwin-editor.previous
assert_file "$PREVIOUS/install.sh"
grep -Fx 'version 2' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 1' "$PREVIOUS/deployment-version" >/dev/null
assert_absent "$REMOTE_HOME/.local/share/edwin-editor.previous.previous"

mv "$SOURCE/mise.toml" "$SOURCE/mise.toml.saved"
if PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host; then
  fail "an incomplete snapshot was promoted"
fi
mv "$SOURCE/mise.toml.saved" "$SOURCE/mise.toml"
grep -Fx 'version 2' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 1' "$PREVIOUS/deployment-version" >/dev/null

printf 'version 3\n' >"$SOURCE/deployment-version"
export FAKE_TRANSFER_STATUS=23
if PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host; then
  fail "a failed transfer was accepted"
else
  status=$?
fi
unset FAKE_TRANSFER_STATUS
[[ $status -eq 23 ]] || fail "transfer failure status was not preserved"
grep -Fx 'version 2' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 1' "$PREVIOUS/deployment-version" >/dev/null

mkdir "$REMOTE_HOME/.local/share/.edwin-editor.deploy.lock"
if PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host; then
  fail "a stale deployment lock was ignored"
fi
rmdir "$REMOTE_HOME/.local/share/.edwin-editor.deploy.lock"
grep -Fx 'version 2' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 1' "$PREVIOUS/deployment-version" >/dev/null

export FAKE_PROMOTION_FAIL=1
if PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host; then
  fail "a failed promotion was accepted"
fi
unset FAKE_PROMOTION_FAIL
grep -Fx 'version 2' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 1' "$PREVIOUS/deployment-version" >/dev/null

export FAKE_INSTALL_STATUS=42
if PATH="$LOCAL_BIN:$PATH" "$SOURCE/bootstrap.sh" fake-host; then
  fail "a failed remote installer was accepted"
else
  status=$?
fi
unset FAKE_INSTALL_STATUS
[[ $status -eq 42 ]] || fail "remote installer status was not preserved"
grep -Fx 'version 3' "$DEPLOY/deployment-version" >/dev/null
grep -Fx 'version 2' "$PREVIOUS/deployment-version" >/dev/null
assert_absent "$REMOTE_HOME/.local/share/edwin-editor.previous.previous"

printf 'All checks passed.\n'
