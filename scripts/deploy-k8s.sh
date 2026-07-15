#!/usr/bin/env bash
set -Eeuo pipefail

# Build and deploy the application from source to Kubernetes.
# Designed for Bash on CentOS Stream 10 and compatible Linux distributions.

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly DEPLOYMENTS_DIR="${ROOT_DIR}/deployments"
readonly NAMESPACE="advanced-observability"
readonly SERVICES=(traffic-ingest analytics-engine alert-manager observability-frontend)

CLUSTER_TYPE="auto"
CLUSTER_NAME=""
REGISTRY=""
IMAGE_TAG=""
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-300s}"
SKIP_BUILD=false

usage() {
  cat <<'EOF'
Usage:
  ./scripts/deploy-k8s.sh [options]

Options:
  --cluster TYPE       auto, kind, minikube, or generic (default: auto)
  --cluster-name NAME  Kind cluster name or Minikube profile
  --registry HOST/PATH Registry prefix for a generic cluster, for example
                       registry.example.com/team (required for generic)
  --tag TAG            Image tag (default: Git commit plus UTC timestamp)
  --engine ENGINE      docker or podman (default: auto-detect)
  --timeout DURATION   kubectl rollout timeout (default: 300s)
  --skip-build         Reuse images already present in the container engine
  -h, --help           Show this help

Secrets are read from environment variables. For a shared cluster, set at least:
  POSTGRES_PASSWORD and ALERT_API_KEY

Examples:
  # Current context is a Kind cluster
  POSTGRES_PASSWORD='db-secret' ALERT_API_KEY='api-secret' \
    ./scripts/deploy-k8s.sh --cluster kind --cluster-name observability

  # Remote cluster whose nodes can pull from an authenticated registry
  podman login registry.example.com
  POSTGRES_PASSWORD='db-secret' ALERT_API_KEY='api-secret' \
    ./scripts/deploy-k8s.sh --cluster generic \
      --registry registry.example.com/my-team
EOF
}

log() {
  printf '\n==> %s\n' "$*"
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
    --cluster)
      (($# >= 2)) || die "--cluster requires a value"
      CLUSTER_TYPE="$2"
      shift 2
      ;;
    --cluster-name)
      (($# >= 2)) || die "--cluster-name requires a value"
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --registry)
      (($# >= 2)) || die "--registry requires a value"
      REGISTRY="${2%/}"
      shift 2
      ;;
    --tag)
      (($# >= 2)) || die "--tag requires a value"
      IMAGE_TAG="$2"
      shift 2
      ;;
    --engine)
      (($# >= 2)) || die "--engine requires a value"
      CONTAINER_ENGINE="$2"
      shift 2
      ;;
    --timeout)
      (($# >= 2)) || die "--timeout requires a value"
      ROLLOUT_TIMEOUT="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

case "$CLUSTER_TYPE" in
  auto|kind|minikube|generic) ;;
  *) die "Unsupported cluster type: ${CLUSTER_TYPE}" ;;
esac

case "$CONTAINER_ENGINE" in
  "")
    if command -v docker >/dev/null 2>&1; then
      CONTAINER_ENGINE="docker"
    elif command -v podman >/dev/null 2>&1; then
      CONTAINER_ENGINE="podman"
    else
      die "Install Docker or Podman before running this script"
    fi
    ;;
  docker|podman) require_command "$CONTAINER_ENGINE" ;;
  *) die "Unsupported container engine: ${CONTAINER_ENGINE}" ;;
esac

require_command kubectl

CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null)" || \
  die "No current kubectl context is configured"

if [[ "$CLUSTER_TYPE" == "auto" ]]; then
  case "$CURRENT_CONTEXT" in
    kind-*) CLUSTER_TYPE="kind" ;;
    minikube|*-minikube) CLUSTER_TYPE="minikube" ;;
    *) CLUSTER_TYPE="generic" ;;
  esac
fi

if [[ "$CLUSTER_TYPE" == "kind" ]]; then
  require_command kind
  [[ -n "$CLUSTER_NAME" ]] || CLUSTER_NAME="${CURRENT_CONTEXT#kind-}"
  if [[ "$CONTAINER_ENGINE" == "podman" ]]; then
    export KIND_EXPERIMENTAL_PROVIDER="${KIND_EXPERIMENTAL_PROVIDER:-podman}"
  fi
elif [[ "$CLUSTER_TYPE" == "minikube" ]]; then
  require_command minikube
  [[ -n "$CLUSTER_NAME" ]] || CLUSTER_NAME="minikube"
elif [[ -z "$REGISTRY" ]]; then
  die "--registry is required for a generic cluster"
fi

if [[ -z "$IMAGE_TAG" ]]; then
  DEPLOY_TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
  if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IMAGE_TAG="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)-${DEPLOY_TIMESTAMP}"
  else
    IMAGE_TAG="$DEPLOY_TIMESTAMP"
  fi
fi

