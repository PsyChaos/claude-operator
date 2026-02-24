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

GPG_KEY_FILE="$HOME/.config/claude-operator/claude-operator.gpg.pub"
GPG_KEY_URL="https://raw.githubusercontent.com/$REPO/$BRANCH/claude-operator.gpg.pub"

TARGET_FILE="$(pwd)/CLAUDE.md"
MODE_FILE="$(pwd)/.claude_mode"

# ─── Strict checksum flag ─────────────────────────────────────────────────────

STRICT_CHECKSUM=false
[[ "${OPERATOR_STRICT_CHECKSUM:-false}" == "true" ]] && STRICT_CHECKSUM=true || true

# ─── Plugin config dirs ───────────────────────────────────────────────────────

CONFIG_DIR="${CLAUDE_OPERATOR_CONFIG_DIR:-$HOME/.config/claude-operator}"
PLUGINS_DIR="$CONFIG_DIR/plugins"
REGISTRIES_FILE="$CONFIG_DIR/registries.conf"
LOCAL_PLUGINS_DIR="$(pwd)/claude-operator-plugins"

# ─── Signature verification flag ──────────────────────────────────────────────

VERIFY_SIG=false
[[ "${OPERATOR_VERIFY_SIG:-false}" == "true" ]] && VERIFY_SIG=true || true

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

# ─── Conflict resolution ──────────────────────────────────────────────────────

# Backup dir and sentinel constants
BACKUP_DIR="$(pwd)/.claude_backup"
SENTINEL_BEGIN="<!-- claude-operator:begin"
SENTINEL_END="<!-- claude-operator:end -->"
MAX_BACKUPS=5

# Conflict resolution mode: prompt | backup | merge | force
# Can be overridden via env var CLAUDE_OPERATOR_CONFLICT
CONFLICT_MODE="${CLAUDE_OPERATOR_CONFLICT:-prompt}"

# ─── Argument parsing ─────────────────────────────────────────────────────────

while [[ "${1:-}" == --* ]]; do
  case "${1:-}" in
    --strict-checksum)
      STRICT_CHECKSUM=true
      shift
      ;;
    --verify-sig)
      VERIFY_SIG=true
      shift
      ;;
    --force)
      CONFLICT_MODE="force"
      shift
      ;;
    --backup)
      CONFLICT_MODE="backup"
      shift
      ;;
    --merge)
      CONFLICT_MODE="merge"
      shift
      ;;
    *)
      break
      ;;
  esac
done

MODE="${1:-}"
VERSION="${2:-}"

if [ -z "$MODE" ]; then
  echo "Usage: ./operator.sh [flags] <mode> [version]"
  echo "       ./operator.sh update"
  echo "       ./operator.sh restore [--list] [timestamp]"
  echo "       ./operator.sh plugin <add|list|remove|update> [registry] [version]"
  echo "       ./operator.sh trust-key"
  echo "       ./operator.sh enterprise-status"
  echo ""
  echo "Flags:"
  echo "  --strict-checksum   Hard fail if no sha256 tool found"
  echo "  --verify-sig        Verify GPG signature of downloaded files"
  echo "  --force             Overwrite CLAUDE.md without prompting"
  echo "  --backup            Backup existing CLAUDE.md then overwrite (non-interactive)"
  echo "  --merge             Append profile below existing content using sentinels (opt-in)"
  echo ""
  echo "Examples:"
  echo "  ./operator.sh elite"
  echo "  ./operator.sh elite v1.0.0"
  echo "  ./operator.sh --verify-sig elite v1.0.0"
  echo "  ./operator.sh --strict-checksum --verify-sig elite v1.0.0"
  echo "  ./operator.sh --merge elite v1.0.0"
  echo "  ./operator.sh --backup elite v1.0.0"
  echo "  ./operator.sh --force elite v1.0.0"
  echo "  ./operator.sh restore"
  echo "  ./operator.sh restore --list"
  echo "  ./operator.sh update"
  echo "  ./operator.sh plugin add myorg/my-profiles"
  echo "  ./operator.sh plugin list"
  echo "  ./operator.sh trust-key"
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

# ─── Conflict detection & resolution ─────────────────────────────────────────

