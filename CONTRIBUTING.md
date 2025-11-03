# Contributing

Thanks for helping improve Zero Shell Message Queue! This document captures the full developer workflow using the repository's POSIX shell scripts.

## Prerequisites
- POSIX-compliant shell (`/bin/sh` is assumed for automation).
- Git submodules initialised (handled by the bootstrap script).
- GitHub CLI (`gh`) authenticated when publishing releases.

## Workspace Setup
Run the bootstrap script once per clone (or whenever submodules need refreshing):

```sh
./scripts/bootstrap.sh
```

This initializes vendored dependencies (ShellSpec, getoptions) and ensures `tmp/` exists for runtime assets.

## Running Tests
Execute the full ShellSpec suite via the dedicated test runner:

```sh
./scripts/test.sh
```

Environment overrides:

- `SHELLSPEC_SHELL=/path/to/sh ./scripts/test.sh`
- `SHELLSPEC_FLAGS="--format progress --output junit --reportdir tmp/reports" ./scripts/test.sh`

When generating reports, create the target directory first (e.g., `mkdir -p tmp/reports`). CI expects the JUnit output at `tmp/reports/results_junit.xml`.

### Test Coverage

| Feature | Verification |
| --- | --- |
| Runtime lifecycle (`ctx new`, `ctx destroy`) | `spec/lib/ctx_spec.sh` |
| Topic asset management (`topic new`, `topic destroy`) | `spec/lib/topic_spec.sh` |
| Topic dispatcher lifecycle (`topic start`, `topic stop`) | `spec/lib/topic_dispatch_spec.sh` |
| Topic publishing (`topic send`) | `spec/lib/topic_send_spec.sh` |
| Bus provisioning and registry management (`bus new`, `bus start`, `bus stop`) | `spec/lib/bus_spec.sh` |

> **Notes**
> - Bus fan-out routing is under active repair; the end-to-end example in `spec/lib/bus_spec.sh` is temporarily skipped while the issue is investigated.
> - `topic sub` is an interactive streaming command and is validated manually to avoid hanging CI jobs.

## Building a Release Artifact
The release script assembles the self-contained `zshmq` binary using the version recorded in `VERSION`. Ensure the file contains a semantic version string before running:

```sh
./scripts/release.sh
```

This embeds the vendored libraries, updates the executable bit, and preserves the `VERSION` file.

## Publishing a Release
To bump the version, regenerate the bundled script, tag, and push to GitHub:

```sh
VERSION=1.2.3 ./scripts/publish.sh
```

The script updates `VERSION`, rebuilds the artifact, amends or creates a release commit, force-tags `v<version>`, pushes to `origin`, and creates a GitHub release that attaches the generated script. Authenticate `gh` beforehand.

## Manual Verification
- Smoke-test the CLI with `./bin/zshmq.sh <command> ...` before submitting changes.
- Use `tmp/` for runtime fixtures during development; never commit FIFOs or other generated assets.
- Prefer short-lived debugging logs (`-d/--debug`, `-t/--trace`) to keep default executions silent.

## Coding & Review Guidelines
- Every module in `lib/` needs a matching ShellSpec file under `spec/`.
- Follow the repository-wide style guide in `AGENTS.md` for headers, logging, and function naming.
- Keep commits scoped and use Conventional Commit prefixes (`feat:`, `fix:`, `chore:`).
