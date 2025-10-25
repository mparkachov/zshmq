Describe 'zshmq --help'
  It 'lists available commands only and references per-command help'
    When run ./zshmq --help
    The status should be success
    The stdout should include 'Commands:'
    The stdout should include 'ctx_new - Bootstrap the runtime directory (default: /tmp/zshmq).'
    The stdout should include 'ctx_destroy - Remove the runtime directory (default: /tmp/zshmq) and its state file.'
    The stdout should include 'Each command supports -h/--help for detailed usage.'
    The stdout should not include 'Command: ctx_new'
    The stdout should not include 'Command: ctx_destroy'
  End
End

Describe 'zshmq ctx_new --help'
  It 'shows command-specific documentation'
    When run ./zshmq ctx_new --help
    The status should be success
    The stdout should include 'Command: ctx_new'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq ctx_destroy --help'
  It 'shows command-specific documentation'
    When run ./zshmq ctx_destroy --help
    The status should be success
    The stdout should include 'Command: ctx_destroy'
    The stdout should include 'Options:'
  End
End
