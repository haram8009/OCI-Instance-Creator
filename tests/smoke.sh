#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/bin"
CAPTURE_DIR="$TMP_DIR/discord"

mkdir -p "$FAKE_BIN" "$CAPTURE_DIR"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

cat > "$FAKE_BIN/curl" <<'FAKE_CURL'
#!/usr/bin/env bash
set -Eeuo pipefail

payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -d)
      payload="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

count_file="$TEST_CAPTURE_DIR/count"
count=0
if [ -f "$count_file" ]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s' "$count" > "$count_file"
printf '%s\n' "$payload" > "$TEST_CAPTURE_DIR/payload-$count.json"
FAKE_CURL

cat > "$FAKE_BIN/oci" <<'FAKE_OCI'
#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$1 $2 $3" = "resource-manager job get-job-logs-content" ]; then
  jq -n --arg data 'Terraform v1.5.7\non: 8.18.0, released on 2026-06-10.\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] Service: Core Instance\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] Operation Name: LaunchInstance\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] OPC request ID: fake-request-id\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] Error: Out of host capacity.\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] with oci_core_instance.generated_oci_core_instance,\n2026/06/11 09:42:03[TERRAFORM_CONSOLE] [INFO] on main.tf line 3, in resource "oci_core_instance" "generated_oci_core_instance":' '{data: $data}'
  exit 0
fi

case "${FAKE_OCI_SCENARIO:-success}" in
  success)
    jq -n '{data: {"lifecycle-state": "SUCCEEDED", id: "ocid1.ormjob.oc1..success"}}'
    ;;
  failed)
    printf 'fake capacity error\n' >&2
    jq -n '{data: {"lifecycle-state": "FAILED", id: "ocid1.ormjob.oc1..failed"}}'
    ;;
  command_failed)
    printf 'fake auth failure\n' >&2
    exit 13
    ;;
  *)
    printf 'unknown fake scenario\n' >&2
    exit 99
    ;;
esac
FAKE_OCI

cat > "$FAKE_BIN/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
exit 0
FAKE_SLEEP

chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/oci" "$FAKE_BIN/sleep"

run_case() {
  local scenario="$1"
  local expected_exit="$2"
  local expected_title="$3"
  local expected_description="$4"
  local expected_stop_description="${5:-}"
  local case_dir="$TMP_DIR/$scenario"

  mkdir -p "$case_dir/logs" "$case_dir/discord"
  set +e
  TEST_CAPTURE_DIR="$case_dir/discord" \
    PATH="$FAKE_BIN:$PATH" \
    APP_HOME="$ROOT_DIR" \
    OCI_STACK_ID="ocid1.ormstack.oc1.ap-osaka-1.test" \
    OCI_CONFIG_PROFILE="DEFAULT" \
    DISCORD_WEBHOOK_URL="https://discord.example/webhook" \
    DISCORD_DELIVERY_ATTEMPTS="1" \
    DISCORD_DELIVERY_RETRY_SECONDS="0" \
    RETRY_INTERVAL_SECONDS="0" \
    MAX_WAIT_SECONDS="1" \
    MAX_ATTEMPTS="1" \
    LOG_DIR="$case_dir/logs" \
    CONTROL_DIR="$case_dir/control" \
    RUN_ID="test-$scenario" \
    FAKE_OCI_SCENARIO="$scenario" \
    JOB_LOG_FETCH_ENABLED="true" \
    "$ROOT_DIR/scripts/bin/retry-loop.sh"
  actual_exit=$?
  set -e

  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "Expected exit $expected_exit for $scenario, got $actual_exit" >&2
    return 1
  fi

  if ! jq -r '.embeds[0].title' "$case_dir"/discord/payload-*.json | grep -Fqx "$expected_title"; then
    echo "Missing Discord title '$expected_title' for $scenario" >&2
    return 1
  fi

  if ! jq -r \
      --arg title "$expected_title" \
      'select(.embeds[0].title == $title) | .embeds[0].description' \
      "$case_dir"/discord/payload-*.json | grep -Fqx "$expected_description"; then
    echo "Missing Discord description '$expected_description' for $scenario" >&2
    return 1
  fi

  if [ "$scenario" != "failed" ]; then
    if ! jq -r \
        --arg title "$expected_title" \
        'select(.embeds[0].title == $title) | (.content // "")' \
        "$case_dir"/discord/payload-*.json | grep -Fxq '@here'; then
      echo "Missing @here mention for '$expected_title' in $scenario" >&2
      return 1
    fi
  fi

  if [ -n "$expected_stop_description" ]; then
    if ! jq -r \
        'select(.embeds[0].title == "🛑 OCI A1 retry stopped") | .embeds[0].description' \
        "$case_dir"/discord/payload-*.json | grep -Fqx "$expected_stop_description"; then
      echo "Missing max-attempts description '$expected_stop_description' for $scenario" >&2
      return 1
    fi

    if ! jq -r \
        'select(.embeds[0].title == "🛑 OCI A1 retry stopped") | (.content // "")' \
        "$case_dir"/discord/payload-*.json | grep -Fxq '@here'; then
      echo "Missing @here mention for max-attempts stop in $scenario" >&2
      return 1
    fi
  fi

  if [ ! -s "$case_dir/logs/runs/test-$scenario/retry.log" ]; then
    echo "Missing preserved retry log for $scenario" >&2
    return 1
  fi

  if [ ! -s "$case_dir/control/status.json" ]; then
    echo "Missing status file for $scenario" >&2
    return 1
  fi
}

