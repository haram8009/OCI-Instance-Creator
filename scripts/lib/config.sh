#!/usr/bin/env bash

require_env() {
  local name="$1"

  if [ -z "${!name:-}" ]; then
    echo "$name is required" >&2
    exit 64
  fi
}

is_non_negative_int() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]]
}

is_positive_int() {
  local value="$1"
  [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

validate_int_env() {
  local name="$1"
  local value="${!name:-}"
  local mode="$2"

  if { [ "$mode" = "positive" ] && ! is_positive_int "$value"; } \
    || { [ "$mode" = "non_negative" ] && ! is_non_negative_int "$value"; }; then
    echo "$name must be a $mode integer. Got: $value" >&2
    exit 64
  fi
}

load_config() {
  require_env OCI_STACK_ID
  require_env DISCORD_WEBHOOK_URL

  OCI_CONFIG_PROFILE="${OCI_CONFIG_PROFILE:-DEFAULT}"
  DISCORD_USERNAME="${DISCORD_USERNAME:-OCI A1 Retry}"
  DISCORD_DELIVERY_REQUIRED="${DISCORD_DELIVERY_REQUIRED:-true}"
  DISCORD_DELIVERY_ATTEMPTS="${DISCORD_DELIVERY_ATTEMPTS:-5}"
  DISCORD_DELIVERY_RETRY_SECONDS="${DISCORD_DELIVERY_RETRY_SECONDS:-5}"
  DISCORD_BOT_ENABLED="${DISCORD_BOT_ENABLED:-false}"
  DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
  DISCORD_GUILD_ID="${DISCORD_GUILD_ID:-}"
  DISCORD_ALLOWED_USER_IDS="${DISCORD_ALLOWED_USER_IDS:-}"
  DISCORD_ALLOWED_ROLE_IDS="${DISCORD_ALLOWED_ROLE_IDS:-}"
  RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-1800}"
  MAX_WAIT_SECONDS="${MAX_WAIT_SECONDS:-1800}"
  MAX_ATTEMPTS="${MAX_ATTEMPTS:-0}"
  LOG_DIR="${LOG_DIR:-/app/logs}"
  LOG_CLEANUP_ENABLED="${LOG_CLEANUP_ENABLED:-true}"
  LOG_RETENTION_RUNS="${LOG_RETENTION_RUNS:-50}"
  LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
  CONTROL_DIR="${CONTROL_DIR:-/app/control}"
  JOB_LOG_FETCH_ENABLED="${JOB_LOG_FETCH_ENABLED:-true}"
  JOB_LOG_TAIL_CHARS="${JOB_LOG_TAIL_CHARS:-900}"
  OCI_CLI_EXTRA_ARGS="${OCI_CLI_EXTRA_ARGS:-}"
  RUN_ID="${RUN_ID:-$(date -u '+%Y%m%d-%H%M%S')}"

  validate_int_env DISCORD_DELIVERY_ATTEMPTS positive
  validate_int_env DISCORD_DELIVERY_RETRY_SECONDS non_negative
  validate_int_env RETRY_INTERVAL_SECONDS non_negative
  validate_int_env MAX_WAIT_SECONDS positive
  validate_int_env MAX_ATTEMPTS non_negative
  validate_int_env LOG_RETENTION_RUNS non_negative
  validate_int_env LOG_RETENTION_DAYS non_negative
  validate_int_env JOB_LOG_TAIL_CHARS positive

  if [ "$DISCORD_BOT_ENABLED" = "true" ] && [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo "DISCORD_BOT_TOKEN is required when DISCORD_BOT_ENABLED=true" >&2
    exit 64
  fi

  export OCI_CONFIG_PROFILE
  export DISCORD_USERNAME
  export DISCORD_DELIVERY_REQUIRED
  export DISCORD_DELIVERY_ATTEMPTS
  export DISCORD_DELIVERY_RETRY_SECONDS
  export DISCORD_BOT_ENABLED
  export DISCORD_BOT_TOKEN
  export DISCORD_GUILD_ID
  export DISCORD_ALLOWED_USER_IDS
  export DISCORD_ALLOWED_ROLE_IDS
  export RETRY_INTERVAL_SECONDS
  export MAX_WAIT_SECONDS
  export MAX_ATTEMPTS
  export LOG_DIR
  export LOG_CLEANUP_ENABLED
  export LOG_RETENTION_RUNS
  export LOG_RETENTION_DAYS
  export CONTROL_DIR
  export JOB_LOG_FETCH_ENABLED
  export JOB_LOG_TAIL_CHARS
  export OCI_CLI_EXTRA_ARGS
  export RUN_ID
  export RUN_DIR="$LOG_DIR/runs/$RUN_ID"
  export LOG_FILE="$RUN_DIR/retry.log"
  export CONTROL_COMMAND_FILE="$CONTROL_DIR/command.json"
  export STATUS_FILE="$CONTROL_DIR/status.json"
}
