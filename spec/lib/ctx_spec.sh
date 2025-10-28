Describe 'ctx'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT" "$SHELLSPEC_TMPDIR"/ctx_spec_*
  }

  BeforeEach 'before_each'

  It 'creates the default runtime directory'
    When call ctx new
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT" should exist
  End

  It 'honours an explicit --path option'
    custom="$SHELLSPEC_TMPDIR/ctx_spec_custom"
    When call ctx --path "$custom" new
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$custom" should exist
  End

  It 'succeeds when the runtime already exists'
    mkdir -p "$ZSHMQ_CTX_ROOT"
    When call ctx --path "$ZSHMQ_CTX_ROOT" new
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT" should exist
  End

  It 'removes the runtime directory when empty'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    When call ctx --path "$ZSHMQ_CTX_ROOT" destroy
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT" should not exist
  End

  It 'refuses to remove a non-empty runtime without --force'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    touch "$ZSHMQ_CTX_ROOT/data"
    When run ctx --path "$ZSHMQ_CTX_ROOT" destroy
    The status should be failure
    The stderr should include '[ERROR] ctx destroy: runtime contains files'
    The path "$ZSHMQ_CTX_ROOT" should exist
  End

  It 'forcefully removes a non-empty runtime when requested'
    ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    touch "$ZSHMQ_CTX_ROOT/data"
    When call ctx --path "$ZSHMQ_CTX_ROOT" destroy --force
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
    The path "$ZSHMQ_CTX_ROOT" should not exist
  End

  It 'succeeds gracefully when the target does not exist'
    missing="$SHELLSPEC_TMPDIR/ctx_spec_missing"
    When call ctx --path "$missing" destroy
    The status should be success
    The stdout should equal ''
    The stderr should equal ''
  End
End