[[ "$IMAGE_TAG" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || \
  die "Invalid container image tag: ${IMAGE_TAG}"

if [[ "$CLUSTER_TYPE" == "generic" ]]; then
  [[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD is required for a generic cluster"
  [[ -n "${ALERT_API_KEY:-}" ]] || die "ALERT_API_KEY is required for a generic cluster"
else
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-local-observability-password}"
  ALERT_API_KEY="${ALERT_API_KEY:-local-observability-api-key}"
fi

POSTGRES_USER="${POSTGRES_USER:-observability}"
POSTGRES_DB="${POSTGRES_DB:-observability}"
SMTP_ADDRESS="${SMTP_ADDRESS:-smtp.example.com:587}"
SMTP_HOST="${SMTP_HOST:-smtp.example.com}"
SMTP_USERNAME="${SMTP_USERNAME:-change-me}"
SMTP_PASSWORD="${SMTP_PASSWORD:-change-me}"
SMTP_FROM="${SMTP_FROM:-alerts@example.com}"

for secret_name in \
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB ALERT_API_KEY \
  SMTP_ADDRESS SMTP_HOST SMTP_USERNAME SMTP_PASSWORD SMTP_FROM; do
  secret_value="${!secret_name}"
  [[ "$secret_value" != *$'\n'* && "$secret_value" != *$'\r'* ]] || \
    die "${secret_name} must not contain a newline"
done

log "Step 1/7: Validate access to Kubernetes context '${CURRENT_CONTEXT}'"
kubectl cluster-info >/dev/null
kubectl auth can-i create deployments.apps --namespace "$NAMESPACE" >/dev/null || \
  die "Current Kubernetes identity cannot create deployments in ${NAMESPACE}"

declare -A IMAGE_NAMES
for service in "${SERVICES[@]}"; do
  if [[ "$CLUSTER_TYPE" == "generic" ]]; then
    IMAGE_NAMES["$service"]="${REGISTRY}/${service}"
  else
    IMAGE_NAMES["$service"]="ckad/${service}"
  fi
done

if [[ "$SKIP_BUILD" == false ]]; then
  log "Step 2/7: Build application images from source with ${CONTAINER_ENGINE}"
  for service in "${SERVICES[@]}"; do
    image="${IMAGE_NAMES[$service]}:${IMAGE_TAG}"
    printf 'Building %s\n' "$image"
    "$CONTAINER_ENGINE" build \
      --build-arg "SERVICE=${service}" \
      --tag "$image" \
      "$ROOT_DIR"
  done
else
  log "Step 2/7: Skip image build"
fi

log "Step 3/7: Make application images available to cluster nodes"
for service in "${SERVICES[@]}"; do
  image="${IMAGE_NAMES[$service]}:${IMAGE_TAG}"
  case "$CLUSTER_TYPE" in
    kind)
      kind load docker-image "$image" --name "$CLUSTER_NAME"
      ;;
    minikube)
      minikube image load "$image" --profile "$CLUSTER_NAME"
      ;;
    generic)
      "$CONTAINER_ENGINE" push "$image"
      ;;
  esac
done

OVERLAY_DIR="$(mktemp -d "${DEPLOYMENTS_DIR}/.deploy-overlay.XXXXXX")"
cleanup() {
  rm -rf -- "$OVERLAY_DIR"
}
trap cleanup EXIT
umask 077

cat >"${OVERLAY_DIR}/secrets.env" <<EOF
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
ALERT_API_KEY=${ALERT_API_KEY}
SMTP_ADDRESS=${SMTP_ADDRESS}
SMTP_HOST=${SMTP_HOST}
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_FROM=${SMTP_FROM}
EOF

cat >"${OVERLAY_DIR}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE}
resources:
  - ../base
images:
  - name: ckad/traffic-ingest
    newName: ${IMAGE_NAMES[traffic-ingest]}
    newTag: ${IMAGE_TAG}
  - name: ckad/analytics-engine
    newName: ${IMAGE_NAMES[analytics-engine]}
    newTag: ${IMAGE_TAG}
  - name: ckad/alert-manager
    newName: ${IMAGE_NAMES[alert-manager]}
    newTag: ${IMAGE_TAG}
  - name: ckad/observability-frontend
    newName: ${IMAGE_NAMES[observability-frontend]}
    newTag: ${IMAGE_TAG}
secretGenerator:
  - name: observability-secrets
    namespace: ${NAMESPACE}
    behavior: replace
    envs:
      - secrets.env
generatorOptions:
  disableNameSuffixHash: true
EOF

log "Step 4/7: Validate generated Kubernetes manifests"
kubectl kustomize "$OVERLAY_DIR" >/dev/null

log "Step 5/7: Apply Kubernetes manifests"
kubectl apply -k "$OVERLAY_DIR"

log "Step 6/7: Wait for database and application rollouts"
if ! kubectl rollout status statefulset/observability-db \
  --namespace "$NAMESPACE" --timeout "$ROLLOUT_TIMEOUT"; then
  kubectl get pods --namespace "$NAMESPACE" -o wide
  die "Database rollout failed"
fi

for deployment in alert-manager analytics-engine traffic-ingest observability-frontend; do
  if ! kubectl rollout status "deployment/${deployment}" \
    --namespace "$NAMESPACE" --timeout "$ROLLOUT_TIMEOUT"; then
    kubectl get pods --namespace "$NAMESPACE" -o wide
    kubectl describe "deployment/${deployment}" --namespace "$NAMESPACE"
    die "Rollout failed: ${deployment}"
  fi
done

log "Step 7/7: Show deployed resources"
kubectl get pods,services,persistentvolumeclaims --namespace "$NAMESPACE" -o wide

cat <<EOF

Deployment completed successfully.

Frontend:
  kubectl port-forward --namespace ${NAMESPACE} service/observability-frontend 8083:8083
  Open http://localhost:8083

Traffic ingestion API (run in another terminal):
  kubectl port-forward --namespace ${NAMESPACE} service/traffic-ingest 8080:8080
  POST metrics to http://localhost:8080/api/v1/metrics
EOF
