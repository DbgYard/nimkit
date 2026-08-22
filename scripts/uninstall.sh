#!/usr/bin/env sh
# nimkit uninstaller for Linux & macOS
# Usage:
#   sh scripts/uninstall.sh
#   curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.sh | sh

set -eu

INSTALL_DIR="${HOME}/.nimkit/bin"
PREFIX=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) INSTALL_DIR="$2"; shift 2 ;;
    --help|-h)
      echo "nimkit uninstaller"
      echo "Usage: uninstall.sh [--prefix <dir>]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ -n "$PREFIX" ]; then
  INSTALL_DIR="$PREFIX"
fi

info() { printf "[nimkit] %s\n" "$*"; }
log() { printf "  %s\n" "$*"; }

info "Uninstalling nimkit from $INSTALL_DIR"

# Remove binary
if [ -f "$INSTALL_DIR/nimkit" ]; then
  rm -f "$INSTALL_DIR/nimkit"
  log "Removed $INSTALL_DIR/nimkit"
else
  log "Binary not found at $INSTALL_DIR/nimkit (already removed?)"
fi

# Try to remove empty dirs
if [ -d "$INSTALL_DIR" ]; then
  rmdir "$INSTALL_DIR" 2>/dev/null && log "Removed empty $INSTALL_DIR" || true
  # also try parent ~/.nimkit if empty
  parent=$(dirname "$INSTALL_DIR")
  if [ "$parent" = "$HOME/.nimkit" ] && [ -d "$parent" ]; then
    rmdir "$parent" 2>/dev/null && log "Removed empty $parent" || true
  fi
fi

# Remove PATH entries from shell rcs
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.config/fish/config.fish"; do
  [ -f "$rc" ] || continue
  if grep -qF "$INSTALL_DIR" "$rc" 2>/dev/null; then
    # create backup and remove lines added by installer
    cp "$rc" "$rc.bak.nimkit" 2>/dev/null || true
    # remove the two lines we added: "# nimkit" and the export/fish_add_path
    # use temp file for portability (no GNU sed -i quirks)
    tmp=$(mktemp 2>/dev/null || mktemp -t nimkit)
    # shellcheck disable=SC2016
    awk -v dir="$INSTALL_DIR" '
      $0 == "# nimkit" { skip=2; next }
      skip>0 { skip--; next }
      { print }
    ' "$rc" > "$tmp" 2>/dev/null || cat "$rc" > "$tmp"
    # more robust: also grep -v the exact export line if awk failed
    if grep -qF "$INSTALL_DIR" "$tmp" 2>/dev/null; then
      grep -vF "$INSTALL_DIR" "$rc" > "$tmp" 2>/dev/null || true
      # also remove orphan "# nimkit" line
      grep -v "^# nimkit$" "$tmp" > "$tmp.new" 2>/dev/null && mv "$tmp.new" "$tmp" || true
    fi
    cat "$tmp" > "$rc"
    rm -f "$tmp"
    log "Cleaned PATH from $rc (backup: $rc.bak.nimkit)"
  fi
done

info "Uninstalled. Restart your terminal to refresh PATH."
info "If you installed via a custom --prefix, re-run with --prefix <dir>."
