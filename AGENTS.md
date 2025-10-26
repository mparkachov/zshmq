# Repository Guidelines

## Project Structure & Module Organization
Keep the command-line entrypoint in the repository root during development, but ensure the release-ready binary lands in `bin/`. Place reusable logic in `lib/`, one function per file, e.g., `lib/start.sh` and `lib/publisher.sh`. Specs live under `spec/` following ShellSpec conventions (`spec/lib/start_spec.sh`). Temporary assets belong in `tmp/` and should be ignored by Git. Update `README.md` and `AGENT.md` whenever the public interface or build contract changes. Configure every tool dependency as a Git submodule and avoid assuming anything beyond a POSIX shell is installed on the system.

Do not hand-edit the bundled `./zshmq` release script. Always regenerate it with `make release` after curating `VERSION` so the embedded code stays in sync with `lib/`.

## Build, Test, and Development Commands
Expose every build, package, and test workflow through POSIX-compliant `make` targets (strictly POSIX make syntax - no GNU extensions). Provide at minimum `make build` to emit `bin/zshmq.sh` and `make test` to run the full ShellSpec suite; add focused targets or variables for module-level specs when useful. The underlying scripts may still live in `scripts/`, but users should be able to rely on `make` alone. Verify the CLI manually via `./bin/zshmq.sh <command> ...` before shipping a change.

`zshmq ctx_new` must bootstrap the runtime directory (default `/tmp/zshmq`) and rely on the vendored getoptions parser for command-line flags.

Provide `make bootstrap` to initialise submodules and the local `tmp/` workspace before running other targets.

## Coding Style & Naming Conventions
Author POSIX-compliant shell (`#!/usr/bin/env sh`). Prefer two-space indentation, guard against unbound variables (`set -eu`), and use `printf` over `echo` when formatting output. Keep documentation and code ASCII-only - avoid emojis or iconography. Name files and functions with snake_case (`dispatcher_loop`, `lib/subscriber.sh`) and mirror relevant ZeroMQ function names when behaviors align to ease cross-referencing. Keep functions pure where possible; side-effect helpers should end with `_cmd` to signal command usage. Document non-obvious logic with short inline comments.

Each command module must include a Javadoc-style header (`#/** ... */`) containing `@usage:`, `@summary:`, `@description:`, and `@option:` tags so the CLI `--help` aggregate remains accurate. Use the shared helpers (`zshmq_parser_defaults`, `zshmq_eval_parser`, `zshmq_print_command_help`) to attach the standard `-h/--help` parser and rendering so new modules only specify command-specific parameters.

## Testing Guidelines
Write a ShellSpec file for every module under `lib/`. Name contexts after the command or function (`Describe dispatcher_loop`). Use doubles and fixtures in `spec/support/` instead of touching `/tmp`. Add regression specs for bugs before fixing them. Aim to cover both happy paths and failure modes such as FIFO contention or missing environment variables.

## Commit & Pull Request Guidelines
Follow Conventional Commits (`feat:`, `fix:`, `chore:`) for easy changelog generation. Keep commits small and scoped to one concern. Pull requests should include a concise summary, testing note (`shellspec` output or manual steps), and a validation snippet demonstrating the CLI (`./bin/zshmq.sh send "ALERT: test"`). Reference related issues and add screenshots or transcripts when behavior is user-facing.

## Security & Environment Tips
Never commit actual FIFOs or files created in `/tmp`. Sanitize topic patterns received from users before interpolation. When testing locally, override `ZSHMQ_BUS` and `ZSHMQ_STATE` to point inside the repository (`export ZSHMQ_BUS=$PWD/tmp/bus`). Clean up stray FIFOs with `./bin/zshmq.sh stop` or manual `rm` to prevent resource leaks.
