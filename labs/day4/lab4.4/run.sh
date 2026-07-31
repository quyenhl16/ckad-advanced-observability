#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="pvc-client"
readonly DATA_VALUE="ckad-day4-persistent-data"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

default_storage_class() {
  kubectl get storageclass \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' \
    | awk '$2 == "true" {print $1; exit}'
}

apply_pvc() {
  local storage_class
  storage_class="${STORAGE_CLASS:-$(default_storage_class)}"
  [[ -n "$storage_class" ]] || {
    printf 'No default StorageClass found. Set STORAGE_CLASS to a dynamic provisioner.\n' >&2
    return 1
  }
  if [[ -n "${STORAGE_CLASS:-}" ]]; then
    sed "/^  accessModes:/i\\  storageClassName: ${storage_class}" \
      "${LAB_DIR}/pvc.yaml" | kubectl apply -f -
  else
    kubectl apply -f "${LAB_DIR}/pvc.yaml"
  fi
  printf 'Using dynamic StorageClass: %s\n' "$storage_class"
}

apply_pod() {
  local image
  image="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  sed "s|ckad/traffic-ingest:local|${image}|" \
    "${LAB_DIR}/pod.yaml" | kubectl apply -f -
}

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  apply_pvc
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  apply_pod
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=180s
  [[ "$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.status.phase}')" == "Bound" ]]
  kubectl exec "$POD" -n "$NAMESPACE" -c storage-probe -- \
    sh -c 'printf "%s\n" "$1" > /data/day4.txt && sync' sh "$DATA_VALUE"
  printf 'Wrote persistent value through the first Pod.\n'
}

recreate() {
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  apply_pod
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=180s
  printf 'Recreated Pod with the original claim.\n'
}

verify() {
  local actual
  [[ "$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.status.phase}')" == "Bound" ]]
  actual="$(kubectl exec "$POD" -n "$NAMESPACE" -c storage-probe -- cat /data/day4.txt)"
  [[ "$actual" == "$DATA_VALUE" ]] || {
    printf 'Expected %s, found %s.\n' "$DATA_VALUE" "$actual" >&2
    return 1
  }
  printf 'Verified data after Pod recreation: %s\n' "$actual"
}

status() {
  kubectl get pod "$POD" -n "$NAMESPACE" -o wide
  kubectl get pvc day4-data -n "$NAMESPACE" -o wide
  kubectl get pv "$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')"
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/pod.yaml" --ignore-not-found
  kubectl delete -f "${LAB_DIR}/pvc.yaml" --ignore-not-found
}

case "$ACTION" in
  run) deploy; recreate; verify; status ;;
  deploy) deploy ;;
  recreate) recreate ;;
  verify) verify ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|deploy|recreate|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
