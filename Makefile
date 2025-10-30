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
		printf '\n'; \
		sed '/^#!\/usr\/bin\/env sh/d' "lib/command_helpers.sh"; \
		printf '\n'; \
		sed '/^#!\/usr\/bin\/env sh/d' "lib/logging.sh"; \
		for lib in $$(cd lib && ls *.sh | sort); do \
			case "$$lib" in command_helpers.sh|logging.sh) continue ;; esac; \
			printf '\n'; \
			sed '/^#!\/usr\/bin\/env sh/d' "lib/$$lib"; \
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
		git tag "v$$version"; \
		printf 'Created tag v%s\n' "$$version" >&2; \
	fi; \
	printf 'Release artifact is available at %s\n' "$(RELEASE_ARTIFACT)" >&2

.PHONY: release-publish
release-publish:
	@if [ -z "$(VERSION)" ]; then \
		printf '%s\n' 'Usage: VERSION=<semver> make release-publish' >&2; \
		exit 1; \
	fi; \
	printf '%s\n' "$(VERSION)" > "$(VERSION_FILE)"; \
	printf 'Updated %s to %s\n' "$(VERSION_FILE)" "$(VERSION)" >&2; \
	if git diff --quiet -- "$(VERSION_FILE)"; then \
		: ; \
	else \
		git add "$(VERSION_FILE)"; \
		git commit -m "Release $(VERSION)"; \
	fi; \
	$(MAKE) release >/dev/null; \
	git add "$(RELEASE_ARTIFACT)"; \
	git commit --amend --no-edit >/dev/null 2>&1 || git commit -m "Release $(VERSION)"; \
	git add "$(RELEASE_ARTIFACT)" "$(VERSION_FILE)"; \
	g_version=$$(tr -d '\r\n' < "$(VERSION_FILE)"); \
	git tag -f "v$$g_version"; \
	git push origin HEAD; \
	git push origin --tags; \
	gh release create "v$$g_version" "$(RELEASE_ARTIFACT)" --title "v$$g_version" --notes "Release $$g_version" --latest >/dev/null

$(SHELLSPEC):
	@printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
	@exit 1
