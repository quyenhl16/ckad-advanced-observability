#!/usr/bin/env bash
set -uo pipefail

readonly DAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${DAY_DIR}/../.." && pwd)"
readonly NAMESPACE="ckad-labs"

source "${ROOT_DIR}/labs/common/verify.sh"
init_verifier 'CKAD Labs - Day 4 Verification' "$@"

verify_lab_4_1() {
  grep -n 'selector: {app: day4-backend-mismatch}' "${DAY_DIR}/lab4.1/services.yaml" || return 1
  kubectl get deployment,pod,service,endpoints -n "$NAMESPACE" -l lab=4.1 -o wide || return 1
  [[ "$(kubectl get service day4-backend -n "$NAMESPACE" -o jsonpath='{.spec.selector.app}')" == day4-backend ]] || return 1
  bash "${DAY_DIR}/lab4.1/run.sh" verify
}

verify_lab_4_2() {
  kubectl get ingressclass || return 1
  kubectl get deployment,pod,service,ingress -n "$NAMESPACE" -l lab=4.2 -o wide || return 1
  kubectl get ingress day4-frontend day4-backend -n "$NAMESPACE" \
    -o custom-columns=NAME:.metadata.name,CLASS:.spec.ingressClassName,HOST:.spec.rules[0].host,PATH:.spec.rules[0].http.paths[0].path,BACKEND:.spec.rules[0].http.paths[0].backend.service.name || return 1
  bash "${DAY_DIR}/lab4.2/run.sh" verify
}

verify_lab_4_3() {
  kubectl get pod,service,networkpolicy -n "$NAMESPACE" -l lab=4.3 -o wide || return 1
  kubectl describe networkpolicy backend-ingress-from-frontend backend-deny-all-egress \
    -n "$NAMESPACE" || return 1
  bash "${DAY_DIR}/lab4.3/run.sh" verify
}

verify_lab_4_4() {
  local phase volume storage_class requested
  kubectl get pod pvc-client -n "$NAMESPACE" -o wide || return 1
  kubectl get pvc day4-data -n "$NAMESPACE" -o wide || return 1
  phase="$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.status.phase}')"
  volume="$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.spec.volumeName}')"
  storage_class="$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.spec.storageClassName}')"
  requested="$(kubectl get pvc day4-data -n "$NAMESPACE" -o jsonpath='{.spec.resources.requests.storage}')"
  kubectl get pv "$volume" || return 1
  printf 'phase=%s requested=%s volume=%s storageClass=%s\n' "$phase" "$requested" "$volume" "$storage_class"
  [[ "$phase" == Bound && "$requested" == 1Gi && -n "$volume" && -n "$storage_class" ]] || return 1
  bash "${DAY_DIR}/lab4.4/run.sh" verify
}

run_lab_check 'D4-L1' 'Lab 4.1 - ClusterIP and NodePort' \
  'The repaired backend ClusterIP and frontend NodePort Services both have endpoints and answer in-cluster health probes.' \
  'kubectl get deployment,pod,service,endpoints -l lab=4.1; ./labs/day4/lab4.1/run.sh verify' \
  verify_lab_4_1 \
  'Service types, selectors, endpoints and both health routes are live.'

run_lab_check 'D4-L2' 'Lab 4.2 - Ingress Routing' \
  'An installed IngressClass routes / to the frontend and /api to the backend for the configured host.' \
  'kubectl get ingressclass/ingress; ./labs/day4/lab4.2/run.sh verify' \
  verify_lab_4_2 \
  'Both host/path routes succeed through the discovered ingress-controller endpoint.'

run_lab_check 'D4-L3' 'Lab 4.3 - NetworkPolicy Isolation' \
  'Only the frontend can reach the backend, the intruder is denied, and backend egress to 0.0.0.0/0 is blocked.' \
  'kubectl get/describe networkpolicy; ./labs/day4/lab4.3/run.sh verify' \
  verify_lab_4_3 \
  'Positive frontend traffic succeeds while both negative NetworkPolicy probes fail as required.'

run_lab_check 'D4-L4' 'Lab 4.4 - Persistent Volume Claims' \
  'A dynamically provisioned 1 Gi PVC is Bound and the known data value remains after Pod recreation.' \
  'kubectl get pod/pvc/pv; ./labs/day4/lab4.4/run.sh verify' \
  verify_lab_4_4 \
  'The claim is Bound and the recreated Pod reads the original persistent value.'

finish_verifier
