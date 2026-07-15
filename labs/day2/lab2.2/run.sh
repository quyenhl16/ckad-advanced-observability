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
    DEFAULT_IMAGE=""
    if [[ -z "${BLUE_IMAGE:-}" || -z "${GREEN_IMAGE:-}" ]]; then
      DEFAULT_IMAGE="$(resolve_workload_image "${IMAGE:-}" \
        advanced-observability traffic-ingest 'app=traffic-ingest')"
    fi
    BLUE_IMAGE="${BLUE_IMAGE:-$DEFAULT_IMAGE}"
    GREEN_IMAGE="${GREEN_IMAGE:-$DEFAULT_IMAGE}"
    sed "s|ckad/traffic-ingest:local|${BLUE_IMAGE}|" "${LAB_DIR}/blue.yaml" | kubectl apply -f -
    sed "s|ckad/traffic-ingest:local|${GREEN_IMAGE}|" "${LAB_DIR}/green.yaml" | kubectl apply -f -
    kubectl apply -f "${LAB_DIR}/service.yaml"
    kubectl rollout status deployment/traffic-bg-blue -n "$NAMESPACE" --timeout=180s
    kubectl rollout status deployment/traffic-bg-green -n "$NAMESPACE" --timeout=180s
    ;;
  blue|green)
    kubectl patch service traffic-ingest-bg -n "$NAMESPACE" --type=merge \
      -p "{\"spec\":{\"selector\":{\"app\":\"traffic-ingest-bg\",\"version\":\"${ACTION}\"}}}"
    ;;
  status)
    kubectl get deployments,pods -n "$NAMESPACE" -l app=traffic-ingest-bg -L version
    kubectl get service traffic-ingest-bg -n "$NAMESPACE" \
      -o jsonpath='selected-version={.spec.selector.version}{"\n"}'
    kubectl get endpointslice -n "$NAMESPACE" \
      -l kubernetes.io/service-name=traffic-ingest-bg
    ;;
  cleanup)
    kubectl delete -f "${LAB_DIR}/service.yaml" --ignore-not-found
    kubectl delete deployment traffic-bg-blue traffic-bg-green -n "$NAMESPACE" --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {deploy|blue|green|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
