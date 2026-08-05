#!/usr/bin/env bash
set -Eeuo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly INGRESS_NAMESPACE="${INGRESS_NAMESPACE:-ingress-nginx}"
readonly INGRESS_SERVICE="${INGRESS_SERVICE:-ingress-nginx-controller}"
readonly INGRESS_HOST="${INGRESS_HOST:-observability.local}"
readonly NODE_NAME="${NODE_NAME:-node-1}"
readonly COUNT="${COUNT:-1000}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-${ROOT_DIR}/data/generated-traces-$(date -u +%Y%m%dT%H%M%SZ).csv}"

TARGET_URL="${TARGET_URL:-}"
WEB_UI_URL="${WEB_UI_URL:-}"
WEB_UI_CHECK_URL=""
node_ip=""
ingress_port=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/generate-traces.sh

Generate metric requests through the project Ingress. Every accepted request
creates a trace, and every third sample exceeds the default 150 ms threshold.

Environment:
  COUNT                 Number of samples (default: 1000)
  NAMESPACE             Project namespace (default: advanced-observability)
  NODE_NAME             Kubernetes node exposed by NodePort (default: node-1)
  INGRESS_NAMESPACE     Ingress controller namespace (default: ingress-nginx)
  INGRESS_SERVICE       Ingress controller Service
  INGRESS_HOST          HTTP Host header (default: observability.local)
  TARGET_URL            Complete metric endpoint; skips Kubernetes discovery
  WEB_UI_URL            Dashboard URL; inferred from the Ingress by default
  OUTPUT_FILE           CSV trace mapping path

Examples:
  ./scripts/generate-traces.sh
  COUNT=100 TARGET_URL=http://127.0.0.1:8080/api/v1/metrics \
    WEB_UI_URL=http://127.0.0.1:8083 ./scripts/generate-traces.sh
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

if (($# > 0)); then
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
fi

[[ "$COUNT" =~ ^[1-9][0-9]*$ ]] && ((COUNT <= 100000)) || {
  printf 'ERROR: COUNT must be an integer from 1 to 100000.\n' >&2
  exit 2
}

require_command curl

if [[ -z "$TARGET_URL" ]]; then
  require_command kubectl

  node_ip="$(
    kubectl get node "$NODE_NAME" \
      -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'
  )"
  ingress_port="$(
    kubectl get service "$INGRESS_SERVICE" \
      -n "$INGRESS_NAMESPACE" \
      -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}'
  )"
  if [[ -z "$ingress_port" ]]; then
    ingress_port="$(
      kubectl get service "$INGRESS_SERVICE" \
        -n "$INGRESS_NAMESPACE" \
        -o jsonpath='{.spec.ports[0].nodePort}'
    )"
  fi

  [[ -n "$node_ip" && -n "$ingress_port" ]] || {
    printf 'ERROR: could not discover the Ingress NodePort endpoint.\n' >&2
    exit 1
  }

  base_url="http://${node_ip}:${ingress_port}"
  TARGET_URL="${base_url}/api/v1/metrics"
  WEB_UI_CHECK_URL="${base_url}/"
  WEB_UI_URL="${WEB_UI_URL:-http://${INGRESS_HOST}:${ingress_port}/}"
elif [[ -z "$WEB_UI_URL" ]]; then
  WEB_UI_URL="${TARGET_URL%/api/v1/metrics}/"
  WEB_UI_CHECK_URL="$WEB_UI_URL"
else
  WEB_UI_CHECK_URL="$WEB_UI_URL"
fi

output_directory="$(dirname "$OUTPUT_FILE")"
mkdir -p "$output_directory"
[[ ! -e "$OUTPUT_FILE" ]] || {
  printf 'ERROR: output file already exists: %s\n' "$OUTPUT_FILE" >&2
  exit 1
}

printf '%s\n' \
  'sequence,observed_at,device_type,device_id,trace_id,latency_ms,expected_status' \
  > "$OUTPUT_FILE"

readonly DEVICE_TYPES=(router switch server firewall access_point)
accepted=0
expected_alerts=0
last_trace_id=""
started_at="$(date +%s)"

printf 'Generating %d trace samples\n' "$COUNT"
printf 'Metric endpoint: %s (Host: %s)\n' "$TARGET_URL" "$INGRESS_HOST"
printf 'Trace mapping:  %s\n\n' "$OUTPUT_FILE"

