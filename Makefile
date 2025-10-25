.POSIX:
SHELL = /bin/sh

SHELLSPEC = vendor/shellspec/shellspec
SHELLSPEC_FLAGS ?=
SHELLSPEC_SHELL ?= /bin/sh

.PHONY: bootstrap
bootstrap:
	@git submodule update --init --recursive
	@mkdir -p tmp

.PHONY: test
test: bootstrap $(SHELLSPEC)
	$(SHELLSPEC) --shell "$(SHELLSPEC_SHELL)" $(SHELLSPEC_FLAGS)

$(SHELLSPEC):
	@printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
	@exit 1
