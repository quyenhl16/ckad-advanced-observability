#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly NAMESPACE="${NAMESPACE:-advanced-observability}"

REGISTRY="ckad"
IMAGE_TAG="1.0.0"
CANARY_TAG="1.1.0"
DATABASE_NODE="node-2"
DATABASE_PATH="/var/lib/observability-postgres"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-5m}"
PROFILE="dev"

usage() {
  cat <<'EOF'
Usage:
  POSTGRES_PASSWORD='...' ALERT_API_KEY='...' ./scripts/deploy-helm.sh [options]

Install or upgrade all service charts in dependency order in the main
advanced-observability namespace.

Options:
  --registry PATH      Image prefix (default: ckad)
  --tag TAG            Stable application image tag (default: 1.0.0)
  --canary-tag TAG     traffic-ingest canary tag (default: 1.1.0)
  --db-node NAME       Hostname for the local PostgreSQL PV (default: node-2)
  --db-path PATH       PostgreSQL directory on that node
  --profile NAME       dev or prod (default: dev)
  --timeout DURATION   Helm wait timeout (default: 5m)
  -h, --help           Show help

Required environment variables:
  POSTGRES_PASSWORD, ALERT_API_KEY

Optional secret variables:
  POSTGRES_USER, POSTGRES_DB, SMTP_ADDRESS, SMTP_HOST, SMTP_USERNAME,
  SMTP_PASSWORD, SMTP_FROM

Do not run this over resources created by Kustomize. Clean the old deployment
first with: ./scripts/cleanup.sh --confirm advanced-observability
EOF
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while (($# > 0)); do
  case "$1" in
    --registry) (($# >= 2)) || die '--registry requires a value'; REGISTRY="${2%/}"; shift 2 ;;
    --tag) (($# >= 2)) || die '--tag requires a value'; IMAGE_TAG="$2"; shift 2 ;;
    --canary-tag) (($# >= 2)) || die '--canary-tag requires a value'; CANARY_TAG="$2"; shift 2 ;;
    --db-node) (($# >= 2)) || die '--db-node requires a value'; DATABASE_NODE="$2"; shift 2 ;;
    --db-path) (($# >= 2)) || die '--db-path requires a value'; DATABASE_PATH="$2"; shift 2 ;;
    --profile) (($# >= 2)) || die '--profile requires a value'; PROFILE="$2"; shift 2 ;;
    --timeout) (($# >= 2)) || die '--timeout requires a value'; ROLLOUT_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ "$PROFILE" == dev || "$PROFILE" == prod ]] || die '--profile must be dev or prod'
[[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || die "Invalid namespace: $NAMESPACE"
[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "Invalid image tag: $IMAGE_TAG"
[[ "$CANARY_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || die "Invalid canary tag: $CANARY_TAG"
[[ -n "$REGISTRY" ]] || die 'Registry prefix cannot be empty'
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die 'POSTGRES_PASSWORD is required'
[[ -n "${ALERT_API_KEY:-}" ]] || die 'ALERT_API_KEY is required'

require_command kubectl
require_command helm

POSTGRES_USER="${POSTGRES_USER:-observability}"
POSTGRES_DB="${POSTGRES_DB:-observability}"
SMTP_ADDRESS="${SMTP_ADDRESS:-smtp.example.com:587}"
SMTP_HOST="${SMTP_HOST:-smtp.example.com}"
SMTP_USERNAME="${SMTP_USERNAME:-unused}"
SMTP_PASSWORD="${SMTP_PASSWORD:-unused}"
SMTP_FROM="${SMTP_FROM:-alerts@example.com}"
DEPLOY_REVISION="$(date -u +%Y%m%d%H%M%S)-$$"

for secret_name in POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB ALERT_API_KEY \
  SMTP_ADDRESS SMTP_HOST SMTP_USERNAME SMTP_PASSWORD SMTP_FROM; do
  secret_value="${!secret_name}"
  [[ "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] || \
    die "${secret_name} must not contain a newline"
done

printf 'Kubernetes context: '
kubectl config current-context

for resource in \
  statefulset/observability-db deployment/alert-manager \
  deployment/analytics-engine deployment/traffic-ingest \
  deployment/observability-frontend; do
  if kubectl get "$resource" -n "$NAMESPACE" >/dev/null 2>&1; then
    managed_by="$(kubectl get "$resource" -n "$NAMESPACE" \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')"
    [[ "$managed_by" == Helm ]] || \
      die "$resource already exists but is not managed by Helm; run project cleanup first"
  fi
done

for resource in storageclass/observability-local pv/observability-db-pv-node2; do
  if kubectl get "$resource" >/dev/null 2>&1; then
    managed_by="$(kubectl get "$resource" \
      -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}')"
    [[ "$managed_by" == Helm ]] || \
      die "$resource already exists but is not managed by Helm; run project cleanup first"
  fi
done

printf '\n==> Prepare namespace and runtime Secret\n'
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NAMESPACE" \
  app.kubernetes.io/part-of=advanced-observability \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted --overwrite

umask 077
SECRET_ENV_FILE="$(mktemp)"
cleanup() {
  if [[ -n "${SECRET_ENV_FILE:-}" && -f "$SECRET_ENV_FILE" && ! -L "$SECRET_ENV_FILE" ]]; then
    rm -f -- "$SECRET_ENV_FILE"
  fi
}
trap cleanup EXIT
printf '%s\n' \
  "POSTGRES_USER=${POSTGRES_USER}" \
  "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" \
  "POSTGRES_DB=${POSTGRES_DB}" \
  "ALERT_API_KEY=${ALERT_API_KEY}" \
  "SMTP_ADDRESS=${SMTP_ADDRESS}" \
  "SMTP_HOST=${SMTP_HOST}" \
  "SMTP_USERNAME=${SMTP_USERNAME}" \
  "SMTP_PASSWORD=${SMTP_PASSWORD}" \
  "SMTP_FROM=${SMTP_FROM}" >"$SECRET_ENV_FILE"
kubectl create secret generic observability-secrets -n "$NAMESPACE" \
  --from-env-file="$SECRET_ENV_FILE" --dry-run=client -o yaml | kubectl apply -f -

printf '\n==> Install namespace-level controls\n'
helm upgrade --install observability-platform "${ROOT_DIR}/helm/observability-platform" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT"

printf '\n==> Install observability-db\n'
helm upgrade --install observability-db "${ROOT_DIR}/helm/observability-db" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT" \
  --set-string "persistence.local.nodeHostname=${DATABASE_NODE}" \
  --set-string "persistence.local.path=${DATABASE_PATH}" \
  --set-string "podAnnotations.observability\\.io/deploy-revision=${DEPLOY_REVISION}"

printf '\n==> Synchronize the retained PostgreSQL role password\n'
if ! printf '%s\n' "ALTER ROLE CURRENT_USER WITH PASSWORD :'db_password';" | \
  kubectl exec -i observability-db-0 -n "$NAMESPACE" -- \
  sh -ec 'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 --set=db_password="$POSTGRES_PASSWORD"'; then
  die 'Could not synchronize the retained PostgreSQL role; POSTGRES_USER and POSTGRES_DB must match the existing database'
fi

ALERT_REPLICAS=1
FRONTEND_REPLICAS=1
TRAFFIC_MIN_REPLICAS=2
TRAFFIC_MAX_REPLICAS=6
if [[ "$PROFILE" == prod ]]; then
  ALERT_REPLICAS=2
  FRONTEND_REPLICAS=2
  TRAFFIC_MIN_REPLICAS=3
  TRAFFIC_MAX_REPLICAS=8
fi

printf '\n==> Install alert-manager\n'
helm upgrade --install alert-manager "${ROOT_DIR}/helm/alert-manager" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT" \
  --set-string "image.repository=${REGISTRY}/alert-manager" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set "replicaCount=${ALERT_REPLICAS}"

printf '\n==> Install analytics-engine\n'
helm upgrade --install analytics-engine "${ROOT_DIR}/helm/analytics-engine" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT" \
  --set-string "image.repository=${REGISTRY}/analytics-engine" \
  --set-string "image.tag=${IMAGE_TAG}"

printf '\n==> Install traffic-ingest\n'
helm upgrade --install traffic-ingest "${ROOT_DIR}/helm/traffic-ingest" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT" \
  --set-string "image.repository=${REGISTRY}/traffic-ingest" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set-string "canary.image.repository=${REGISTRY}/traffic-ingest-canary" \
  --set-string "canary.image.tag=${CANARY_TAG}" \
  --set "autoscaling.minReplicas=${TRAFFIC_MIN_REPLICAS}" \
  --set "autoscaling.maxReplicas=${TRAFFIC_MAX_REPLICAS}"

printf '\n==> Install observability-frontend and Ingress\n'
helm upgrade --install observability-frontend "${ROOT_DIR}/helm/observability-frontend" \
  -n "$NAMESPACE" --wait --atomic --timeout "$ROLLOUT_TIMEOUT" \
  --set-string "image.repository=${REGISTRY}/observability-frontend" \
  --set-string "image.tag=${IMAGE_TAG}" \
  --set "replicaCount=${FRONTEND_REPLICAS}"

printf '\n==> Helm releases\n'
helm list -n "$NAMESPACE"
printf '\n==> Workloads and endpoints\n'
kubectl get pods,services,hpa,ingress,pvc -n "$NAMESPACE" -o wide

printf '\nHelm deployment completed. Verify with:\n'
printf '  ./scripts/verify-helm.sh --live\n'
