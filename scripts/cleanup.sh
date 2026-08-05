#!/usr/bin/env bash
set -Eeuo pipefail

readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly DATABASE_PV="observability-db-pv-node2"
readonly DATABASE_STORAGE_CLASS="observability-local"

CONFIRMATION=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/cleanup.sh --confirm advanced-observability [options]

Delete all project Kubernetes resources managed by this repository. The local
PostgreSQL files on node-2 are retained and this script never connects to a
cluster node through SSH.

Options:
  --confirm NAME       Required safety token; must equal the namespace
  -h, --help           Show this help

Environment:
  NAMESPACE            Project namespace (default: advanced-observability)

This script does not remove the CNI, Ingress controller, Metrics Server,
default dynamic StorageClass or /var/lib/observability-postgres on node-2.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

while (($# > 0)); do
  case "$1" in
    --confirm)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --confirm requires a value' >&2; exit 2; }
      CONFIRMATION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || {
  printf 'ERROR: invalid namespace: %s\n' "$NAMESPACE" >&2
  exit 2
}
[[ "$CONFIRMATION" == "$NAMESPACE" ]] || {
  printf 'ERROR: pass --confirm %s to authorize project cleanup.\n' "$NAMESPACE" >&2
  exit 2
}

require_command kubectl

printf 'Kubernetes context: '
kubectl config current-context
printf 'Cleanup targets:\n'
printf '  namespace:     %s\n' "$NAMESPACE"
printf '  PV:            %s\n' "$DATABASE_PV"
printf '  StorageClass:  %s\n' "$DATABASE_STORAGE_CLASS"
printf '  database data: retained on node-2\n'

printf '\nDeleting project namespace and cluster-scoped storage objects...\n'
kubectl delete namespace "$NAMESPACE" \
  --ignore-not-found --wait=true --timeout=300s
kubectl delete pv "$DATABASE_PV" \
  --ignore-not-found --wait=true --timeout=120s
kubectl delete storageclass "$DATABASE_STORAGE_CLASS" --ignore-not-found

printf '\nCleanup completed successfully.\n'
printf 'PostgreSQL files remain at /var/lib/observability-postgres on node-2.\n'
printf 'Redeploy with:\n'
printf '  ./scripts/deploy.sh --cluster generic --overlay prod --registry REGISTRY/PATH\n'
