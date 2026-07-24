#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly DEPLOYMENT="traffic-rollout"
ACTION="${1:-status}"

source "${ROOT_DIR}/labs/common/images.sh"

validate_version() {
  local version="$1"
  if [[ ! "$version" =~ ^[A-Za-z0-9]([A-Za-z0-9_.-]{0,61}[A-Za-z0-9])?$ ]]; then
    printf "Invalid version label '%s'. Use 1-63 letters, numbers, '.', '_' or '-'.\n" \
      "$version" >&2
    exit 1
  fi
}

patch_rollout() {
  local image="$1"
  local version="$2"

  validate_version "$version"
  kubectl patch deployment "$DEPLOYMENT" -n "$NAMESPACE" --type=strategic \
    -p "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"version\":\"${version}\"}},\"spec\":{\"containers\":[{\"name\":\"app\",\"image\":\"${image}\"}]}}}}"
}

case "$ACTION" in
  deploy)
    kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
    IMAGE_V1="$(resolve_workload_image "${IMAGE_V1:-${IMAGE:-}}" \
      advanced-observability traffic-ingest 'app=traffic-ingest')"
    VERSION_V1="${VERSION_V1:-v1}"
    validate_version "$VERSION_V1"
    sed \
      -e "s|ckad/traffic-ingest:local|${IMAGE_V1}|" \
      -e "s|version: v1|version: ${VERSION_V1}|" \
      "${LAB_DIR}/deployment.yaml" | kubectl apply -f -
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  update)
    [[ -n "${IMAGE_V2:-}" ]] || { printf 'Set IMAGE_V2 to a valid second image tag.\n' >&2; exit 1; }
    VERSION_V2="${VERSION_V2:-v2}"
    patch_rollout "$IMAGE_V2" "$VERSION_V2"
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  fail)
    patch_rollout \
      invalid.invalid/traffic-ingest:does-not-exist \
      "${VERSION_FAIL:-failed}"
    if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=45s; then
      printf 'Unexpected: bad rollout completed.\n' >&2
      exit 1
    fi
    printf 'Expected failure observed. Run: %s undo\n' "$0"
    ;;
  undo)
    kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
    ;;
  history)
    kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"
    ;;
  status)
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o wide
    kubectl get replicasets -n "$NAMESPACE" -l app="$DEPLOYMENT" -L version
    kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -L version -o wide
    ;;
  cleanup)
    kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
    ;;
  *)
    printf 'Usage: %s {deploy|update|fail|undo|history|status|cleanup}\n' "$0" >&2
    exit 1
    ;;
esac
