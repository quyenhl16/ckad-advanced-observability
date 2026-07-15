#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
kubectl delete job metric-once -n "$NAMESPACE" --ignore-not-found
kubectl apply -f "${LAB_DIR}/job.yaml"
kubectl apply -f "${LAB_DIR}/cronjob.yaml"

kubectl wait --for=condition=Complete job/metric-once \
  -n "$NAMESPACE" --timeout=90s
kubectl logs -n "$NAMESPACE" job/metric-once
kubectl get jobs,cronjobs,pods -n "$NAMESPACE"
