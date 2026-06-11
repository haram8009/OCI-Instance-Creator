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
  printf 'fake terraform log tail\n'
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

  if [ ! -s "$case_dir/logs/runs/test-$scenario/retry.log" ]; then
    echo "Missing preserved retry log for $scenario" >&2
    return 1
  fi
}

run_case success 0 "OCI Stack Apply succeeded"
run_case failed 1 "OCI Stack Apply did not succeed"
run_case command_failed 1 "OCI apply command failed"

echo "Smoke tests passed."
