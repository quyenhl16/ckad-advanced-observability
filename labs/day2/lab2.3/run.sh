#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-status}"

case "$ACTION" in
  deploy)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE="${IMAGE:-$(kubectl get deployment traffic-ingest -n advanced-observability \
      -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)}"
    IMAGE="${IMAGE:-ckad/traffic-ingest:local}"
    sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/deployment.yaml" | kubectl apply -f -
    kubectl rollout status deployment/traffic-hpa -n "$NAMESPACE" --timeout=180s
    ;;
  scale)
    kubectl scale deployment traffic-hpa -n "$NAMESPACE" --replicas=10
    kubectl get pods -n "$NAMESPACE" -l app=traffic-hpa
    ;;
  hpa)
    kubectl apply -f "${LAB_DIR}/hpa.yaml"
    kubectl get hpa traffic-hpa -n "$NAMESPACE"
    ;;
  status)
    kubectl get deployment,pods,hpa -n "$NAMESPACE" -l app=traffic-hpa
    kubectl top pods -n "$NAMESPACE" -l app=traffic-hpa 2>/dev/null || \
      printf 'Pod metrics unavailable; verify Metrics Server.\n'
    ;;
  cleanup)
    kubectl delete -f "${LAB_DIR}/hpa.yaml" --ignore-not-found
    kubectl delete deployment traffic-hpa -n "$NAMESPACE" --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {deploy|scale|hpa|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
