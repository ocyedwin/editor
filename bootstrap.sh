#!/usr/bin/env bash
set -euo pipefail

ROOT=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)

if [[ $# -ne 1 || $1 == -* ]]; then
  printf 'Usage: %s <ssh-target>\n' "${0##*/}" >&2
  exit 2
fi

TARGET=$1

if [[ ! -t 0 ]]; then
  printf 'error: bootstrap.sh must run from an interactive terminal\n' >&2
  exit 1
fi

untracked_found=0
while IFS= read -r -d '' path; do
  printf 'error: refusing to deploy untracked file: %q\n' "$path" >&2
  untracked_found=1
done < <(git -C "$ROOT" ls-files --others --exclude-standard -z)
if [[ $untracked_found -ne 0 ]]; then
  printf 'error: review each file, then git add it or add it to .gitignore\n' >&2
  exit 1
fi

commit=$(git -C "$ROOT" rev-parse --short HEAD)
state=clean
[[ -z $(git -C "$ROOT" status --porcelain) ]] || state=dirty
printf 'Deploying %s (%s) to %s\n' "$commit" "$state" "$TARGET"

remote_platform=$(ssh "$TARGET" 'printf "%s/%s\n" "$(uname -s)" "$(uname -m)"')
local_platform=$(printf '%s/%s\n' "$(uname -s)" "$(uname -m)")
HERDR_ROOT=${HERDR_ROOT:-$ROOT/../2026-08-12-herdrdev-herdr}
if [[ -z ${HERDR_BINARY:-} ]]; then
  case $remote_platform in
    Darwin/arm64)
      candidates=("$HERDR_ROOT/target/aarch64-apple-darwin/release/herdr")
      ;;
    Darwin/x86_64)
      candidates=("$HERDR_ROOT/target/x86_64-apple-darwin/release/herdr")
      ;;
    Linux/x86_64)
      candidates=(
        "$HERDR_ROOT/target/x86_64-unknown-linux-musl/release/herdr"
        "$HERDR_ROOT/target/x86_64-unknown-linux-gnu/release/herdr"
      )
      ;;
    Linux/aarch64|Linux/arm64)
      candidates=(
        "$HERDR_ROOT/target/aarch64-unknown-linux-musl/release/herdr"
        "$HERDR_ROOT/target/aarch64-unknown-linux-gnu/release/herdr"
      )
      ;;
    *)
      printf 'error: unsupported Herdr target platform: %s\n' "$remote_platform" >&2
      exit 1
      ;;
  esac
  if [[ $local_platform == "$remote_platform" ]]; then
    candidates+=("$HERDR_ROOT/target/release/herdr")
  fi
  for candidate in "${candidates[@]}"; do
    if [[ -x $candidate ]]; then
      HERDR_BINARY=$candidate
      break
    fi
  done
fi
if [[ ! -x ${HERDR_BINARY:-} ]]; then
  printf 'error: no custom Herdr build for %s; build it under %s/target or set HERDR_BINARY\n' \
    "$remote_platform" "$HERDR_ROOT" >&2
  exit 1
fi
printf 'Including custom Herdr build: %s\n' "$HERDR_BINARY"

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
rotated=0
promoted=0
cleanup() {
  if [ "$rotated" -eq 1 ]; then
    if [ "$promoted" -eq 0 ]; then
      if { [ -e "$destination" ] || [ -L "$destination" ]; } &&
        [ ! -e "$stage" ] && [ ! -L "$stage" ]; then
        mv "$destination" "$stage" 2>/dev/null || true
      fi
      if [ ! -e "$destination" ] && [ ! -L "$destination" ] &&
        [ -e "$previous" ] && [ ! -L "$previous" ]; then
        mv "$previous" "$destination" 2>/dev/null || true
      fi
      if { [ -e "$saved_previous" ] || [ -L "$saved_previous" ]; } &&
        [ ! -e "$previous" ] && [ ! -L "$previous" ]; then
        mv "$saved_previous" "$previous" 2>/dev/null || true
      fi
    elif [ -e "$saved_previous" ] || [ -L "$saved_previous" ]; then
      rm -rf "$saved_previous"
    fi
  fi
  [ -z "${stage:-}" ] || rm -rf "$stage"
  rmdir "$lock" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 1' 1 2 15
mkdir "$stage"
tar -xf - -C "$stage"

valid_snapshot() {
  [ -d "$1" ] && [ ! -L "$1" ] &&
    [ -x "$1/install.sh" ] && [ ! -L "$1/install.sh" ] &&
    [ -f "$1/mise.toml" ] && [ ! -L "$1/mise.toml" ] &&
    {
      { [ -f "$1/.chezmoiroot" ] && [ ! -L "$1/.chezmoiroot" ] &&
        [ -f "$1/home/dot_config/nvim/init.lua" ] &&
        [ ! -L "$1/home/dot_config/nvim/init.lua" ]; } ||
      { [ -f "$1/nvim/init.lua" ] && [ ! -L "$1/nvim/init.lua" ]; }
    }
}

valid_snapshot "$stage" || {
  printf 'error: transferred snapshot is incomplete\n' >&2
  exit 1
}
[ -x "$stage/herdr" ] || {
  printf 'error: transferred snapshot has no custom Herdr binary\n' >&2
  exit 1
}
"$stage/herdr" --version >/dev/null 2>&1 || {
  printf 'error: transferred Herdr binary cannot run on this target\n' >&2
  exit 1
}
for snapshot in "$destination" "$previous"; do
  if { [ -e "$snapshot" ] || [ -L "$snapshot" ]; } && ! valid_snapshot "$snapshot"; then
    printf 'error: refusing to replace unrelated deployment: %s\n' "$snapshot" >&2
    exit 1
  fi
done

if [ -e "$destination" ] || [ -L "$destination" ]; then
  rotated=1
  if [ -e "$previous" ] || [ -L "$previous" ]; then
    mv "$previous" "$saved_previous"
  fi
  mv "$destination" "$previous"
fi
if ! mv "$stage" "$destination"; then
  printf 'error: failed to promote the new deployment\n' >&2
  exit 1
fi
promoted=1
stage=
trap - 1 2 15
REMOTE

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/edwin-editor.XXXXXX")
raw_list=$temp_dir/git-files
file_list=$temp_dir/archive-files
archive=$temp_dir/editor.tar
payload=$temp_dir/payload
cleanup_temp() {
  rm -rf "$temp_dir"
}
trap cleanup_temp EXIT
trap 'exit 1' HUP INT TERM

git -C "$ROOT" ls-files --cached -z >"$raw_list"

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
mkdir "$payload"
cp "$HERDR_BINARY" "$payload/herdr"
chmod 755 "$payload/herdr"
COPYFILE_DISABLE=1 tar -C "$payload" -rf "$archive" herdr

# Never allocate a TTY while streaming a binary archive.
# The static command is intentionally interpreted by the remote shell.
# shellcheck disable=SC2029
ssh -T "$TARGET" "$remote_deploy" <"$archive"

if ssh -t "$TARGET" 'exec "$HOME/.local/share/edwin-editor/install.sh"'; then
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
