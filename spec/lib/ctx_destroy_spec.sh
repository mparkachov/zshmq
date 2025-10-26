Describe 'ctx_destroy'
  Include lib/command_helpers.sh
  Include lib/ctx_new.sh
  Include lib/ctx_destroy.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT" "$SHELLSPEC_TMPDIR"/ctx_destroy_*
  }

  BeforeEach 'before_each'

  It 'removes the runtime directory created by ctx_new'
    target="$SHELLSPEC_TMPDIR/ctx_destroy_clean"
    ctx_new --path "$target" >/dev/null
    When call ctx_destroy --path "$target"
    The status should be success
    The stdout should equal "$target"
    The path "$target" should not exist
  End

  It 'removes the state file but preserves other contents'
    target="$SHELLSPEC_TMPDIR/ctx_destroy_with_data"
    ctx_new --path "$target" >/dev/null
    touch "$target/data"
    printf '%s\n' '999' > "$target/dispatcher.pid"
    When call ctx_destroy --path "$target"
    The status should be success
    The stdout should equal "$target"
    The path "$target/state" should not exist
    The path "$target/bus" should not exist
    The path "$target/dispatcher.pid" should not exist
    The path "$target" should exist
  End

  It 'succeeds gracefully when the target does not exist'
    missing="$SHELLSPEC_TMPDIR/ctx_destroy_missing"
    When call ctx_destroy --path "$missing"
    The status should be success
    The stdout should equal "$missing"
  End
End
