#!/usr/bin/env bash
set -uo pipefail

readonly DAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${DAY_DIR}/../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly HELM_RELEASE="${RELEASE:-day5-observer}"

source "${ROOT_DIR}/labs/common/verify.sh"
init_verifier 'CKAD Labs - Day 5 Verification' "$@"

verify_lab_5_1() {
  local restarts
  kubectl get deployment,pod -n "$NAMESPACE" -l app=self-healing-app -o wide || return 1
  kubectl get pod -n "$NAMESPACE" -l app=self-healing-app \
    -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" restarts="}{.restartCount}{"\n"}{end}{end}' || return 1
  bash "${DAY_DIR}/lab5.1/run.sh" verify || return 1
  restarts="$(kubectl get pod -n "$NAMESPACE" -l app=self-healing-app -o jsonpath='{.items[0].status.containerStatuses[?(@.name=="readiness-helper")].restartCount}')"
  printf 'readinessHelperRestarts=%s\n' "$restarts"
  [[ "${restarts:-0}" -ge 1 ]]
}

verify_lab_5_2() {
  local app_ready restarts
  kubectl get pod cli-observer -n "$NAMESPACE" -o wide || return 1
  kubectl get pod cli-observer -n "$NAMESPACE" \
    -o jsonpath='{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" restarts="}{.restartCount}{"\n"}{end}' || return 1
  bash "${DAY_DIR}/lab5.2/run.sh" logs || return 1
  bash "${DAY_DIR}/lab5.2/run.sh" top || return 1
  app_ready="$(kubectl get pod cli-observer -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[?(@.name=="app")].ready}')"
  restarts="$(kubectl get pod cli-observer -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[?(@.name=="log-helper")].restartCount}')"
  [[ "$app_ready" == true && "$restarts" -ge 1 ]]
}

verify_lab_5_3() {
  local image target_port endpoints selector_error
  if selector_error="$(kubectl apply --dry-run=server -f "${DAY_DIR}/lab5.3/broken-selector.yaml" 2>&1)"; then
    printf '%s\n' 'broken-selector.yaml was unexpectedly accepted by the API server'
    return 1
  fi
  printf '%s\n' "$selector_error"
  grep -Eqi 'selector.*(match|label)|does not match' <<<"$selector_error" || return 1
  grep -n 'INVALID_IMAGE_NAME' "${DAY_DIR}/lab5.3/broken-runtime.yaml" || return 1
  grep -n 'targetPort: web' "${DAY_DIR}/lab5.3/broken-runtime.yaml" || return 1
  kubectl get deployment,pod,service,endpoints -n "$NAMESPACE" -l lab=5.3 -o wide || return 1
  image="$(kubectl get deployment triage-app -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  target_port="$(kubectl get service triage-app -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')"
  endpoints="$(kubectl get endpoints triage-app -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}')"
  printf 'fixedImage=%s fixedTargetPort=%s endpoints=%s\n' "$image" "$target_port" "$endpoints"
  [[ "$image" != INVALID_IMAGE_NAME && "$target_port" == http && -n "$endpoints" ]] || return 1
  bash "${DAY_DIR}/lab5.3/run.sh" verify
}

verify_lab_5_4() {
  local status revisions history
  command -v helm >/dev/null 2>&1 || { printf '%s\n' 'helm is required'; return 1; }
  helm status "$HELM_RELEASE" -n "$NAMESPACE" || return 1
  history="$(helm history "$HELM_RELEASE" -n "$NAMESPACE")" || return 1
  printf '%s\n' "$history"
  status="$(helm status "$HELM_RELEASE" -n "$NAMESPACE" | awk '$1 == "STATUS:" {print $2; exit}')"
  revisions="$(awk 'NR > 1 && $1 ~ /^[0-9]+$/ {count++} END {print count+0}' <<<"$history")"
  printf 'releaseStatus=%s revisions=%s\n' "$status" "$revisions"
  [[ "$status" == deployed && "$revisions" -ge 3 ]] || return 1
  grep -qi 'rollback' <<<"$history" || return 1
  bash "${DAY_DIR}/lab5.4/run.sh" verify
}

run_lab_check 'D5-L1' 'Lab 5.1 - Self-Healing App' \
  'The real app has startup/liveness probes, the helper has file readiness, and a deliberate helper liveness failure caused at least one successful restart.' \
  'kubectl get pod probes/restarts; ./labs/day5/lab5.1/run.sh verify' \
  verify_lab_5_1 \
  'Probe configuration, application health and kubelet self-healing are demonstrated.'

run_lab_check 'D5-L2' 'Lab 5.2 - CLI Observability' \
  'Current app/helper logs, previous helper logs, restart state and per-container CPU/memory metrics are available.' \
  'kubectl logs current/--previous; kubectl top pod cli-observer --containers' \
  verify_lab_5_2 \
  'The intentional crash is visible in previous logs, the Pod recovered, and Metrics Server returns usage.'

run_lab_check 'D5-L3' 'Lab 5.3 - Broken YAML Triage' \
  'The exercise contains selector/image/targetPort faults, while the repaired live Deployment uses a valid image, named http targetPort and populated endpoints.' \
  'grep broken-runtime.yaml; kubectl get deployment/service/endpoints; ./labs/day5/lab5.3/run.sh verify' \
  verify_lab_5_3 \
  'Static fault evidence and the fully repaired live Service path are both verified.'

run_lab_check 'D5-L4' 'Lab 5.4 - Helm Deploy and Rollback' \
  'The Helm release is deployed, has at least two revisions proving upgrade/rollback practice, and its chart-configured Service is healthy.' \
  'helm status/history day5-observer; ./labs/day5/lab5.4/run.sh verify' \
  verify_lab_5_4 \
  'Helm release state, revision history, ConfigMap injection and health endpoint are verified.'

finish_verifier
