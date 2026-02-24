# claude-operator

Runtime profile switching system for `CLAUDE.md`.

Production-safe, versioned, reproducible configuration management for Claude operating modes.

---

## Why?

Managing multiple Claude operating styles across projects can become inconsistent and error-prone.

You may want:

- **Senior Production mode** for infrastructure and stability-critical systems
- **High Autonomy mode** for rapid iteration and reduced clarification loops
- **Elite Hybrid mode** for production-grade autonomy with risk calibration

`claude-operator` allows deterministic switching between these modes across projects, with
conflict detection, backup/restore, GPG-verified releases, plugin registries, and enterprise
policy enforcement — all in pure Bash with no dependencies beyond `curl` and standard POSIX tools.

---

## Features

- Centralized profile management
- Deterministic mode switching
- Remote profile fetching (GitHub raw)
- Version pinning with SHA256 checksum verification
- **Strict checksum mode** — hard fail if no sha256 tool is available (`--strict-checksum`)
- **Atomic profile writes** — temp file + `mv`, no partial writes to `CLAUDE.md`
- **Conflict detection** — detects pre-existing `CLAUDE.md` before overwriting; offers backup, merge, force, or abort
- **Backup & restore** — timestamped backups in `.claude_backup/`, smart restore with sentinel awareness
- **Merge mode** — append profile below existing content using sentinel markers; idempotent re-apply
- **GPG signed releases** — all release assets signed by CI bot key (`--verify-sig`)
- **Trust key management** — `trust-key` command imports the public key automatically
- **Plugin architecture** — add any GitHub repo as a profile registry
- **Local profile override** — `./claude-operator-plugins/` takes precedence over everything
- **Enterprise mode** — policy enforcement, audit logging, offline cache, custom registry
- **Global CLI binary** (`claude-operator` on your PATH)
- **Self-update command** (`./operator.sh update`)
- Makefile integration
- Semantic Versioning (SemVer)
- CI-friendly

---

## Repository Structure

```
claude-operator/
├── profiles/
│   ├── senior-production.md
│   ├── high-autonomy.md
│   └── elite.md
├── operator.sh
├── install.sh
├── Makefile
├── claude-operator.gpg.pub
└── .github/workflows/release.yaml
```

---

## Installation

### One-line install (latest, no checksum)

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh | bash
```

### Pinned install with checksum verification (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0
```

Downloads `operator.sh` from the GitHub Release and verifies its SHA256 checksum before installing.

### Pinned install with GPG signature verification

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0 --verify-sig
```

Verifies both the SHA256 checksum and the GPG detached signature before writing anything to disk.

### Global install (adds `claude-operator` to your PATH)

```bash
# Latest
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --global

# Pinned + verified (recommended)
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --global --version v1.0.0 --verify-sig
```

Installs to `~/.local/bin/claude-operator`. If `~/.local/bin` is not in your `$PATH`, the
installer will print the line to add to your shell profile.

### Enterprise install

```bash
curl -fsSL https://raw.githubusercontent.com/PsyChaos/claude-operator/master/install.sh \
  | bash -s -- --version v1.0.0 --enterprise
