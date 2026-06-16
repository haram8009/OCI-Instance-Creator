#!/usr/bin/env bash
set -Eeuo pipefail

APP_HOME="${APP_HOME:-/app}"

source "$APP_HOME/scripts/lib/config.sh"
source "$APP_HOME/scripts/lib/control.sh"

load_config
init_control

child_pid=""
bot_pid=""

stop_process() {
  local pid="$1"

  if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
  fi
}

shutdown() {
  stop_process "$child_pid"
  stop_process "$bot_pid"
  exit 143
}

start_bot() {
  if [ "$DISCORD_BOT_ENABLED" != "true" ]; then
    return 0
  fi

  python "$APP_HOME/scripts/bin/discord-control-bot.py" &
  bot_pid="$!"
  echo "Discord control bot started. pid=$bot_pid"
}

trap shutdown INT TERM

start_bot

while true; do
  clear_control_command
  child_run_id="$(date -u '+%Y%m%d-%H%M%S')"

  echo "Starting retry loop. run_id=$child_run_id"
  set +e
  RUN_ID="$child_run_id" "$APP_HOME/scripts/bin/retry-loop.sh" &
  child_pid="$!"
  wait "$child_pid"
  exit_code="$?"
  child_pid=""
  set -e

  case "$exit_code" in
    75)
      echo "Retry loop stopped by control command."
      exit 0
      ;;
    76)
      echo "Retry loop restarting by control command."
      sleep 1
      ;;
    *)
      exit "$exit_code"
      ;;
  esac
done
