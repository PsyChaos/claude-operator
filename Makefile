# claude-operator Makefile
# Repo: https://github.com/PsyChaos/claude-operator

MODE ?= elite
VERSION ?=

.PHONY: claude list current update install-global help plugin-add plugin-list plugin-remove plugin-update

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
	@echo "Examples:"
	@echo "  make claude MODE=elite"
	@echo "  make claude MODE=elite VERSION=v1.0.0"
	@echo "  bash install.sh --version v1.0.0          # pinned + checksum"
	@echo "  bash install.sh --global --version v1.0.0  # global + checksum"
	@echo ""
