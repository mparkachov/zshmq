Describe 'ctx_new'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx_new.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
  }

  BeforeEach 'before_each'

  It 'creates the context directory and state file using defaults'
    When call ctx_new
    The status should be success
    The stdout should equal "$ZSHMQ_CTX_ROOT"
    The path "$ZSHMQ_CTX_ROOT" should exist
    The path "$ZSHMQ_CTX_ROOT/bus" should be pipe
    The path "$ZSHMQ_CTX_ROOT/state" should be file
    The path "$ZSHMQ_CTX_ROOT/state" should be empty file
  End

  It 'honours an explicit --path argument'
    custom_path="$SHELLSPEC_TMPDIR/custom"
    When call ctx_new --path "$custom_path"
    The status should be success
    The stdout should equal "$custom_path"
    The path "$custom_path" should exist
    The path "$custom_path/bus" should be pipe
    The path "$custom_path/state" should be file
    The path "$custom_path/state" should be empty file
  End

  It 'does not fail if the target already exists'
    preexisting="$SHELLSPEC_TMPDIR/existing"
    rm -rf "$preexisting"
    mkdir -p "$preexisting"
    mkfifo "$preexisting/bus"
    printf '%s\n' 'pattern|fifo' > "$preexisting/state"
    When call ctx_new --path "$preexisting"
    The status should be success
    The stdout should equal "$preexisting"
    The path "$preexisting/bus" should be pipe
    The path "$preexisting/state" should be empty file
  End

  It 'fails when a non-fifo bus path already exists'
    preexisting="$SHELLSPEC_TMPDIR/existing_file"
    rm -rf "$preexisting"
    mkdir -p "$preexisting"
    : > "$preexisting/bus"
    When run ctx_new --path "$preexisting"
    The status should be failure
    The stderr should include '[ERROR] ctx_new: bus path is not a FIFO'
  End

  It 'fails when unexpected positional arguments are provided'
    When run ctx_new extra
    The status should be failure
    The stderr should include '[ERROR] ctx_new: unexpected argument'
  End
End
