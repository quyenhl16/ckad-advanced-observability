#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly INGRESS_HOST="${INGRESS_HOST:-day4.local}"
readonly INGRESS_CLASS="${INGRESS_CLASS:-nginx}"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

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
  sed \
    -e "s|INGRESS_CLASS_PLACEHOLDER|${INGRESS_CLASS}|" \
    -e "s|day4.local|${INGRESS_HOST}|g" \
    "${LAB_DIR}/ingress.yaml" | kubectl apply -f -
  kubectl rollout status deployment/ingress-backend -n "$NAMESPACE" --timeout=180s
  kubectl rollout status deployment/ingress-frontend -n "$NAMESPACE" --timeout=180s
}

controller_endpoint() {
  local controller_namespace controller_name controller_port
  if [[ -n "${INGRESS_ENDPOINT:-}" ]]; then
    case "$INGRESS_ENDPOINT" in
      http://*|https://*) printf '%s' "$INGRESS_ENDPOINT" | sed 's|/$||' ;;
      *) printf 'http://%s' "$INGRESS_ENDPOINT" | sed 's|/$||' ;;
    esac
    return 0
  fi
  if [[ -n "${INGRESS_CONTROLLER_SERVICE:-}" ]]; then
    [[ "$INGRESS_CONTROLLER_SERVICE" == */* ]] || {
      printf 'INGRESS_CONTROLLER_SERVICE must use namespace/name format.\n' >&2
      return 1
    }
    controller_namespace="${INGRESS_CONTROLLER_SERVICE%%/*}"
    controller_name="${INGRESS_CONTROLLER_SERVICE#*/}"
  else
    while IFS=/ read -r controller_namespace controller_name; do
      [[ -n "$controller_namespace" && -n "$controller_name" ]] || continue
      controller_port="$(kubectl get service "$controller_name" -n "$controller_namespace" \
        -o jsonpath='{.spec.ports[?(@.name=="http")].port}')"
      if [[ -n "$controller_port" ]]; then
        printf 'http://%s.%s.svc.cluster.local:%s' \
          "$controller_name" "$controller_namespace" "$controller_port"
        return 0
      fi
    done < <(kubectl get service --all-namespaces \
      -l app.kubernetes.io/component=controller \
      -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')
  fi
  [[ -n "$controller_namespace" && -n "$controller_name" ]] || {
    printf 'Could not discover an ingress controller Service. Set INGRESS_CONTROLLER_SERVICE=namespace/name or INGRESS_ENDPOINT=host:port.\n' >&2
    return 1
  }
  controller_port="$(kubectl get service "$controller_name" -n "$controller_namespace" \
    -o jsonpath='{.spec.ports[?(@.name=="http")].port}')"
  [[ -n "$controller_port" ]] || {
    printf 'Ingress controller Service %s/%s has no port named http. Set INGRESS_ENDPOINT explicitly.\n' \
      "$controller_namespace" "$controller_name" >&2
    return 1
  }
  printf 'http://%s.%s.svc.cluster.local:%s' \
    "$controller_name" "$controller_namespace" "$controller_port"
}

probe_route() {
  local endpoint="$1" path="$2" probe_name="$3"
  kubectl delete pod "$probe_name" -n "$NAMESPACE" --ignore-not-found --wait=false >/dev/null
  kubectl run "$probe_name" -n "$NAMESPACE" --rm --attach --restart=Never \
    --image=busybox:1.37 --command -- \
    sh -c 'wget -qO- -T 5 --header="Host: $1" "$2$3"' \
    sh "$INGRESS_HOST" "$endpoint" "$path"
}

verify() {
  local endpoint attempt
  [[ "$(kubectl get ingress day4-frontend -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')" == "ingress-frontend" ]]
  [[ "$(kubectl get ingress day4-backend -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')" == "ingress-backend" ]]
  endpoint="$(controller_endpoint)"
  for attempt in $(seq 1 30); do
    if probe_route "$endpoint" /health/ready lab4-2-frontend-probe >/dev/null 2>&1 && \
       probe_route "$endpoint" /api/health/ready lab4-2-backend-probe >/dev/null 2>&1; then
      printf 'Verified / -> frontend and /api -> backend through %s with Host %s.\n' "$endpoint" "$INGRESS_HOST"
      return 0
    fi
    sleep 2
  done
  printf 'Ingress routes did not become reachable through %s.\n' "$endpoint" >&2
  return 1
}

status() {
  kubectl get deployment,pod,service,ingress -n "$NAMESPACE" -l lab=4.2 -o wide
  kubectl describe ingress day4-frontend day4-backend -n "$NAMESPACE"
}

cleanup() {
  sed \
    -e "s|INGRESS_CLASS_PLACEHOLDER|${INGRESS_CLASS}|" \
    -e "s|day4.local|${INGRESS_HOST}|g" \
    "${LAB_DIR}/ingress.yaml" | kubectl delete -f - --ignore-not-found
  kubectl delete -f "${LAB_DIR}/workloads.yaml" --ignore-not-found
  kubectl delete pod lab4-2-frontend-probe lab4-2-backend-probe \
    -n "$NAMESPACE" --ignore-not-found
}

case "$ACTION" in
  run) deploy; verify; status ;;
  deploy) deploy ;;
  verify) verify ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
