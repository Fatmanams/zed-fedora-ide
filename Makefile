SHELL := /bin/bash
.DEFAULT_GOAL := list

.PHONY: setup dry-run verify restore lint list test

setup:
	./install.sh

dry-run:
	./install.sh --dry-run

verify:
	./scripts/verify.sh

restore:
	./install.sh --restore

lint:
	@status=0; \
	files=$$(find . -path ./.git -prune -o -path ./logs -prune -o -path ./backups -prune -o -type f \( -name '*.sh' -o -name '*.sh.example' \) -print | sort); \
	for file in $$files; do \
		printf 'bash -n %s\n' "$$file"; \
		bash -n "$$file" || status=1; \
	done; \
	if command -v shellcheck >/dev/null 2>&1; then \
		printf 'shellcheck %s\n' "$$files"; \
		shellcheck $$files || status=1; \
	else \
		printf 'shellcheck not installed; skipped (bash -n already ran)\n'; \
	fi; \
	exit $$status

list:
	./install.sh --list

test:
	python3 config/templates/test/test_zed_config.py
