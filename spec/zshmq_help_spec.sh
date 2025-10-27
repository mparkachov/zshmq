Describe 'zshmq --help'
  It 'lists available commands only and references per-command help'
    When run ./bin/zshmq.sh --help
    The status should be success
    The stdout should include 'Commands:'
    The stdout should include 'ctx - Manage the runtime directory (default: /tmp/zshmq).'
    The stdout should include 'topic - Manage topic FIFOs and state files.'
    The stdout should include 'start - Launch the dispatcher (default root: /tmp/zshmq) in the background.'
    The stdout should include 'stop - Stop the dispatcher running for the given runtime directory (default: /tmp/zshmq).'
    The stdout should include 'send - Publish a message through the dispatcher FIFO.'
    The stdout should include 'Each command supports -h/--help plus -d/--debug and -t/--trace for log verbosity.'
    The stdout should not include 'Command: ctx'
    The stdout should not include 'Command: topic'
  End
End

Describe 'zshmq ctx --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh ctx --help
    The status should be success
    The stdout should include 'Usage: zshmq ctx <command>'
    The stdout should include 'new      Initialise the runtime directory'
    The stdout should include 'destroy  Remove the runtime directory (use --force to ignore leftovers)'
  End
End

Describe 'zshmq topic --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh topic --help
    The status should be success
    The stdout should include 'Usage: zshmq topic <command>'
    The stdout should include 'new      Initialise topic assets (-T/--topic required)'
    The stdout should include 'destroy  Remove topic assets    (-T/--topic required)'
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

Describe 'zshmq send --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh send --help
    The status should be success
    The stdout should include 'Command: send'
    The stdout should include 'Options:'
  End
End
