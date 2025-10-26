Describe 'stop'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx_new.sh
  Include lib/start.sh
  Include lib/stop.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null
  }

  after_each() {
    stop --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1 || :
  }

  BeforeEach 'before_each'
  AfterEach 'after_each'

  It 'stops a running dispatcher and removes the pid file'
    start --path "$ZSHMQ_CTX_ROOT" >/dev/null 2>&1
    pid_before=$(cat "$ZSHMQ_CTX_ROOT/dispatcher.pid")
    When run stop --path "$ZSHMQ_CTX_ROOT"
    The status should be success
    The stderr should include "[INFO] Dispatcher stopped (pid=$pid_before)"
    The path "$ZSHMQ_CTX_ROOT/dispatcher.pid" should not exist
  End

  It 'succeeds even when the dispatcher is not running'
    When run stop --path "$ZSHMQ_CTX_ROOT"
    The status should be success
    The stderr should include '[INFO] Dispatcher is not running.'
  End
End
