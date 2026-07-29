#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-quota-lab"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

resolve_image() {
  resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest'
}

deploy() {
  kubectl apply -f "${LAB_DIR}/namespace-policy.yaml"
  IMAGE="$(resolve_image)"
  kubectl delete pod quota-accepted quota-exceeded -n "$NAMESPACE" --ignore-not-found
  sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/accepted-pod.yaml" | kubectl apply -f -
  kubectl wait --for=condition=Ready pod/quota-accepted -n "$NAMESPACE" --timeout=120s
}

reject() {
  local output
  IMAGE="$(resolve_image)"
  kubectl delete pod quota-exceeded -n "$NAMESPACE" --ignore-not-found
  if output="$(sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/rejected-pod.yaml" | kubectl apply -f - 2>&1)"; then
    kubectl delete pod quota-exceeded -n "$NAMESPACE" --ignore-not-found
    printf 'Expected ResourceQuota admission rejection, but the Pod was accepted.\n' >&2
    return 1
  fi
  printf '%s\n' "$output"
  grep -qi 'exceeded quota' <<<"$output"
  printf 'Quota rejection observed as expected.\n'
}

case "$ACTION" in
  run) deploy; reject; kubectl describe resourcequota compute-quota -n "$NAMESPACE" ;;
  deploy) deploy ;;
  reject) reject ;;
  status)
    kubectl get pod,resourcequota,limitrange -n "$NAMESPACE"
    kubectl describe resourcequota compute-quota -n "$NAMESPACE"
    kubectl describe limitrange container-defaults -n "$NAMESPACE"
    ;;
  cleanup) kubectl delete namespace "$NAMESPACE" --ignore-not-found ;;
  *) printf 'Usage: %s {run|deploy|reject|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
