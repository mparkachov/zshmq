#!/usr/bin/env sh
# shellcheck shell=sh

# ctx_new bootstraps the runtime directory for zshmq.
# It creates the target directory (default: /tmp/zshmq) and ensures a state file exists.

ctx_new() {
	set -eu

	if ! command -v getoptions >/dev/null 2>&1; then
		if [ -z "${ZSHMQ_ROOT:-}" ]; then
			printf '%s\n' 'ctx_new: ZSHMQ_ROOT is not set' >&2
			return 1
		fi
		# Load getoptions library from the vendored dependency.
		# shellcheck disable=SC1090
		. "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
		# shellcheck disable=SC1090
		. "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
		# shellcheck disable=SC1090
		. "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
	fi

	parser_definition_ctx_new() {
		# Use getoptions DSL to define the parser.
		setup REST help:usage -- "Usage: ctx_new [options]" ''
		msg -- 'Options:'
		param CTX_PATH -p --path -- 'Target directory to initialise'
		disp :usage -h --help
	}

	# Generate and run the parser.
	eval "$(getoptions parser_definition_ctx_new parse_ctx_new)" || return 1
	parse_ctx_new "$@"
	eval "set -- $REST"

	if [ $# -gt 0 ]; then
		printf 'ctx_new: unexpected argument -- %s\n' "$1" >&2
		return 1
	fi

	target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

	if [ -z "$target" ]; then
		printf '%s\n' 'ctx_new: target path is empty' >&2
		return 1
	fi

	if [ ! -d "$target" ]; then
		mkdir -p "$target"
	fi

	state_file="${target%/}/state"
	if [ ! -f "$state_file" ]; then
		: > "$state_file"
	fi

	printf '%s\n' "$target"
}
