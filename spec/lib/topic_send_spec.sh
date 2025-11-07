Describe 'topic send'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  after_each() {
    if [ -d "$ZSHMQ_CTX_ROOT" ]; then
      topic stop --path "$ZSHMQ_CTX_ROOT" --topic test >/dev/null 2>&1 || :
    fi
    if [ -n "${TOPIC_SEND_SPEC_DISPATCHER_PID:-}" ]; then
      kill "$TOPIC_SEND_SPEC_DISPATCHER_PID" >/dev/null 2>&1 || :
      wait "$TOPIC_SEND_SPEC_DISPATCHER_PID" 2>/dev/null || :
    fi
    if [ -n "${TOPIC_SEND_SPEC_READER_PID:-}" ]; then
      kill "$TOPIC_SEND_SPEC_READER_PID" >/dev/null 2>&1 || :
      wait "$TOPIC_SEND_SPEC_READER_PID" 2>/dev/null || :
    fi
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  ensure_dispatcher_running() {
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
    TOPIC_SEND_SPEC_CAPTURE=${TOPIC_SEND_SPEC_CAPTURE:-"$SHELLSPEC_TMPDIR/send_capture"}
    : > "$TOPIC_SEND_SPEC_CAPTURE"
    {
      while IFS= read -r line; do
        printf '%s\n' "$line" >> "$TOPIC_SEND_SPEC_CAPTURE"
        break
      done < "${ZSHMQ_CTX_ROOT}/test.fifo"
    } &
    TOPIC_SEND_SPEC_READER_PID=$!
    ( sleep 60 ) &
    TOPIC_SEND_SPEC_DISPATCHER_PID=$!
    printf '%s\n' "$TOPIC_SEND_SPEC_DISPATCHER_PID" > "${ZSHMQ_CTX_ROOT}/test.pid"
  }

  It 'publishes to the requested topic'
    TOPIC_SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/test_payload"
    ensure_dispatcher_running
    When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test 'system overload'
    The status should be success
    The stdout should equal ''
    The stderr should not include '[INFO] topic send:'
    The stderr should not include '[TRACE]'
    wait "$TOPIC_SEND_SPEC_READER_PID" 2>/dev/null || :
    TOPIC_SEND_SPEC_READER_PID=
    The contents of file "$TOPIC_SEND_SPEC_CAPTURE" should equal 'PUB|test|system overload'
  End

  It 'logs the dispatched message when trace logging is enabled'
    TOPIC_SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/test_payload"
    ensure_dispatcher_running
    When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test --trace 'system overload'
    The status should be success
    The stdout should equal ''
    The stderr should include '[TRACE] topic send: topic=test message=system overload'
    The stderr should not include '[INFO] topic send:'
    wait "$TOPIC_SEND_SPEC_READER_PID" 2>/dev/null || :
    TOPIC_SEND_SPEC_READER_PID=
  End

  It 'fails when the dispatcher is not running'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
    When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test 'no loop'
    The status should be failure
    The stderr should include '[ERROR] topic send: dispatcher is not running'
  End

  It 'requires --topic'
    ensure_dispatcher_running
    When run topic --path "$ZSHMQ_CTX_ROOT" send 'Malformed message'
    The status should be failure
    The stderr should include '[ERROR] topic send: --topic is required'
  End

  It 'allows message payloads containing pipes'
    TOPIC_SEND_SPEC_CAPTURE="$SHELLSPEC_TMPDIR/test_payload"
    ensure_dispatcher_running
    When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test 'value | with | pipes'
    The status should be success
    The stdout should equal ''
    The stderr should not include '[INFO] topic send:'
    The stderr should not include '[TRACE]'
    wait "$TOPIC_SEND_SPEC_READER_PID" 2>/dev/null || :
    TOPIC_SEND_SPEC_READER_PID=
    The contents of file "$TOPIC_SEND_SPEC_CAPTURE" should equal 'PUB|test|value | with | pipes'
  End
End
