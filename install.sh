#!/bin/bash

# claude-operator installer
# Repo: https://github.com/PsyChaos/claude-operator
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh | bash
#   bash install.sh [--version v1.2.3] [--global]
#
# Options:
#   --version vX.Y.Z   Pin to a specific release (enables checksum verification)
#   --global           Install claude-operator to ~/.local/bin for PATH access

set -euo pipefail

REPO="PsyChaos/claude-operator"
BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
RELEASES_BASE="https://github.com/$REPO/releases/download"

VERSION=""
GLOBAL_INSTALL=false
INSTALL_DIR="$(pwd)"

# ─── Argument parsing ─────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --version requires a tag argument (e.g. --version v1.0.0)"
        exit 1
      fi
      VERSION="$2"
      shift 2
      ;;
    --global|-g)
      GLOBAL_INSTALL=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash install.sh [--version v1.2.3] [--global]"
      exit 1
      ;;
  esac
done

# ─── Dependency checks ────────────────────────────────────────────────────────

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required but not installed."
  exit 1
fi

# ─── Checksum helpers ─────────────────────────────────────────────────────────

_sha256_compute() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo ""
  fi
}

_verify_checksum() {
  local file="$1"
  local expected_hash="$2"
  local actual_hash
  actual_hash=$(_sha256_compute "$file")

  if [[ -z "$actual_hash" ]]; then
    echo "  Warning: No sha256 tool found (sha256sum/shasum). Skipping verification."
    return 0
  fi

  if [[ "$actual_hash" == "$expected_hash" ]]; then
    echo "  ✓ Checksum verified: $(basename "$file")"
    return 0
  else
    echo "  ✗ Checksum mismatch: $(basename "$file")"
    echo "    Expected: $expected_hash"
    echo "    Got:      $actual_hash"
    return 1
  fi
}

# ─── Download with optional checksum verification ─────────────────────────────
# Usage: _download_file <filename_in_repo> <destination_path>

_download_file() {
  local filename="$1"
  local dest="$2"

  if [[ -n "$VERSION" ]]; then
    local asset_url="$RELEASES_BASE/$VERSION/$filename"
    local sha_url="$RELEASES_BASE/$VERSION/$filename.sha256"
    local tmp_file tmp_sha
    tmp_file="$(mktemp /tmp/claude-operator-XXXXXX)"
    tmp_sha="$(mktemp /tmp/claude-operator-sha-XXXXXX)"

    echo "  Downloading $filename from release $VERSION..."
    curl -fsSL "$asset_url" -o "$tmp_file" || {
      rm -f "$tmp_file" "$tmp_sha"
      echo "  Error: Failed to download $asset_url"
      exit 1
    }

    echo "  Fetching checksum for $filename..."
    curl -fsSL "$sha_url" -o "$tmp_sha" || {
      rm -f "$tmp_file" "$tmp_sha"
      echo "  Error: Failed to download checksum from $sha_url"
      exit 1
    }

    local expected_hash
    expected_hash=$(awk '{print $1}' "$tmp_sha")

    if ! _verify_checksum "$tmp_file" "$expected_hash"; then
      rm -f "$tmp_file" "$tmp_sha"
      exit 1
    fi

    mv "$tmp_file" "$dest"
    rm -f "$tmp_sha"
  else
    echo "  Downloading $filename from master branch (no checksum)..."
    curl -fsSL "$RAW_BASE/$filename" -o "$dest" || {
      echo "  Error: Failed to download $RAW_BASE/$filename"
      exit 1
    }
  fi
}

# ─── Global install ───────────────────────────────────────────────────────────

if $GLOBAL_INSTALL; then
  GLOBAL_BIN_DIR="$HOME/.local/bin"
  GLOBAL_DEST="$GLOBAL_BIN_DIR/claude-operator"

  mkdir -p "$GLOBAL_BIN_DIR"

  echo "Installing claude-operator globally..."
  echo "  Destination: $GLOBAL_DEST"
  [[ -n "$VERSION" ]] && echo "  Version: $VERSION (checksum verification enabled)" \
                      || echo "  Version: master tip (no checksum — pin with --version for security)"
  echo ""

  _download_file "operator.sh" "$GLOBAL_DEST"
  chmod +x "$GLOBAL_DEST"

  echo ""
  echo "========================================"
  echo " claude-operator installed globally"
  echo "========================================"
  echo ""
  echo "  Binary: $GLOBAL_DEST"
  echo ""

  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$GLOBAL_BIN_DIR"; then
    echo "  ⚠  $GLOBAL_BIN_DIR is not in your PATH."
    echo ""
    echo "  Add to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo '    export PATH="$HOME/.local/bin:$PATH"'
    echo ""
    echo "  Then reload: source ~/.bashrc  (or open a new terminal)"
    echo ""
  else
    echo "  Usage:"
    echo ""
    echo "    claude-operator elite"
    echo "    claude-operator elite v1.0.0"
    echo "    claude-operator update"
    echo ""
  fi

  exit 0
fi

# ─── Local (project-level) install ───────────────────────────────────────────

echo "Installing claude-operator into: $INSTALL_DIR"
[[ -n "$VERSION" ]] && echo "Version: $VERSION (checksum verification enabled)" \
                    || echo "Version: master tip (no checksum — pin with --version for security)"
echo ""

_download_file "operator.sh" "$INSTALL_DIR/operator.sh"
_download_file "Makefile"    "$INSTALL_DIR/Makefile"

chmod +x "$INSTALL_DIR/operator.sh"

echo ""
echo "========================================"
echo " claude-operator installed successfully"
echo "========================================"
echo ""
echo "Usage:"
echo ""
echo "  make claude MODE=elite"
echo "  make claude MODE=elite VERSION=v1.0.0"
echo "  ./operator.sh update"
echo ""

if [[ -z "$VERSION" ]]; then
  echo "Tip: Pin a version for checksum security:"
  echo "  bash install.sh --version v1.0.0"
  echo ""
fi

echo "Done."
