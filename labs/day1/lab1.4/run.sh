#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-run}"

case "$ACTION" in
  cleanup)
    kubectl delete pods -n "$NAMESPACE" -l app=label-client --ignore-not-found
    exit 0
    ;;
  run) ;;
  *) printf 'Usage: %s {run|cleanup}\n' "$0" >&2; exit 1 ;;
esac

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

kubectl delete pods -n "$NAMESPACE" -l app=label-client --ignore-not-found
kubectl apply -f "${LAB_DIR}/pods.yaml"
kubectl wait --for=condition=Ready pods -n "$NAMESPACE" -l app=label-client --timeout=120s

kubectl get pods -n "$NAMESPACE" -l app=label-client --show-labels
kubectl label pods -n "$NAMESPACE" -l app=label-client \
  environment=staging --overwrite
kubectl annotate pods -n "$NAMESPACE" -l app=label-client \
  owner=platform-team --overwrite

printf '\nOdd-index Pods:\n'
kubectl get pods -n "$NAMESPACE" -l 'index in (1,3,5)' --show-labels
