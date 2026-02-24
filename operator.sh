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

# ─── Enterprise ───────────────────────────────────────────────────────────────

ENTERPRISE_CONFIG_SYSTEM="/etc/claude-operator/enterprise.conf"
ENTERPRISE_CONFIG_USER="${CLAUDE_OPERATOR_ENTERPRISE_CONFIG:-$HOME/.config/claude-operator/enterprise.conf}"
CACHE_DIR="$HOME/.config/claude-operator/cache"

# Enterprise defaults (overridden by config)
ENTERPRISE_MODE=false
ALLOWED_PROFILES=""
ALLOWED_REGISTRIES=""
REQUIRE_VERSION_PIN=false
REQUIRE_CHECKSUM=false
REQUIRE_SIGNATURE=false
AUDIT_LOG=""
PROFILE_REGISTRY_URL=""
UPDATE_POLICY="auto"
OFFLINE_MODE=false

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
  echo "       ./operator.sh enterprise-status"
  echo ""
  echo "Examples:"
  echo "  ./operator.sh elite"
  echo "  ./operator.sh elite v1.0.0"
  echo "  ./operator.sh --strict-checksum elite v1.0.0"
  echo "  ./operator.sh update"
  echo "  ./operator.sh enterprise-status"
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

# ─── Enterprise config loader ─────────────────────────────────────────────────

_load_enterprise_config() {
  # Load system-level config first
  if [[ -f "$ENTERPRISE_CONFIG_SYSTEM" ]]; then
    # shellcheck source=/dev/null
    source "$ENTERPRISE_CONFIG_SYSTEM"
  fi

  # Load user-level config (overrides system)
  if [[ -f "$ENTERPRISE_CONFIG_USER" ]]; then
    # shellcheck source=/dev/null
    source "$ENTERPRISE_CONFIG_USER"
  fi

  # Env vars override config files
  [[ -n "${CO_ENTERPRISE_MODE:-}" ]]       && ENTERPRISE_MODE="$CO_ENTERPRISE_MODE"
  [[ -n "${CO_ALLOWED_PROFILES:-}" ]]      && ALLOWED_PROFILES="$CO_ALLOWED_PROFILES"
  [[ -n "${CO_REQUIRE_VERSION_PIN:-}" ]]   && REQUIRE_VERSION_PIN="$CO_REQUIRE_VERSION_PIN"
  [[ -n "${CO_REQUIRE_CHECKSUM:-}" ]]      && REQUIRE_CHECKSUM="$CO_REQUIRE_CHECKSUM"
  [[ -n "${CO_REQUIRE_SIGNATURE:-}" ]]     && REQUIRE_SIGNATURE="$CO_REQUIRE_SIGNATURE"
  [[ -n "${CO_AUDIT_LOG:-}" ]]             && AUDIT_LOG="$CO_AUDIT_LOG"
  [[ -n "${CO_PROFILE_REGISTRY_URL:-}" ]]  && PROFILE_REGISTRY_URL="$CO_PROFILE_REGISTRY_URL"
  [[ -n "${CO_UPDATE_POLICY:-}" ]]         && UPDATE_POLICY="$CO_UPDATE_POLICY"
  [[ -n "${CO_OFFLINE_MODE:-}" ]]          && OFFLINE_MODE="$CO_OFFLINE_MODE"
}

# ─── Audit logger ─────────────────────────────────────────────────────────────

_audit_log() {
  local outcome="$1"
  local message="${2:-}"
  if [[ -n "$AUDIT_LOG" ]]; then
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry="[$timestamp] user=${USER:-unknown} mode=${MODE:-unknown} version=${VERSION:-unset} outcome=$outcome"
    [[ -n "$message" ]] && entry="$entry message=$message"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    echo "$entry" >> "$AUDIT_LOG" 2>/dev/null || true
  fi
}

# ─── Enterprise policy enforcement ───────────────────────────────────────────

