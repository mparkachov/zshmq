Describe 'start'
  Include lib/command_helpers.sh
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
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be success
    The stdout should include 'Dispatcher started (pid='
    The path "$ZSHMQ_CTX_ROOT/dispatcher.pid" should be file
    The file "$ZSHMQ_CTX_ROOT/dispatcher.pid" should not be empty file
    The contents of file "$ZSHMQ_CTX_ROOT/dispatcher.pid" should match pattern '[0-9][0-9]*'
  End

  It 'fails when the dispatcher is already running'
    ctx_new --path "$ZSHMQ_CTX_ROOT" >/dev/null
    start --path "$ZSHMQ_CTX_ROOT" >/dev/null
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be failure
    The stderr should include 'dispatcher already running'
  End

  It 'fails when the runtime directory has not been initialised'
    When run start --path "$ZSHMQ_CTX_ROOT"
    The status should be failure
    The stderr should include 'runtime directory not found'
  End
End
