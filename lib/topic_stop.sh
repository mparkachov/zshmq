#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# topic stop - Terminate the dispatcher loop for a topic.
# @usage: zshmq topic stop --topic TOPIC [--path PATH]
# @summary: Stop the dispatcher that serves a topic and remove its PID file.
# @description: Looks up the dispatcher PID for the requested topic (or via environment overrides), sends a termination signal, waits briefly for shutdown, and cleans up PID artifacts. No-op when the dispatcher is already stopped.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name whose dispatcher should be stopped.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

:
