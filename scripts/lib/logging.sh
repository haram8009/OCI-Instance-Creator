#!/usr/bin/env bash

init_logging() {
  mkdir -p "$RUN_DIR" "$RUN_DIR/attempts" "$RUN_DIR/discord" "$RUN_DIR/discord/unsent"
  touch "$LOG_FILE"
  ln -sfn "runs/$RUN_ID/retry.log" "$LOG_DIR/latest.log"
  cleanup_old_logs
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

cleanup_old_logs() {
  local runs_dir="$LOG_DIR/runs"
  local dir
  local count

  if [ "${LOG_CLEANUP_ENABLED:-true}" != "true" ] || [ ! -d "$runs_dir" ]; then
    return 0
  fi

  if [ "${LOG_RETENTION_DAYS:-0}" -gt 0 ]; then
    find "$runs_dir" -mindepth 1 -maxdepth 1 -type d -mtime +"$LOG_RETENTION_DAYS" \
      ! -name "$RUN_ID" -exec rm -rf {} +
  fi

  if [ "${LOG_RETENTION_RUNS:-0}" -eq 0 ]; then
    return 0
  fi

  if ! ls "$runs_dir"/* >/dev/null 2>&1; then
    return 0
  fi

  count=0
  for dir in $(ls -1dt "$runs_dir"/* 2>/dev/null); do
    if [ ! -d "$dir" ]; then
      continue
    fi
    if [ "$(basename "$dir")" = "$RUN_ID" ]; then
      continue
    fi

    count=$((count + 1))
    if [ "$count" -gt "$LOG_RETENTION_RUNS" ]; then
      rm -rf "$dir"
    fi
  done
}
