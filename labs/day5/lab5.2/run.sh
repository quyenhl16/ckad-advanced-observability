#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="cli-observer"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

deploy() {
  local image restart_count ready attempt
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  image="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  sed "s|ckad/traffic-ingest:local|${image}|" \
    "${LAB_DIR}/pod.yaml" | kubectl apply -f -
  for attempt in $(seq 1 60); do
    restart_count="$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.containerStatuses[?(@.name=="log-helper")].restartCount}' 2>/dev/null || true)"
    ready="$(kubectl get pod "$POD" -n "$NAMESPACE" \
      -o jsonpath='{.status.containerStatuses[?(@.name=="app")].ready}' 2>/dev/null || true)"
    if [[ "${restart_count:-0}" -ge 1 && "$ready" == "true" ]]; then
      printf 'Pod recovered from its intentional first crash.\n'
      return 0
    fi
    sleep 2
  done
  printf 'Timed out waiting for the app container to crash once and recover.\n' >&2
  return 1
}

logs() {
  local app current previous
  app="$(kubectl logs "$POD" -n "$NAMESPACE" -c app --tail=20)"
  current="$(kubectl logs "$POD" -n "$NAMESPACE" -c log-helper)"
  previous="$(kubectl logs "$POD" -n "$NAMESPACE" -c log-helper --previous)"
  grep -q 'HTTP server started' <<<"$app"
  grep -q 'log helper recovered' <<<"$current"
  grep -q 'intentional crash' <<<"$previous"
  printf '%s\n' '--- traffic-ingest app ---' "$app"
  printf '%s\n' '--- log-helper (current) ---' "$current"
  printf '%s\n' '--- log-helper (previous) ---' "$previous"
}

events() {
  kubectl describe pod "$POD" -n "$NAMESPACE"
  kubectl get events -n "$NAMESPACE" \
    --field-selector involvedObject.name="$POD" \
    --sort-by=.lastTimestamp
}

top_usage() {
  local output attempt
  for attempt in $(seq 1 30); do
    if output="$(kubectl top pod "$POD" -n "$NAMESPACE" --containers 2>&1)"; then
      printf '%s\n' "$output"
      return 0
    fi
    sleep 2
  done
  printf 'kubectl top did not return metrics. Verify that Metrics Server is installed and healthy.\n%s\n' \
    "$output" >&2
  return 1
}

status() {
  kubectl get pod "$POD" -n "$NAMESPACE" -o wide
  kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath='{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" restarts="}{.restartCount}{"\n"}{end}'
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/pod.yaml" --ignore-not-found
}

case "$ACTION" in
  run) deploy; logs; events; top_usage; status ;;
  deploy) deploy ;;
  logs) logs ;;
  events) events ;;
  top) top_usage ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|logs|events|top|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
