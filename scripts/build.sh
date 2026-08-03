#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly SERVICES=(traffic-ingest analytics-engine alert-manager observability-frontend)

ENGINE="${CONTAINER_ENGINE:-docker}"
REGISTRY="${REGISTRY_PREFIX:-ckad}"
TAG="${IMAGE_TAG:-}"
CANARY_TAG="${CANARY_IMAGE_TAG:-}"

if [[ -z "${TAG}" ]]; then
  TAG="$(git -C "${ROOT_DIR}" rev-parse --short=12 HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"
fi

[[ "${TAG}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || {
  printf 'Invalid image tag: %s\n' "${TAG}" >&2
  exit 1
}
[[ -n "${CANARY_TAG}" ]] || CANARY_TAG="${TAG}-canary"
[[ "${CANARY_TAG}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || {
  printf 'Invalid canary image tag: %s\n' "${CANARY_TAG}" >&2
  exit 1
}
command -v "${ENGINE}" >/dev/null 2>&1 || {
  printf 'Container engine not found: %s\n' "${ENGINE}" >&2
  exit 1
}

for service in "${SERVICES[@]}"; do
  image="${REGISTRY%/}/${service}:${TAG}"
  printf 'Building %s\n' "${image}"
  "${ENGINE}" build \
    --file "${ROOT_DIR}/services/${service}/Dockerfile" \
    --tag "${image}" \
    "${ROOT_DIR}"
done

"${ENGINE}" tag \
  "${REGISTRY%/}/traffic-ingest:${TAG}" \
  "${REGISTRY%/}/traffic-ingest-canary:${CANARY_TAG}"

printf 'Built core tag %s and canary tag %s.\n' "${TAG}" "${CANARY_TAG}"
