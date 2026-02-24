# claude-operator Makefile
# Repo: https://github.com/PsyChaos/claude-operator

MODE ?= elite
VERSION ?=
ENTERPRISE_CONFIG ?=

.PHONY: claude list current update install-global enterprise-config audit-log enterprise-status help

claude:
	@if [ -n "$(VERSION)" ]; then \
		./operator.sh $(MODE) $(VERSION); \
	else \
		./operator.sh $(MODE); \
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

help:
	@echo ""
	@echo "claude-operator commands:"
	@echo ""
	@echo "  make claude MODE=<profile> [VERSION=<tag>]"
	@echo "      → Activate profile (optionally pinned to tag)"
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
	@echo "  make enterprise-config [ENTERPRISE_CONFIG=/path/to/config]"
	@echo "      → Generate enterprise config template"
	@echo ""
	@echo "  make enterprise-status"
	@echo "      → Show current enterprise configuration"
	@echo ""
	@echo "  make audit-log"
	@echo "      → Display the audit log"
	@echo ""
	@echo "Examples:"
	@echo "  make claude MODE=elite"
	@echo "  make claude MODE=elite VERSION=v1.0.0"
	@echo "  bash install.sh --version v1.0.0          # pinned + checksum"
	@echo "  bash install.sh --global --version v1.0.0  # global + checksum"
	@echo "  bash install.sh --enterprise               # generate enterprise config"
	@echo ""
