#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-run}"

case "$ACTION" in
  cleanup)
    kubectl delete job/metric-once cronjob/metric-every-minute \
      -n "$NAMESPACE" --ignore-not-found
    exit 0
    ;;
  run) ;;
  *) printf 'Usage: %s {run|cleanup}\n' "$0" >&2; exit 1 ;;
esac

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
kubectl delete job metric-once -n "$NAMESPACE" --ignore-not-found
kubectl apply -f "${LAB_DIR}/job.yaml"
kubectl apply -f "${LAB_DIR}/cronjob.yaml"

kubectl wait --for=condition=Complete job/metric-once \
  -n "$NAMESPACE" --timeout=90s
kubectl logs -n "$NAMESPACE" job/metric-once
kubectl get jobs,cronjobs,pods -n "$NAMESPACE"
