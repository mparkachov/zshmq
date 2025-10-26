Describe 'send'
  Include lib/command_helpers.sh
  Include lib/ctx_new.sh
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
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null
    : > "$SEND_SPEC_CAPTURE"
    {
      while IFS= read -r line; do
        printf '%s\n' "$line" >> "$SEND_SPEC_CAPTURE"
        break
      done < "${ZSHMQ_CTX_ROOT}/bus"
    } &
    SEND_SPEC_READER_PID=$!
    ( sleep 60 ) &
    SEND_SPEC_DISPATCHER_PID=$!
    printf '%s\n' "$SEND_SPEC_DISPATCHER_PID" > "${ZSHMQ_CTX_ROOT}/dispatcher.pid"
  }

  It 'publishes using an inferred topic and prints the routing tuple'
    SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/bus_payload"
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" 'ALERT: system overload'
    The status should be success
    The stdout should equal 'ALERT|system overload'
    wait "$SEND_SPEC_READER_PID" 2>/dev/null || :
    SEND_SPEC_READER_PID=
    The contents of file "$SEND_SPEC_CAPTURE" should equal 'PUB|ALERT|system overload'
  End

  It 'fails when the dispatcher is not running'
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null
    When run send --path "$ZSHMQ_CTX_ROOT" 'ALERT: no loop'
    The status should be failure
    The stderr should include 'dispatcher is not running'
  End

  It 'requires an explicit topic when it cannot infer one'
    SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/bus_payload"
    ensure_dispatcher_running
    When run send --path "$ZSHMQ_CTX_ROOT" 'Malformed message'
    The status should be failure
    The stderr should include 'unable to infer topic'
  End
End