run_log_cleanup_case() {
  local case_dir="$TMP_DIR/log-cleanup"

  mkdir -p "$case_dir/logs/runs/old-1" "$case_dir/logs/runs/old-2" "$case_dir/logs/runs/old-3" "$case_dir/discord"
  touch "$case_dir/logs/runs/old-1/retry.log"
  touch "$case_dir/logs/runs/old-1"
  sleep 1
  touch "$case_dir/logs/runs/old-2/retry.log"
  touch "$case_dir/logs/runs/old-2"
  sleep 1
  touch "$case_dir/logs/runs/old-3/retry.log"
  touch "$case_dir/logs/runs/old-3"

  set +e
  TEST_CAPTURE_DIR="$case_dir/discord" \
    PATH="$FAKE_BIN:$PATH" \
    APP_HOME="$ROOT_DIR" \
    OCI_STACK_ID="ocid1.ormstack.oc1.ap-osaka-1.test" \
    OCI_CONFIG_PROFILE="DEFAULT" \
    DISCORD_WEBHOOK_URL="https://discord.example/webhook" \
    DISCORD_DELIVERY_ATTEMPTS="1" \
    DISCORD_DELIVERY_RETRY_SECONDS="0" \
    RETRY_INTERVAL_SECONDS="0" \
    MAX_WAIT_SECONDS="1" \
    MAX_ATTEMPTS="1" \
    LOG_DIR="$case_dir/logs" \
    LOG_RETENTION_RUNS="1" \
    LOG_RETENTION_DAYS="0" \
    CONTROL_DIR="$case_dir/control" \
    RUN_ID="test-log-cleanup" \
    FAKE_OCI_SCENARIO="success" \
    JOB_LOG_FETCH_ENABLED="true" \
    "$ROOT_DIR/scripts/bin/retry-loop.sh"
  actual_exit=$?
  set -e

  if [ "$actual_exit" -ne 0 ]; then
    echo "Expected log cleanup case to succeed, got $actual_exit" >&2
    return 1
  fi

  remaining_old_runs="$(find "$case_dir/logs/runs" -maxdepth 1 -type d -name 'old-*' | wc -l | tr -d ' ')"
  if [ "$remaining_old_runs" -gt 1 ]; then
    echo "Expected log cleanup to keep at most one old run, kept $remaining_old_runs" >&2
    return 1
  fi
}

