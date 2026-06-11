#!/usr/bin/env bash

discord_required() {
  [ "${DISCORD_DELIVERY_REQUIRED:-true}" = "true" ]
}

discord_payload_file() {
  local event_name="$1"
  local attempt_number="${2:-0}"
  local timestamp

  timestamp="$(date -u '+%Y%m%d-%H%M%S')"
  printf '%s/discord/%s-attempt-%s-%s.json' "$RUN_DIR" "$timestamp" "$attempt_number" "$event_name"
}

send_discord_payload() {
  local payload="$1"
  local payload_file="$2"
  local attempt=1

  printf '%s\n' "$payload" > "$payload_file"

  while [ "$attempt" -le "$DISCORD_DELIVERY_ATTEMPTS" ]; do
    if curl -fsS \
        --connect-timeout 10 \
        --max-time 30 \
        -H "Content-Type: application/json" \
        -X POST \
        -d "$payload" \
        "$DISCORD_WEBHOOK_URL" >/dev/null; then
      log_info "Discord notification delivered. Payload: $payload_file"
      return 0
    fi

    log_warn "Discord notification failed. delivery_attempt=$attempt payload=$payload_file"

    if [ "$attempt" -lt "$DISCORD_DELIVERY_ATTEMPTS" ] && [ "$DISCORD_DELIVERY_RETRY_SECONDS" -gt 0 ]; then
      sleep "$DISCORD_DELIVERY_RETRY_SECONDS"
    fi

    attempt=$((attempt + 1))
  done

  cp "$payload_file" "$RUN_DIR/discord/unsent/$(basename "$payload_file")"
  log_error "Discord notification was not delivered after $DISCORD_DELIVERY_ATTEMPTS attempts. Payload saved under discord/unsent."
  return 1
}

send_discord_event() {
  local event_name="$1"
  local title="$2"
  local color="$3"
  local description="$4"
  local fields_json="$5"
  local attempt_number="${6:-0}"
  local payload_file
  local payload

  payload_file="$(discord_payload_file "$event_name" "$attempt_number")"
  payload="$(
    jq -n \
      --arg username "$DISCORD_USERNAME" \
      --arg title "$title" \
      --arg description "$description" \
      --argjson color "$color" \
      --argjson fields "$fields_json" \
      '{
        username: $username,
        embeds: [
          {
            title: $title,
            description: $description,
            color: $color,
            fields: $fields,
            timestamp: (now | todateiso8601)
          }
        ]
      }'
  )"

  send_discord_payload "$payload" "$payload_file"
}

common_fields_json() {
  local attempt_number="$1"
  local state="$2"
  local job_id="$3"
  local next_retry="$4"
  local log_path="$5"

  jq -n \
    --arg stack "$OCI_STACK_ID" \
    --arg run "$RUN_ID" \
    --arg attempt "$attempt_number" \
    --arg state "$state" \
    --arg job "$job_id" \
    --arg next "$next_retry" \
    --arg log "$log_path" \
    '[
      {name: "Stack OCID", value: $stack, inline: false},
      {name: "Run ID", value: $run, inline: true},
      {name: "Attempt", value: $attempt, inline: true},
      {name: "State", value: $state, inline: true},
      {name: "Job ID", value: $job, inline: false},
      {name: "Next retry", value: $next, inline: true},
      {name: "Log path", value: $log, inline: false}
    ]'
}

append_detail_field_json() {
  local fields_json="$1"
  local detail_name="$2"
  local detail_value="$3"

  if [ -z "$detail_value" ]; then
    detail_value="(empty)"
  fi

  detail_value="$(shorten_text "$detail_value" 950)"

  jq \
    --arg name "$detail_name" \
    --arg value "$detail_value" \
    '. + [{name: $name, value: $value, inline: false}]' <<< "$fields_json"
}