for ((index = 1; index <= COUNT; index++)); do
  type_index=$(((index - 1) % ${#DEVICE_TYPES[@]}))
  device_type="${DEVICE_TYPES[$type_index]}"
  device_sequence=$((((index - 1) / ${#DEVICE_TYPES[@]}) % 20 + 1))
  printf -v device_id 'demo-%s-%03d' "$device_type" "$device_sequence"

  cpu=$((20 + (index * 17) % 76))
  memory=$((25 + (index * 13) % 71))
  temperature=$((35 + (index * 7) % 46))
  packet_loss=$(((index * 7) % 6))
  expected_status=NORMAL
  if ((index % 3 == 0)); then
    latency=$((160 + (index * 19) % 241))
    expected_status=THRESHOLD_EXCEEDED
    ((expected_alerts += 1))
  else
    latency=$((20 + (index * 11) % 120))
  fi

  payload="$(printf \
    '{"device_type":"%s","device_id":"%s","cpu_usage_percent":%d,"memory_usage_percent":%d,"temperature_celsius":%d,"latency_ms":%d,"packet_loss_percent":%d}' \
    "$device_type" "$device_id" "$cpu" "$memory" "$temperature" "$latency" "$packet_loss")"

  if ! response="$(
    curl --silent --show-error \
      --connect-timeout 5 \
      --max-time 15 \
      --header "Host: ${INGRESS_HOST}" \
      --header 'Content-Type: application/json' \
      --data "$payload" \
      --write-out $'\n%{http_code}' \
      "$TARGET_URL"
  )"; then
    printf 'ERROR: request %d failed for %s. Partial CSV: %s\n' \
      "$index" "$device_id" "$OUTPUT_FILE" >&2
    exit 1
  fi

  http_status="${response##*$'\n'}"
  response_body="${response%$'\n'*}"
  trace_id="$(
    printf '%s' "$response_body" | \
      sed -n 's/.*"trace_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
  )"

  if [[ "$http_status" != 202 || -z "$trace_id" ]]; then
    printf 'ERROR: request %d returned HTTP %s: %s\n' \
      "$index" "$http_status" "$response_body" >&2
    printf 'Partial CSV: %s\n' "$OUTPUT_FILE" >&2
    exit 1
  fi

  observed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%d,%s,%s,%s,%s,%d,%s\n' \
    "$index" "$observed_at" "$device_type" "$device_id" "$trace_id" \
    "$latency" "$expected_status" >> "$OUTPUT_FILE"
  ((accepted += 1))
  last_trace_id="$trace_id"

  if ((index == 1 || index % 50 == 0 || index == COUNT)); then
    printf '[%d/%d] accepted; latest device=%s trace=%s\n' \
      "$index" "$COUNT" "$device_id" "$trace_id"
  fi
done

dashboard_status="$(
  curl --silent --show-error \
    --output /dev/null \
    --connect-timeout 5 \
    --max-time 15 \
    --header "Host: ${INGRESS_HOST}" \
    --write-out '%{http_code}' \
    "$WEB_UI_CHECK_URL"
)"
[[ "$dashboard_status" == 200 ]] || {
  printf 'ERROR: traces were generated, but Web UI returned HTTP %s: %s\n' \
    "$dashboard_status" "$WEB_UI_CHECK_URL" >&2
  exit 1
}

elapsed=$(( $(date +%s) - started_at ))
printf '\nGeneration completed successfully.\n'
printf 'Accepted traces: %d\n' "$accepted"
printf 'Expected alerts: %d\n' "$expected_alerts"
printf 'Elapsed:         %d seconds\n' "$elapsed"
printf 'CSV:             %s\n' "$OUTPUT_FILE"
if [[ -n "$node_ip" ]]; then
  printf 'Browser DNS:     add "%s %s" to /etc/hosts if DNS is absent\n' \
    "$node_ip" "$INGRESS_HOST"
fi
printf 'Web UI:          %s\n' "$WEB_UI_URL"
printf 'Latest trace:    %s?trace_id=%s\n' "$WEB_UI_URL" "$last_trace_id"
printf 'Note: the dashboard displays the latest 100 events and alerts.\n'
