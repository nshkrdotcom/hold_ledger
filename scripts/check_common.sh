# Shared implementation for check_*.sh; source this file, do not execute it.
check_main() {
  check_mode=$1
  shift
  check_quiet=false
  check_options=()
  while (( $# )); do
    case "$1" in
      --quiet) check_quiet=true; shift ;;
      --jobs)
        if [[ ${2:-} =~ ^[1-9][0-9]*$ ]]; then
          check_options+=(--jobs "$2")
          shift 2
        else
          echo "--jobs requires a positive integer" >&2
          exit 2
        fi
        ;;
      -h|--help)
        echo "Usage: $0 [--quiet] [--jobs N]"
        echo "Run $check_mode checks with automatic CPU/memory limits."
        echo "Log all output under /tmp; --quiet hides live output."
        exit 0
        ;;
      *) echo "Usage: $0 [--quiet] [--jobs N]" >&2; exit 2 ;;
    esac
  done
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
  check_log_path=$(mktemp "/tmp/hold-ledger-check-${check_mode}.XXXXXXXX.log")
  echo "Check log: $check_log_path" >&2
  trap check_finish EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  check_pid=
  check_tee_pid=
  check_pipe_dir=
  if "$check_quiet"; then
    check_execute >>"$check_log_path" 2>&1 &
    check_pid=$!
  else
    check_pipe_dir=$(mktemp -d /tmp/hold-ledger-check-pipe.XXXXXXXX)
    mkfifo "$check_pipe_dir/output"
    tee -a "$check_log_path" <"$check_pipe_dir/output" &
    check_tee_pid=$!
    check_execute >"$check_pipe_dir/output" 2>&1 &
    check_pid=$!
  fi
  wait "$check_pid"
}

check_execute() {
  uv run --no-sync python scripts/check_suite.py "$check_mode" "${check_options[@]}"
}

check_finish() {
  check_status=$?
  trap - EXIT
  trap '' INT TERM
  if [[ -n ${check_pid:-} ]] && kill -0 "$check_pid" 2>/dev/null; then
    python3 - "$check_pid" "$PWD/scripts" <<'PYTHON'
import sys
sys.path.insert(0, sys.argv[2])
from check_runtime import stop_tree
stop_tree(int(sys.argv[1]))
PYTHON
    wait "$check_pid" 2>/dev/null || true
  fi
  if [[ -n ${check_tee_pid:-} ]]; then
    if wait "$check_tee_pid"; then :; elif (( check_status == 0 )); then check_status=1; fi
  fi
  if [[ -n ${check_pipe_dir:-} ]]; then rm -rf -- "$check_pipe_dir"; fi
  printf '\nChecks finished (exit %s). Log: %s\n' "$check_status" "$check_log_path" |
    tee -a "$check_log_path" >&2
  exit "$check_status"
}
