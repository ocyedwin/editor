#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

usage() {
  printf 'Usage: %s <ssh-target>\n' "${0##*/}"
}

if [[ $# -ne 1 || $1 == -* ]]; then
  usage >&2
  exit 2
fi

TARGET=$1

if [[ ! -t 0 ]]; then
  printf 'error: bootstrap.sh must run from an interactive terminal\n' >&2
  exit 1
fi

for command_name in git ssh tar; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'error: required local command not found: %s\n' "$command_name" >&2
    exit 1
  }
done

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'error: %s is not a Git working tree\n' "$ROOT" >&2
  exit 1
}

commit=$(git -C "$ROOT" rev-parse --short HEAD)
if [[ -n $(git -C "$ROOT" status --porcelain) ]]; then
  state=dirty
else
  state=clean
fi
printf 'Deploying %s (%s) to %s\n' "$commit" "$state" "$TARGET"

IFS= read -r -d '' remote_deploy <<'REMOTE' || true
set -eu
case ${HOME:-} in
  /*) [ "$HOME" != "/" ] || {
    printf 'error: invalid remote HOME\n' >&2
    exit 1
  } ;;
  *)
    printf 'error: remote HOME must be absolute\n' >&2
    exit 1
    ;;
esac
command -v tar >/dev/null 2>&1 || {
  printf 'error: remote tar is required\n' >&2
  exit 1
}
data_root=$HOME/.local/share
destination=$data_root/edwin-editor
previous=$data_root/edwin-editor.previous
lock=$data_root/.edwin-editor.deploy.lock
mkdir -p "$data_root"
if ! mkdir "$lock"; then
  printf 'error: another deployment is running, or this lock is stale: %s\n' "$lock" >&2
  exit 1
fi
stage=$lock/stage
saved_previous=$lock/previous
had_previous=0
had_destination=0
moved_destination=0
promoted=0
finish_commit() {
  [ "$had_previous" -eq 1 ] || return 0
  if [ "$had_destination" -eq 1 ]; then
    if [ -e "$saved_previous" ] || [ -L "$saved_previous" ]; then
      rm -rf "$saved_previous"
    fi
  elif [ -e "$saved_previous" ] || [ -L "$saved_previous" ]; then
    [ ! -e "$previous" ] && [ ! -L "$previous" ] || return 1
    mv "$saved_previous" "$previous"
  fi
}
cleanup() {
  if [ "$promoted" -eq 0 ]; then
    if [ "$moved_destination" -eq 1 ]; then
      if { [ -e "$destination" ] || [ -L "$destination" ]; } &&
        [ ! -e "$stage" ] && [ ! -L "$stage" ]; then
        mv "$destination" "$stage" 2>/dev/null || true
      fi
      if [ ! -e "$destination" ] && [ ! -L "$destination" ] &&
        [ -e "$previous" ] && [ ! -L "$previous" ]; then
        mv "$previous" "$destination" 2>/dev/null || true
      fi
    fi
    if [ "$had_previous" -eq 1 ] &&
      { [ -e "$saved_previous" ] || [ -L "$saved_previous" ]; } &&
      [ ! -e "$previous" ] && [ ! -L "$previous" ]; then
      mv "$saved_previous" "$previous" 2>/dev/null || true
    fi
  else
    finish_commit 2>/dev/null || true
  fi
  [ -z "${stage:-}" ] || rm -rf "$stage"
  rmdir "$lock" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 1' 1 2 15
mkdir "$stage"
tar -xf - -C "$stage"
[ -x "$stage/install.sh" ] && [ ! -L "$stage/install.sh" ] &&
  [ -f "$stage/mise.toml" ] && [ ! -L "$stage/mise.toml" ] &&
  [ -f "$stage/nvim/init.lua" ] && [ ! -L "$stage/nvim/init.lua" ] || {
  printf 'error: transferred snapshot is incomplete\n' >&2
  exit 1
}

valid_snapshot() {
  [ -d "$1" ] && [ ! -L "$1" ] &&
    [ -x "$1/install.sh" ] && [ ! -L "$1/install.sh" ] &&
    [ -f "$1/mise.toml" ] && [ ! -L "$1/mise.toml" ] &&
    [ -f "$1/nvim/init.lua" ] && [ ! -L "$1/nvim/init.lua" ]
}

if [ -e "$destination" ] || [ -L "$destination" ]; then
  valid_snapshot "$destination" || {
    printf 'error: refusing to replace unrelated deployment: %s\n' "$destination" >&2
    exit 1
  }
fi
if [ -e "$previous" ] || [ -L "$previous" ]; then
  valid_snapshot "$previous" || {
    printf 'error: refusing to remove unrelated previous deployment: %s\n' "$previous" >&2
    exit 1
  }
fi

if [ -e "$previous" ] || [ -L "$previous" ]; then
  had_previous=1
  mv "$previous" "$saved_previous"
fi
if [ -e "$destination" ] || [ -L "$destination" ]; then
  moved_destination=1
  mv "$destination" "$previous"
  had_destination=1
fi
if ! mv "$stage" "$destination"; then
  printf 'error: failed to promote the new deployment\n' >&2
  exit 1
fi
promoted=1
stage=
finish_commit
trap - 1 2 15
REMOTE

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/edwin-editor.XXXXXX")
raw_list=$temp_dir/git-files
file_list=$temp_dir/archive-files
archive=$temp_dir/editor.tar
cleanup_temp() {
  rm -rf "$temp_dir"
}
trap cleanup_temp EXIT
trap 'exit 1' HUP INT TERM

git -C "$ROOT" ls-files --cached --others --exclude-standard -z >"$raw_list"

while IFS= read -r -d '' path; do
  if [[ -e "$ROOT/$path" || -L "$ROOT/$path" ]]; then
    if [[ -d "$ROOT/$path" && ! -L "$ROOT/$path" ]]; then
      printf 'error: directory or submodule cannot be deployed as a file: %s\n' "$path" >&2
      exit 1
    fi
    printf '%s\0' "$path"
  fi
done <"$raw_list" >"$file_list"

tar_options=(--null --no-recursion --no-xattrs --no-acls)
if [[ $(uname -s) == Darwin ]]; then
  tar_options+=(--no-mac-metadata --no-fflags)
fi

COPYFILE_DISABLE=1 tar -C "$ROOT" "${tar_options[@]}" -T "$file_list" -cf "$archive"

# Never allocate a TTY while streaming a binary archive.
# The static command is intentionally interpreted by the remote shell.
# shellcheck disable=SC2029
ssh -T "$TARGET" "$remote_deploy" <"$archive"

IFS= read -r -d '' remote_install <<'REMOTE' || true
set -eu
data_root=$HOME/.local/share
exec "$data_root/edwin-editor/install.sh"
REMOTE

if ssh -t "$TARGET" "$remote_install"; then
  :
else
  status=$?
  printf 'Remote installer failed; any previous snapshot remains in the remote data directory.\n' >&2
  # Keep remote variables literal in the suggested command.
  # shellcheck disable=SC2016
  printf 'Rollback: ssh %q '\''data=$HOME/.local/share; previous=$data/edwin-editor.previous; current=$data/edwin-editor; failed=$data/edwin-editor.failed.$(date +%%Y%%m%%d%%H%%M%%S).$$; test -x "$previous/install.sh" && test ! -e "$failed" && mv "$current" "$failed" && mv "$previous" "$current"'\''\n' \
    "$TARGET" >&2
  exit "$status"
fi

printf 'Remote editor installation complete: %s\n' "$TARGET"
