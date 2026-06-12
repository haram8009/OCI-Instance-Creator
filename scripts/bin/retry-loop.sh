#!/usr/bin/env bash
set -Eeuo pipefail

APP_HOME="${APP_HOME:-/app}"

source "$APP_HOME/scripts/lib/config.sh"
source "$APP_HOME/scripts/lib/logging.sh"
source "$APP_HOME/scripts/lib/discord.sh"
source "$APP_HOME/scripts/lib/job-log.sh"

load_config
init_logging

send_or_exit() {
  if send_discord_event "$@"; then
    return 0
  fi

  if discord_required; then
    log_error "Stopping because Discord delivery is required."
    exit 70
  fi

  return 0
}

retry_label() {
  if [ "$1" = "none" ]; then
    printf 'none'
  else
    printf '%ss' "$1"
  fi
}

attempt=1

start_fields="$(
  jq -n \
    --arg stack "$OCI_STACK_ID" \
    --arg run "$RUN_ID" \
    --arg retry "${RETRY_INTERVAL_SECONDS}s" \
    --arg maxAttempts "$MAX_ATTEMPTS" \
    --arg maxWait "${MAX_WAIT_SECONDS}s" \
    --arg log "$RUN_DIR" \
    '[
      {name: "Stack OCID", value: $stack, inline: false},
      {name: "Run ID", value: $run, inline: true},
      {name: "Retry interval", value: $retry, inline: true},
      {name: "Max attempts", value: $maxAttempts, inline: true},
      {name: "Max wait per apply", value: $maxWait, inline: true},
      {name: "Log path", value: $log, inline: false}
    ]'
)"

log_info "OCI A1 retry started. run_id=$RUN_ID stack=$OCI_STACK_ID"
send_or_exit "start" "🔁 OCI A1 retry started" 3447003 "The retry loop is active." "$start_fields" 0

while true; do
  summary_file="$RUN_DIR/attempts/attempt-$attempt/summary.json"
  APPLY_RESULT_FILE="$summary_file" ATTEMPT_NUMBER="$attempt" "$APP_HOME/scripts/bin/apply-once.sh" >/dev/null

  command_exit_code="$(jq -r '.command_exit_code' "$summary_file")"
  state="$(jq -r '.state' "$summary_file")"
  job_id="$(jq -r '.job_id' "$summary_file")"
  err_file="$(jq -r '.err_file' "$summary_file")"
  out_file="$(jq -r '.out_file' "$summary_file")"
  job_log_file="$(jq -r '.job_log_file' "$summary_file")"
  normalized_job_log_file="$(jq -r '.normalized_job_log_file' "$summary_file")"
  attempt_dir="$(jq -r '.attempt_dir' "$summary_file")"

  next_retry="$RETRY_INTERVAL_SECONDS"
  if [ "$MAX_ATTEMPTS" -gt 0 ] && [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    next_retry="none"
  fi

  fields="$(common_fields_json "$attempt" "$state" "$job_id" "$(retry_label "$next_retry")" "$attempt_dir")"

  if [ "$command_exit_code" -ne 0 ]; then
    detail="$(extract_oci_error_message "$err_file")"
    if [ -z "$detail" ]; then
      detail="OCI CLI command failed."
    fi
    log_error "OCI apply command failed. attempt=$attempt exit_code=$command_exit_code"
    send_or_exit "command-failed" "⚠️ OCI apply command failed" 15158332 "$detail" "$fields" "$attempt" "@here"
  elif [ "$state" = "SUCCEEDED" ]; then
    log_info "OCI Stack Apply succeeded. attempt=$attempt job_id=$job_id"
    send_or_exit "success" "✅ OCI Stack Apply succeeded" 3066993 "Apply succeeded." "$fields" "$attempt" "@here"
    exit 0
  else
    detail=""
    if [ -s "$normalized_job_log_file" ]; then
      detail="$(job_log_summary_line "$normalized_job_log_file" "$JOB_LOG_TAIL_CHARS")"
    elif [ -s "$err_file" ]; then
      detail="$(extract_oci_error_message "$err_file")"
      if [ -z "$detail" ]; then
        detail="OCI CLI stderr available."
      fi
    elif [ -s "$out_file" ]; then
      detail="$(job_log_summary_line "$out_file" "$JOB_LOG_TAIL_CHARS")"
      if [ -z "$detail" ]; then
        detail="OCI CLI output available."
      fi
    fi

    log_warn "OCI Stack Apply did not succeed. attempt=$attempt state=$state job_id=$job_id"
    if [ -z "$detail" ]; then
      detail="OCI Stack Apply did not succeed."
    fi
    send_or_exit "apply-failed" "❌ OCI Stack Apply did not succeed" 15105570 "$detail" "$fields" "$attempt"
  fi

  if [ "$MAX_ATTEMPTS" -gt 0 ] && [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    stop_fields="$(common_fields_json "$attempt" "$state" "$job_id" "none" "$RUN_DIR")"
    log_error "Max attempts reached. max_attempts=$MAX_ATTEMPTS"
    send_or_exit "max-attempts-reached" "🛑 OCI A1 retry stopped" 10038562 "Last attempt failed with state $state." "$stop_fields" "$attempt" "@here"
    exit 1
  fi

  attempt=$((attempt + 1))
  log_info "Sleeping before next retry. seconds=$RETRY_INTERVAL_SECONDS next_attempt=$attempt"
  sleep "$RETRY_INTERVAL_SECONDS"
done
