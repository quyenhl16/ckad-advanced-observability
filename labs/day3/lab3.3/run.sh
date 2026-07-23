#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="rbac-api-client"
ACTION="${1:-run}"

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl apply -f "${LAB_DIR}/rbac.yaml"
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${LAB_DIR}/pod.yaml"
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=120s
}

verify() {
  [[ "$(kubectl auth can-i list pods --as=system:serviceaccount:${NAMESPACE}:pod-reader -n "$NAMESPACE")" == "yes" ]]
  [[ "$(kubectl auth can-i get secrets --as=system:serviceaccount:${NAMESPACE}:pod-reader -n "$NAMESPACE")" == "no" ]]

  local attempt
  for attempt in $(seq 1 30); do
    if kubectl exec -n "$NAMESPACE" "$POD" -c app -- test -s /www/pods.json 2>/dev/null; then
      kubectl exec -n "$NAMESPACE" "$POD" -c app -- \
        curl -fsS http://127.0.0.1:8080/pods.json >/dev/null
      printf 'ServiceAccount listed Pods through the Kubernetes API; Secret access remains denied.\n'
      return 0
    fi
    sleep 2
  done
  printf 'Timed out waiting for the PodList API response.\n' >&2
  return 1
}

case "$ACTION" in
  run) deploy; verify ;;
  deploy) deploy ;;
  verify) verify ;;
  status)
    kubectl get serviceaccount,role,rolebinding,pod -n "$NAMESPACE" -l 'lab=3.3'
    kubectl auth can-i --list --as=system:serviceaccount:${NAMESPACE}:pod-reader -n "$NAMESPACE"
    ;;
  cleanup)
    kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
    kubectl delete -f "${LAB_DIR}/rbac.yaml" --ignore-not-found
    ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
