#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 0 ] || die "usage: ./install.sh"

case ${HOME:-} in
  /*) [ "$HOME" != "/" ] || die "HOME must identify a user home directory" ;;
  *) die "HOME must be an absolute user home directory" ;;
esac

OS=$(uname -s)

missing_commands() {
  missing=
  for command_name in git curl cc make; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="$missing $command_name"
    fi
  done
  printf '%s' "$missing"
}

missing=$(missing_commands)
[ -z "$missing" ] || die "missing:$missing; install these prerequisites and rerun"

LOCAL_BIN=$HOME/.local/bin
mkdir -p "$LOCAL_BIN"

if command -v mise >/dev/null 2>&1; then
  MISE=$(command -v mise)
elif [ -x "$LOCAL_BIN/mise" ]; then
  MISE=$LOCAL_BIN/mise
else
  MISE_VERSION=2026.7.13
  case "$OS/$(uname -m)" in
    Darwin/arm64|Darwin/aarch64)
      mise_platform=macos-arm64
      mise_sha256=ef747f4bd944d7cb4efe1832ec6cd29dfdbc217389122fa37c20d116d90c1eb6
      ;;
    Darwin/x86_64)
      mise_platform=macos-x64
      mise_sha256=3cd0f468c4c8ba1196d949441cb84eeaebb92b94666ef8caa17602c82421f420
      ;;
    Linux/aarch64|Linux/arm64)
      mise_platform=linux-arm64
      mise_sha256=f115d1f911b8eed1bdc9d889d94ff6fdaf892131d573b5678914b2bcf14b2965
      ;;
    Linux/x86_64)
      mise_platform=linux-x64
      mise_sha256=47878bc295922c5f7ba4b7054cc372ce6ae730a1f12b0753c1cda2f04376eee2
      ;;
    *) die "mise has no pinned build for $OS/$(uname -m)" ;;
  esac

  if command -v sha256sum >/dev/null 2>&1; then
    sha256_command=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    sha256_command='shasum -a 256'
  else
    die "sha256sum or shasum is required to verify mise"
  fi

  log "Installing verified mise $MISE_VERSION in $LOCAL_BIN"
  mise_download=$(mktemp "${TMPDIR:-/tmp}/edwin-mise.XXXXXX")
  trap 'rm -f "$mise_download"' 0 1 2 15
  mise_asset=mise-v$MISE_VERSION-$mise_platform
  curl -fsSL "https://github.com/jdx/mise/releases/download/v$MISE_VERSION/$mise_asset" -o "$mise_download"
  # sha256_command is selected only from the two fixed commands above.
  # shellcheck disable=SC2086
  mise_actual_sha256=$($sha256_command "$mise_download" | awk '{print $1}')
  [ "$mise_actual_sha256" = "$mise_sha256" ] ||
    die "mise $MISE_VERSION checksum verification failed"
  chmod 755 "$mise_download"
  mv "$mise_download" "$LOCAL_BIN/mise"
  trap - 0 1 2 15
  MISE=$LOCAL_BIN/mise
fi

[ -x "$MISE" ] || die "mise installation failed"
log "Installing stable tools with mise"
"$MISE" trust --yes "$SCRIPT_DIR/mise.toml"
"$MISE" install --yes --cd "$SCRIPT_DIR"

for binary_name in nvim rg lazygit chezmoi hunk node pi; do
  target=$("$MISE" which --cd "$SCRIPT_DIR" "$binary_name")
  [ -x "$target" ] || die "mise did not provide an executable $binary_name"
  link=$LOCAL_BIN/$binary_name
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    die "$link exists and is not a symlink"
  fi
  rm -f "$link"
  ln -s "$target" "$link"
done

case ":${PATH:-}:" in
  *":$LOCAL_BIN:"*) ;;
  *) warn "$LOCAL_BIN is not on PATH; add it before starting a new shell" ;;
esac

install_skills() {
  skills_standard_remote=git@github.com:ocyedwin/skills.git
  skills_personal_remote=git@github-ocyedwin:ocyedwin/skills.git
  skills_dir=$HOME/.local/share/edwin-skills

  skills_remote_allowed() {
    case $1 in
      "$skills_standard_remote"|"$skills_personal_remote") return 0 ;;
      *) return 1 ;;
    esac
  }

  skills_remote_accessible() {
    git ls-remote "$1" HEAD >/dev/null 2>&1
  }

  select_skills_remote() {
    preferred_remote=${1:-}
    if [ -n "$preferred_remote" ] &&
      skills_remote_allowed "$preferred_remote" &&
      skills_remote_accessible "$preferred_remote"; then
      printf '%s' "$preferred_remote"
      return 0
    fi

    for candidate_remote in "$skills_standard_remote" "$skills_personal_remote"; do
      [ "$candidate_remote" != "$preferred_remote" ] || continue
      if skills_remote_accessible "$candidate_remote"; then
        printf '%s' "$candidate_remote"
        return 0
      fi
    done
    return 1
  }

  if [ -e "$skills_dir" ] || [ -L "$skills_dir" ]; then
    [ -d "$skills_dir" ] && [ ! -L "$skills_dir" ] ||
      die "$skills_dir exists and is not a real directory"
    skills_root=$(git -C "$skills_dir" rev-parse --show-toplevel 2>/dev/null) ||
      die "$skills_dir is not a Git checkout"
    skills_root=$(CDPATH='' cd -- "$skills_root" && pwd -P)
    [ "$skills_root" = "$(CDPATH='' cd -- "$skills_dir" && pwd -P)" ] ||
      die "$skills_dir is not the skills checkout root"
    actual_remote=$(git -C "$skills_dir" remote get-url origin 2>/dev/null) ||
      die "$skills_dir has no origin remote"
    skills_remote_allowed "$actual_remote" ||
      die "$skills_dir has unexpected origin: $actual_remote"
    skills_remote=$(select_skills_remote "$actual_remote") ||
      die "cannot read the personal skills repository; configure GitHub SSH access and rerun"
    if [ "$skills_remote" != "$actual_remote" ]; then
      log "Switching personal skills origin to accessible SSH host $skills_remote"
      git -C "$skills_dir" remote set-url origin "$skills_remote"
    fi
  else
    skills_remote=$(select_skills_remote) ||
      die "cannot read the personal skills repository; configure GitHub SSH access and rerun"
    mkdir -p "$HOME/.local/share"
    skills_temporary=$(mktemp -d "$HOME/.local/share/.edwin-skills.XXXXXX")
    trap 'rm -rf "$skills_temporary"' 0 1 2 15
    log "Cloning personal skills into $skills_dir"
    git clone --recurse-submodules "$skills_remote" "$skills_temporary" ||
      die "cannot read $skills_remote; configure GitHub SSH access and rerun"
    [ -x "$skills_temporary/check.sh" ] ||
      die "the skills checkout has no executable check.sh"
    "$skills_temporary/check.sh" --staged "$skills_temporary"
    mv "$skills_temporary" "$skills_dir"
    trap - 0 1 2 15
  fi

  [ -x "$skills_dir/sync.sh" ] ||
    die "the skills checkout has no executable sync.sh"
  log "Synchronizing personal agent skills"
  "$skills_dir/sync.sh" ||
    die "skill synchronization failed; verify the checkout and GitHub SSH access"
}

validate_ghostty_config() {
  [ "$OS" = Darwin ] || return 0
  target=$SCRIPT_DIR/home/Library/Application\ Support/com.mitchellh.ghostty/config
  ghostty=
  if command -v ghostty >/dev/null 2>&1; then
    ghostty=$(command -v ghostty)
  elif [ -x /Applications/Ghostty.app/Contents/MacOS/ghostty ]; then
    ghostty=/Applications/Ghostty.app/Contents/MacOS/ghostty
  fi
  if [ -n "$ghostty" ]; then
    "$ghostty" +validate-config --config-file="$target"
  else
    warn "Ghostty is not installed; applying configuration without validation"
  fi
}

validate_ghostty_config
log "Applying dotfiles with chezmoi"
"$LOCAL_BIN/chezmoi" --source "$SCRIPT_DIR" apply
[ ! -x "$LOCAL_BIN/herdr" ] || "$LOCAL_BIN/herdr" config check

install_skills

log "Installing Pi packages"
"$MISE" exec --cd "$SCRIPT_DIR" -- pi install git:github.com/ocyedwin/pi-langfuse

log "Restoring pinned LazyVim plugins"
"$LOCAL_BIN/nvim" --headless "+Lazy! restore" +qa

log "Installed $("$LOCAL_BIN/nvim" --version | sed -n '1p')"
log "Installed Pi $("$LOCAL_BIN/pi" --version)"
log "Dotfiles source: $SCRIPT_DIR"