# Returns 0 if CLAUDE.md is managed by claude-operator, 1 if unmanaged/absent
_is_operator_managed() {
  # Not present at all → not a conflict
  [[ ! -f "$TARGET_FILE" ]] && return 0
  # Has operator sentinel header → managed
  grep -q "^$SENTINEL_BEGIN" "$TARGET_FILE" 2>/dev/null && return 0
  # Has .claude_mode state file → managed
  [[ -f "$MODE_FILE" ]] && return 0
  # Exists but no evidence of operator ownership → unmanaged
  return 1
}

# Ensure .claude_backup/ is in .gitignore
_ensure_gitignore() {
  local gitignore="$(pwd)/.gitignore"
  local entry=".claude_backup/"
  if [[ -f "$gitignore" ]]; then
    if ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
      printf '\n# claude-operator backups\n%s\n' "$entry" >> "$gitignore"
      echo "  Note: Added $entry to .gitignore" >&2
    fi
  else
    printf '# claude-operator backups\n%s\n' "$entry" > "$gitignore"
    echo "  Note: Created .gitignore with $entry" >&2
  fi
}

# Rotate backups — keep at most MAX_BACKUPS, remove oldest first
_rotate_backups() {
  [[ ! -d "$BACKUP_DIR" ]] && return 0
  local count
  count=$(ls -1 "$BACKUP_DIR"/CLAUDE.md.* 2>/dev/null | wc -l)
  if [[ "$count" -ge "$MAX_BACKUPS" ]]; then
    local to_delete=$(( count - MAX_BACKUPS + 1 ))
    ls -1t "$BACKUP_DIR"/CLAUDE.md.* 2>/dev/null | tail -n "$to_delete" | while IFS= read -r f; do
      rm -f "$f"
    done
  fi
}

# Backup existing CLAUDE.md to .claude_backup/<timestamp>
_backup_existing() {
  [[ ! -f "$TARGET_FILE" ]] && return 0
  _ensure_gitignore
  mkdir -p "$BACKUP_DIR"
  _rotate_backups
  local ts
  ts=$(date -u +"%Y%m%dT%H%M%SZ")
  local dest="$BACKUP_DIR/CLAUDE.md.$ts"
  cp "$TARGET_FILE" "$dest"
  echo "  Backed up: $dest" >&2
}

# Apply profile via merge/composition (sentinel-based)
# $1 = path to downloaded profile tmp file
# $2 = mode@ref label for sentinel
_apply_merge() {
  local profile_tmp="$1"
  local label="$2"

  local begin_line="$SENTINEL_BEGIN $label -->"
  local end_line="$SENTINEL_END"

  if [[ ! -f "$TARGET_FILE" ]]; then
    # No existing file — write with sentinel wrapper
    {
      printf '%s\n' "$begin_line"
      cat "$profile_tmp"
      printf '%s\n' "$end_line"
    } > "$TARGET_FILE"
    echo "  Created CLAUDE.md with operator section." >&2
    return 0
  fi

  if grep -q "^$SENTINEL_BEGIN" "$TARGET_FILE" 2>/dev/null; then
    # Sentinel exists — replace the operator section in-place
    local tmp_merged
    tmp_merged="$(mktemp /tmp/claude-operator-merge-XXXXXX)"
    local in_sentinel=false
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" == $SENTINEL_BEGIN* ]]; then
        in_sentinel=true
        # Write new begin sentinel + new content
        printf '%s\n' "$begin_line" >> "$tmp_merged"
        cat "$profile_tmp" >> "$tmp_merged"
        printf '%s\n' "$end_line" >> "$tmp_merged"
        continue
      fi
      if [[ "$line" == "$SENTINEL_END" ]]; then
        in_sentinel=false
        continue
      fi
      [[ "$in_sentinel" == "false" ]] && printf '%s\n' "$line" >> "$tmp_merged"
    done < "$TARGET_FILE"
    mv "$tmp_merged" "$TARGET_FILE"
    echo "  Updated operator section in CLAUDE.md (project content preserved)." >&2
  else
    # No sentinel yet — append operator section below existing content
    {
      echo ""
      echo "---"
      echo ""
      printf '%s\n' "$begin_line"
      cat "$profile_tmp"
      printf '%s\n' "$end_line"
    } >> "$TARGET_FILE"
    echo "  Appended operator section to existing CLAUDE.md." >&2
  fi
}

