#!/usr/bin/env sh
# nimkit installer for Linux & macOS
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh -s -- --from-source
#   curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh -s -- --tag nightly
#   sh scripts/install.sh --help

set -eu

REPO="DbgYard/nimkit"
TAG="nightly"
INSTALL_DIR="${HOME}/.nimkit/bin"
FROM_SOURCE=0
FORCE=0

# parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --from-source) FROM_SOURCE=1; shift ;;
    --force|-f) FORCE=1; shift ;;
    --tag) TAG="$2"; shift 2 ;;
    --prefix) INSTALL_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "nimkit installer"
      echo ""
      echo "Usage: install.sh [options]"
      echo ""
      echo "Options:"
      echo "  --from-source   Build from source instead of downloading binary"
      echo "  --force, -f     Force overwrite existing installation (default: always overwrites)"
      echo "  --tag <tag>     Release tag to download (default: nightly)"
      echo "  --prefix <dir>  Install directory (default: ~/.nimkit/bin)"
      echo "  --help          Show this help"
      echo ""
      echo "Examples:"
      echo "  sh install.sh                          # install nightly, overwrite if exists"
      echo "  sh install.sh --tag v0.2.0             # update/downgrade to v0.2.0"
      echo "  sh install.sh --from-source            # rebuild from source and overwrite"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() { printf "  %s\n" "$*"; }
info() { printf "[nimkit] %s\n" "$*"; }
warn() { printf "[nimkit] WARN: %s\n" "$*" >&2; }
die() { printf "[nimkit] ERROR: %s\n" "$*" >&2; exit 1; }

# detect OS/arch -> asset name
detect_asset() {
  os=$(uname -s 2>/dev/null || echo "Unknown")
  arch=$(uname -m 2>/dev/null || echo "x86_64")
  case "$os" in
    Linux*)  echo "nimkit-linux-amd64" ;;
    Darwin*)
      case "$arch" in
        arm64|aarch64) echo "nimkit-macos-arm64" ;;
        *) echo "nimkit-macos-arm64" ;; # Intel Macs use arm64 via Rosetta or fallback to build
      esac
      ;;
    *) echo "" ;;
  esac
}

ensure_dir() {
  mkdir -p "$INSTALL_DIR"
}

add_to_path() {
  # Add INSTALL_DIR to PATH for current session
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *) export PATH="$INSTALL_DIR:$PATH" ;;
  esac

  # Persist across shells
  exported=0
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    if grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then
      exported=1
      continue
    fi
    # only modify bashrc/zshrc that exist, and profile as fallback
    if [ "$rc" = "$HOME/.bashrc" ] || [ "$rc" = "$HOME/.zshrc" ] || [ "$exported" -eq 0 ]; then
      printf '\n# nimkit\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$rc"
      log "Added to PATH in $rc"
      exported=1
    fi
  done

  # Fish shell
  fish_config="$HOME/.config/fish/config.fish"
  if [ -d "$HOME/.config/fish" ]; then
    mkdir -p "$(dirname "$fish_config")"
    if ! grep -qF "$INSTALL_DIR" "$fish_config" 2>/dev/null; then
      printf '\n# nimkit\nfish_add_path "%s"\n' "$INSTALL_DIR" >> "$fish_config"
      log "Added to PATH in $fish_config"
    fi
  fi

  if [ "$exported" -eq 0 ]; then
    printf '\n# nimkit\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$HOME/.profile"
    log "Added to PATH in ~/.profile"
  fi
}

try_download() {
  asset=$(detect_asset)
  if [ -z "$asset" ]; then
    return 1
  fi
  url="https://github.com/${REPO}/releases/download/${TAG}/${asset}"
  dest="$INSTALL_DIR/nimkit"
  # update: remove old binary first so we never leave a stale version on failure
  if [ -f "$dest" ]; then
    info "Existing binary found at $dest — will overwrite with $TAG"
    rm -f "$dest"
  fi
  info "Downloading $asset from $TAG..."
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
      chmod +x "$dest"
      return 0
    fi
  elif command -v wget >/dev/null 2>&1; then
    if wget -qO "$dest" "$url" 2>/dev/null; then
      chmod +x "$dest"
      return 0
    fi
  fi
  return 1
}

build_from_source() {
  info "Building from source..."
  if ! command -v nim >/dev/null 2>&1; then
    die "Nim not found. Install Nim >= 2.0.0 via choosenim: https://github.com/dom96/choosenim"
  fi
  if ! command -v git >/dev/null 2>&1; then
    die "git not found. Install git first."
  fi
  dest="$INSTALL_DIR/nimkit"
  if [ -f "$dest" ]; then
    info "Existing binary at $dest — will overwrite with fresh build from $TAG"
    rm -f "$dest"
  fi
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t nimkit)
  # clone the requested tag if not nightly, otherwise default branch
  if [ "$TAG" != "nightly" ]; then
    info "Cloning $REPO (tag $TAG) into $tmp..."
    git clone --depth 1 --branch "$TAG" "https://github.com/${REPO}.git" "$tmp/nimkit" >/dev/null 2>&1 || {
      warn "Tag $TAG not found, cloning default branch and building HEAD"
      rm -rf "$tmp/nimkit"
      git clone --depth 1 "https://github.com/${REPO}.git" "$tmp/nimkit" >/dev/null 2>&1 || die "git clone failed"
    }
  else
    info "Cloning $REPO into $tmp..."
    git clone --depth 1 "https://github.com/${REPO}.git" "$tmp/nimkit" >/dev/null 2>&1 || die "git clone failed"
  fi
  (
    cd "$tmp/nimkit"
    # if tag checkout didn't happen via --branch (fallback), try explicit checkout
    if [ "$TAG" != "nightly" ]; then
      git fetch --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG" >/dev/null 2>&1 || true
      git checkout "$TAG" >/dev/null 2>&1 || true
    fi
    nim c --path:src -o:nimkit src/nimkit.nim
    cp -f nimkit "$dest"
    chmod +x "$dest"
  )
  rm -rf "$tmp"
}

main() {
  # detect existing install for update messaging
  if [ -x "$INSTALL_DIR/nimkit" ]; then
    old_ver=$("$INSTALL_DIR/nimkit" help 2>&1 | head -n 1 || echo "unknown")
    info "Existing installation detected: $old_ver"
    info "Updating to $TAG..."
  else
    info "Installing nimkit ($TAG) to $INSTALL_DIR"
  fi
  ensure_dir

  if [ "$FROM_SOURCE" -eq 1 ]; then
    build_from_source
  else
    if ! try_download; then
      warn "Download failed (no release for $TAG or network issue), falling back to source build"
      build_from_source
    fi
  fi

  add_to_path

  if [ -x "$INSTALL_DIR/nimkit" ]; then
    info "Installed: $INSTALL_DIR/nimkit"
    "$INSTALL_DIR/nimkit" help 2>&1 | head -n 5 || true
    echo ""
    info "Add $INSTALL_DIR to your PATH if not already:"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
    info "Then run: nimkit help"
    # also export for current shell if sourced
    if [ "${0##*/}" != "sh" ] && [ -n "${BASH_VERSION:-}" ]; then
      export PATH="$INSTALL_DIR:$PATH"
    fi
  else
    die "Install failed: $INSTALL_DIR/nimkit not found"
  fi
}

main
