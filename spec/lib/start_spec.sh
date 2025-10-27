Describe 'start'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx_new.sh
  Include lib/start.sh
  Include lib/stop.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  after_each() {
    if [ -d "$ZSHMQ_CTX_ROOT" ]; then
      stop --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1 || :
    fi
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  It 'starts the dispatcher and records its PID'
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be success
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/dispatcher.pid" should be file
    The file "$ZSHMQ_CTX_ROOT/dispatcher.pid" should not be empty file
    The contents of file "$ZSHMQ_CTX_ROOT/dispatcher.pid" should match pattern '[0-9][0-9]*'
  End

  It 'fails when the dispatcher is already running'
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1
    start --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be failure
    The stderr should equal ''
  End

  It 'fails when the runtime directory has not been initialised'
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be failure
    The stderr should include '[ERROR] start: runtime directory not found'
  End

  start_trace_log_helper() {
    export ZSHMQ_LOG_LEVEL=TRACE
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1
    trace_log="$SHELLSPEC_TMPDIR/start_trace.log"
    : > "$trace_log"

    zshmq_dispatch_loop "${ZSHMQ_CTX_ROOT}/bus" "${ZSHMQ_CTX_ROOT}/state" 2>"$trace_log" &
    dispatcher_pid=$!

    printf '%s\n' 'PUB|ALERT|system overload' > "${ZSHMQ_CTX_ROOT}/bus"

    attempts=0
    while [ "$attempts" -lt 50 ]; do
      if grep -F 'dispatcher: topic=ALERT' "$trace_log" >/dev/null 2>&1; then
        break
      fi
      sleep 0.1
      attempts=$((attempts + 1))
    done

    kill "$dispatcher_pid" 2>/dev/null || :
    wait "$dispatcher_pid" 2>/dev/null || :

    cat "$trace_log"
  }

  It 'logs dispatched messages when trace logging is enabled'
    When run start_trace_log_helper
    The status should be success
    The stdout should include '[TRACE] dispatcher: topic=ALERT message=system overload'
  End
End
