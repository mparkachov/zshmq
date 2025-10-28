Describe 'stop'
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
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T bus >/dev/null 2>&1
  }

  after_each() {
    stop --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1 || :
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  It 'stops a running dispatcher for the requested topic'
    start --path "$ZSHMQ_CTX_ROOT" --topic bus >/dev/null 2>&1
    When run stop --path "$ZSHMQ_CTX_ROOT" --topic bus
    The status should be success
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/bus.pid" should not exist
  End

  It 'stops a dispatcher by topic using default runtime'
    start --path "$ZSHMQ_CTX_ROOT" --topic bus >/dev/null 2>&1
    When run stop --topic bus
    The status should be success
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/bus.pid" should not exist
  End

  It 'succeeds even when the dispatcher is not running'
    When run stop --path "$ZSHMQ_CTX_ROOT"
    The status should be success
    The stderr should equal ''
  End
End
