#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly OVERLAY="${LAB_DIR}/overlays/lab"
readonly RENDERED="/tmp/lab2.4-rendered.yaml"
ACTION="${1:-render}"

source "${ROOT_DIR}/labs/common/images.sh"

render() {
  kubectl kustomize "$OVERLAY" > "$RENDERED"
  if [[ -n "${IMAGE:-}" ]]; then
    sed -i "s|10.206.0.3:5000/traffic-ingest:lab-v2|${IMAGE}|" "$RENDERED"
  fi
}

case "$ACTION" in
  render)
    render
    cat "$RENDERED"
    ;;
  diff)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE="$(resolve_workload_image "${IMAGE:-}" \
      advanced-observability traffic-ingest 'app=traffic-ingest')"
    export IMAGE
    render
    kubectl diff -f "$RENDERED" || status=$?
    [[ "${status:-0}" -le 1 ]] || exit "$status"
    ;;
  apply)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE="$(resolve_workload_image "${IMAGE:-}" \
      advanced-observability traffic-ingest 'app=traffic-ingest')"
    export IMAGE
    render
    kubectl apply -f "$RENDERED"
    kubectl rollout status deployment/traffic-kustomize -n "$NAMESPACE" --timeout=180s
    ;;
  status)
    kubectl get deployment,pod,service -n "$NAMESPACE" -l app=traffic-kustomize -o wide
    ;;
  cleanup)
    kubectl delete deployment,service -n "$NAMESPACE" -l app=traffic-kustomize --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {render|diff|apply|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
