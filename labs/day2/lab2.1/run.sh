#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly DEPLOYMENT="traffic-rollout"
ACTION="${1:-status}"

current_image() {
  kubectl get deployment traffic-ingest -n advanced-observability \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

case "$ACTION" in
  deploy)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE_V1="${IMAGE_V1:-$(current_image)}"
    IMAGE_V1="${IMAGE_V1:-ckad/traffic-ingest:local}"
    sed "s|ckad/traffic-ingest:local|${IMAGE_V1}|" "${LAB_DIR}/deployment.yaml" | kubectl apply -f -
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  update)
    [[ -n "${IMAGE_V2:-}" ]] || { printf 'Set IMAGE_V2 to a valid second image tag.\n' >&2; exit 1; }
    kubectl set image deployment/"$DEPLOYMENT" -n "$NAMESPACE" app="$IMAGE_V2"
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  fail)
    kubectl set image deployment/"$DEPLOYMENT" -n "$NAMESPACE" \
      app=invalid.invalid/traffic-ingest:does-not-exist
    if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=45s; then
      printf 'Unexpected: bad rollout completed.\n' >&2
      exit 1
    fi
    printf 'Expected failure observed. Run: %s undo\n' "$0"
    ;;
  undo)
    kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  history)
    kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    ;;
  status)
    kubectl get deployment,replicaset,pod -n "$NAMESPACE" -l app="$DEPLOYMENT" -o wide
    ;;
  cleanup)
    kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {deploy|update|fail|undo|history|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
