#!/usr/bin/env bash
set -Eeuo pipefail

APP_HOME="${APP_HOME:-/app}"

source "$APP_HOME/scripts/lib/config.sh"
source "$APP_HOME/scripts/lib/logging.sh"
source "$APP_HOME/scripts/lib/job-log.sh"

load_config

ATTEMPT_NUMBER="${ATTEMPT_NUMBER:-1}"
ATTEMPT_DIR="$RUN_DIR/attempts/attempt-$ATTEMPT_NUMBER"
SUMMARY_FILE="${APPLY_RESULT_FILE:-$ATTEMPT_DIR/summary.json}"
OUT_FILE="$ATTEMPT_DIR/oci-create-apply-job.out.json"
ERR_FILE="$ATTEMPT_DIR/oci-create-apply-job.err.log"
JOB_LOG_FILE="$ATTEMPT_DIR/oci-job.log"
NORMALIZED_JOB_LOG_FILE="$ATTEMPT_DIR/oci-job.normalized.log"

mkdir -p "$ATTEMPT_DIR"

STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
DISPLAY_NAME="auto-a1-apply-$RUN_ID-attempt-$ATTEMPT_NUMBER"

log_info "Starting OCI apply attempt. attempt=$ATTEMPT_NUMBER display_name=$DISPLAY_NAME"

OCI_ARGS=(
  resource-manager job create-apply-job
  --stack-id "$OCI_STACK_ID"
  --execution-plan-strategy AUTO_APPROVED
  --display-name "$DISPLAY_NAME"
  --wait-for-state SUCCEEDED
  --wait-for-state FAILED
  --wait-for-state CANCELED
  --max-wait-seconds "$MAX_WAIT_SECONDS"
  --profile "$OCI_CONFIG_PROFILE"
)

if [ -n "$OCI_CLI_EXTRA_ARGS" ]; then
  read -r -a EXTRA_ARGS <<< "$OCI_CLI_EXTRA_ARGS"
  OCI_ARGS+=("${EXTRA_ARGS[@]}")
fi

set +e
oci "${OCI_ARGS[@]}" >"$OUT_FILE" 2>"$ERR_FILE"
OCI_EXIT_CODE=$?
set -e

FINISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
STATE="COMMAND_FAILED"
JOB_ID="unknown"

if [ "$OCI_EXIT_CODE" -eq 0 ]; then
  STATE="$(jq -r '.data."lifecycle-state" // "UNKNOWN"' "$OUT_FILE")"
  JOB_ID="$(jq -r '.data.id // "unknown"' "$OUT_FILE")"
fi

if [ "$JOB_LOG_FETCH_ENABLED" = "true" ] && [ "$JOB_ID" != "unknown" ]; then
  LOG_ARGS=(
    resource-manager job get-job-logs-content
    --job-id "$JOB_ID"
    --profile "$OCI_CONFIG_PROFILE"
  )

  if [ -n "$OCI_CLI_EXTRA_ARGS" ]; then
    LOG_ARGS+=("${EXTRA_ARGS[@]}")
  fi

  if ! oci "${LOG_ARGS[@]}" >"$JOB_LOG_FILE" 2>>"$ERR_FILE"; then
    log_warn "Could not fetch OCI job log. job_id=$JOB_ID"
  fi

  if [ -s "$JOB_LOG_FILE" ]; then
    normalize_job_log_file "$JOB_LOG_FILE" "$NORMALIZED_JOB_LOG_FILE"
  fi
fi

jq -n \
  --arg attempt "$ATTEMPT_NUMBER" \
  --arg displayName "$DISPLAY_NAME" \
  --arg startedAt "$STARTED_AT" \
  --arg finishedAt "$FINISHED_AT" \
  --arg state "$STATE" \
  --arg jobId "$JOB_ID" \
  --arg outFile "$OUT_FILE" \
  --arg errFile "$ERR_FILE" \
  --arg jobLogFile "$JOB_LOG_FILE" \
  --arg normalizedJobLogFile "$NORMALIZED_JOB_LOG_FILE" \
  --arg attemptDir "$ATTEMPT_DIR" \
  --argjson exitCode "$OCI_EXIT_CODE" \
  '{
    attempt: ($attempt | tonumber),
    display_name: $displayName,
    started_at: $startedAt,
    finished_at: $finishedAt,
    command_exit_code: $exitCode,
    state: $state,
    job_id: $jobId,
    out_file: $outFile,
    err_file: $errFile,
    job_log_file: $jobLogFile,
    normalized_job_log_file: $normalizedJobLogFile,
    attempt_dir: $attemptDir
  }' > "$SUMMARY_FILE"

log_info "OCI apply attempt finished. attempt=$ATTEMPT_NUMBER exit_code=$OCI_EXIT_CODE state=$STATE job_id=$JOB_ID"

printf '%s\n' "$SUMMARY_FILE"
