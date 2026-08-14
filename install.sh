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

usage() {
  cat <<'EOF'
Usage: ./install.sh

Installs editor tools and applies the portable dotfiles with chezmoi.
EOF
}

case ${1:-} in
  '') ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; die "unknown argument: $1" ;;
esac
[ "$#" -le 1 ] || { usage >&2; die "too many arguments"; }

case ${HOME:-} in
  /*) [ "$HOME" != "/" ] || die "HOME must identify a user home directory" ;;
  *) die "HOME must be an absolute user home directory" ;;
esac

confirm() {
  prompt=$1
  if ! ( : </dev/tty >/dev/tty ) 2>/dev/null; then
    die "$prompt (a controlling TTY is required)"
  fi
  printf '%s [y/N] ' "$prompt" >/dev/tty
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

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

install_prerequisites() {
  missing=$1
  if [ "$OS" = Darwin ]; then
    command_text="xcode-select --install"
  else
    if [ "$(id -u)" -eq 0 ]; then
      elevate=
    elif command -v sudo >/dev/null 2>&1; then
      elevate=sudo
    else
      die "missing:$missing; install Git, curl, and a C build toolchain, then rerun"
    fi

    if command -v apt-get >/dev/null 2>&1; then
      command_text="$elevate apt-get update && $elevate apt-get install -y git curl ca-certificates build-essential"
    elif command -v dnf >/dev/null 2>&1; then
      command_text="$elevate dnf install -y git curl ca-certificates gcc gcc-c++ make"
    elif command -v yum >/dev/null 2>&1; then
      command_text="$elevate yum install -y git curl ca-certificates gcc gcc-c++ make"
    elif command -v pacman >/dev/null 2>&1; then
      command_text="$elevate pacman -S --needed git curl ca-certificates base-devel"
    elif command -v zypper >/dev/null 2>&1; then
      command_text="$elevate zypper install -y git curl ca-certificates gcc gcc-c++ make"
    else
      die "missing:$missing; unsupported package manager, install Git, curl, and a C build toolchain"
    fi
  fi

  if ! confirm "Missing:$missing. Run: $command_text ?"; then
    die "prerequisites were not installed; run this command manually: $command_text"
  fi
  sh -c "$command_text"

  remaining=$(missing_commands)
  [ -z "$remaining" ] || die "still missing:$remaining; finish installing prerequisites and rerun"
}

missing=$(missing_commands)
[ -z "$missing" ] || install_prerequisites "$missing"

LOCAL_BIN=$HOME/.local/bin
mkdir -p "$LOCAL_BIN"

if command -v mise >/dev/null 2>&1; then
  MISE=$(command -v mise)
elif [ -x "$LOCAL_BIN/mise" ]; then
  MISE=$LOCAL_BIN/mise
else
  log "Installing mise in $LOCAL_BIN"
  mise_installer=$(mktemp "${TMPDIR:-/tmp}/edwin-mise.XXXXXX")
  trap 'rm -f "$mise_installer"' 0 1 2 15
  curl -fsSL https://mise.run -o "$mise_installer"
  MISE_INSTALL_PATH=$LOCAL_BIN/mise MISE_INSTALL_SKIP_IF_EXISTS=1 sh "$mise_installer"
  rm -f "$mise_installer"
  trap - 0 1 2 15
  MISE=$LOCAL_BIN/mise
fi

[ -x "$MISE" ] || die "mise installation failed"
log "Installing stable tools with mise"
"$MISE" trust --yes "$SCRIPT_DIR/mise.toml"
"$MISE" install --yes --cd "$SCRIPT_DIR"

for binary_name in nvim rg fd fzf lazygit tree-sitter chezmoi hunk; do
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

install_herdr() {
  source=$SCRIPT_DIR/herdr
  [ -x "$source" ] || return 0
  temporary=$LOCAL_BIN/.herdr.$$
  trap 'rm -f "$temporary"' 0 1 2 15
  cp "$source" "$temporary"
  chmod 755 "$temporary"
  "$temporary" --version >/dev/null
  mv "$temporary" "$LOCAL_BIN/herdr"
  trap - 0 1 2 15
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
install_herdr
log "Applying dotfiles with chezmoi"
"$LOCAL_BIN/chezmoi" --source "$SCRIPT_DIR" apply
[ ! -x "$LOCAL_BIN/herdr" ] || "$LOCAL_BIN/herdr" config check

log "Restoring pinned LazyVim plugins"
"$LOCAL_BIN/nvim" --headless "+Lazy! restore" +qa

log "Installed $("$LOCAL_BIN/nvim" --version | sed -n '1p')"
log "Dotfiles source: $SCRIPT_DIR"
