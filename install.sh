#!/bin/bash

# claude-operator installer
# Repo: https://github.com/PsyChaos/claude-operator
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh | bash
#   bash install.sh [--version v1.2.3] [--global] [--strict-checksum] [--verify-sig] [--enterprise] [--enterprise-config /path/to/config]
#
# Options:
#   --version vX.Y.Z                   Pin to a specific release (enables checksum verification)
#   --global                           Install claude-operator to ~/.local/bin for PATH access
#   --strict-checksum / -s             Abort if no sha256 tool is available
#   --verify-sig / -S                  Verify GPG signatures on downloaded files (requires gpg)
#   --enterprise / -e                  Generate an enterprise configuration template
#   --enterprise-config <path>         Write enterprise config template to a custom path

set -euo pipefail

REPO="PsyChaos/claude-operator"
BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
RELEASES_BASE="https://github.com/$REPO/releases/download"

GPG_KEY_FILE="${CLAUDE_OPERATOR_GPG_KEY:-$HOME/.config/claude-operator/claude-operator.gpg.pub}"
GPG_KEY_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/claude-operator.gpg.pub"

VERSION=""
GLOBAL_INSTALL=false
STRICT_CHECKSUM=false
VERIFY_SIG=false
INSTALL_DIR="$(pwd)"
ENTERPRISE_INSTALL=false
ENTERPRISE_CONFIG_PATH=""

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
    --strict-checksum|-s)
      STRICT_CHECKSUM=true
      shift
      ;;
    --verify-sig|-S)
      VERIFY_SIG=true
      shift
      ;;
    --enterprise|-e)
      ENTERPRISE_INSTALL=true
      shift
      ;;
    --enterprise-config)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --enterprise-config requires a path argument"
        exit 1
      fi
      ENTERPRISE_CONFIG_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: bash install.sh [--version v1.2.3] [--global] [--strict-checksum] [--verify-sig] [--enterprise] [--enterprise-config /path/to/config]"
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
  local strict="${3:-false}"
  local actual_hash
  actual_hash=$(_sha256_compute "$file")

  if [[ -z "$actual_hash" ]]; then
    if [[ "$strict" == "true" ]]; then
      echo "Error: Strict checksum mode enabled but no sha256 tool found (sha256sum/shasum). Install one or unset OPERATOR_STRICT_CHECKSUM."
      exit 1
    else
      echo "  Warning: No sha256 tool found (sha256sum/shasum). Skipping verification."
      return 0
    fi
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

# ─── GPG helpers ─────────────────────────────────────────────────────────────

_ensure_gpg() {
  if ! command -v gpg >/dev/null 2>&1; then
    echo "Error: gpg is required for signature verification but not installed."
    echo "Install gpg (e.g. apt install gnupg) or omit --verify-sig."
    exit 1
  fi
}

_import_trust_key() {
  local key_file="${1:-$GPG_KEY_FILE}"
  _ensure_gpg
  if [[ ! -f "$key_file" ]]; then
    echo "Error: Public key not found at $key_file"
    echo "Run: ./operator.sh trust-key"
    exit 1
  fi
  gpg --import "$key_file" 2>/dev/null || {
    echo "Error: Failed to import GPG key from $key_file"
    exit 1
  }
  echo "  ✓ GPG key imported from $key_file"
}

_verify_signature() {
  local file="$1"
  local sig_file="$2"
  _ensure_gpg
  if [[ ! -f "$sig_file" ]]; then
    echo "Error: Signature file not found: $sig_file"
    exit 1
  fi
  if gpg --verify "$sig_file" "$file" 2>/dev/null; then
    echo "  ✓ GPG signature verified: $(basename "$file")"
    return 0
  else
    echo "  ✗ GPG signature verification FAILED: $(basename "$file")"
    echo "    This file may have been tampered with!"
    return 1
  fi
}

# ─── Enterprise config template ───────────────────────────────────────────────

