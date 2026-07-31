#!/usr/bin/env bash
set -Eeuo pipefail

readonly LAB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${LAB_DIR}/../../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly DEPLOYMENT="triage-app"
ACTION="${1:-run}"

diagnose_selector() {
  local output
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
  if output="$(kubectl apply -f "${LAB_DIR}/broken-selector.yaml" 2>&1)"; then
    printf 'Expected the Deployment selector mismatch to be rejected.\n' >&2
    return 1
  fi
  printf '%s\n' "$output"
  grep -Eqi 'selector.*(match|label)|does not match' <<<"$output" || {
    printf 'Apply failed, but the expected selector diagnostic was not found.\n' >&2
    return 1
  }
  printf 'Diagnosed Deployment selector/template label mismatch.\n'
}

runtime_failure() {
  local pod reason attempt container_port target_port
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found
  kubectl apply -f "${LAB_DIR}/broken-runtime.yaml"
  for attempt in $(seq 1 30); do
    pod="$(kubectl get pod -n "$NAMESPACE" -l app=triage-app \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    if [[ -n "$pod" ]]; then
      reason="$(kubectl get pod "$pod" -n "$NAMESPACE" \
        -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)"
      [[ "$reason" == "InvalidImageName" ]] && {
        printf 'Diagnosed invalid image name on Pod %s.\n' "$pod"
        container_port="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
          -o jsonpath='{.spec.template.spec.containers[0].ports[0].name}')"
        target_port="$(kubectl get service triage-app -n "$NAMESPACE" \
          -o jsonpath='{.spec.ports[0].targetPort}')"
        [[ "$container_port" != "$target_port" ]]
        printf 'Diagnosed Service targetPort %s; container port is named %s.\n' \
          "$target_port" "$container_port"
        kubectl describe pod "$pod" -n "$NAMESPACE"
        return 0
      }
    fi
    sleep 2
  done
  printf 'Expected InvalidImageName, observed %s.\n' "${reason:-no waiting reason}" >&2
  return 1
}

fix() {
  kubectl apply -f "${ROOT_DIR}/labs/common/namespace.yaml"
  kubectl apply -f "${LAB_DIR}/fixed.yaml"
  kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
}

endpoint_addresses() {
  kubectl get endpoints triage-app -n "$NAMESPACE" \
    -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true
}

verify() {
  local addresses attempt image target_port
  for attempt in $(seq 1 30); do
    addresses="$(endpoint_addresses)"
    [[ -n "$addresses" ]] && break
    sleep 2
  done
  [[ -n "${addresses:-}" ]] || {
    printf 'Service still has no ready endpoints.\n' >&2
    return 1
  }
  image="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].image}')"
  target_port="$(kubectl get service triage-app -n "$NAMESPACE" \
    -o jsonpath='{.spec.ports[0].targetPort}')"
  [[ "$image" == "busybox:1.37" ]]
  [[ "$target_port" == "http" ]]
  kubectl delete pod lab5-3-probe -n "$NAMESPACE" \
    --ignore-not-found --wait=false >/dev/null
  kubectl run lab5-3-probe -n "$NAMESPACE" --rm --attach --restart=Never \
    --image=busybox:1.37 --command -- \
    wget -qO- -T 5 http://triage-app:8080/
  printf 'Verified selector, image, targetPort, and Service endpoints.\n'
}

status() {
  kubectl get deployment,pod,service,endpoints -n "$NAMESPACE" -l lab=5.3 -o wide
  kubectl get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 15
}

cleanup() {
  kubectl delete -f "${LAB_DIR}/fixed.yaml" --ignore-not-found
  kubectl delete pod lab5-3-probe -n "$NAMESPACE" --ignore-not-found
}

case "$ACTION" in
  run) diagnose_selector; runtime_failure; fix; verify; status ;;
  diagnose) diagnose_selector ;;
  runtime) runtime_failure ;;
  fix) fix ;;
  verify) verify ;;
  status) status ;;
  cleanup) cleanup ;;
  *) printf 'Usage: %s {run|diagnose|runtime|fix|verify|status|cleanup}\n' "$0" >&2; exit 1 ;;
esac
