#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly GENERATED_MANIFEST="/tmp/lab1.1-pod.yaml"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

IMAGE="${IMAGE:-$(kubectl get deployment traffic-ingest \
  -n advanced-observability \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)}"
IMAGE="${IMAGE:-ckad/traffic-ingest:local}"

kubectl run traffic-pod-60 \
  -n "$NAMESPACE" \
  --image="$IMAGE" \
  --restart=Never \
  --labels='app=traffic-pod-60,tier=lab' \
  --env='HTTP_ADDR=:8080' \
  --env='ANALYTICS_URL=http://analytics-engine.advanced-observability.svc.cluster.local:8081' \
  --dry-run=client \
  -o yaml > /tmp/lab1.1-pod-base.yaml

kubectl set resources \
  -f /tmp/lab1.1-pod-base.yaml \
  --local \
  --requests=cpu=50m,memory=32Mi \
  --limits=cpu=250m,memory=128Mi \
  -o yaml > "$GENERATED_MANIFEST"

kubectl apply -f "$GENERATED_MANIFEST"
kubectl wait --for=condition=Ready pod/traffic-pod-60 \
  -n "$NAMESPACE" --timeout=90s
kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o wide --show-labels
kubectl get pod traffic-pod-60 -n "$NAMESPACE" \
  -o jsonpath='requests={.spec.containers[0].resources.requests} limits={.spec.containers[0].resources.limits}{"\n"}'

printf 'Generated manifest: %s\n' "$GENERATED_MANIFEST"
