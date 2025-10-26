# Zero Shell Message Queue (zshmq)

**Zero Shell Message Queue (zshmq)** is a lightweight, [ZeroMQ](https://zeromq.org/)-inspired **message bus for POSIX shells**.
It provides a simple **publish/subscribe** mechanism using only **FIFOs (named pipes)** - no sockets, daemons, or dependencies.

> Think of it as *ZeroMQ for the Unix shell* - pure inter-process messaging built entirely with standard POSIX tools.

---

## Overview

- **Pure POSIX:** Works anywhere `sh`, `mkfifo`, and `read` exist.
- **Publish/Subscribe:** Multiple publishers and dynamic subscribers.
- **Zero dependencies:** Uses only core Unix utilities.
- **Efficient:** Blocking FIFO I/O -> near-zero CPU when idle.
- **ZeroMQ-like CLI:** Familiar commands (`send`, `sub`, `start`, etc.).
- **Tiny:** A single portable shell script.

---

## Motivation

ZeroMQ is great - but sometimes you just need **inter-process messaging** between shell scripts, without compiling or linking anything.

`zshmq` brings the same conceptual model - **topics**, **publishers**, and **subscribers** - into pure shell territory.

It's perfect for:
- Event-driven shell workflows  
- Lightweight coordination between processes  
- Teaching message-passing fundamentals  

---

## Requirements

| Component | Requirement |
|------------|-------------|
| Shell | POSIX-compliant (`bash`, `dash`, `zsh`, `ksh`, etc.) |
| Tools | Core POSIX utilities (`mkfifo`, `grep`, `cat`, `awk`, `read`, `kill`, `rm`) bundled with your shell environment; any extras ship as Git submodules |
| OS | Linux, macOS, BSD - any Unix with FIFOs |

---

## Architecture

```mermaid
graph LR
    P1[Publisher 1] --> B[( /tmp/zshmq/bus )]
    P2[Publisher 2] --> B
    B --> D[Dispatcher]
    D --> S1[Subscriber A - Pattern: ^ALERT]
    D --> S2[Subscriber B - Pattern: ^INFO]
```

- Publishers write messages into /tmp/zshmq/bus.
- The Dispatcher reads messages and routes them to subscribers whose patterns match.
- Each Subscriber owns its own FIFO (e.g. /tmp/zshmq/sub.<pid>).

## Installation

Clone and install manually:
```bash
git clone https://github.com/mparkachov/zshmq.git
cd zshmq
make release
sudo cp ./zshmq /usr/local/bin/zshmq
```

Or run locally:
```bash
zshmq <command> ...
```

## Development Guidelines

- Initialize tool dependencies with `git submodule update --init --recursive`; every non-shell helper ships as a Git submodule.
- Assume only a POSIX shell exists on the host; vendor any additional tooling through submodules.
- Name new functions after their ZeroMQ counterparts (or close equivalents) to signal behavioral parity.

## Testing

Bootstrap vendored tooling and scaffolding:
```sh
make bootstrap
```

Run the ShellSpec suite:
```sh
make test
```
By default the suite executes with `/bin/sh`. Override via `make test SHELLSPEC_SHELL=path/to/shell`.

Generate a JUnit report (ensure `tmp/reports` exists first):
```sh
mkdir -p tmp/reports
make test SHELLSPEC_FLAGS="--format progress --output junit --reportdir tmp/reports"
```
The report will be written to `tmp/reports/results_junit.xml` and published automatically by CI.

Build a release artifact using the version recorded in `VERSION` (update the file manually when bumping releases):
```sh
make release
```
This creates a self-contained `zshmq` that embeds all library code without modifying `VERSION`.

### Supported Make Targets
- `make bootstrap`
- `make test`
- `make release`

## Usage
### Step 0: Bootstrap the runtime directory
```sh
zshmq ctx_new
```
Creates `/tmp/zshmq` (or the directory specified with `--path` / `$ZSHMQ_CTX_ROOT`), recreates the main FIFO bus, and truncates the subscription state so every session starts from a clean slate. Re-run this command whenever you need to reset the environment.

List available commands (each supports `-h/--help` plus `-d/--debug` and `-t/--trace` for logging control):
```sh
zshmq --help
```

Show command-specific usage:
```sh
zshmq help ctx_new
```

### Step 1: Start Dispatcher
```bash
zshmq start
```
Runs the router that listens for messages and subscription updates. This command expects `zshmq ctx_new` to have prepared the runtime directory first and will exit with an error if the context is missing.
Pass `--foreground` (or `-f`) to keep the dispatcher attached to the current terminal; press `Ctrl+C` to stop it and clean up the PID file.

### Step 2: Subscribe to a Topic
```bash
zshmq sub '^ALERT'
```
Creates /tmp/zshmq/sub.<pid> and prints matching messages:

Subscribed to '^ALERT'
ALERT: CPU overload

### Step 3: Publish Messages
```bash
zshmq send "ALERT: CPU overload"
zshmq send "INFO: Cooling active"
```
Messages are routed to subscribers with matching filters.
`send` infers the topic from the text before the first colon (`ALERT` or `INFO` above); pass `--topic <name>` to override the inference when your payload lacks a colon.

### Step 4: List Active Subscribers
```bash
zshmq list
```
Example output:

PID     FIFO                   PATTERN
2314    /tmp/zshmq/sub.2314    ^ALERT
2318    /tmp/zshmq/sub.2318    ^INFO

### Step 5: Unsubscribe
```bash
zshmq unsub
```
Removes your FIFO and deregisters from the dispatcher.

### Step 6: Stop Dispatcher
```bash
zshmq stop
```
Gracefully terminates the router and cleans up /tmp/zshmq/bus.

### Step 7: Destroy Runtime (optional)
```bash
zshmq ctx_destroy
```
Removes `/tmp/zshmq` (or the directory specified with `--path` / `$ZSHMQ_CTX_ROOT`) when you are done testing.

### Command Reference
Command	Description
zshmq ctx_destroy	Remove the runtime directory (default: /tmp/zshmq) and its runtime files
zshmq ctx_new	Create or reset the runtime directory, FIFO bus, and state file (default: /tmp/zshmq)
zshmq start	Start the dispatcher process (use --foreground to stay attached to the terminal)
zshmq send <message>	Publish a message (infers the topic from "<topic>: <message>" or use --topic)
zshmq sub <pattern>	Subscribe to matching messages
zshmq list	Show active subscribers
zshmq unsub	Unregister the current subscriber
zshmq stop	Stop the dispatcher
zshmq --help	Show usage
zshmq --version	Display version info

### Environment Variables
Variable	Default	Description
ZSHMQ_CTX_ROOT	/tmp/zshmq	Root directory initialised by ctx_new
ZSHMQ_BUS	/tmp/zshmq/bus	Main FIFO path
ZSHMQ_STATE	/tmp/zshmq/state	Subscription table
ZSHMQ_DISPATCH_PID	/tmp/zshmq/dispatcher.pid	PID file tracked by start/stop
ZSHMQ_LOG_LEVEL	INFO	Minimum log level emitted by the logger (TRACE, DEBUG, INFO, WARN, ERROR, FATAL); overridden by -d/--debug and -t/--trace

### Example Session

Terminal 1 - Dispatcher
```bash
zshmq start
```

Terminal 2 - Subscriber
```bash
zshmq sub '^ALERT'
```

Terminal 3 - Publisher
```bash
zshmq send "ALERT: Disk full"
zshmq send "INFO: Backup started"
```

Subscriber Output
```bash
ALERT: Disk full
```
## Implementation Summary

- Dispatcher uses a blocking read on /tmp/zshmq/bus (no polling).
- Subscriptions stored in /tmp/zshmq/state as PATTERN|FIFO.
- Subscribers each have a private FIFO (/tmp/zshmq/sub.<pid>).
- Multiple publishers supported (atomic writes up to PIPE_BUF).
- Fully POSIX; no arrays or Bash-specific syntax.

## Limitations

- One reader per FIFO (FIFO property).
- No guaranteed delivery or message persistence.
- Filtering uses shell patterns (case), not full regex.
- Single host only (no networking).
- Single broker per machine because all instances share the /tmp/zshmq/ directory.

## Roadmap

- Implement REQ/REP and PUSH/PULL patterns
- Add persistence and re-delivery
- Add metrics and TTLs
- Optional Unix-socket backend

## Design Philosophy

**Principle	Description**
Zero dependencies	Pure POSIX implementation
Brokerless	Simple dispatcher; no background services
Transparent messages	Human-readable text
Efficient	Blocking I/O, 0 % CPU idle
Educational	Teaches message-passing concepts with FIFOs

## License

MIT License (c) 2025 - Maxim Parkachov

## Inspiration

- [ZeroMQ](https://zeromq.org/) - distributed messaging patterns
- [Plan 9 Plumber](https://9p.io/sys/doc/plumb.html) - pattern-based routing
- [The Unix philosophy](https://en.wikipedia.org/wiki/Unix_philosophy) - composability through pipes
