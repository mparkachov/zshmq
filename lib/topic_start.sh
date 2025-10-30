#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# topic start - Launch the dispatcher loop for a topic.
# @usage: zshmq topic start --topic TOPIC [--path PATH]
# @summary: Spawn the topic dispatcher (default runtime: /tmp/zshmq) in the background.
# @description: Validates a runtime directory created by `ctx new`, then spawns the dispatcher loop so publishers and subscribers can exchange messages via the topic FIFO. Supports foreground mode for debugging.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name handled by this dispatcher.
# @option: -f, --foreground   Run the dispatcher in the foreground.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

:
