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
    pause)
      log_warn "Pause requested through control command."
      write_status "paused" "${attempt:-0}" "PAUSED" "${job_id:-unknown}" "paused"
      wait_until_resumed
      ;;
    resume)
      log_warn "Resume requested through control command."
      clear_control_command
      write_status "running" "${attempt:-0}" "RESUMED" "${job_id:-unknown}" "unknown"
      ;;
    stop)
      log_warn "Stop requested through control command."
      write_status "stopped" "${attempt:-0}" "STOPPED" "${job_id:-unknown}" "none"
      exit 75
      ;;
    restart)
      log_warn "Restart requested through control command."
      write_status "restarting" "${attempt:-0}" "RESTART_REQUESTED" "unknown" "none"
      exit 76
      ;;
    shutdown)
      log_warn "Shutdown requested through control command."
      write_status "shutting-down" "${attempt:-0}" "SHUTDOWN_REQUESTED" "${job_id:-unknown}" "none"
      exit 77
      ;;
  esac
}

wait_until_resumed() {
  local command

  while true; do
    command="$(control_command)"
    case "$command" in
      resume)
        log_warn "Resume requested through control command."
        clear_control_command
        write_status "running" "${attempt:-0}" "RESUMED" "${job_id:-unknown}" "unknown"
        return 0
        ;;
      stop)
        log_warn "Stop requested through control command while paused."
        write_status "stopped" "${attempt:-0}" "STOPPED" "${job_id:-unknown}" "none"
        exit 75
        ;;
      restart)
        log_warn "Restart requested through control command while paused."
        write_status "restarting" "${attempt:-0}" "RESTART_REQUESTED" "unknown" "none"
        exit 76
        ;;
      shutdown)
        log_warn "Shutdown requested through control command while paused."
        write_status "shutting-down" "${attempt:-0}" "SHUTDOWN_REQUESTED" "${job_id:-unknown}" "none"
        exit 77
        ;;
    esac

    sleep 5
  done
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
