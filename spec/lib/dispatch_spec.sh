Describe 'dispatch'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh
  Include lib/dispatch.sh

  dispatch_global_before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  stop_all_dispatchers() {
    if [ ! -d "$ZSHMQ_CTX_ROOT" ]; then
      return 0
    fi

    for candidate in "$ZSHMQ_CTX_ROOT"/*.pid; do
      [ -f "$candidate" ] || continue
      topic_name=${candidate##*/}
      topic_name=${topic_name%.pid}
      dispatch stop --path "$ZSHMQ_CTX_ROOT" --topic "$topic_name" >/dev/null 2>&1 || :
    done
  }

  dispatch_global_after_each() {
    stop_all_dispatchers
  }

  BeforeEach 'dispatch_global_before_each'
  AfterEach 'dispatch_global_after_each'

  Context 'start'
    It 'launches the dispatcher and records its PID'
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      When run dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be success
      The stderr should equal ''
      The path "$ZSHMQ_CTX_ROOT/test.pid" should be file
      The file "$ZSHMQ_CTX_ROOT/test.pid" should not be empty file
      The contents of file "$ZSHMQ_CTX_ROOT/test.pid" should match pattern '[0-9][0-9]*'
    End

    It 'requires --topic'
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      When run dispatch start --path "$ZSHMQ_CTX_ROOT"
      The status should be failure
      The stderr should include '[ERROR] dispatch start: --topic is required'
    End

    It 'fails when the dispatcher is already running'
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1
      When run dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be failure
      The stderr should equal ''
    End

    It 'fails when the runtime directory is missing'
      When run dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be failure
      The stderr should include '[ERROR] dispatch start: runtime directory not found'
    End

    It 'fails when topic assets are missing'
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      When run dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be failure
      The stderr should include '[ERROR] dispatch start: topic FIFO not found'
    End

    It 'supports concurrent dispatchers for distinct topics'
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T alerts >/dev/null 2>&1

      dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1
      test_pid=$(cat "$ZSHMQ_CTX_ROOT/test.pid" 2>/dev/null || :)
      kill -0 "$test_pid"

      When run dispatch start --path "$ZSHMQ_CTX_ROOT" --topic alerts
      The status should be success
      The stderr should equal ''

      alerts_pid=$(cat "$ZSHMQ_CTX_ROOT/alerts.pid" 2>/dev/null || :)
      The path "$ZSHMQ_CTX_ROOT/test.pid" should be file
      The path "$ZSHMQ_CTX_ROOT/alerts.pid" should be file
      The variable test_pid should not equal "$alerts_pid"
      kill -0 "$test_pid"
      kill -0 "$alerts_pid"
    End

    dispatch_trace_log_helper() {
      export ZSHMQ_LOG_LEVEL=TRACE
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      trace_log="$SHELLSPEC_TMPDIR/dispatch_trace.log"
      : > "$trace_log"

      zshmq_dispatch_loop "${ZSHMQ_CTX_ROOT}/test.fifo" "${ZSHMQ_CTX_ROOT}/test.state" 2>"$trace_log" &
      dispatcher_pid=$!

      printf '%s\n' 'PUB|ALERT|system overload' > "${ZSHMQ_CTX_ROOT}/test.fifo"

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
      When run dispatch_trace_log_helper
      The status should be success
      The stdout should include '[TRACE] dispatcher: topic=ALERT message=system overload'
    End
  End

  Context 'stop'
    dispatch_stop_before_each() {
      ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      dispatch start --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1
    }

    dispatch_stop_after_each() {
      dispatch stop --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1 || :
    }

    BeforeEach 'dispatch_stop_before_each'
    AfterEach 'dispatch_stop_after_each'

    It 'terminates the dispatcher for the requested topic'
      When run dispatch stop --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be success
      The stderr should equal ''
      The path "$ZSHMQ_CTX_ROOT/test.pid" should not exist
    End

    It 'requires --topic when no environment override is set'
      When run dispatch stop --path "$ZSHMQ_CTX_ROOT"
      The status should be failure
      The stderr should include '[ERROR] dispatch stop: --topic is required'
    End

    It 'succeeds when the dispatcher is already stopped'
      dispatch stop --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1
      When run dispatch stop --path "$ZSHMQ_CTX_ROOT" --topic test
      The status should be success
      The stderr should equal ''
    End
  End
End
