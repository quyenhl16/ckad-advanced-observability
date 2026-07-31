#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly DEPLOYMENT="self-healing-app"
ACTION="${1:-run}"

pod_name() {
  kubectl get pod -n "$NAMESPACE" -l app=self-healing-app \
    -o jsonpath='{.items[0].metadata.name}'
}

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl apply -f "${LAB_DIR}/deployment.yaml"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
}

verify() {
  local pod
  pod="$(pod_name)"
  [[ -n "$pod" ]]
  [[ "$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].startupProbe.httpGet.path}')" == "/health" ]]
  [[ "$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.path}')" == "/health" ]]
  [[ "$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.exec.command[2]}')" == "test -f /tmp/ready" ]]
  kubectl exec "$pod" -n "$NAMESPACE" -- test -f /tmp/ready
  kubectl exec "$pod" -n "$NAMESPACE" -- wget -qO- http://127.0.0.1:8080/health
  printf 'Startup, HTTP liveness, and file readiness probes verified.\n'
}

break_and_recover() {
  local pod before after ready attempt
  pod="$(pod_name)"
  before="$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
  kubectl exec "$pod" -n "$NAMESPACE" -- rm -f /www/health
  for attempt in $(seq 1 60); do
    after="$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')"
    ready="$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}')"
    if (( after > before )) && [[ "$ready" == "true" ]]; then
      printf 'Liveness recovery verified: restartCount %s -> %s.\n' "$before" "$after"
      return 0
    fi
    sleep 2
  done
  printf 'Container did not restart and recover after the liveness failure.\n' >&2
  return 1
}

status() {
  kubectl get deployment,pod -n "$NAMESPACE" -l app=self-healing-app -o wide
  kubectl describe pod "$(pod_name)" -n "$NAMESPACE"
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/deployment.yaml" --ignore-not-found
}

case "$ACTION" in
  run) deploy; verify; break_and_recover; status ;;
  deploy) deploy ;;
  verify) verify ;;
  break) break_and_recover ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|verify|break|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
