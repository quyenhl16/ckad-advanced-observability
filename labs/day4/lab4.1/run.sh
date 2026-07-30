#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

endpoint_addresses() {
  kubectl get endpoints "$1" -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true
}

deploy() {
  local backend_image frontend_image
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  backend_image="$(resolve_workload_image "${BACKEND_IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  frontend_image="$(resolve_workload_image "${FRONTEND_IMAGE:-}" \
    advanced-observability observability-frontend 'app=observability-frontend')"
  sed \
    -e "s|ckad/traffic-ingest:local|${backend_image}|" \
    -e "s|ckad/observability-frontend:local|${frontend_image}|" \
    "${LAB_DIR}/workloads.yaml" | kubectl apply -f -
  kubectl apply -f "${LAB_DIR}/services.yaml"
  kubectl rollout status deployment/day4-backend -n "$NAMESPACE" --timeout=180s
  kubectl rollout status deployment/day4-frontend -n "$NAMESPACE" --timeout=180s
}

diagnose() {
  local attempt backend_addresses frontend_addresses
  backend_addresses="$(endpoint_addresses day4-backend)"
  for attempt in $(seq 1 15); do
    frontend_addresses="$(endpoint_addresses day4-frontend)"
    [[ -n "$frontend_addresses" ]] && break
    sleep 1
  done
  [[ -z "$backend_addresses" ]] || {
    printf 'Expected the initial backend selector mismatch, but endpoints exist: %s\n' "$backend_addresses" >&2
    return 1
  }
  [[ -n "$frontend_addresses" ]] || {
    printf 'Frontend Service has no ready endpoints.\n' >&2
    return 1
  }
  printf 'Diagnosed backend selector mismatch: Service has zero endpoints.\n'
  kubectl get service day4-backend -n "$NAMESPACE" -o jsonpath='service-selector={.spec.selector}{"\n"}'
  kubectl get pods -n "$NAMESPACE" -l lab=4.1 --show-labels
}

fix() {
  kubectl patch service day4-backend -n "$NAMESPACE" --type=merge \
    -p '{"spec":{"selector":{"app":"day4-backend"}}}'
}

verify() {
  local attempt backend_addresses frontend_addresses node_port
  for attempt in $(seq 1 30); do
    backend_addresses="$(endpoint_addresses day4-backend)"
    frontend_addresses="$(endpoint_addresses day4-frontend)"
    [[ -n "$backend_addresses" && -n "$frontend_addresses" ]] && break
    sleep 2
  done
  [[ -n "${backend_addresses:-}" && -n "${frontend_addresses:-}" ]] || {
    printf 'Timed out waiting for Service endpoints.\n' >&2
    return 1
  }
  [[ "$(kubectl get service day4-backend -n "$NAMESPACE" -o jsonpath='{.spec.type}')" == "ClusterIP" ]]
  [[ "$(kubectl get service day4-frontend -n "$NAMESPACE" -o jsonpath='{.spec.type}')" == "NodePort" ]]
  node_port="$(kubectl get service day4-frontend -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"
  [[ "$node_port" =~ ^[0-9]+$ ]]
  kubectl delete pod lab4-1-probe -n "$NAMESPACE" \
    --ignore-not-found --wait=false >/dev/null
  kubectl run lab4-1-probe -n "$NAMESPACE" --rm --attach --restart=Never \
    --image=busybox:1.37 --command -- \
    sh -c 'wget -qO- -T 5 http://day4-backend:8080/health/ready >/dev/null && wget -qO- -T 5 http://day4-frontend:8080/health/ready >/dev/null'
  printf 'Verified ClusterIP and NodePort endpoints; frontend NodePort is %s.\n' "$node_port"
}

status() {
  kubectl get deployment,pod,service,endpoints -n "$NAMESPACE" -l lab=4.1 -o wide
  kubectl get endpointslice -n "$NAMESPACE" \
    -l 'kubernetes.io/service-name in (day4-backend,day4-frontend)'
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/services.yaml" --ignore-not-found
  kubectl delete -f "${LAB_DIR}/workloads.yaml" --ignore-not-found
  kubectl delete pod lab4-1-probe -n "$NAMESPACE" --ignore-not-found
}

case "$ACTION" in
  run) deploy; diagnose; fix; verify; status ;;
  deploy) deploy ;;
  diagnose) diagnose ;;
  fix) fix ;;
  verify) verify ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|diagnose|fix|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
