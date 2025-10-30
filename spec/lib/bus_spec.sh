Describe 'bus'
  Include lib/command_helpers.sh
  Include lib/logging.sh
  Include lib/ctx.sh
  Include lib/topic.sh
  Include lib/topic_send.sh
  Include lib/topic_sub.sh
  Include lib/bus.sh

  zshmq_cli() {
    ./bin/zshmq.sh "$@"
  }

  bus_before_each() {
    export ZSHMQ_ROOT="$PWD"
    export ZSHMQ_CTX_ROOT="$SHELLSPEC_TMPDIR/zshmq"
    rm -rf "$ZSHMQ_CTX_ROOT"
    zshmq_cli ctx --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1
    BUS_SPEC_SUBSCRIBER_PID=
  }

  bus_after_each() {
    if [ -n "${BUS_SPEC_SUBSCRIBER_PID:-}" ]; then
      kill "$BUS_SPEC_SUBSCRIBER_PID" 2>/dev/null || :
      wait "$BUS_SPEC_SUBSCRIBER_PID" 2>/dev/null || :
      BUS_SPEC_SUBSCRIBER_PID=
    fi

    if [ -n "${BUS_SPEC_SUBSCRIBER_LOG:-}" ]; then
      rm -f "$BUS_SPEC_SUBSCRIBER_LOG" 2>/dev/null || :
      BUS_SPEC_SUBSCRIBER_LOG=
    fi

    if [ -d "$ZSHMQ_CTX_ROOT" ]; then
      if [ -f "$ZSHMQ_CTX_ROOT/bus.pid" ]; then
        zshmq_cli bus --path "$ZSHMQ_CTX_ROOT" stop >/dev/null 2>&1 || :
      fi

      for pid_file in "$ZSHMQ_CTX_ROOT"/*.pid; do
        [ -f "$pid_file" ] || continue
        case $pid_file in
          "$ZSHMQ_CTX_ROOT/bus.pid")
            continue
            ;;
        esac
        topic_name=${pid_file##*/}
        topic_name=${topic_name%.pid}
        zshmq_cli topic --path "$ZSHMQ_CTX_ROOT" stop --topic "$topic_name" >/dev/null 2>&1 || :
      done
    fi
  }

  bus_wait_for_pattern() {
    file_path=$1
    pattern=$2
    attempts=${3:-20}
    sleep_interval=${4:-0.1}

    count=0
    while [ "$count" -lt "$attempts" ]; do
      if [ -f "$file_path" ] && grep -F -- "$pattern" "$file_path" >/dev/null 2>&1; then
        return 0
      fi
      sleep "$sleep_interval"
      count=$((count + 1))
    done
    return 1
  }

  bus_spec_verify_registry() {
    zshmq_cli bus --path "$ZSHMQ_CTX_ROOT" new >/dev/null 2>&1 || return 1
    tab=$(printf '\t')
    if ! grep -F "bus${tab}" "$ZSHMQ_CTX_ROOT/topics.reg" >/dev/null 2>&1; then
      return 1
    fi
    return 0
  }

  BeforeEach 'bus_before_each'
  AfterEach 'bus_after_each'

  It 'provisions the bus topic and registry entry'
    When call bus_spec_verify_registry
    The status should be success
    The path "$ZSHMQ_CTX_ROOT/bus.fifo" should be pipe
    The path "$ZSHMQ_CTX_ROOT/bus.state" should be file
  End
  It 'records topic regex entries in the registry file'
    tab=$(printf '\t')
    When call zshmq_cli topic --path "$ZSHMQ_CTX_ROOT" new -T alerts --regex '^ALERT'
    The status should be success
    The file "$ZSHMQ_CTX_ROOT/topics.reg" should be file
    The contents of file "$ZSHMQ_CTX_ROOT/topics.reg" should include "alerts${tab}^ALERT"
  End
End
