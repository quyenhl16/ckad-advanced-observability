#!/usr/bin/env bash
set -Eeuo pipefail

readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly DATABASE_PV="observability-db-pv-node2"
readonly DATABASE_STORAGE_CLASS="observability-local"
readonly DATABASE_DIR="/var/lib/observability-postgres"

DATA_NODE="${DATA_NODE:-node-2}"
CONFIRMATION=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/cleanup.sh --confirm advanced-observability [options]

Delete all project Kubernetes resources and prepare node-2 for a fresh
PostgreSQL deployment. All existing files under the validated database
directory are permanently deleted.

Options:
  --confirm NAME       Required safety token; must equal the namespace
  --data-node NAME     Node reached through SSH (default: node-2)
  -h, --help           Show this help

Environment:
  NAMESPACE            Project namespace (default: advanced-observability)
  DATA_NODE            Same as --data-node

This script does not remove the CNI, Ingress controller, Metrics Server,
default dynamic StorageClass or files outside the validated database path.
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
    --data-node)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --data-node requires a value' >&2; exit 2; }
      DATA_NODE="$2"
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
[[ "$DATA_NODE" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || {
  printf 'ERROR: invalid data node name: %s\n' "$DATA_NODE" >&2
  exit 2
}
[[ "$CONFIRMATION" == "$NAMESPACE" ]] || {
  printf 'ERROR: pass --confirm %s to authorize project cleanup.\n' "$NAMESPACE" >&2
  exit 2
}

require_command kubectl
require_command ssh

printf 'Kubernetes context: '
kubectl config current-context
printf 'Cleanup targets:\n'
printf '  namespace:     %s\n' "$NAMESPACE"
printf '  PV:            %s\n' "$DATABASE_PV"
printf '  StorageClass:  %s\n' "$DATABASE_STORAGE_CLASS"
printf '  database data: permanently removed from %s on %s\n' "$DATABASE_DIR" "$DATA_NODE"
kubectl get node "$DATA_NODE" >/dev/null
ssh -o ConnectTimeout=10 "$DATA_NODE" \
  'command -v bash >/dev/null && command -v realpath >/dev/null && command -v find >/dev/null && command -v install >/dev/null && command -v mktemp >/dev/null && command -v rm >/dev/null && { test "$(id -u)" -eq 0 || command -v sudo >/dev/null; }'

printf '\nDeleting project namespace and cluster-scoped storage objects...\n'
kubectl delete namespace "$NAMESPACE" \
  --ignore-not-found --wait=true --timeout=300s
kubectl delete pv "$DATABASE_PV" \
  --ignore-not-found --wait=true --timeout=120s
kubectl delete storageclass "$DATABASE_STORAGE_CLASS" --ignore-not-found

printf '\nPurging the retained PostgreSQL directory on %s...\n' "$DATA_NODE"
ssh -o ConnectTimeout=10 "$DATA_NODE" bash -s -- "$DATABASE_DIR" <<'REMOTE_SCRIPT'
set -Eeuo pipefail

readonly expected_dir=/var/lib/observability-postgres
readonly database_dir="${1:?database directory is required}"

if [[ "$EUID" -eq 0 ]]; then
  privileged=()
else
  privileged=(sudo)
fi

[[ "$database_dir" == "$expected_dir" ]] || {
  printf 'ERROR: unexpected database directory: %s\n' "$database_dir" >&2
  exit 1
}

if [[ -e "$database_dir" || -L "$database_dir" ]]; then
  [[ -d "$database_dir" && ! -L "$database_dir" ]] || {
    printf 'ERROR: database path is not a regular directory: %s\n' "$database_dir" >&2
    exit 1
  }

  resolved_dir="$(realpath -e -- "$database_dir")"
  [[ "$resolved_dir" == "$expected_dir" ]] || {
    printf 'ERROR: database directory resolved outside the expected path: %s\n' "$resolved_dir" >&2
    exit 1
  }

  target_count=0
  symlink_count=0
  targets_file="$(mktemp /tmp/observability-cleanup-targets.XXXXXX)"
  symlinks_file="$(mktemp /tmp/observability-cleanup-symlinks.XXXXXX)"
  [[ "$targets_file" == /tmp/observability-cleanup-targets.* ]]
  [[ "$symlinks_file" == /tmp/observability-cleanup-symlinks.* ]]
  cleanup_manifests() {
    rm -f -- "$targets_file" "$symlinks_file"
  }
  trap cleanup_manifests EXIT

  "${privileged[@]}" find "$database_dir" -xdev -mindepth 1 -print0 >"$targets_file"
  "${privileged[@]}" find "$database_dir" -xdev -mindepth 1 -type l -print0 >"$symlinks_file"

  printf 'Database targets to remove:\n'
  while IFS= read -r -d '' target; do
    printf '  %q\n' "$target"
    target_count=$((target_count + 1))
  done <"$targets_file"
  while IFS= read -r -d '' target; do
    symlink_count=$((symlink_count + 1))
  done <"$symlinks_file"
  printf 'Target count: %d\n' "$target_count"
  printf 'Symlink count: %d (removed as links; never followed)\n' "$symlink_count"

  "${privileged[@]}" find "$database_dir" -xdev -mindepth 1 -delete

  : >"$targets_file"
  "${privileged[@]}" find "$database_dir" -xdev -mindepth 1 -print0 >"$targets_file"
  remaining_count=0
  while IFS= read -r -d '' target; do
    remaining_count=$((remaining_count + 1))
  done <"$targets_file"
  [[ "$remaining_count" -eq 0 ]] || {
    printf 'ERROR: database cleanup left %d target(s); stopping.\n' "$remaining_count" >&2
    exit 1
  }
  printf 'Permanently removed %d database target(s).\n' "$target_count"
fi

"${privileged[@]}" install -d -o 70 -g 70 -m 700 "$expected_dir"
printf 'Fresh database directory prepared at %s\n' "$expected_dir"
REMOTE_SCRIPT

printf '\nCleanup completed successfully.\n'
printf 'Redeploy with:\n'
printf '  ./scripts/deploy.sh --cluster generic --overlay prod --registry REGISTRY/PATH\n'
