#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"

kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"

for index in 1 2 3 4 5; do
  kubectl delete pod "label-client-${index}" -n "$NAMESPACE" --ignore-not-found
  kubectl run "label-client-${index}" \
    -n "$NAMESPACE" \
    --image=busybox:1.37 \
    --restart=Never \
    --labels="app=label-client,environment=test,index=${index}" \
    --command -- sleep 3600
done

kubectl get pods -n "$NAMESPACE" -l app=label-client --show-labels
kubectl label pods -n "$NAMESPACE" -l app=label-client \
  environment=staging --overwrite
kubectl annotate pods -n "$NAMESPACE" -l app=label-client \
  owner=platform-team --overwrite

printf '\nOdd-index Pods:\n'
kubectl get pods -n "$NAMESPACE" -l 'index in (1,3,5)' --show-labels
