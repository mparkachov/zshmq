Describe 'topic'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
  }

  BeforeEach 'before_each'

  It 'creates the fifo and state for a topic'
    When call topic --path "$ZSHMQ_CTX_ROOT" new -T test
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/test.fifo" should be pipe
    The path "$ZSHMQ_CTX_ROOT/test.state" should be file
    The path "$ZSHMQ_CTX_ROOT/test.state" should be empty file
  End

  It 'supports multiple topics in the same runtime'
    topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
    topic --path "$ZSHMQ_CTX_ROOT" new -T alerts >/dev/null 2>&1
    The path "$ZSHMQ_CTX_ROOT/test.fifo" should be pipe
    The path "$ZSHMQ_CTX_ROOT/test.state" should be file
    The path "$ZSHMQ_CTX_ROOT/alerts.fifo" should be pipe
    The path "$ZSHMQ_CTX_ROOT/alerts.state" should be file
  End

  It 'destroys the fifo and state for a topic'
    topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
    When call topic --path "$ZSHMQ_CTX_ROOT" destroy -T test
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT/test.fifo" should not exist
    The path "$ZSHMQ_CTX_ROOT/test.state" should not exist
  End

  It 'requires a topic argument for new'
    When run topic --path "$ZSHMQ_CTX_ROOT" new
    The status should be failure
    The stderr should include '[ERROR] topic new: --topic is required'
  End

  It 'requires a topic argument for destroy'
    When run topic --path "$ZSHMQ_CTX_ROOT" destroy
    The status should be failure
    The stderr should include '[ERROR] topic destroy: --topic is required'
  End
End
