Describe 'ctx_new'
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
    The path "$ZSHMQ_CTX_ROOT/state" should be file
  End

  It 'honours an explicit --path argument'
    custom_path="$SHELLSPEC_TMPDIR/custom"
    When call ctx_new --path "$custom_path"
    The status should be success
    The stdout should equal "$custom_path"
    The path "$custom_path" should exist
    The path "$custom_path/state" should be file
  End

  It 'does not fail if the target already exists'
    preexisting="$SHELLSPEC_TMPDIR/existing"
    mkdir -p "$preexisting"
    : > "$preexisting/state"
    When call ctx_new --path "$preexisting"
    The status should be success
    The stdout should equal "$preexisting"
  End

  It 'fails when unexpected positional arguments are provided'
    When run ctx_new extra
    The status should be failure
    The stderr should include 'unexpected argument'
  End
End
