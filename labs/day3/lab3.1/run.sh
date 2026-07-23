#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="config-injection"
ACTION="${1:-run}"

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl create secret generic lab3-1-secret -n "$NAMESPACE" \
    --from-file=api-key="${LAB_DIR}/api-key.txt" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl create configmap lab3-1-config -n "$NAMESPACE" \
    --from-literal=APP_MODE=training \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${LAB_DIR}/pod.yaml"
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=120s
}

verify() {
  kubectl exec -n "$NAMESPACE" "$POD" -c app -- sh -c \
    'test -n "$API_KEY" && test "$(cat /config/APP_MODE)" = training'
  kubectl exec -n "$NAMESPACE" "$POD" -c app -- \
    wget -qO- http://127.0.0.1:8080/
  printf '\nSecret env and ConfigMap volume verified.\n'
}

case "$ACTION" in
  run) deploy; verify ;;
  deploy) deploy ;;
  verify) verify ;;
  status)
    kubectl get pod/"$POD" configmap/lab3-1-config secret/lab3-1-secret \
      -n "$NAMESPACE" --show-labels
    kubectl describe pod "$POD" -n "$NAMESPACE"
    ;;
  cleanup)
    kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
    kubectl delete configmap lab3-1-config -n "$NAMESPACE" --ignore-not-found
    kubectl delete secret lab3-1-secret -n "$NAMESPACE" --ignore-not-found
    ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
