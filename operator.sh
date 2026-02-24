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

CONFIG_DIR="${CLAUDE_OPERATOR_CONFIG_DIR:-$HOME/.config/claude-operator}"
PLUGINS_DIR="$CONFIG_DIR/plugins"
REGISTRIES_FILE="$CONFIG_DIR/registries.conf"
LOCAL_PLUGINS_DIR="$(pwd)/claude-operator-plugins"

MODE="${1:-}"
VERSION="${2:-}"

if [ -z "$MODE" ]; then
  echo "Usage: ./operator.sh <mode> [version]"
  echo "       ./operator.sh update"
  echo "       ./operator.sh plugin <add|list|remove|update> [registry] [version]"
  echo ""
  echo "Examples:"
  echo "  ./operator.sh elite"
  echo "  ./operator.sh elite v1.0.0"
  echo "  ./operator.sh update"
  echo "  ./operator.sh plugin add myorg/my-profiles"
  echo "  ./operator.sh plugin add myorg/my-profiles v1.0.0"
  echo "  ./operator.sh plugin list"
  echo "  ./operator.sh plugin remove myorg/my-profiles"
  echo "  ./operator.sh plugin update"
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
  local actual_hash
  actual_hash=$(_sha256_compute "$file")

  if [[ -z "$actual_hash" ]]; then
    echo "  Warning: No sha256 tool found (sha256sum/shasum). Skipping checksum verification."
    return 0
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

  if ! _verify_checksum "$tmp_new" "$expected_hash"; then
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

# ─── Profile fetch ────────────────────────────────────────────────────────────

if [ -n "$VERSION" ]; then
  REF="$VERSION"
else
  REF="$BRANCH"
fi

# Resolve mode source
RESOLVED=$(_resolve_mode "$MODE")
RESOLVE_TYPE="${RESOLVED%%:*}"
RESOLVE_PATH="${RESOLVED#*:}"

if [[ "$RESOLVE_TYPE" == "local" ]]; then
  echo "Using local profile: $MODE"
  echo "Source: $RESOLVE_PATH"
  cp "$RESOLVE_PATH" "$TARGET_FILE"
  echo "$MODE@local" > "$MODE_FILE"
  echo ""
  echo "========================================"
  echo " Active Claude Mode: $MODE"
  echo " Source: local"
  echo " CLAUDE.md updated successfully"
  echo "========================================"
  echo ""
  exit 0
fi

if [[ "$RESOLVE_TYPE" == "plugin" ]]; then
  echo "Using cached plugin profile: $MODE"
  echo "Source: $RESOLVE_PATH"
  cp "$RESOLVE_PATH" "$TARGET_FILE"
  echo "$MODE@plugin" > "$MODE_FILE"
  echo ""
  echo "========================================"
  echo " Active Claude Mode: $MODE"
  echo " Source: plugin cache"
  echo " CLAUDE.md updated successfully"
  echo "========================================"
  echo ""
  exit 0
fi

# Remote core profile (existing behavior)
PROFILE_URL="https://raw.githubusercontent.com/$REPO/$REF/profiles/$MODE.md"

echo "Fetching profile: $MODE"
echo "Source: $PROFILE_URL"

curl -fsSL "$PROFILE_URL" -o "$TARGET_FILE" || {
  echo "Error: Failed to fetch profile '$MODE' (ref: $REF)"
  echo "Check that the profile name is valid and the version tag exists."
  exit 1
}

echo "$MODE@$REF" > "$MODE_FILE"

echo ""
echo "========================================"
echo " Active Claude Mode: $MODE"
echo " Version/Ref: $REF"
echo " CLAUDE.md updated successfully"
echo "========================================"
echo ""
