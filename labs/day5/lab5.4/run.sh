#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly CHART_DIR="${LAB_DIR}/chart/observer-demo"
readonly NAMESPACE="ckad-labs"
readonly RELEASE="${RELEASE:-day5-observer}"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

require_tools() {
  command -v helm >/dev/null || {
    printf 'helm is required for Lab 5.4.\n' >&2
    return 1
  }
  command -v kubectl >/dev/null || {
    printf 'kubectl is required for Lab 5.4.\n' >&2
    return 1
  }
}

install_release() {
  local image
  require_tools
  image="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  helm upgrade --install "$RELEASE" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set replicaCount="${REPLICAS:-1}" \
    --set-string image.ref="${image}" \
    --set-string message="${MESSAGE:-release-v1}" \
    --set service.type="${SERVICE_TYPE:-ClusterIP}" \
    --wait --timeout 3m
}

upgrade_release() {
  local image
  require_tools
  image="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  helm upgrade "$RELEASE" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    --reuse-values \
    --set replicaCount="${REPLICAS:-2}" \
    --set-string image.ref="${image}" \
    --set-string message="${MESSAGE:-release-v2}" \
    --wait --timeout 3m
}

previous_revision() {
  local revisions count
  revisions="$(helm history "$RELEASE" -n "$NAMESPACE" --max 2 \
    | awk 'NR > 1 && $1 ~ /^[0-9]+$/ {print $1}')"
  count="$(wc -w <<<"$revisions")"
  [[ "$count" -ge 2 ]] || {
    printf 'Release %s needs at least two revisions before rollback.\n' "$RELEASE" >&2
    return 1
  }
  sort -n <<<"$revisions" | head -n 1
}

rollback_release() {
  local revision
  require_tools
  revision="${REVISION:-$(previous_revision)}"
  helm rollback "$RELEASE" "$revision" \
    --namespace "$NAMESPACE" \
    --wait --timeout 3m
  printf 'Rolled back %s to revision %s.\n' "$RELEASE" "$revision"
}

verify() {
  local config_name health image message
  require_tools
  message="$(kubectl get configmap "$RELEASE" -n "$NAMESPACE" \
    -o jsonpath='{.data.index\.html}')"
  config_name="$(kubectl get deployment "$RELEASE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="LAB_RELEASE_MESSAGE")].valueFrom.configMapKeyRef.name}')"
  image="$(kubectl get deployment "$RELEASE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
  [[ "$config_name" == "$RELEASE" ]]
  kubectl delete pod lab5-4-probe -n "$NAMESPACE" \
    --ignore-not-found --wait=false >/dev/null
  health="$(kubectl run lab5-4-probe -n "$NAMESPACE" --rm --attach --restart=Never \
    --image=busybox:1.37 --command -- \
    wget -qO- -T 5 "http://${RELEASE}:8080/health/ready")"
  [[ -n "$health" ]]
  printf 'Verified image %s, chart message %s, and application health.\n' \
    "$image" "$message"
}

history() {
  require_tools
  helm status "$RELEASE" -n "$NAMESPACE"
  helm history "$RELEASE" -n "$NAMESPACE"
}

cleanup() {
  require_tools
  helm uninstall "$RELEASE" -n "$NAMESPACE" --ignore-not-found
  kubectl delete pod lab5-4-probe -n "$NAMESPACE" --ignore-not-found
}

case "$ACTION" in
  run) install_release; upgrade_release; history; rollback_release; verify; history ;;
  install) install_release ;;
  upgrade) upgrade_release ;;
  rollback) rollback_release ;;
  verify) verify ;;
  history) history ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|install|upgrade|rollback|verify|history|cleanup}\n' "$0" >&2; exit 1 ;;
esac
