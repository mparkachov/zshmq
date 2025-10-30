Describe 'zshmq_eval_parser logging flags'
  Include vendor/getoptions/lib/getoptions_base.sh
  Include vendor/getoptions/lib/getoptions_abbr.sh
  Include vendor/getoptions/lib/getoptions_help.sh
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/topic.sh

  before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_LOG_LEVEL=INFO
    unset ZSHMQ_REST || :
    unset ZSHMQ_HELP || :
    unset ZSHMQ_DEBUG || :
    unset ZSHMQ_TRACE || :
  }

  BeforeEach 'before_each'

  It 'retains existing log level when no verbosity flag is provided'
    export ZSHMQ_LOG_LEVEL=WARN
    When call zshmq_eval_parser topic_start topic_start_parser_definition
    The status should be success
    The variable ZSHMQ_LOG_LEVEL should equal 'WARN'
  End

  It 'sets DEBUG log level when -d/--debug is provided'
    When call zshmq_eval_parser topic_start topic_start_parser_definition -d
    The status should be success
    The variable ZSHMQ_LOG_LEVEL should equal 'DEBUG'
  End

  It 'sets TRACE log level when -t/--trace is provided'
    When call zshmq_eval_parser topic_start topic_start_parser_definition --trace
    The status should be success
    The variable ZSHMQ_LOG_LEVEL should equal 'TRACE'
  End

  It 'prefers TRACE log level when both debug and trace are provided'
    When call zshmq_eval_parser topic_start topic_start_parser_definition -d --trace
    The status should be success
    The variable ZSHMQ_LOG_LEVEL should equal 'TRACE'
  End
End
