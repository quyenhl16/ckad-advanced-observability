#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="config-injection"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

deploy() {
  : "${LAB_API_KEY:?Set LAB_API_KEY before running this lab}"
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl apply -f "${LAB_DIR}/configmap.yaml"
  kubectl create secret generic lab3-1-secret -n "$NAMESPACE" \
    --from-literal=api-key="$LAB_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
  IMAGE="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/pod.yaml" | kubectl apply -f -
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=120s
}

verify() {
  [[ "$(kubectl get configmap lab3-1-config -n "$NAMESPACE" -o jsonpath='{.data.APP_MODE}')" == "training" ]]
  [[ "$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="app")].env[?(@.name=="API_KEY")].valueFrom.secretKeyRef.name}')" == "lab3-1-secret" ]]
  [[ "$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="app")].env[?(@.name=="APP_MODE")].valueFrom.configMapKeyRef.name}')" == "lab3-1-config" ]]
  [[ "$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.volumes[?(@.name=="app-config")].configMap.name}')" == "lab3-1-config" ]]
  [[ "$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="app")].volumeMounts[?(@.name=="app-config")].mountPath}')" == "/config" ]]
  kubectl exec -n "$NAMESPACE" "$POD" -c log-sidecar -- \
    wget -qO- http://127.0.0.1:8080/health/ready >/dev/null
  printf 'Secret env, ConfigMap env/volume, and application health verified.\n'
}

case "$ACTION" in
  run) deploy; verify ;;
  deploy) deploy ;;
  verify) verify ;;
  status)
    kubectl get pod/"$POD" configmap/lab3-1-config secret/lab3-1-secret \
      -n "$NAMESPACE" --show-labels
    kubectl describe pod "$POD" -n "$NAMESPACE"
    ;;
  cleanup)
    kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
    kubectl delete -f "${LAB_DIR}/configmap.yaml" --ignore-not-found
    kubectl delete secret lab3-1-secret -n "$NAMESPACE" --ignore-not-found
    ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