_enforce_enterprise_policies() {
  if [[ "$ENTERPRISE_MODE" != "true" ]]; then
    return 0
  fi

  echo "  [Enterprise] Policy enforcement active"

  # Require version pin
  if [[ "$REQUIRE_VERSION_PIN" == "true" && -z "$VERSION" && "$MODE" != "update" && "$MODE" != "plugin" ]]; then
    echo "Error: [Enterprise] Version pinning required. Use: ./operator.sh <mode> <version>"
    _audit_log "failed" "version_pin_required"
    exit 1
  fi

  # Require strict checksum
  if [[ "$REQUIRE_CHECKSUM" == "true" ]]; then
    STRICT_CHECKSUM=true
  fi

  # Require signature
  if [[ "$REQUIRE_SIGNATURE" == "true" ]]; then
    VERIFY_SIG="${VERIFY_SIG:-false}"  # will be set if signed-releases feature is present
  fi

  # Check allowed profiles
  if [[ -n "$ALLOWED_PROFILES" && "$MODE" != "update" && "$MODE" != "plugin" && "$MODE" != "trust-key" ]]; then
    local allowed=false
    for p in $ALLOWED_PROFILES; do
      [[ "$p" == "$MODE" ]] && allowed=true && break
    done
    if [[ "$allowed" != "true" ]]; then
      echo "Error: [Enterprise] Profile '$MODE' is not in the allowed list: $ALLOWED_PROFILES"
      _audit_log "failed" "profile_not_allowed=$MODE"
      exit 1
    fi
  fi

  # Block updates if policy is manual
  if [[ "$UPDATE_POLICY" == "manual" && "$MODE" == "update" ]]; then
    echo "Error: [Enterprise] Auto-updates are disabled (UPDATE_POLICY=manual)."
    echo "       Contact your administrator to update claude-operator."
    _audit_log "failed" "update_blocked_by_policy"
    exit 1
  fi
}

# ─── Cache helpers ────────────────────────────────────────────────────────────

_cache_profile() {
  local mode="$1"
  local ref="$2"
  local src_file="$3"
  mkdir -p "$CACHE_DIR"
  local cache_file="$CACHE_DIR/${mode}@${ref}.md"
  cp "$src_file" "$cache_file" 2>/dev/null || true
}

_serve_from_cache() {
  local mode="$1"
  local ref="$2"
  local cache_file="$CACHE_DIR/${mode}@${ref}.md"
  if [[ -f "$cache_file" ]]; then
    echo "  [Cache] Serving from cache: $cache_file"
    cp "$cache_file" "$TARGET_FILE"
    return 0
  fi
  return 1
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
  _audit_log "success" "updated_to=$latest_tag"
  exit 0
}

# ─── Enterprise status command ────────────────────────────────────────────────

if [[ "$MODE" == "enterprise-status" ]]; then
  _load_enterprise_config
  echo "Enterprise Configuration:"
  echo "  ENTERPRISE_MODE:       $ENTERPRISE_MODE"
  echo "  ALLOWED_PROFILES:      ${ALLOWED_PROFILES:-<all>}"
  echo "  REQUIRE_VERSION_PIN:   $REQUIRE_VERSION_PIN"
  echo "  REQUIRE_CHECKSUM:      $REQUIRE_CHECKSUM"
  echo "  REQUIRE_SIGNATURE:     $REQUIRE_SIGNATURE"
  echo "  AUDIT_LOG:             ${AUDIT_LOG:-<disabled>}"
  echo "  PROFILE_REGISTRY_URL:  ${PROFILE_REGISTRY_URL:-<github>}"
  echo "  UPDATE_POLICY:         $UPDATE_POLICY"
  echo "  OFFLINE_MODE:          $OFFLINE_MODE"
  echo "  CACHE_DIR:             $CACHE_DIR"
  exit 0
fi

# ─── Load enterprise config and enforce policies ──────────────────────────────

_load_enterprise_config
_enforce_enterprise_policies

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

  # Offline mode: serve from cache only
  if [[ "$OFFLINE_MODE" == "true" ]]; then
    if _serve_from_cache "$MODE" "$ref"; then
      echo "$MODE@$ref" > "$MODE_FILE"
      echo ""
      echo "========================================"
      echo " Active Claude Mode: $MODE"
      echo " Version/Ref: $ref"
      echo " CLAUDE.md updated successfully"
      echo "========================================"
      echo ""
      return 0
    else
      echo "Error: [Enterprise] Offline mode enabled but no cached version of '$MODE@$ref' found."
      exit 1
    fi
  fi

  # Determine profile URL
  local profile_url
  if [[ -n "$PROFILE_REGISTRY_URL" ]]; then
    profile_url="${PROFILE_REGISTRY_URL%/}/profiles/$MODE.md"
  else
    profile_url="https://raw.githubusercontent.com/$REPO/$ref/profiles/$MODE.md"
  fi

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

  # Cache the successfully fetched profile
  _cache_profile "$MODE" "$ref" "$TARGET_FILE"

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
_audit_log "success"
