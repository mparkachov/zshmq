#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# dispatch stop - Terminate the dispatcher loop for a topic.
# @usage: zshmq dispatch stop --topic TOPIC [--path PATH]
# @summary: Stop the dispatcher running for the given runtime directory (default: /tmp/zshmq).
# @description: Read the dispatcher PID from the runtime directory, send it SIGTERM, and remove the PID file once the dispatcher exits.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name whose dispatcher should be stopped.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

:
