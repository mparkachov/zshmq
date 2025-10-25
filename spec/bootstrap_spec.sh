Describe 'bootstrap environment'
  It 'runs a placeholder check'
    When call printf '%s' 'zshmq ok'
    The output should equal 'zshmq ok'
  End
End
