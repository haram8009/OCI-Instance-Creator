#!/usr/bin/env bash

init_logging() {
  mkdir -p "$RUN_DIR" "$RUN_DIR/attempts" "$RUN_DIR/discord" "$RUN_DIR/discord/unsent"
  touch "$LOG_FILE"
  ln -sfn "runs/$RUN_ID/retry.log" "$LOG_DIR/latest.log"
}

log_line() {
  local level="$1"
  local message="$2"
  local timestamp

  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" | tee -a "$LOG_FILE"
}

log_info() {
  log_line "INFO" "$1"
}

log_warn() {
  log_line "WARN" "$1"
}

log_error() {
  log_line "ERROR" "$1"
}

shorten_text() {
  local input="$1"
  local max_chars="$2"

  printf '%s' "$input" | head -c "$max_chars"
}
