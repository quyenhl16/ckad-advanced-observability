#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly POD="security-lockdown"
ACTION="${1:-run}"

deploy() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${LAB_DIR}/pod.yaml"
  kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=120s
}

verify() {
  readonly uid="$(kubectl exec -n "$NAMESPACE" "$POD" -c app -- id -u)"
  [[ "$uid" != "0" ]] || { printf 'App unexpectedly runs as root.\n' >&2; exit 1; }
  if kubectl exec -n "$NAMESPACE" "$POD" -c app -- touch /rootfs-write-test 2>/dev/null; then
    printf 'Unexpectedly wrote to the read-only root filesystem.\n' >&2
    exit 1
  fi
  kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{range .spec.containers[*]}{.name}{" nonRoot="}{.securityContext.runAsNonRoot}{" readOnly="}{.securityContext.readOnlyRootFilesystem}{" noEscalation="}{.securityContext.allowPrivilegeEscalation}{" drop="}{.securityContext.capabilities.drop}{"\n"}{end}'
  printf 'Verified non-root UID %s and blocked root-filesystem write.\n' "$uid"
}

case "$ACTION" in
  run) deploy; verify ;;
  deploy) deploy ;;
  verify) verify ;;
  status) kubectl get pod "$POD" -n "$NAMESPACE" -o wide; kubectl describe pod "$POD" -n "$NAMESPACE" ;;
  cleanup) kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found ;;
  *) printf 'Usage: %s {run|deploy|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
