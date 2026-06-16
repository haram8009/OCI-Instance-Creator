#!/usr/bin/env bash

init_control() {
  mkdir -p "$CONTROL_DIR"
}

clear_control_command() {
  rm -f "$CONTROL_COMMAND_FILE"
}

control_command() {
  if [ ! -s "$CONTROL_COMMAND_FILE" ]; then
    return 0
  fi

  jq -r '.command // ""' "$CONTROL_COMMAND_FILE" 2>/dev/null || true
}

write_status() {
  local phase="$1"
  local attempt="${2:-0}"
  local state="${3:-UNKNOWN}"
  local job_id="${4:-unknown}"
  local next_retry="${5:-unknown}"

  mkdir -p "$CONTROL_DIR"

  jq -n \
    --arg run "$RUN_ID" \
    --arg phase "$phase" \
    --arg attempt "$attempt" \
    --arg state "$state" \
    --arg job "$job_id" \
    --arg next "$next_retry" \
    --arg log "$RUN_DIR" \
    '{
      run_id: $run,
      phase: $phase,
      attempt: ($attempt | tonumber),
      state: $state,
      job_id: $job,
      next_retry: $next,
      log_path: $log,
      updated_at: (now | todateiso8601)
    }' > "$STATUS_FILE.tmp"
  mv "$STATUS_FILE.tmp" "$STATUS_FILE"
}

handle_control_command() {
  local command

  command="$(control_command)"
  case "$command" in
    stop)
      log_warn "Stop requested through control command."
      write_status "stopping" "${attempt:-0}" "STOP_REQUESTED" "unknown" "none"
      exit 75
      ;;
    restart)
      log_warn "Restart requested through control command."
      write_status "restarting" "${attempt:-0}" "RESTART_REQUESTED" "unknown" "none"
      exit 76
      ;;
  esac
}

sleep_with_control() {
  local remaining="$1"
  local chunk

  while [ "$remaining" -gt 0 ]; do
    handle_control_command
    chunk=5
    if [ "$remaining" -lt "$chunk" ]; then
      chunk="$remaining"
    fi
    sleep "$chunk"
    remaining=$((remaining - chunk))
  done

  handle_control_command
}