_write_enterprise_config_template() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  cat > "$dest" << 'ENTERPRISE_CONFIG'
# claude-operator Enterprise Configuration
# Generated by: bash install.sh --enterprise
#
# Uncomment and set values to enable enterprise policies.
# This file is sourced as bash, so use KEY=value syntax.
#
# Location precedence:
#   1. /etc/claude-operator/enterprise.conf   (system-wide)
#   2. ~/.config/claude-operator/enterprise.conf  (user-level)
#   3. CO_* environment variables (highest priority)

# Enable enterprise mode (enforces all active policies below)
# ENTERPRISE_MODE=true

# Whitelist of allowed profiles (space-separated). Empty = all allowed.
# ALLOWED_PROFILES="elite senior-production"

# Require version pinning (reject: ./operator.sh elite without a version tag)
# REQUIRE_VERSION_PIN=true

# Require checksum verification (fail if no sha256 tool found)
# REQUIRE_CHECKSUM=true

# Require GPG signature verification (requires trust-key to be set up)
# REQUIRE_SIGNATURE=false

# Audit log file path (append-only, ISO8601 timestamps)
# AUDIT_LOG=/var/log/claude-operator.log

# Custom profile registry URL (replace GitHub with internal mirror)
# Must serve profiles at: <URL>/profiles/<mode>.md
# PROFILE_REGISTRY_URL=https://internal.corp/claude-profiles

# Update policy: "auto" (default) or "manual" (blocks ./operator.sh update)
# UPDATE_POLICY=auto

# Offline mode: serve from local cache only, no network requests
# OFFLINE_MODE=false
ENTERPRISE_CONFIG
  echo "  Enterprise config template written to: $dest"
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

    if ! _verify_checksum "$tmp_file" "$expected_hash" "$STRICT_CHECKSUM"; then
      rm -f "$tmp_file" "$tmp_sha"
      exit 1
    fi

    rm -f "$tmp_sha"

    if [[ "$VERIFY_SIG" == "true" ]]; then
      local tmp_sig
      tmp_sig="$(mktemp /tmp/claude-operator-sig-XXXXXX)"
      curl -fsSL "$RELEASES_BASE/$VERSION/$filename.sig" -o "$tmp_sig" || {
        rm -f "$tmp_file" "$tmp_sig"
        echo "  Error: Failed to download signature"
        exit 1
      }
      # Ensure public key is available
      if [[ ! -f "$GPG_KEY_FILE" ]]; then
        echo "  Fetching GPG public key..."
        mkdir -p "$(dirname "$GPG_KEY_FILE")"
        curl -fsSL "$GPG_KEY_URL" -o "$GPG_KEY_FILE" || {
          rm -f "$tmp_file" "$tmp_sig"
          echo "  Error: Failed to download public key"
          exit 1
        }
      fi
      _import_trust_key "$GPG_KEY_FILE"
      if ! _verify_signature "$tmp_file" "$tmp_sig"; then
        rm -f "$tmp_file" "$tmp_sig"
        exit 1
      fi
      rm -f "$tmp_sig"
    fi

    mv "$tmp_file" "$dest"
  else
    echo "  Downloading $filename from master branch (no checksum)..."
    echo ""
    echo "  Warning: Installing from master branch without checksum verification."
    echo "           For supply-chain security, use: --version vX.Y.Z --strict-checksum"
    echo ""
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

  if $ENTERPRISE_INSTALL; then
    local_config_dest="${ENTERPRISE_CONFIG_PATH:-$HOME/.config/claude-operator/enterprise.conf}"
    echo ""
    echo "Setting up enterprise configuration..."
    _write_enterprise_config_template "$local_config_dest"
    echo "  Edit the config file to enable enterprise policies."
    echo "  Test with: claude-operator enterprise-status"
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
  echo "  bash install.sh --version v1.0.0 --strict-checksum"
  echo ""
fi

if $ENTERPRISE_INSTALL; then
  local_config_dest="${ENTERPRISE_CONFIG_PATH:-$HOME/.config/claude-operator/enterprise.conf}"
  echo ""
  echo "Setting up enterprise configuration..."
  _write_enterprise_config_template "$local_config_dest"
  echo "  Edit the config file to enable enterprise policies."
  echo "  Test with: ./operator.sh enterprise-status"
fi

echo "Done."
