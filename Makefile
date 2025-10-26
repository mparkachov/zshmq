.POSIX:
SHELL = /bin/sh

SHELLSPEC = vendor/shellspec/shellspec
SHELLSPEC_FLAGS ?=
SHELLSPEC_SHELL ?= /bin/sh
ZSHMQ_BIN = bin/zshmq.sh
VERSION_FILE = VERSION
RELEASE_ARTIFACT = zshmq

.PHONY: bootstrap
bootstrap:
	@git submodule update --init --recursive
	@mkdir -p tmp

.PHONY: test
test: bootstrap $(SHELLSPEC)
	$(SHELLSPEC) --shell "$(SHELLSPEC_SHELL)" $(SHELLSPEC_FLAGS)

.PHONY: release
release: bootstrap $(ZSHMQ_BIN)
	@if [ -f "$(VERSION_FILE)" ]; then \
		version=$$(tr -d '\r\n' < "$(VERSION_FILE)"); \
	else \
		version=0.0.0; \
	fi; \
	if [ -z "$$version" ]; then \
		printf '%s\n' 'VERSION file is empty; set a semantic version before releasing.' >&2; \
		exit 1; \
	fi; \
	printf 'Building release %s\n' "$$version" >&2; \
	tmp=$$(mktemp); \
	{ \
		printf '%s\n' '#!/usr/bin/env sh'; \
		printf 'ZSHMQ_EMBEDDED=1\n'; \
		printf 'ZSHMQ_VERSION=%s\n' "$$version"; \
		for vendor in vendor/getoptions/lib/getoptions_base.sh vendor/getoptions/lib/getoptions_abbr.sh vendor/getoptions/lib/getoptions_help.sh; do \
			printf '\n'; \
			sed '/^#!\/usr\/bin\/env sh/d' "$$vendor"; \
		done; \
		for lib in lib/command_helpers.sh lib/logging.sh lib/ctx_new.sh lib/ctx_destroy.sh lib/start.sh lib/stop.sh lib/send.sh; do \
			printf '\n'; \
			sed '/^#!\/usr\/bin\/env sh/d' "$$lib"; \
		done; \
		printf '\n'; \
		tail -n +2 "$(ZSHMQ_BIN)"; \
	} > "$$tmp"; \
	chmod +x "$$tmp"; \
	mv "$$tmp" "$(RELEASE_ARTIFACT)"; \
	chmod +x "$(RELEASE_ARTIFACT)"; \
	if git rev-parse "v$$version" >/dev/null 2>&1; then \
		printf 'Tag v%s already exists; skipping tag creation.\n' "$$version" >&2; \
	else \
		echo git tag "v$$version"; \
		printf 'Created tag v%s\n' "$$version" >&2; \
	fi

$(SHELLSPEC):
	@printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
	@exit 1