# Remove sentinel block from CLAUDE.md (restore project-only content)
_remove_sentinel() {
  [[ ! -f "$TARGET_FILE" ]] && return 0
  if ! grep -q "^$SENTINEL_BEGIN" "$TARGET_FILE" 2>/dev/null; then
    echo "  No operator sentinel found in CLAUDE.md — nothing to remove."
    return 0
  fi
  local tmp_stripped
  tmp_stripped="$(mktemp /tmp/claude-operator-stripped-XXXXXX)"
  local in_sentinel=false
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == $SENTINEL_BEGIN* ]]; then
      in_sentinel=true
      continue
    fi
    if [[ "$line" == "$SENTINEL_END" ]]; then
      in_sentinel=false
      continue
    fi
    [[ "$in_sentinel" == "false" ]] && printf '%s\n' "$line" >> "$tmp_stripped"
  done < "$TARGET_FILE"
  # Strip trailing blank lines left by sentinel removal
  sed -i 's/[[:space:]]*$//' "$tmp_stripped"
  mv "$tmp_stripped" "$TARGET_FILE"
  echo "  Operator section removed. Project content preserved."
}

# Interactive conflict prompt — returns chosen action: backup|merge|force|abort
_prompt_conflict() {
  echo "" >&2
  echo "Warning: CLAUDE.md exists and is not managed by claude-operator." >&2
  echo "" >&2
  echo "  [b] Backup & overwrite  — save to .claude_backup/, apply profile  (default)" >&2
  echo "  [m] Merge               — keep project content, append profile below" >&2
  echo "  [o] Overwrite           — replace entirely (current content will be lost)" >&2
  echo "  [a] Abort               — do nothing" >&2
  echo "" >&2

  local choice=""
  local timeout=10
  if read -r -t "$timeout" -p "Choice [b/m/o/a] (default: b, auto-selects in ${timeout}s): " choice 2>/dev/null; then
    : # got input
  else
    echo "" >&2
    echo "  Timeout — defaulting to: backup" >&2
    choice="b"
  fi

  case "${choice,,}" in
    m) printf 'merge'  ;;
    o) printf 'force'  ;;
    a) printf 'abort'  ;;
    *) printf 'backup' ;;  # b or empty or anything else
  esac
}

# Main conflict resolver — decides what to do when unmanaged CLAUDE.md exists
# $1 = profile tmp file path, $2 = mode@ref label
# Returns: writes to TARGET_FILE using the chosen strategy
_resolve_conflict() {
  local profile_tmp="$1"
  local label="$2"
  local action="$CONFLICT_MODE"

  # If not interactive terminal and mode is still "prompt", default to backup
  if [[ "$action" == "prompt" ]] && [[ ! -t 0 ]]; then
    echo "  Non-interactive mode — defaulting to: backup" >&2
    action="backup"
  fi

  # Interactive prompt
  if [[ "$action" == "prompt" ]]; then
    action=$(_prompt_conflict)
  fi

  case "$action" in
    abort)
      echo "" >&2
      echo "Aborted. CLAUDE.md was not modified." >&2
      exit 0
      ;;
    backup)
      _backup_existing
      mv "$profile_tmp" "$TARGET_FILE"
      printf 'backup'
      ;;
    merge)
      _apply_merge "$profile_tmp" "$label"
      rm -f "$profile_tmp"
      printf 'merge'
      ;;
    force)
      mv "$profile_tmp" "$TARGET_FILE"
      printf 'force'
      ;;
    *)
      # Fallback — should not happen
      mv "$profile_tmp" "$TARGET_FILE"
      printf 'force'
      ;;
  esac
}

# ─── Restore ──────────────────────────────────────────────────────────────────

