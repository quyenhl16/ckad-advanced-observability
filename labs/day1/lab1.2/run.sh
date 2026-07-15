#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

IMAGE="${IMAGE:-$(kubectl get deployment analytics-engine \
  -n advanced-observability \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}' 2>/dev/null || true)}"
IMAGE="${IMAGE:-ckad/analytics-engine:local}"

sed "s|ckad/analytics-engine:local|${IMAGE}|" "${LAB_DIR}/pod.yaml" | kubectl apply -f -
kubectl wait --for=condition=Ready pod/analytics-pattern \
  -n "$NAMESPACE" --timeout=120s
kubectl get pod analytics-pattern -n "$NAMESPACE" \
  -o jsonpath='{range .spec.initContainers[*]}init={.name}{"\n"}{end}{range .spec.containers[*]}container={.name}{"\n"}{end}'

printf '\nTail the sidecar with:\n'
printf 'kubectl logs -n %s analytics-pattern -c log-collector -f\n' "$NAMESPACE"
