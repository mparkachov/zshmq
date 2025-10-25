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
		current=$$(tr -d '\r\n' < "$(VERSION_FILE)"); \
	else \
		current=0.0.0; \
	fi; \
	major=$${current%%.*}; \
	rest=$${current#*.}; \
	if [ "$$rest" = "$$current" ]; then \
		minor=0; patch=0; \
	else \
		minor=$${rest%%.*}; \
		patch_part=$${rest#*.}; \
		[ "$$patch_part" = "$$rest" ] && patch_part=0; \
		patch=$$patch_part; \
	fi; \
	major=$${major:-0}; minor=$${minor:-0}; patch=$${patch:-0}; \
	patch=$$((patch + 1)); \
	new_version="$$major.$$minor.$$patch"; \
	printf '%s\n' "$$new_version" > "$(VERSION_FILE)"; \
	printf 'Building release %s\n' "$$new_version" >&2; \
	tmp=$$(mktemp); \
	{ \
		printf '%s\n' '#!/usr/bin/env sh'; \
		printf 'ZSHMQ_EMBEDDED=1\n'; \
		printf 'ZSHMQ_VERSION=%s\n' "$$new_version"; \
		for vendor in vendor/getoptions/lib/getoptions_base.sh vendor/getoptions/lib/getoptions_abbr.sh vendor/getoptions/lib/getoptions_help.sh; do \
			printf '\n'; \
			sed '/^#!\/usr\/bin\/env sh/d' "$$vendor"; \
		done; \
		for lib in lib/command_helpers.sh lib/ctx_new.sh lib/ctx_destroy.sh; do \
			printf '\n'; \
			sed '/^#!\/usr\/bin\/env sh/d' "$$lib"; \
		done; \
		printf '\n'; \
		tail -n +2 "$(ZSHMQ_BIN)"; \
	} > "$$tmp"; \
	chmod +x "$$tmp"; \
	mv "$$tmp" "$(RELEASE_ARTIFACT)"; \
	chmod +x "$(RELEASE_ARTIFACT)"

$(SHELLSPEC):
	@printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
	@exit 1