_do_restore() {
  local list_mode=false
  local target_ts=""

  # Parse restore sub-args
  local restore_arg="${2:-}"
  local restore_arg2="${3:-}"
  if [[ "$restore_arg" == "--list" ]]; then
    list_mode=true
  elif [[ -n "$restore_arg" ]]; then
    target_ts="$restore_arg"
  fi

  # --list: show available backups
  if [[ "$list_mode" == "true" ]]; then
    echo "Available backups:"
    if [[ -d "$BACKUP_DIR" ]] && ls "$BACKUP_DIR"/CLAUDE.md.* &>/dev/null; then
      ls -1t "$BACKUP_DIR"/CLAUDE.md.* | while IFS= read -r f; do
        local ts
        ts="$(basename "$f" | sed 's/CLAUDE\.md\.//')"
        echo "  $ts"
      done
    else
      echo "  (none)"
    fi
    return 0
  fi

  # Determine what write_mode was used (from .claude_mode)
  local write_mode="overwrite"
  if [[ -f "$MODE_FILE" ]]; then
    local mode_entry
    mode_entry="$(cat "$MODE_FILE")"
    if [[ "$mode_entry" == *:* ]]; then
      write_mode="${mode_entry##*:}"
    fi
  fi

  local has_sentinel=false
  local has_backup=false

  grep -q "^$SENTINEL_BEGIN" "$TARGET_FILE" 2>/dev/null && has_sentinel=true
  [[ -d "$BACKUP_DIR" ]] && ls "$BACKUP_DIR"/CLAUDE.md.* &>/dev/null && has_backup=true

  # Determine action based on what's available and write_mode
  local action=""

  if [[ "$write_mode" == "merge" && "$has_backup" == "false" ]]; then
    action="sentinel"
  elif [[ "$write_mode" == "backup" && "$has_sentinel" == "false" ]]; then
    action="backup"
  elif [[ "$write_mode" == "merge+backup" ]] || \
       ( [[ "$has_sentinel" == "true" ]] && [[ "$has_backup" == "true" ]] ); then
    # Both available — ask
    echo ""
    echo "Both a sentinel section and a backup are available."
    echo ""
    echo "  [s] Remove sentinel   — keep project content, strip operator section"
    echo "  [b] From backup       — restore last backup"
    echo "  [a] Abort"
    echo ""
    local choice=""
    read -r -p "Choice [s/b/a] (default: s): " choice 2>/dev/null || choice="s"
    case "${choice,,}" in
      b) action="backup" ;;
      a) echo "Aborted."; return 0 ;;
      *) action="sentinel" ;;
    esac
  elif [[ "$has_sentinel" == "true" ]]; then
    action="sentinel"
  elif [[ "$has_backup" == "true" ]]; then
    action="backup"
  else
    echo "Nothing to restore. No backup or sentinel found."
    return 0
  fi

  # Execute restore action
  if [[ "$action" == "sentinel" ]]; then
    echo "Removing operator sentinel section..."
    _remove_sentinel
  elif [[ "$action" == "backup" ]]; then
    local backup_file=""
    if [[ -n "$target_ts" ]]; then
      backup_file="$BACKUP_DIR/CLAUDE.md.$target_ts"
      if [[ ! -f "$backup_file" ]]; then
        echo "Error: No backup found for timestamp '$target_ts'"
        echo "Run: ./operator.sh restore --list"
        exit 1
      fi
    else
      backup_file=$(ls -1t "$BACKUP_DIR"/CLAUDE.md.* 2>/dev/null | head -1)
      if [[ -z "$backup_file" ]]; then
        echo "Error: No backups found in $BACKUP_DIR"
        exit 1
      fi
    fi
    cp "$backup_file" "$TARGET_FILE"
    echo "  Restored from: $(basename "$backup_file")"
  fi

  # Clear mode file
  rm -f "$MODE_FILE"

  echo ""
  echo "========================================"
  echo " CLAUDE.md restored successfully"
  echo "========================================"
  echo ""
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
  [[ -n "${CO_ENTERPRISE_MODE:-}" ]]       && ENTERPRISE_MODE="$CO_ENTERPRISE_MODE"       || true
  [[ -n "${CO_ALLOWED_PROFILES:-}" ]]      && ALLOWED_PROFILES="$CO_ALLOWED_PROFILES"      || true
  [[ -n "${CO_REQUIRE_VERSION_PIN:-}" ]]   && REQUIRE_VERSION_PIN="$CO_REQUIRE_VERSION_PIN" || true
  [[ -n "${CO_REQUIRE_CHECKSUM:-}" ]]      && REQUIRE_CHECKSUM="$CO_REQUIRE_CHECKSUM"      || true
  [[ -n "${CO_REQUIRE_SIGNATURE:-}" ]]     && REQUIRE_SIGNATURE="$CO_REQUIRE_SIGNATURE"    || true
  [[ -n "${CO_AUDIT_LOG:-}" ]]             && AUDIT_LOG="$CO_AUDIT_LOG"                    || true
  [[ -n "${CO_PROFILE_REGISTRY_URL:-}" ]]  && PROFILE_REGISTRY_URL="$CO_PROFILE_REGISTRY_URL" || true
  [[ -n "${CO_UPDATE_POLICY:-}" ]]         && UPDATE_POLICY="$CO_UPDATE_POLICY"            || true
  [[ -n "${CO_OFFLINE_MODE:-}" ]]          && OFFLINE_MODE="$CO_OFFLINE_MODE"              || true
  return 0
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
  local http_code
  release_json=$(curl -fsSL --write-out "\n__HTTP_CODE__:%{http_code}" "$API_BASE/releases/latest" 2>/dev/null) || true
  http_code=$(printf '%s' "$release_json" | grep -o '__HTTP_CODE__:[0-9]*' | cut -d: -f2)
  release_json=$(printf '%s' "$release_json" | grep -v '__HTTP_CODE__:')

  if [[ "$http_code" == "404" ]]; then
    echo "Already up to date. No releases published yet."
    exit 0
  fi

  if [[ -z "$release_json" || "$http_code" != "200" ]]; then
    echo "Error: Failed to reach GitHub API (HTTP $http_code). Check your internet connection."
    exit 1
  fi

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

  if [[ "$VERIFY_SIG" == "true" ]]; then
    local tmp_sig
    tmp_sig="$(mktemp /tmp/claude-operator-sig-XXXXXX)"
    local sig_url="$RELEASES_BASE/$latest_tag/operator.sh.sig"
    echo "  Fetching GPG signature..."
    curl -fsSL "$sig_url" -o "$tmp_sig" || {
      rm -f "$tmp_new" "$tmp_sig"
      echo "  Error: Failed to download signature from $sig_url"
      exit 1
    }
    _import_trust_key
    if ! _verify_signature "$tmp_new" "$tmp_sig"; then
      rm -f "$tmp_new" "$tmp_sig"
      echo "  Aborting update due to signature verification failure."
      exit 1
    fi
    rm -f "$tmp_sig"
  fi

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

