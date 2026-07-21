#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly GENERATED_MANIFEST="/tmp/lab1.1-pod.yaml"

source "${ROOT_DIR}/labs/common/images.sh"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

IMAGE="$(resolve_workload_image "${IMAGE:-}" \
  advanced-observability traffic-ingest 'app=traffic-ingest')"

sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/pod.yaml" > "$GENERATED_MANIFEST"

kubectl delete pod traffic-pod-60 -n "$NAMESPACE" --ignore-not-found
kubectl apply -f "$GENERATED_MANIFEST"
kubectl wait --for=condition=Ready pod/traffic-pod-60 \
  -n "$NAMESPACE" --timeout=90s
kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o wide --show-labels
kubectl get pod traffic-pod-60 -n "$NAMESPACE" \
  -o jsonpath='init={.spec.initContainers[0].name} containers={range .spec.containers[*]}{.name}{" "}{end}{"\n"}requests={.spec.containers[0].resources.requests} limits={.spec.containers[0].resources.limits}{"\n"}'

printf 'Generated manifest: %s\n' "$GENERATED_MANIFEST"
