#!/bin/bash

# claude-operator
# Remote profile switcher for CLAUDE.md
# Repo: https://github.com/PsyChaos/claude-operator

set -euo pipefail

# Version embedded at install time — used by `operator.sh update`
OPERATOR_VERSION="master"

REPO="PsyChaos/claude-operator"
BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/$REPO/$BRANCH"
RELEASES_BASE="https://github.com/$REPO/releases/download"
API_BASE="https://api.github.com/repos/$REPO"

TARGET_FILE="$(pwd)/CLAUDE.md"
MODE_FILE="$(pwd)/.claude_mode"

# ─── Strict checksum flag ─────────────────────────────────────────────────────

STRICT_CHECKSUM=false
[[ "${OPERATOR_STRICT_CHECKSUM:-false}" == "true" ]] && STRICT_CHECKSUM=true

# ─── Argument parsing ─────────────────────────────────────────────────────────

if [[ "${1:-}" == "--strict-checksum" ]]; then
  STRICT_CHECKSUM=true
  shift
fi

MODE="${1:-}"
VERSION="${2:-}"

if [ -z "$MODE" ]; then
  echo "Usage: ./operator.sh [--strict-checksum] <mode> [version]"
  echo "       ./operator.sh update"
  echo ""
  echo "Examples:"
  echo "  ./operator.sh elite"
  echo "  ./operator.sh elite v1.0.0"
  echo "  ./operator.sh --strict-checksum elite v1.0.0"
  echo "  ./operator.sh update"
  exit 1
fi

# ─── Dependency check ─────────────────────────────────────────────────────────

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
      echo "  Warning: No sha256 tool found (sha256sum/shasum). Skipping checksum verification."
      return 0
    fi
  fi

  if [[ "$actual_hash" == "$expected_hash" ]]; then
    echo "  ✓ Checksum verified"
    return 0
  else
    echo "  ✗ Checksum mismatch!"
    echo "    Expected: $expected_hash"
    echo "    Got:      $actual_hash"
    return 1
  fi
}

# ─── Self-Update ──────────────────────────────────────────────────────────────

_do_update() {
  local self="$0"

  echo "Checking for updates..."
  echo "Current version: $OPERATOR_VERSION"
  echo ""

  # Fetch latest release metadata (no jq required)
  local release_json
  release_json=$(curl -fsSL "$API_BASE/releases/latest") || {
    echo "Error: Failed to reach GitHub API. Check your internet connection."
    exit 1
  }

  local latest_tag
  latest_tag=$(printf '%s' "$release_json" \
    | grep -o '"tag_name": *"[^"]*"' \
    | grep -o 'v[0-9][^"]*' \
    | head -1)

  if [[ -z "$latest_tag" ]]; then
    echo "Error: Could not parse latest release tag from GitHub API response."
    exit 1
  fi

  echo "Latest release: $latest_tag"

  if [[ "$OPERATOR_VERSION" == "$latest_tag" ]]; then
    echo ""
    echo "Already up to date."
    exit 0
  fi

  echo "Updating $OPERATOR_VERSION → $latest_tag..."
  echo ""

  local tmp_new tmp_sha
  tmp_new="$(mktemp /tmp/claude-operator-update-XXXXXX)"
  tmp_sha="$(mktemp /tmp/claude-operator-sha-XXXXXX)"

  local asset_url="$RELEASES_BASE/$latest_tag/operator.sh"
  local sha_url="$RELEASES_BASE/$latest_tag/operator.sh.sha256"

  echo "  Downloading operator.sh $latest_tag..."
  curl -fsSL "$asset_url" -o "$tmp_new" || {
    rm -f "$tmp_new" "$tmp_sha"
    echo "  Error: Failed to download $asset_url"
    exit 1
  }

  echo "  Fetching checksum..."
  curl -fsSL "$sha_url" -o "$tmp_sha" || {
    rm -f "$tmp_new" "$tmp_sha"
    echo "  Error: Failed to download checksum from $sha_url"
    exit 1
  }

  local expected_hash
  expected_hash=$(awk '{print $1}' "$tmp_sha")

  if ! _verify_checksum "$tmp_new" "$expected_hash" "$STRICT_CHECKSUM"; then
    rm -f "$tmp_new" "$tmp_sha"
    echo "  Aborting update due to checksum failure."
    exit 1
  fi

  rm -f "$tmp_sha"
  chmod +x "$tmp_new"

  # Atomic replace — mv is atomic on same filesystem
  mv "$tmp_new" "$self" 2>/dev/null || {
    rm -f "$tmp_new"
    echo ""
    echo "Error: Cannot replace $self (permission denied)."
    echo "If installed system-wide, try: sudo operator.sh update"
    exit 1
  }

  echo ""
  echo "========================================"
  echo " claude-operator updated to $latest_tag"
  echo "========================================"
  echo ""
  exit 0
}

# ─── Update branch ────────────────────────────────────────────────────────────

if [[ "$MODE" == "update" ]]; then
  _do_update
fi

# ─── Profile fetch ────────────────────────────────────────────────────────────

_do_fetch_profile() {
  local tmp_profile
  tmp_profile="$(mktemp /tmp/claude-operator-profile-XXXXXX)"

  local ref
  if [ -n "$VERSION" ]; then
    ref="$VERSION"
  else
    ref="$BRANCH"
  fi

  local profile_url="https://raw.githubusercontent.com/$REPO/$ref/profiles/$MODE.md"

  echo "Fetching profile: $MODE"
  echo "Source: $profile_url"

  curl -fsSL "$profile_url" -o "$tmp_profile" || {
    rm -f "$tmp_profile"
    echo "Error: Failed to fetch profile '$MODE' (ref: $ref)"
    echo "Check that the profile name is valid and the version tag exists."
    exit 1
  }

  if [ -n "$VERSION" ]; then
    # Versioned fetch — verify against sidecar checksum
    local tmp_sha
    tmp_sha="$(mktemp /tmp/claude-operator-sha-XXXXXX)"
    local sha_url="$RELEASES_BASE/$VERSION/profiles/$MODE.md.sha256"

    echo "  Fetching profile checksum..."
    curl -fsSL "$sha_url" -o "$tmp_sha" || {
      rm -f "$tmp_profile" "$tmp_sha"
      echo "  Error: Failed to download profile checksum from $sha_url"
      exit 1
    }

    local expected_hash
    expected_hash=$(awk '{print $1}' "$tmp_sha")

    if ! _verify_checksum "$tmp_profile" "$expected_hash" "$STRICT_CHECKSUM"; then
      rm -f "$tmp_profile" "$tmp_sha"
      echo "  Aborting due to profile checksum failure."
      exit 1
    fi

    rm -f "$tmp_sha"
  else
    # Master branch fetch — no sidecar checksum available
    echo "  Note: Fetching from master branch. No checksum sidecar available."
    echo "        For supply-chain security, use: ./operator.sh <mode> vX.Y.Z"
  fi

  mv "$tmp_profile" "$TARGET_FILE"

  echo "$MODE@$ref" > "$MODE_FILE"

  echo ""
  echo "========================================"
  echo " Active Claude Mode: $MODE"
  echo " Version/Ref: $ref"
  echo " CLAUDE.md updated successfully"
  echo "========================================"
  echo ""
}

_do_fetch_profile