# ─── Plugin helpers ───────────────────────────────────────────────────────────

_plugin_registry_slug() {
  local registry="$1"
  printf '%s' "$registry" | sed 's|/|__|g'
}

_plugin_add() {
  local registry="${1:-}"
  local version="${2:-}"

  if [[ -z "$registry" ]]; then
    echo "Error: registry argument required (format: owner/repo)"
    exit 1
  fi

  # Validate format
  if ! printf '%s' "$registry" | grep -qE '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$'; then
    echo "Error: Invalid registry format '$registry'. Expected: owner/repo"
    exit 1
  fi

  local slug
  slug=$(_plugin_registry_slug "$registry")

  local plugin_dir="$PLUGINS_DIR/$slug"
  mkdir -p "$plugin_dir"

  local ref="${version:-HEAD}"

  echo "Adding plugin registry: $registry"
  [[ -n "$version" ]] && echo "Version: $version"
  echo ""

  # Fetch plugin.json manifest if it exists (optional, silent on failure)
  local manifest_url="https://raw.githubusercontent.com/$registry/$ref/plugin.json"
  local manifest
  manifest=$(curl -fsSL "$manifest_url" 2>/dev/null) || true

  if [[ -n "$manifest" ]]; then
    local plugin_name plugin_desc plugin_profiles
    plugin_name=$(printf '%s' "$manifest" | grep -o '"name": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"') || true
    plugin_desc=$(printf '%s' "$manifest" | grep -o '"description": *"[^"]*"' | head -1 | grep -o '"[^"]*"$' | tr -d '"') || true
    plugin_profiles=$(printf '%s' "$manifest" | grep -o '"profiles": *\[[^]]*\]' | grep -o '"[^"]*"' | tr -d '"' | tr '\n' ' ') || true

    echo "Plugin manifest:"
    [[ -n "$plugin_name" ]]     && echo "  Name:        $plugin_name"
    [[ -n "$plugin_desc" ]]     && echo "  Description: $plugin_desc"
    [[ -n "$plugin_profiles" ]] && echo "  Profiles:    $plugin_profiles"
    echo ""
  fi

  # Discover profiles via GitHub Contents API
  local contents_url="https://api.github.com/repos/$registry/contents/profiles"
  [[ -n "$version" ]] && contents_url="$contents_url?ref=$version"

  local contents_json
  contents_json=$(curl -fsSL "$contents_url" 2>/dev/null) || {
    echo "Error: Failed to fetch profiles listing from $contents_url"
    exit 1
  }

  local profiles
  profiles=$(printf '%s' "$contents_json" \
    | grep -o '"name": *"[^"]*\.md"' \
    | grep -o '"[^"]*\.md"' \
    | tr -d '"') || true

  if [[ -z "$profiles" ]]; then
    echo "Warning: No .md profiles found in $registry/profiles/"
    echo "0 profiles downloaded."
  else
    local count=0
    while IFS= read -r profile_file; do
      [[ -z "$profile_file" ]] && continue
      local mode_name="${profile_file%.md}"
      local raw_url="https://raw.githubusercontent.com/$registry/$ref/profiles/$profile_file"
      local dest="$plugin_dir/$profile_file"

      echo "  Downloading: $mode_name"
      curl -fsSL "$raw_url" -o "$dest" || {
        echo "  Warning: Failed to download $profile_file — skipping"
        continue
      }

      # If version given, also download .sha256 sidecar and verify
      if [[ -n "$version" ]]; then
        local sha_url="${raw_url}.sha256"
        local tmp_sha
        tmp_sha="$(mktemp /tmp/claude-operator-plugin-sha-XXXXXX)"
        if curl -fsSL "$sha_url" -o "$tmp_sha" 2>/dev/null; then
          local expected_hash
          expected_hash=$(awk '{print $1}' "$tmp_sha")
          if ! _verify_checksum "$dest" "$expected_hash"; then
            rm -f "$tmp_sha" "$dest"
            echo "  Aborting: checksum failure for $profile_file"
            exit 1
          fi
        fi
        rm -f "$tmp_sha"
      fi

      count=$((count + 1))
    done <<< "$profiles"

    echo ""
    echo "$count profile(s) downloaded."
  fi

  # Update registries.conf
  mkdir -p "$(dirname "$REGISTRIES_FILE")"
  local entry="$registry"
  [[ -n "$version" ]] && entry="$registry@$version"

  local already_present=false
  if [[ -f "$REGISTRIES_FILE" ]]; then
    if grep -qF "$registry" "$REGISTRIES_FILE" 2>/dev/null; then
      already_present=true
    fi
  fi

  if [[ "$already_present" == "false" ]]; then
    printf '%s\n' "$entry" >> "$REGISTRIES_FILE"
    echo "Registered: $entry"
  else
    echo "Registry already present in $REGISTRIES_FILE"
  fi

  echo ""
  echo "========================================"
  echo " Plugin added: $registry"
  echo "========================================"
  echo ""
}