run_control_pause_resume_case() {
  local case_dir="$TMP_DIR/control-pause-resume"

  mkdir -p "$case_dir/control" "$case_dir/logs"
  jq -n '{command: "pause"}' > "$case_dir/control/command.json"

  (
    PATH="$FAKE_BIN:$PATH"
    APP_HOME="$ROOT_DIR"
    OCI_STACK_ID="ocid1.ormstack.oc1.ap-osaka-1.test"
    DISCORD_WEBHOOK_URL="https://discord.example/webhook"
    CONTROL_DIR="$case_dir/control"
    LOG_DIR="$case_dir/logs"
    RUN_ID="test-control-pause-resume"
    source "$ROOT_DIR/scripts/lib/config.sh"
    source "$ROOT_DIR/scripts/lib/control.sh"

    log_warn() {
      :
    }

    load_config
    init_control
    attempt=2

    (
      /bin/sleep 0.2
      jq -n '{command: "resume"}' > "$case_dir/control/command.json"
    ) &
    resume_pid="$!"

    handle_control_command
    wait "$resume_pid"
  )

  if [ -e "$case_dir/control/command.json" ]; then
    echo "Expected resume to clear pause command" >&2
    return 1
  fi

  if ! jq -e '.phase == "running" and .state == "RESUMED"' "$case_dir/control/status.json" >/dev/null; then
    echo "Expected pause/resume status to end as RESUMED" >&2
    return 1
  fi
}

run_control_stop_case() {
  local case_dir="$TMP_DIR/control-stop"
  local actual_exit

  mkdir -p "$case_dir/control" "$case_dir/logs"
  jq -n '{command: "stop"}' > "$case_dir/control/command.json"

  set +e
  (
    PATH="$FAKE_BIN:$PATH"
    APP_HOME="$ROOT_DIR"
    OCI_STACK_ID="ocid1.ormstack.oc1.ap-osaka-1.test"
    DISCORD_WEBHOOK_URL="https://discord.example/webhook"
    CONTROL_DIR="$case_dir/control"
    LOG_DIR="$case_dir/logs"
    RUN_ID="test-control-stop"
    source "$ROOT_DIR/scripts/lib/config.sh"
    source "$ROOT_DIR/scripts/lib/control.sh"

    log_warn() {
      :
    }

    load_config
    init_control
    attempt=2
    handle_control_command
  )
  actual_exit=$?
  set -e

  if [ "$actual_exit" -ne 75 ]; then
    echo "Expected stop control to exit 75, got $actual_exit" >&2
    return 1
  fi

  if ! jq -e '.phase == "stopped" and .state == "STOPPED"' "$case_dir/control/status.json" >/dev/null; then
    echo "Expected stop control to write STOPPED status" >&2
    return 1
  fi
}

run_control_shutdown_case() {
  local case_dir="$TMP_DIR/control-shutdown"
  local actual_exit

  mkdir -p "$case_dir/control" "$case_dir/logs"
  jq -n '{command: "shutdown"}' > "$case_dir/control/command.json"

  set +e
  (
    PATH="$FAKE_BIN:$PATH"
    APP_HOME="$ROOT_DIR"
    OCI_STACK_ID="ocid1.ormstack.oc1.ap-osaka-1.test"
    DISCORD_WEBHOOK_URL="https://discord.example/webhook"
    CONTROL_DIR="$case_dir/control"
    LOG_DIR="$case_dir/logs"
    RUN_ID="test-control-shutdown"
    source "$ROOT_DIR/scripts/lib/config.sh"
    source "$ROOT_DIR/scripts/lib/control.sh"

    log_warn() {
      :
    }

    load_config
    init_control
    attempt=2
    handle_control_command
  )
  actual_exit=$?
  set -e

  if [ "$actual_exit" -ne 77 ]; then
    echo "Expected shutdown control to exit 77, got $actual_exit" >&2
    return 1
  fi

  if ! jq -e '.phase == "shutting-down" and .state == "SHUTDOWN_REQUESTED"' "$case_dir/control/status.json" >/dev/null; then
    echo "Expected shutdown control to write SHUTDOWN_REQUESTED status" >&2
    return 1
  fi
}

run_case success 0 "✅ OCI Stack Apply succeeded" "Apply succeeded."
run_case failed 1 "❌ OCI Stack Apply did not succeed" "Error: Out of host capacity." "Last attempt failed with state FAILED."
run_case command_failed 1 "⚠️ OCI apply command failed" "fake auth failure" "Last attempt failed with state COMMAND_FAILED."
run_log_cleanup_case
run_control_pause_resume_case
run_control_stop_case
run_control_shutdown_case

echo "Smoke tests passed."