```

Installs the binary and generates a commented enterprise configuration template at
`~/.config/claude-operator/enterprise.conf`.

### Install flags

```
bash install.sh [--version v1.2.3] [--global] [--strict-checksum] [--verify-sig] [--enterprise] [--enterprise-config /path]
```

| Flag | Description |
|------|-------------|
| `--version v1.0.0` | Pin to a release and verify SHA256 checksum |
| `--global` | Install to `~/.local/bin` for global PATH access |
| `--strict-checksum` / `-s` | Abort if no sha256 tool is available (instead of warning) |
| `--verify-sig` / `-S` | Verify GPG signature of downloaded files (requires `gpg`) |
| `--enterprise` / `-e` | Generate enterprise configuration template |
| `--enterprise-config <path>` | Write enterprise config template to a custom path |

---

## Usage

### Switch profile

```bash
make claude MODE=elite
./operator.sh elite
claude-operator elite          # after global install
```

### Switch profile (pinned to a specific release)

```bash
make claude MODE=elite VERSION=v1.0.0
./operator.sh elite v1.0.0
```

Versioned fetches verify the profile's SHA256 checksum against the sidecar published in the
GitHub Release.

### Runtime flags

```
./operator.sh [--strict-checksum] [--verify-sig] [--force|--backup|--merge] <mode> [version]
```

| Flag | Description |
|------|-------------|
| `--strict-checksum` | Hard fail if no sha256 tool found (env: `OPERATOR_STRICT_CHECKSUM=true`) |
| `--verify-sig` | Verify GPG signature of the downloaded profile (env: `OPERATOR_VERIFY_SIG=true`) |
| `--force` | Overwrite `CLAUDE.md` without prompting |
| `--backup` | Backup existing `CLAUDE.md` then overwrite (non-interactive) |
| `--merge` | Append profile below existing content using sentinels (preserves project content) |

### List available profiles

```bash
make list
./operator.sh plugin list      # includes plugin + local profiles
```

### Show current mode

```bash
make current
```

### Self-update to latest release

```bash
./operator.sh update
make update
claude-operator update         # after global install
```

Queries the GitHub Releases API, compares the current version, downloads the new binary,
verifies its SHA256 checksum (and GPG signature if `--verify-sig` is set), and atomically
replaces itself. No manual steps required.

---

## Conflict Detection

When you apply a profile and `CLAUDE.md` already exists, `claude-operator` detects whether it
is managed by the operator or contains your own project content.

### How managed status is determined

A `CLAUDE.md` is considered **operator-managed** if either:

1. It contains a sentinel header: `<!-- claude-operator:begin ... -->`
2. A `.claude_mode` state file exists in the same directory

If neither condition is met, the file is treated as **unmanaged** (your project's own content)
and conflict resolution is triggered.

### Conflict resolution modes

| Mode | Flag | Env var value | Behavior |
|------|------|---------------|----------|
| `prompt` | _(default)_ | `prompt` | Interactive prompt with 10s timeout; defaults to backup |
| `backup` | `--backup` | `backup` | Backup to `.claude_backup/`, then overwrite |
| `merge` | `--merge` | `merge` | Append profile below existing content using sentinels |
| `force` | `--force` | `force` | Overwrite without saving backup |
| _(abort)_ | — | — | Choose `[a]` at the prompt to cancel |

Set the default non-interactively via the environment variable:

```bash
CLAUDE_OPERATOR_CONFLICT=backup ./operator.sh elite v1.0.0
CLAUDE_OPERATOR_CONFLICT=merge  ./operator.sh elite
CLAUDE_OPERATOR_CONFLICT=force  ./operator.sh elite
```

Or via Makefile:

```bash
make claude MODE=elite CONFLICT=backup
make claude MODE=elite CONFLICT=merge
make claude MODE=elite CONFLICT=force
```

### Interactive prompt

When conflict mode is `prompt` (the default), you will see:

```
CLAUDE.md already exists and is not managed by claude-operator.
How should this be handled?
  [b] Backup & overwrite  — save to .claude_backup/, apply profile  (default)
  [m] Merge               — append operator section below your content
  [o] Overwrite (force)   — discard existing content
  [a] Abort               — do nothing, exit
Choice [b/m/o/a] (10s timeout, default=b):
```

After 10 seconds with no input, `backup` is applied automatically.

### Merge mode and sentinels

In merge mode, the operator section is delimited by sentinel comments:

```
<!-- claude-operator:begin elite@v1.0.0 -->
... operator profile content ...
<!-- claude-operator:end -->
```

- If `CLAUDE.md` has no sentinel yet, the operator section is appended below existing content.
- If a sentinel already exists, it is replaced in-place — the surrounding project content is preserved.
- Re-applying the same profile is fully idempotent.

The `.claude_mode` file records the write mode used:

```
elite@v1.0.0:merge
```

Format: `<mode>@<ref>:<write_mode>` where `write_mode` is one of `overwrite`, `backup`, `merge`.

### Backups

Backups are written to `.claude_backup/CLAUDE.md.<timestamp>` and are automatically added to
`.gitignore` on first use. A maximum of 5 backups are kept; the oldest are rotated out.

```bash
# List all backups
./operator.sh restore --list
make restore-list

# Restore latest backup or remove sentinel (smart restore)
./operator.sh restore
make restore

# Restore a specific backup by timestamp
./operator.sh restore 20260224T103000
```

The `restore` command is context-aware:

- If `write_mode` was `merge` and no backup exists → removes the sentinel section, preserving project content
- If `write_mode` was `backup` and no sentinel exists → restores from the backup file
- If both are available → prompts you to choose between sentinel removal or backup restore

---

## Plugin Architecture

Any GitHub repository that contains a `profiles/` directory with `.md` files can be used as a
plugin registry.

### Profile resolution order

1. `./claude-operator-plugins/<mode>.md` — project-local (no network)
2. `~/.config/claude-operator/plugins/<registry>/<mode>.md` — cached plugin profiles
3. `https://raw.githubusercontent.com/PsyChaos/claude-operator/...` — core remote profiles

### Add a plugin registry

```bash
./operator.sh plugin add myorg/my-profiles
./operator.sh plugin add myorg/my-profiles v1.0.0   # pinned + checksum verified

make plugin-add REGISTRY=myorg/my-profiles
make plugin-add REGISTRY=myorg/my-profiles VERSION=v1.0.0
```

### List all available profiles (core + plugins + local)

```bash
./operator.sh plugin list
make plugin-list
```

```
Core profiles (PsyChaos/claude-operator):
  elite
  high-autonomy
  senior-production

Plugin: myorg/my-profiles
  fast
  careful

Local (./claude-operator-plugins/):
  custom-mode
```

### Remove a plugin registry

```bash
./operator.sh plugin remove myorg/my-profiles
make plugin-remove REGISTRY=myorg/my-profiles
```

### Update plugin profiles

```bash
./operator.sh plugin update                    # update all
./operator.sh plugin update myorg/my-profiles  # update specific

make plugin-update
make plugin-update REGISTRY=myorg/my-profiles
```

### Local profile override

Place `.md` files in `./claude-operator-plugins/` in your project directory. These take
precedence over plugin cache and core remote profiles — no network required.

```bash
mkdir -p claude-operator-plugins
cp my-custom-mode.md claude-operator-plugins/
./operator.sh my-custom-mode   # uses local file, no network call
```

### Plugin manifest (optional)

Plugin repos can include a `plugin.json` at their root to provide metadata:

```json
{
  "name": "my-profiles",
  "description": "Custom Claude profiles for my team",
  "profiles": ["fast", "careful", "debug"]
}
```

Plugin cache is stored at `~/.config/claude-operator/plugins/`.  
Registry list is stored at `~/.config/claude-operator/registries.conf`.

---

## Remote Profile Source

Profiles are fetched from:

```
https://raw.githubusercontent.com/PsyChaos/claude-operator/<ref>/profiles/
```

When a `VERSION` is supplied, profiles are fetched from that release tag's ref, ensuring the
profile content matches exactly what was shipped with that version. A SHA256 sidecar checksum
is also fetched and verified.

---

## Security

### Checksum verification

Release assets (`operator.sh`, `install.sh`, `profiles/*.md`) are accompanied by SHA256
checksum sidecar files generated by CI and attached to every GitHub Release.

When installing with `--version`, checksums are fetched and verified before any file is written
to disk. A mismatch aborts the install and removes all temporary files.

Profile downloads are also written to a temp file first and atomically moved to `CLAUDE.md`
only after verification passes — no partial writes.

Use `--strict-checksum` to treat a missing sha256 tool as a hard error instead of a warning.

### GPG signature verification

Every release asset is signed with a GPG detached signature (`.sig` file) by the CI bot key.
The public key is distributed at `claude-operator.gpg.pub` in this repository.

To trust the key and verify future downloads:

```bash
# Import the public key
./operator.sh trust-key

# Then verify on any subsequent operation
./operator.sh --verify-sig elite v1.0.0
./operator.sh --verify-sig update
```

The `trust-key` command downloads the public key from the repository and imports it into your
local GPG keyring.

**Key details:**
- **UID:** `Claude Operator <psychaos@gmail.com>`
- **Key file:** `claude-operator.gpg.pub` (repo root)
- **Config path:** `~/.config/claude-operator/claude-operator.gpg.pub`

### Supply-chain recommendations

Pinned installs with signature verification are strongly recommended for:

- Team environments where reproducibility matters
- CI/CD pipelines that pull `operator.sh` as a dependency
- Any environment where supply-chain integrity is a concern
- Enterprise environments (see Enterprise Mode below)

---

## Enterprise Mode

Enterprise mode enables policy enforcement, audit logging, and air-gapped operation.

### Generate config template

```bash
bash install.sh --enterprise
make enterprise-config

# Custom path
bash install.sh --enterprise --enterprise-config /etc/claude-operator/enterprise.conf
make enterprise-config ENTERPRISE_CONFIG=/etc/claude-operator/enterprise.conf
```

Writes a fully-commented template to `~/.config/claude-operator/enterprise.conf`.

### Configuration

The config file is shell-sourceable (`KEY=value` syntax). Config is loaded in priority order:

1. `/etc/claude-operator/enterprise.conf` (system-wide)
2. `~/.config/claude-operator/enterprise.conf` (user-level)
3. `CO_*` environment variables (highest priority, useful for CI)

```bash
# Enable enterprise mode (activates all policies below)
ENTERPRISE_MODE=true

# Whitelist of allowed profiles (space-separated). Empty = all allowed.
ALLOWED_PROFILES="elite senior-production"

# Require version pinning — reject: ./operator.sh elite (without a version tag)
REQUIRE_VERSION_PIN=true

# Hard fail if no sha256 tool found
REQUIRE_CHECKSUM=true

# Require GPG signature verification on all downloads
REQUIRE_SIGNATURE=true

# Audit log (append-only, ISO8601 timestamps)
AUDIT_LOG=/var/log/claude-operator.log

# Custom internal profile registry (replaces GitHub)
# Must serve profiles at: <URL>/profiles/<mode>.md
PROFILE_REGISTRY_URL=https://internal.corp/claude-profiles

# Block self-updates (require manual intervention)
UPDATE_POLICY=manual

# Offline mode — serve from local cache only, no network
OFFLINE_MODE=false
```

### Inspect active configuration

```bash
./operator.sh enterprise-status
make enterprise-status
```

### Audit log

When `AUDIT_LOG` is set, every operation is logged with ISO8601 timestamps:

```
[2026-02-24T10:30:00Z] user=alice mode=elite version=v1.0.0 outcome=success
[2026-02-24T10:31:05Z] user=bob mode=fast version=unset outcome=failed message=version_pin_required
```

```bash
make audit-log
```

### Local profile cache

Profiles are cached at `~/.config/claude-operator/cache/<mode>@<ref>.md` after every
successful fetch. With `OFFLINE_MODE=true`, profiles are served from cache and no network
requests are made.

### Environment variable overrides

All enterprise policies can be set via environment variables:

| Variable | Example value |
|---|---|
| `CO_ENTERPRISE_MODE` | `true` |
| `CO_ALLOWED_PROFILES` | `"elite senior-production"` |
| `CO_REQUIRE_VERSION_PIN` | `true` |
| `CO_REQUIRE_CHECKSUM` | `true` |
| `CO_REQUIRE_SIGNATURE` | `true` |
| `CO_AUDIT_LOG` | `/var/log/claude-operator.log` |
| `CO_PROFILE_REGISTRY_URL` | `https://internal.corp/claude-profiles` |
| `CO_UPDATE_POLICY` | `manual` |
| `CO_OFFLINE_MODE` | `true` |

---

## Versioning

This project follows **Semantic Versioning**.

```
vMAJOR.MINOR.PATCH
```

| Bump | Reason |
|------|--------|
| MAJOR | Breaking behavioral change |
| MINOR | New profile or feature |
| PATCH | Fixes / documentation updates |

Initial release: `v1.0.0`

---

## Full Reference

### Commands

| Command | Description |
|---------|-------------|
| `./operator.sh <mode> [version]` | Apply a profile (with optional version pin) |
| `./operator.sh restore [--list] [timestamp]` | Restore previous `CLAUDE.md` or remove sentinel |
| `./operator.sh update` | Self-update to latest release |
| `./operator.sh trust-key` | Import the CI bot GPG public key |
| `./operator.sh plugin add <org/repo> [ver]` | Add a plugin registry |
| `./operator.sh plugin list` | List all available profiles |
| `./operator.sh plugin remove <org/repo>` | Remove a plugin registry |
| `./operator.sh plugin update [org/repo]` | Update cached plugin profiles |
| `./operator.sh enterprise-status` | Show active enterprise configuration |

### Makefile targets

| Target | Description |
|--------|-------------|
| `make claude MODE=<profile>` | Apply a profile |
| `make claude MODE=<profile> VERSION=v1.0.0` | Apply pinned profile with checksum |
| `make claude MODE=<profile> CONFLICT=backup\|merge\|force` | Apply with explicit conflict mode |
| `make list` | List core profiles |
| `make current` | Show current mode |
| `make update` | Self-update |
| `make restore` | Smart restore (sentinel remove or backup load) |
| `make restore-list` | List all available backups |
| `make plugin-add REGISTRY=org/repo [VERSION=v1.0.0]` | Add plugin registry |
| `make plugin-list` | List all profiles (core + plugins + local) |
| `make plugin-remove REGISTRY=org/repo` | Remove plugin registry |
| `make plugin-update [REGISTRY=org/repo]` | Update plugin profiles |
| `make enterprise-config [ENTERPRISE_CONFIG=/path]` | Generate enterprise config template |
| `make enterprise-status` | Show active enterprise configuration |
| `make audit-log` | Tail the audit log |

### Key paths

| Path | Purpose |
|------|---------|
| `./.claude_mode` | State file: records current mode, version, and write mode |
| `./.claude_backup/` | Timestamped backups of previous `CLAUDE.md` files |
| `./claude-operator-plugins/` | Project-local profile overrides (highest priority) |
| `~/.local/bin/claude-operator` | Global binary (after `--global` install) |
| `~/.config/claude-operator/enterprise.conf` | User-level enterprise configuration |
| `/etc/claude-operator/enterprise.conf` | System-wide enterprise configuration |
| `~/.config/claude-operator/plugins/` | Cached plugin profiles |
| `~/.config/claude-operator/registries.conf` | List of registered plugin registries |
| `~/.config/claude-operator/cache/` | Profile cache for offline mode |
| `~/.config/claude-operator/claude-operator.gpg.pub` | Imported CI bot public key |

### .gitignore entries added automatically

```
.claude_backup/
```

Added to your project's `.gitignore` on first backup. Operator state files (`.claude_mode`)
are not ignored by default — committing them lets teams share the current mode.

---

## Philosophy

Claude configuration is infrastructure.

It should be:

- Versioned
- Explicit
- Reproducible
- Intentional

---

## Contributing

If adding a new profile:

- Keep structural consistency
- Document behavioral philosophy clearly
- Update README
- Bump MINOR version

If adding a new feature:

- Keep it dependency-free (bash + curl + standard POSIX tools only)
- Add corresponding Makefile target
- Update the install flags table and usage sections in README

---

## License

MIT

---

## Author

PsyChaos
