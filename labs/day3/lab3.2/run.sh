#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="security-lockdown"
ACTION="${1:-run}"

source "${ROOT_DIR}/labs/common/images.sh"

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  IMAGE="$(resolve_workload_image "${IMAGE:-}" \
    advanced-observability traffic-ingest 'app=traffic-ingest')"
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  sed "s|ckad/traffic-ingest:local|${IMAGE}|" "${LAB_DIR}/pod.yaml" | kubectl apply -f -
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=120s
}

verify() {
  local uid rootfs
  uid="$(kubectl exec -n "$NAMESPACE" "$POD" -c log-sidecar -- cat /evidence/uid)"
  rootfs="$(kubectl exec -n "$NAMESPACE" "$POD" -c log-sidecar -- cat /evidence/rootfs)"
  [[ "$uid" != "0" ]] || { printf 'Security check unexpectedly ran as root.\n' >&2; exit 1; }
  [[ "$rootfs" == "read-only" ]] || { printf 'Root filesystem was unexpectedly writable.\n' >&2; exit 1; }
  kubectl exec -n "$NAMESPACE" "$POD" -c log-sidecar -- \
    wget -qO- http://127.0.0.1:8080/health/ready >/dev/null
  kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{range .spec.containers[*]}{.name}{" nonRoot="}{.securityContext.runAsNonRoot}{" readOnly="}{.securityContext.readOnlyRootFilesystem}{" noEscalation="}{.securityContext.allowPrivilegeEscalation}{" drop="}{.securityContext.capabilities.drop}{"\n"}{end}'
  printf 'Verified application health, non-root UID %s, and blocked root-filesystem write.\n' "$uid"
}

case "$ACTION" in
  run) deploy; verify ;;
  deploy) deploy ;;
  verify) verify ;;
  status) kubectl get pod "$POD" -n "$NAMESPACE" -o wide; kubectl describe pod "$POD" -n "$NAMESPACE" ;;
  cleanup) kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
