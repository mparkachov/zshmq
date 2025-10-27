Describe 'send'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh
  Include lib/start.sh
  Include lib/stop.sh
  Include lib/send.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  after_each() {
    if [ -d "$ZSHMQ_CTX_ROOT" ]; then
      stop --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1 || :
    fi
    if [ -n "${SEND_SPEC_DISPATCHER_PID:-}" ]; then
      kill "$SEND_SPEC_DISPATCHER_PID" >/dev/null 2>&1 || :
      wait "$SEND_SPEC_DISPATCHER_PID" 2>/dev/null || :
    fi
    if [ -n "${SEND_SPEC_READER_PID:-}" ]; then
      kill "$SEND_SPEC_READER_PID" >/dev/null 2>&1 || :
      wait "$SEND_SPEC_READER_PID" 2>/dev/null || :
    fi
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  ensure_dispatcher_running() {
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    SEND_SPEC_CAPTURE=${SEND_SPEC_CAPTURE:-"$SHELLSPEC_TMPDIR/send_capture"}
    : > "$SEND_SPEC_CAPTURE"
    {
      while IFS= read -r line; do
        printf '%s\n' "$line" >> "$SEND_SPEC_CAPTURE"
        break
      done < "${ZSHMQ_CTX_ROOT}/bus.topic"
    } &
    SEND_SPEC_READER_PID=$!
    ( sleep 60 ) &
    SEND_SPEC_DISPATCHER_PID=$!
    printf '%s\n' "$SEND_SPEC_DISPATCHER_PID" > "${ZSHMQ_CTX_ROOT}/bus.pid"
  }

  It 'publishes to the requested topic'
    SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/bus_payload"
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" --topic bus 'system overload'
    The status should be success
    The stdout should equal ''
    The stderr should not include '[INFO] send: published'
    The stderr should not include '[TRACE]'
    wait "$SEND_SPEC_READER_PID" 2>/dev/null || :
    SEND_SPEC_READER_PID=
    The contents of file "$SEND_SPEC_CAPTURE" should equal 'PUB|bus|system overload'
  End

  It 'logs the dispatched message when trace logging is enabled'
    SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/bus_payload"
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" --topic bus --trace 'system overload'
    The status should be success
    The stdout should equal ''
    The stderr should include '[TRACE] send: topic=bus message=system overload'
    The stderr should not include '[INFO] send: published'
    wait "$SEND_SPEC_READER_PID" 2>/dev/null || :
    SEND_SPEC_READER_PID=
  End

  It 'fails when the dispatcher is not running'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    When run send --path "$ZSHMQ_CTX_ROOT" --topic bus 'no loop'
    The status should be failure
    The stderr should include '[ERROR] send: dispatcher is not running'
  End

  It 'requires --topic'
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" 'Malformed message'
    The status should be failure
    The stderr should include '[ERROR] send: --topic is required'
  End

  It 'allows message payloads containing pipes'
    SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/bus_payload"
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" --topic bus 'value | with | pipes'
    The status should be success
    The stdout should equal ''
    The stderr should not include '[INFO] send: published'
    The stderr should not include '[TRACE]'
    wait "$SEND_SPEC_READER_PID" 2>/dev/null || :
    SEND_SPEC_READER_PID=
    The contents of file "$SEND_SPEC_CAPTURE" should equal 'PUB|bus|value | with | pipes'
  End
End
