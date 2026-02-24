# claude-operator Makefile
# Repo: https://github.com/PsyChaos/claude-operator

MODE ?= elite
VERSION ?=
ENTERPRISE_CONFIG ?=
CONFLICT ?=

.PHONY: claude list current update install-global restore restore-list help plugin-add plugin-list plugin-remove plugin-update enterprise-config audit-log enterprise-status

claude:
	@if [ -n "$(Mode)" ] || [ -n "$(mode)" ]; then \
		echo "Error: Use uppercase MODE=, not Mode= or mode="; \
		echo "  make claude MODE=$(or $(Mode),$(mode))"; \
		exit 1; \
	fi
	@flags=""; \
	[ "$(CONFLICT)" = "merge" ]  && flags="--merge"; \
	[ "$(CONFLICT)" = "force" ]  && flags="--force"; \
	[ "$(CONFLICT)" = "backup" ] && flags="--backup"; \
	if [ -n "$(VERSION)" ]; then \
		./operator.sh $$flags $(MODE) $(VERSION); \
	else \
		./operator.sh $$flags $(MODE); \
	fi

list:
	@echo "Available profiles:"
	@if [ -d profiles ]; then \
		ls profiles/*.md 2>/dev/null | sed 's|profiles/||;s|\.md||' | sed 's/^/  /'; \
	else \
		echo "  senior-production"; \
		echo "  high-autonomy"; \
		echo "  elite"; \
	fi

current:
	@if [ -f .claude_mode ]; then \
		echo "Current mode: $$(cat .claude_mode)"; \
	else \
		echo "No active mode set."; \
	fi

update:
	@./operator.sh update

install-global:
	@bash install.sh --global

REGISTRY ?=

plugin-add:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Usage: make plugin-add REGISTRY=owner/repo [VERSION=vX.Y.Z]"; \
		exit 1; \
	fi
	@if [ -n "$(VERSION)" ]; then \
		./operator.sh plugin add $(REGISTRY) $(VERSION); \
	else \
		./operator.sh plugin add $(REGISTRY); \
	fi

plugin-list:
	@./operator.sh plugin list

plugin-remove:
	@if [ -z "$(REGISTRY)" ]; then \
		echo "Usage: make plugin-remove REGISTRY=owner/repo"; \
		exit 1; \
	fi
	@./operator.sh plugin remove $(REGISTRY)

plugin-update:
	@if [ -n "$(REGISTRY)" ]; then \
		./operator.sh plugin update $(REGISTRY); \
	else \
		./operator.sh plugin update; \
	fi

enterprise-config:
	@if [ -n "$(ENTERPRISE_CONFIG)" ]; then \
		bash install.sh --enterprise --enterprise-config "$(ENTERPRISE_CONFIG)"; \
	else \
		bash install.sh --enterprise; \
	fi

audit-log:
	@if [ -f "$${AUDIT_LOG:-/var/log/claude-operator.log}" ]; then \
		cat "$${AUDIT_LOG:-/var/log/claude-operator.log}"; \
	elif [ -f "$$HOME/.config/claude-operator/audit.log" ]; then \
		cat "$$HOME/.config/claude-operator/audit.log"; \
	else \
		echo "No audit log found."; \
		echo "Set AUDIT_LOG in your enterprise.conf to enable audit logging."; \
	fi

enterprise-status:
	@./operator.sh enterprise-status

restore:
	@./operator.sh restore

restore-list:
	@./operator.sh restore --list

help:
	@echo ""
	@echo "claude-operator commands:"
	@echo ""
	@echo "  make claude MODE=<profile> [VERSION=<tag>] [CONFLICT=merge|backup|force]"
	@echo "      → Activate profile (optionally pinned to tag)"
	@echo "        CONFLICT=merge   keep project content, append profile below"
	@echo "        CONFLICT=backup  backup existing CLAUDE.md then overwrite"
	@echo "        CONFLICT=force   overwrite without prompting"
	@echo ""
	@echo "  make list"
	@echo "      → Show available profiles"
	@echo ""
	@echo "  make current"
	@echo "      → Show active profile"
	@echo ""
	@echo "  make update"
	@echo "      → Self-update operator.sh to latest release"
	@echo ""
	@echo "  make install-global"
	@echo "      → Install claude-operator to ~/.local/bin (global PATH access)"
	@echo ""
	@echo "  make plugin-add REGISTRY=owner/repo [VERSION=vX.Y.Z]"
	@echo "      → Add a plugin registry (GitHub repo with profiles/)"
	@echo ""
	@echo "  make plugin-list"
	@echo "      → List all available profiles (core + plugins + local)"
	@echo ""
	@echo "  make plugin-remove REGISTRY=owner/repo"
	@echo "      → Remove a plugin registry"
	@echo ""
	@echo "  make plugin-update [REGISTRY=owner/repo]"
	@echo "      → Update plugin profiles (all or specific registry)"
	@echo ""
	@echo "  make enterprise-config [ENTERPRISE_CONFIG=/path/to/config]"
	@echo "      → Generate enterprise config template"
	@echo ""
	@echo "  make enterprise-status"
	@echo "      → Show current enterprise configuration"
	@echo ""
	@echo "  make audit-log"
	@echo "      → Display the audit log"
	@echo ""
	@echo "  make restore"
	@echo "      → Restore CLAUDE.md (remove sentinel or load last backup)"
	@echo ""
	@echo "  make restore-list"
	@echo "      → List available backups"
	@echo ""
	@echo "Examples:"
	@echo "  make claude MODE=elite"
	@echo "  make claude MODE=elite VERSION=v1.0.0"
	@echo "  bash install.sh --version v1.0.0          # pinned + checksum"
	@echo "  bash install.sh --global --version v1.0.0  # global + checksum"
	@echo "  bash install.sh --enterprise               # generate enterprise config"
	@echo ""
