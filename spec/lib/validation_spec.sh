Describe 'input validation'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh

  validation_before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
  }

  BeforeEach 'validation_before_each'

  Context 'ctx path validation'
    It 'rejects root directory as runtime path'
      When run ctx --path / new
      The status should be failure
      The stderr should include '[ERROR]'
    End

    It 'rejects empty path'
      When run ctx --path "" new
      The status should be failure
      The stderr should include '[ERROR]'
    End

    It 'handles path with spaces'
      space_path="$SHELLSPEC_TMPDIR/path with spaces"
      mkdir -p "$space_path"
      When run ctx --path "$space_path" new
      The status should be success
      The path "$space_path" should be directory
      rm -rf "$space_path"
    End
  End

  Context 'topic name validation'
    It 'rejects topic containing pipe character'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "test|invalid"
      The status should be failure
      The stderr should include '[ERROR] topic new: topic must not contain "|"'
    End

    It 'rejects topic containing tab character'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "$(printf 'test\ttab')"
      The status should be failure
      The stderr should include '[ERROR] topic new: topic must not contain tabs'
    End

    It 'rejects topic containing slash'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "test/slash"
      The status should be failure
      The stderr should include '[ERROR] topic new: topic must not contain "/"'
    End

    It 'rejects topic containing newline'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "$(printf 'test\nline')"
      The status should be failure
      The stderr should include '[ERROR] topic new: topic must not contain newlines'
    End

    It 'rejects empty topic name'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T ""
      The status should be failure
      The stderr should include '[ERROR]'
    End

    It 'rejects topic containing spaces'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "my topic"
      The status should be failure
      The stderr should include '[ERROR] topic new: topic must not contain spaces'
    End

    It 'rejects very long topic name (255+ chars)'
      long_name=$(printf 'a%.0s' $(seq 1 255))
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T "$long_name"
      # System should reject due to file name length limits
      The status should be failure
      The stderr should include 'File name too long'
    End
  End

  Context 'topic send validation'
    It 'requires dispatcher to be running'
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test "message"
      The status should be failure
      The stderr should include '[ERROR] topic send: dispatcher is not running'
    End

    It 'rejects send with topic containing pipe'
      When run topic --path "$ZSHMQ_CTX_ROOT" send --topic "test|bad" "message"
      The status should be failure
      The stderr should include '[ERROR] topic send: topic must not contain "|"'
    End

    It 'requires message argument'
      When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test
      The status should be failure
      The stderr should include '[ERROR] topic send: message is required'
    End
  End

  Context 'regex validation'
    It 'accepts valid regex patterns'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T alerts --regex '^ALERT.*$'
      The status should be success
      The path "$ZSHMQ_CTX_ROOT/alerts.fifo" should be pipe
    End

    It 'accepts regex with character classes'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T pattern --regex '[A-Z]+[0-9]{3}'
      The status should be success
    End

    It 'accepts regex with alternation'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T multi --regex 'ERROR|WARN|FATAL'
      The status should be success
    End

    It 'accepts empty regex'
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T noreg --regex ''
      The status should be success
    End

    It 'updates existing topic regex'
      topic --path "$ZSHMQ_CTX_ROOT" new -T alerts --regex '^OLD' >/dev/null 2>&1
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T alerts --regex '^NEW'
      The status should be success
      tab=$(printf '\t')
      The contents of file "$ZSHMQ_CTX_ROOT/topics.reg" should include "alerts${tab}^NEW"
      The contents of file "$ZSHMQ_CTX_ROOT/topics.reg" should not include "alerts${tab}^OLD"
    End
  End

  Context 'FIFO and state file edge cases'
    It 'recreates FIFO if it exists as regular file'
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      # Replace FIFO with regular file
      rm -f "$ZSHMQ_CTX_ROOT/test.fifo"
      touch "$ZSHMQ_CTX_ROOT/test.fifo"

      When run topic --path "$ZSHMQ_CTX_ROOT" new -T test
      The status should be failure
      The stderr should include '[ERROR] topic new: topic FIFO path is not a FIFO'
    End

    It 'handles existing state file gracefully'
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1
      printf 'existing data\n' > "$ZSHMQ_CTX_ROOT/test.state"

      When run topic --path "$ZSHMQ_CTX_ROOT" new -T test
      The status should be success
      # State file should be reset
      The file "$ZSHMQ_CTX_ROOT/test.state" should be empty file
    End
  End

  Context 'concurrent operations'
    It 'allows multiple topics in same runtime'
      topic --path "$ZSHMQ_CTX_ROOT" new -T topic1 >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T topic2 >/dev/null 2>&1
      topic --path "$ZSHMQ_CTX_ROOT" new -T topic3 >/dev/null 2>&1

      The path "$ZSHMQ_CTX_ROOT/topic1.fifo" should be pipe
      The path "$ZSHMQ_CTX_ROOT/topic2.fifo" should be pipe
      The path "$ZSHMQ_CTX_ROOT/topic3.fifo" should be pipe
    End
  End

  Context 'error recovery'
    It 'handles missing runtime directory gracefully'
      When run topic --path "$ZSHMQ_CTX_ROOT/nonexistent" new -T test
      The status should be failure
      The stderr should include '[ERROR]'
    End

    It 'handles topic operations without ctx new'
      rm -rf "$ZSHMQ_CTX_ROOT"
      When run topic --path "$ZSHMQ_CTX_ROOT" new -T test
      The status should be failure
      The stderr should include '[ERROR]'
    End

    It 'handles send when dispatcher is stopped'
      topic --path "$ZSHMQ_CTX_ROOT" new -T test >/dev/null 2>&1

      When run topic --path "$ZSHMQ_CTX_ROOT" send --topic test "message"
      The status should be failure
      The stderr should include '[ERROR] topic send: dispatcher is not running'
    End
  End
End
