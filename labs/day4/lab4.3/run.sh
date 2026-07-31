#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

reach_backend() {
  local pod="$1"
  kubectl exec "$pod" -n "$NAMESPACE" -c network-probe -- \
    wget -qO- -T 3 http://policy-backend:8080/health/ready
}

deploy() {
  local backend_image frontend_image
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl delete -f "${LAB_DIR}/network-policies.yaml" --ignore-not-found
  backend_image="$(resolve_workload_image "${BACKEND_IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  frontend_image="$(resolve_workload_image "${FRONTEND_IMAGE:-}" \
    advanced-observability observability-frontend 'app=observability-frontend')"
  kubectl delete pod policy-frontend policy-intruder -n "$NAMESPACE" \
    --ignore-not-found
  sed \
    -e "s|ckad/traffic-ingest:local|${backend_image}|" \
    -e "s|ckad/observability-frontend:local|${frontend_image}|" \
    "${LAB_DIR}/workloads.yaml" | kubectl apply -f -
  kubectl rollout status deployment/policy-backend -n "$NAMESPACE" --timeout=120s
  kubectl wait --for=condition=Ready pod/policy-frontend pod/policy-intruder \
    -n "$NAMESPACE" --timeout=120s
}

baseline() {
  reach_backend policy-frontend >/dev/null
  reach_backend policy-intruder >/dev/null
  printf 'Baseline verified: both clients can reach the backend before isolation.\n'
}

isolate() {
  kubectl apply -f "${LAB_DIR}/network-policies.yaml"
}

verify() {
  local attempt intruder_blocked="false"
  for attempt in $(seq 1 15); do
    if reach_backend policy-frontend >/dev/null && \
       ! reach_backend policy-intruder >/dev/null 2>&1; then
      intruder_blocked="true"
      break
    fi
    sleep 1
  done
  if [[ "$intruder_blocked" != "true" ]]; then
    printf 'Intruder unexpectedly reached the isolated backend. Check CNI NetworkPolicy support.\n' >&2
    return 1
  fi
  if kubectl exec deployment/policy-backend -n "$NAMESPACE" -c network-probe -- \
    wget -qO- -T 3 http://1.1.1.1/ >/dev/null 2>&1; then
    printf 'Backend unexpectedly reached 1.1.1.1; egress is not isolated.\n' >&2
    return 1
  fi
  printf 'Verified frontend-only backend ingress and denied backend egress to 0.0.0.0/0.\n'
}

status() {
  kubectl get pod,service,networkpolicy -n "$NAMESPACE" -l lab=4.3 -o wide
  kubectl describe networkpolicy backend-ingress-from-frontend backend-deny-all-egress \
    -n "$NAMESPACE"
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/network-policies.yaml" --ignore-not-found
  kubectl delete -f "${LAB_DIR}/workloads.yaml" --ignore-not-found
}

case "$ACTION" in
  run) deploy; baseline; isolate; verify; status ;;
  deploy) deploy ;;
  baseline) baseline ;;
  isolate) isolate ;;
  verify) verify ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|baseline|isolate|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
