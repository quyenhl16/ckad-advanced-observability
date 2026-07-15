#!/usr/bin/env bash

# Resolve an application image without trusting a possibly broken Deployment
# rollout. Explicit overrides win, followed by a currently Running Pod. The
# Deployment spec is used only when it does not point at the local placeholder.
resolve_workload_image() {
  local override="$1"
  local namespace="$2"
  local deployment="$3"
  local selector="$4"
  local candidate=""

  if [[ -n "$override" ]]; then
    printf 'Using explicitly configured image: %s\n' "$override" >&2
    printf '%s' "$override"
    return 0
  fi

  candidate="$(kubectl get pods \
    --namespace "$namespace" \
    --selector "$selector" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].spec.containers[0].image}' \
    2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf 'Using image from a Running production Pod: %s\n' "$candidate" >&2
    printf '%s' "$candidate"
    return 0
  fi

  candidate="$(kubectl get deployment "$deployment" \
    --namespace "$namespace" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' \
    2>/dev/null || true)"
  if [[ -n "$candidate" && "$candidate" != ckad/*:local ]]; then
    printf 'Using image from production Deployment: %s\n' "$candidate" >&2
    printf '%s' "$candidate"
    return 0
  fi

  if [[ "$candidate" == ckad/*:local ]]; then
    printf 'ERROR: Deployment %s/%s points to local placeholder image %s, and no Running Pod image was found.\n' \
      "$namespace" "$deployment" "$candidate" >&2
  else
    printf 'ERROR: Could not discover an image from Deployment %s/%s or its Running Pods.\n' \
      "$namespace" "$deployment" >&2
  fi
  printf 'Set IMAGE to a pullable registry image, for example:\n' >&2
  printf '  IMAGE=10.206.0.3:5000/<service>:<tag> %s\n' "$0" >&2
  return 1
}
