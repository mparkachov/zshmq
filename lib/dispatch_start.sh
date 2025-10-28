#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# dispatch start - Launch the dispatcher loop for a topic.
# @usage: zshmq dispatch start --topic TOPIC [--path PATH]
# @summary: Launch the dispatcher (default root: /tmp/zshmq) in the background.
# @description: Validate an existing runtime directory created by ctx new, then spawn the dispatcher loop so publishers and subscribers can communicate via the main topic FIFO.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name handled by this dispatcher.
# @option: -f, --foreground   Run the dispatcher in the foreground.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

:
