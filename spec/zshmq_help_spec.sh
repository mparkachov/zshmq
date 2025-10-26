Describe 'zshmq --help'
  It 'lists available commands only and references per-command help'
    When run ./bin/zshmq.sh --help
    The status should be success
    The stdout should include 'Commands:'
    The stdout should include 'ctx_new - Bootstrap the runtime directory (default: /tmp/zshmq) and transport primitives.'
    The stdout should include 'ctx_destroy - Remove the runtime directory (default: /tmp/zshmq) and its runtime files.'
    The stdout should include 'start - Launch the dispatcher (default root: /tmp/zshmq) in the background.'
    The stdout should include 'stop - Stop the dispatcher running for the given runtime directory (default: /tmp/zshmq).'
    The stdout should include 'Each command supports -h/--help for detailed usage.'
    The stdout should not include 'Command: ctx_new'
    The stdout should not include 'Command: ctx_destroy'
    The stdout should not include 'Command: start'
    The stdout should not include 'Command: stop'
  End
End

Describe 'zshmq ctx_new --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh ctx_new --help
    The status should be success
    The stdout should include 'Command: ctx_new'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq ctx_destroy --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh ctx_destroy --help
    The status should be success
    The stdout should include 'Command: ctx_destroy'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq start --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh start --help
    The status should be success
    The stdout should include 'Command: start'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq stop --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh stop --help
    The status should be success
    The stdout should include 'Command: stop'
    The stdout should include 'Options:'
  End
End
