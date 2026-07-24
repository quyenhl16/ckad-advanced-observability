#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-status}"

source "${ROOT_DIR}/labs/common/images.sh"

case "$ACTION" in
  deploy)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE="$(resolve_workload_image "${IMAGE:-}" \
      advanced-observability traffic-ingest 'app=traffic-ingest')"
    kubectl apply -f "${LAB_DIR}/service.yaml"
    sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/deployment.yaml" | kubectl apply -f -
    kubectl rollout status deployment/traffic-hpa -n "$NAMESPACE" --timeout=180s
    ;;
  scale)
    kubectl scale deployment traffic-hpa -n "$NAMESPACE" --replicas=10
    kubectl get pods -n "$NAMESPACE" -l app=traffic-hpa
    ;;
  hpa)
    kubectl apply -f "${LAB_DIR}/hpa.yaml"
    kubectl describe hpa traffic-hpa -n "$NAMESPACE"
    ;;
  load)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    kubectl get deployment traffic-hpa -n "$NAMESPACE" >/dev/null || {
      printf 'Deploy the target first with: %s deploy\n' "$0" >&2
      exit 1
    }
    kubectl apply -f "${LAB_DIR}/service.yaml"
    kubectl apply -f "${LAB_DIR}/hpa.yaml"
    kubectl apply -f "${LAB_DIR}/load-generator.yaml"
    kubectl set env deployment/hpa-load-generator -n "$NAMESPACE" \
      "WORKERS=${WORKERS:-16}"
    kubectl rollout status deployment/hpa-load-generator -n "$NAMESPACE" --timeout=120s
    printf 'Load started with %s workers. Run \"%s watch\" in another terminal.\n' \
      "${WORKERS:-16}" "$0"
    ;;
  stop-load)
    kubectl delete deployment hpa-load-generator -n "$NAMESPACE" --ignore-not-found
    printf 'Load stopped. Scale-down starts after the 60-second stabilization window.\n'
    ;;
  watch)
    printf 'Watching HPA and target Pods; press Ctrl-C to stop.\n'
    kubectl get hpa,pods -n "$NAMESPACE" -l app=traffic-hpa -w
    ;;
  status)
    kubectl get deployment,pods,hpa -n "$NAMESPACE" -l app=traffic-hpa
    kubectl get deployment hpa-load-generator -n "$NAMESPACE" 2>/dev/null || true
    kubectl top pods -n "$NAMESPACE" -l app=traffic-hpa --containers 2>/dev/null || \
      printf 'Pod metrics unavailable; verify Metrics Server.\n'
    ;;
  cleanup)
    kubectl delete deployment hpa-load-generator -n "$NAMESPACE" --ignore-not-found
    kubectl delete -f "${LAB_DIR}/hpa.yaml" --ignore-not-found
    kubectl delete -f "${LAB_DIR}/service.yaml" --ignore-not-found
    kubectl delete deployment traffic-hpa -n "$NAMESPACE" --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {deploy|scale|hpa|load|stop-load|watch|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
