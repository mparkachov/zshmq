Describe 'start'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh
  Include lib/start.sh
  Include lib/stop.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  stop_all_dispatchers() {
    if [ ! -d "$ZSHMQ_CTX_ROOT" ]; then
      return 0
    fi

    attempts=0
    while [ "$attempts" -lt 10 ]; do
      pid_file=
      for candidate in "$ZSHMQ_CTX_ROOT"/*.pid; do
        if [ -f "$candidate" ]; then
          pid_file=$candidate
          break
        fi
      done

      if [ -z "$pid_file" ]; then
        break
      fi

      stop --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1 || :
      attempts=$((attempts + 1))
    done

    for candidate in "$ZSHMQ_CTX_ROOT"/*.pid; do
      if [ -f "$candidate" ]; then
        dispatcher_pid=$(cat "$candidate" 2>/dev/null || :)
        if [ -n "$dispatcher_pid" ]; then
          kill "$dispatcher_pid" >/dev/null 2>&1 || :
          wait "$dispatcher_pid" 2>/dev/null || :
        fi
        rm -f "$candidate" 2>/dev/null || :
      fi
    done
  }

  after_each() {
    stop_all_dispatchers
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  It 'starts the dispatcher and records its PID'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT" --topic bus
    The status should be success
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/bus.pid" should be file
    The file "$ZSHMQ_CTX_ROOT/bus.pid" should not be empty file
    The contents of file "$ZSHMQ_CTX_ROOT/bus.pid" should match pattern '[0-9][0-9]*'
  End

  It 'requires a topic argument'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be failure
    The stderr should include '[ERROR] start: --topic is required'
  End

  It 'fails when the dispatcher is already running'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    start --path "$ZSHMQ_CTX_ROOT" --topic bus >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT" --topic bus
    The status should be failure
    The stderr should equal ''
  End

  It 'fails when the runtime directory has not been initialised'
    When run start --path "$ZSHMQ_CTX_ROOT" --topic bus
    The status should be failure
    The stderr should include '[ERROR] start: runtime directory not found'
  End

  It 'fails when the topic assets are missing'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    When run start --path "$ZSHMQ_CTX_ROOT" --topic bus
    The status should be failure
    The stderr should include '[ERROR] start: topic FIFO not found'
  End

  It 'supports concurrent dispatchers for distinct topics'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T alerts >/dev/null 2>&1

    start --path "$ZSHMQ_CTX_ROOT" --topic bus >/dev/null 2>&1
    bus_pid=$(cat "$ZSHMQ_CTX_ROOT/bus.pid" 2>/dev/null || :)
    kill -0 "$bus_pid"

    When run start --path "$ZSHMQ_CTX_ROOT" --topic alerts
    The status should be success
    The stderr should equal ''

    alerts_pid=$(cat "$ZSHMQ_CTX_ROOT/alerts.pid" 2>/dev/null || :)
    The path "$ZSHMQ_CTX_ROOT/bus.pid" should be file
    The path "$ZSHMQ_CTX_ROOT/alerts.pid" should be file
    The variable bus_pid should not equal "$alerts_pid"
    kill -0 "$bus_pid"
    kill -0 "$alerts_pid"
  End

  start_trace_log_helper() {
    export ZSHMQ_LOG_LEVEL=TRACE
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
    trace_log="$SHELLSPEC_TMPDIR/start_trace.log"
    : > "$trace_log"

    zshmq_dispatch_loop "${ZSHMQ_CTX_ROOT}/bus.fifo" "${ZSHMQ_CTX_ROOT}/bus.state" 2>"$trace_log" &
    dispatcher_pid=$!

    printf '%s\n' 'PUB|ALERT|system overload' > "${ZSHMQ_CTX_ROOT}/bus.fifo"

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
