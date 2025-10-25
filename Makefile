.POSIX:
SHELL = /bin/sh

SHELLSPEC = vendor/shellspec/shellspec

.PHONY: test
test: $(SHELLSPEC)
	$(SHELLSPEC)

$(SHELLSPEC):
	@printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
	@exit 1
