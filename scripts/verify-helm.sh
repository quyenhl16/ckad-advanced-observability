#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly CHARTS=(observability-platform observability-db alert-manager analytics-engine traffic-ingest observability-frontend)

LIVE=false
if [[ "${1:-}" == --live ]]; then
  LIVE=true
elif (($# > 0)); then
  printf 'Usage: ./scripts/verify-helm.sh [--live]\n' >&2
  exit 2
fi

command -v helm >/dev/null 2>&1 || { printf 'ERROR: helm is required\n' >&2; exit 1; }

failures=0
for chart in "${CHARTS[@]}"; do
  printf '\n[%s] REQUIREMENT: chart must lint and render for namespace %s\n' "$chart" "$NAMESPACE"
  printf 'COMMAND: helm lint helm/%s; helm template %s helm/%s -n %s\n' \
    "$chart" "$chart" "$chart" "$NAMESPACE"
  if helm lint "${ROOT_DIR}/helm/${chart}" && \
    helm template "$chart" "${ROOT_DIR}/helm/${chart}" -n "$NAMESPACE" >/dev/null; then
    printf 'VERIFY: PASS\n'
  else
    printf 'VERIFY: FAIL\n'
    failures=$((failures + 1))
  fi
done

if [[ "$LIVE" == true ]]; then
  command -v kubectl >/dev/null 2>&1 || { printf 'ERROR: kubectl is required for --live\n' >&2; exit 1; }
  printf '\n[LIVE] REQUIREMENT: all six releases are deployed and main workloads are Ready\n'
  printf 'COMMAND: helm list -n %s; kubectl get pods -n %s\n' "$NAMESPACE" "$NAMESPACE"
  helm list -n "$NAMESPACE"
  kubectl get pods -n "$NAMESPACE" -o wide
  for chart in "${CHARTS[@]}"; do
    if ! helm status "$chart" -n "$NAMESPACE" >/dev/null; then
      printf 'Missing Helm release: %s\n' "$chart" >&2
      failures=$((failures + 1))
    fi
  done
  if ! kubectl rollout status statefulset/observability-db \
    -n "$NAMESPACE" --timeout=180s; then
    failures=$((failures + 1))
  fi
  for deployment in alert-manager analytics-engine traffic-ingest \
    traffic-ingest-canary observability-frontend; do
    if ! kubectl rollout status "deployment/${deployment}" \
      -n "$NAMESPACE" --timeout=180s; then
      failures=$((failures + 1))
    fi
  done
  if ((failures == 0)); then
    printf 'VERIFY: PASS\n'
  else
    printf 'VERIFY: FAIL\n'
  fi
fi

printf '\nSUMMARY: %s\n' "$([[ $failures -eq 0 ]] && printf PASS || printf FAIL)"
exit "$([[ $failures -eq 0 ]] && printf 0 || printf 1)"
