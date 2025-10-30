Describe 'zshmq --help'
  It 'lists available commands only and references per-command help'
    When run ./bin/zshmq.sh --help
    The status should be success
    The stdout should include 'Commands:'
    The stdout should include 'ctx - Manage the runtime directory (default: /tmp/zshmq).'
    The stdout should include 'topic - Manage topic FIFOs and state files.'
    The stdout should include 'Each command supports -h/--help plus -d/--debug and -t/--trace for log verbosity.'
    The stdout should not include 'Command: ctx'
    The stdout should not include 'Command: topic'
    The stdout should not include 'Command: start'
    The stdout should not include 'Command: stop'
    The stdout should not include 'dispatch - Start or stop the dispatcher that routes messages for a topic.'
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
    The stdout should include 'start    Launch the topic dispatcher (-T/--topic required)'
    The stdout should include 'stop     Terminate the topic dispatcher (-T/--topic required)'
    The stdout should include 'send     Publish a message      (-T/--topic required)'
    The stdout should include 'sub      Stream topic messages  (-T/--topic required)'
  End
End

Describe 'zshmq topic start --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh topic start --help
    The status should be success
    The stdout should include 'Command: topic start'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq topic stop --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh topic stop --help
    The status should be success
    The stdout should include 'Command: topic stop'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq topic send --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh topic send --help
    The status should be success
    The stdout should include 'Command: topic send'
    The stdout should include 'Options:'
  End
End

Describe 'zshmq topic sub --help'
  It 'shows command-specific documentation'
    When run ./bin/zshmq.sh topic sub --help
    The status should be success
    The stdout should include 'Command: topic sub'
    The stdout should include 'Options:'
  End
End
