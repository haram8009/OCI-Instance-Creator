#!/usr/bin/env bash

normalize_job_log_file() {
  local input_file="$1"
  local output_file="$2"

  if jq -e '.data | type == "string"' "$input_file" >/dev/null 2>&1; then
    jq -r '.data' "$input_file" | decode_log_escapes > "$output_file"
  elif jq -e 'type == "string"' "$input_file" >/dev/null 2>&1; then
    jq -r '.' "$input_file" | decode_log_escapes > "$output_file"
  else
    decode_log_escapes < "$input_file" > "$output_file"
  fi
}

decode_log_escapes() {
  sed \
    -e 's/\\n/\
/g' \
    -e 's/\\t/  /g' \
    -e 's/\\"/"/g'
}

extract_oci_error_message() {
  local input_file="$1"
  local message=""

  if [ ! -s "$input_file" ]; then
    return 0
  fi

  message="$(
    sed -n 's/.*"message":[[:space:]]*"\([^"]*\)".*/\1/p' "$input_file" | head -n 1
  )"

  if [ -n "$message" ]; then
    printf '%s' "$message"
    return 0
  fi

  message="$(awk 'NF {print; exit}' "$input_file")"
  if [ -n "$message" ]; then
    printf '%s' "$message"
  fi
}

job_log_summary_line() {
  local input_file="$1"
  local max_chars="$2"
  local summary

  summary="$(
    job_log_digest "$input_file" "$max_chars" | awk '
      BEGIN {
        fallback = ""
        found = 0
      }

      {
        if (fallback == "") {
          fallback = $0
        }

        if (!found && $0 ~ /(Error:|ServiceError:|Out of host capacity|LimitExceeded|TooManyRequests|NotAuthorized|NotAuthenticated|InvalidParameter)/) {
          print $0
          found = 1
          exit
        }
      }

      END {
        if (!found && fallback != "") {
          print fallback
        }
      }
    '
  )"
  if [ -n "$summary" ]; then
    printf '%s' "$summary"
  fi
}

job_log_digest() {
  local input_file="$1"
  local max_chars="$2"

  if [ ! -s "$input_file" ]; then
    return 0
  fi

  awk '
    function clean(line) {
      gsub(/\r/, "", line)
      gsub(/^[0-9\/]+ [0-9:]+\[TERRAFORM_CONSOLE\] \[[A-Z]+\] ?/, "", line)
      gsub(/^[[:space:]]+/, "", line)
      gsub(/[[:space:]]+$/, "", line)
      return line
    }

    {
      line = clean($0)
      if (line == "" || line ~ /^Terraform v/ || line ~ /^on: / || line ~ /^with oci_/) {
        next
      }

      if (line ~ /(Error:|ServiceError:|Out of host capacity|LimitExceeded|TooManyRequests|NotAuthorized|NotAuthenticated|InvalidParameter|Operation Name:|OPC request ID:|resource "oci_|on .* line [0-9]+)/) {
        selected[++count] = line
      }
    }

    END {
      if (count == 0) {
        exit
      }

      for (i = 1; i <= count; i++) {
        print selected[i]
      }
    }
  ' "$input_file" | head -n 18 | head -c "$max_chars"
}
