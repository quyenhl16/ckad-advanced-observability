#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"

source "${ROOT_DIR}/labs/common/images.sh"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

IMAGE="$(resolve_workload_image "${IMAGE:-}" \
  advanced-observability analytics-engine 'app=analytics-engine')"

sed "s|ckad/analytics-engine:local|${IMAGE}|" "${LAB_DIR}/pod.yaml" | kubectl apply -f -
kubectl wait --for=condition=Ready pod/analytics-pattern \
  -n "$NAMESPACE" --timeout=120s
kubectl get pod analytics-pattern -n "$NAMESPACE" \
  -o jsonpath='{range .spec.initContainers[*]}init={.name}{"\n"}{end}{range .spec.containers[*]}container={.name}{"\n"}{end}'

printf '\nTail the sidecar with:\n'
printf 'kubectl logs -n %s analytics-pattern -c log-collector -f\n' "$NAMESPACE"