_plugin_list() {
  echo "Core profiles ($REPO):"
  echo "  elite"
  echo "  high-autonomy"
  echo "  senior-production"
  echo ""

  if [[ -f "$REGISTRIES_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      # Strip version suffix for slug lookup
      local registry="${line%@*}"
      local slug
      slug=$(_plugin_registry_slug "$registry")
      local plugin_dir="$PLUGINS_DIR/$slug"

      echo "Plugin: $line"
      if [[ -d "$plugin_dir" ]]; then
        local found=false
        for f in "$plugin_dir"/*.md; do
          [[ -e "$f" ]] || continue
          local mode_name
          mode_name="$(basename "$f" .md)"
          echo "  $mode_name"
          found=true
        done
        if [[ "$found" == "false" ]]; then
          echo "  (no profiles cached)"
        fi
      else
        echo "  (not yet downloaded — run: ./operator.sh plugin update $registry)"
      fi
      echo ""
    done < "$REGISTRIES_FILE"
  fi

  if [[ -d "$LOCAL_PLUGINS_DIR" ]]; then
    local local_found=false
    for f in "$LOCAL_PLUGINS_DIR"/*.md; do
      [[ -e "$f" ]] || continue
      local_found=true
      break
    done

    if [[ "$local_found" == "true" ]]; then
      echo "Local (./claude-operator-plugins/):"
      for f in "$LOCAL_PLUGINS_DIR"/*.md; do
        [[ -e "$f" ]] || continue
        local mode_name
        mode_name="$(basename "$f" .md)"
        echo "  $mode_name"
      done
      echo ""
    fi
  fi
}

_plugin_remove() {
  local registry="${1:-}"

  if [[ -z "$registry" ]]; then
    echo "Error: registry argument required (format: owner/repo)"
    exit 1
  fi

  local slug
  slug=$(_plugin_registry_slug "$registry")
  local plugin_dir="$PLUGINS_DIR/$slug"

  if [[ -d "$plugin_dir" ]]; then
    rm -rf "$plugin_dir"
    echo "Removed plugin cache: $plugin_dir"
  else
    echo "No cached profiles found for $registry"
  fi

  if [[ -f "$REGISTRIES_FILE" ]]; then
    local tmp_reg
    tmp_reg="$(mktemp /tmp/claude-operator-reg-XXXXXX)"
    grep -vF "$registry" "$REGISTRIES_FILE" > "$tmp_reg" 2>/dev/null || true
    mv "$tmp_reg" "$REGISTRIES_FILE"
    echo "Removed from registries: $registry"
  fi

  echo ""
  echo "========================================"
  echo " Plugin removed: $registry"
  echo "========================================"
  echo ""
}

_plugin_update() {
  local target_registry="${1:-}"

  if [[ ! -f "$REGISTRIES_FILE" ]]; then
    echo "No registries configured. Use: ./operator.sh plugin add owner/repo"
    exit 0
  fi

  # Snapshot registries into an array to avoid reading while modifying
  local -a entries=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    entries+=("$line")
  done < "$REGISTRIES_FILE"

  for line in "${entries[@]}"; do
    local registry version_part=""
    if printf '%s' "$line" | grep -q '@'; then
      registry="${line%@*}"
      version_part="${line#*@}"
    else
      registry="$line"
    fi

    if [[ -n "$target_registry" && "$registry" != "$target_registry" ]]; then
      continue
    fi

    echo "Updating: $registry"
    # Remove existing cache before re-adding
    local slug
    slug=$(_plugin_registry_slug "$registry")
    rm -rf "$PLUGINS_DIR/$slug"

    # Remove from registries so _plugin_add can re-register cleanly
    if [[ -f "$REGISTRIES_FILE" ]]; then
      local tmp_reg
      tmp_reg="$(mktemp /tmp/claude-operator-reg-XXXXXX)"
      grep -vF "$registry" "$REGISTRIES_FILE" > "$tmp_reg" 2>/dev/null || true
      mv "$tmp_reg" "$REGISTRIES_FILE"
    fi

    _plugin_add "$registry" "$version_part"
  done

  echo "Update complete."
}

# ─── Mode resolution ──────────────────────────────────────────────────────────

_resolve_mode() {
  local mode="$1"

  # 1. Check local plugins directory first
  if [[ -f "$LOCAL_PLUGINS_DIR/$mode.md" ]]; then
    printf 'local:%s' "$LOCAL_PLUGINS_DIR/$mode.md"
    return 0
  fi

  # 2. Check each registered plugin's cached profiles
  if [[ -f "$REGISTRIES_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      local registry="${line%@*}"
      local slug
      slug=$(_plugin_registry_slug "$registry")
      local cached="$PLUGINS_DIR/$slug/$mode.md"
      if [[ -f "$cached" ]]; then
        printf 'plugin:%s' "$cached"
        return 0
      fi
    done < "$REGISTRIES_FILE"
  fi

  # 3. Fall back to remote core profile
  printf 'remote'
  return 0
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

# ─── Restore branch ──────────────────────────────────────────────────────────

if [[ "$MODE" == "restore" ]]; then
  _do_restore "$@"
  exit 0
fi

# ─── Update branch ────────────────────────────────────────────────────────────

if [[ "$MODE" == "update" ]]; then
  _do_update
fi

# ─── Plugin subcommand ────────────────────────────────────────────────────────

if [[ "$MODE" == "plugin" ]]; then
  PLUGIN_CMD="${2:-}"
  PLUGIN_ARG="${3:-}"
  PLUGIN_VERSION="${4:-}"
  case "$PLUGIN_CMD" in
    add)    _plugin_add "$PLUGIN_ARG" "$PLUGIN_VERSION" ;;
    list)   _plugin_list ;;
    remove) _plugin_remove "$PLUGIN_ARG" ;;
    update) _plugin_update "${PLUGIN_ARG:-}" ;;
    *)
      echo "Usage: ./operator.sh plugin <add|list|remove|update> [registry] [version]"
      echo "Examples:"
      echo "  ./operator.sh plugin add myorg/my-profiles"
      echo "  ./operator.sh plugin add myorg/my-profiles v1.0.0"
      echo "  ./operator.sh plugin list"
      echo "  ./operator.sh plugin remove myorg/my-profiles"
      echo "  ./operator.sh plugin update"
      exit 1
      ;;
  esac
  exit 0
fi

# ─── Trust-key branch ─────────────────────────────────────────────────────────

if [[ "$MODE" == "trust-key" ]]; then
  _ensure_gpg
  echo "Fetching claude-operator public GPG key..."
  mkdir -p "$(dirname "$GPG_KEY_FILE")"
  curl -fsSL "$GPG_KEY_URL" -o "$GPG_KEY_FILE" || {
    echo "Error: Failed to download public key from $GPG_KEY_URL"
    exit 1
  }
  echo "  Downloaded to: $GPG_KEY_FILE"
  _import_trust_key "$GPG_KEY_FILE"
  echo ""
  echo "========================================"
  echo " claude-operator GPG key trusted"
  echo " You can now use --verify-sig"
  echo "========================================"
  exit 0
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

    if [[ "$VERIFY_SIG" == "true" ]]; then
      local tmp_profile_sig
      tmp_profile_sig="$(mktemp /tmp/claude-operator-profile-sig-XXXXXX)"
      local profile_sig_url="$RELEASES_BASE/$VERSION/profiles/$MODE.md.sig"
      echo "  Fetching profile GPG signature..."
      curl -fsSL "$profile_sig_url" -o "$tmp_profile_sig" || {
        rm -f "$tmp_profile" "$tmp_profile_sig"
        echo "  Error: Failed to download profile signature from $profile_sig_url"
        exit 1
      }
      _import_trust_key
      if ! _verify_signature "$tmp_profile" "$tmp_profile_sig"; then
        rm -f "$tmp_profile" "$tmp_profile_sig"
        echo "  Aborting profile fetch due to signature verification failure."
        exit 1
      fi
      rm -f "$tmp_profile_sig"
    fi
  else
    # Master branch fetch — no sidecar checksum available
    echo "  Note: Fetching from master branch. No checksum sidecar available."
    echo "        For supply-chain security, use: ./operator.sh <mode> vX.Y.Z"
  fi

  # ─── Conflict detection & write ──────────────────────────────────────────────

  local label="$MODE@$ref"
  local write_mode="overwrite"

  if _is_operator_managed; then
    # Managed by operator — apply directly (or honour --merge flag)
    if [[ "$CONFLICT_MODE" == "merge" ]]; then
      _apply_merge "$tmp_profile" "$label"
      rm -f "$tmp_profile"
      write_mode="merge"
    else
      mv "$tmp_profile" "$TARGET_FILE"
      write_mode="overwrite"
    fi
  else
    # Unmanaged CLAUDE.md exists — run conflict resolution flow
    echo ""
    local resolved_action
    resolved_action=$(_resolve_conflict "$tmp_profile" "$label")
    write_mode="$resolved_action"

    # If merge was chosen via prompt, _apply_merge already wrote the file
    # and tmp was removed inside _resolve_conflict. If backup/force, mv was done.
    # In all cases tmp_profile is handled.
  fi

  # Record write_mode in .claude_mode
  echo "$label:$write_mode" > "$MODE_FILE"

  # Cache the successfully fetched profile
  _cache_profile "$MODE" "$ref" "$TARGET_FILE"

  echo ""
  echo "========================================"
  echo " Active Claude Mode: $MODE"
  echo " Version/Ref: $ref"
  echo " Write mode: $write_mode"
  echo " CLAUDE.md updated successfully"
  echo "========================================"
  echo ""
}

_do_fetch_profile
_audit_log "success"
