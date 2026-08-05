#!/usr/bin/env bash
set -uo pipefail

readonly DAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${DAY_DIR}/../.." && pwd)"
readonly NAMESPACE="ckad-labs"

source "${ROOT_DIR}/labs/common/verify.sh"
init_verifier 'CKAD Labs - Day 2 Verification' "$@"

verify_lab_2_1() {
  local available max_unavailable max_surge revision ready
  kubectl get deployment traffic-rollout -n "$NAMESPACE" -o wide || return 1
  kubectl rollout history deployment/traffic-rollout -n "$NAMESPACE" || return 1
  kubectl get pods -n "$NAMESPACE" -l app=traffic-rollout -L version || return 1
  available="$(kubectl get deployment traffic-rollout -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
  max_unavailable="$(kubectl get deployment traffic-rollout -n "$NAMESPACE" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}')"
  max_surge="$(kubectl get deployment traffic-rollout -n "$NAMESPACE" -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}')"
  revision="$(kubectl get deployment traffic-rollout -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
  ready="$(kubectl get pods -n "$NAMESPACE" -l app=traffic-rollout -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | awk '$1 == "True" {count++} END {print count+0}')"
  printf 'available=%s readyPods=%s maxUnavailable=%s maxSurge=%s revision=%s\n' "$available" "$ready" "$max_unavailable" "$max_surge" "$revision"
  [[ "$available" -eq 3 && "$ready" -eq 3 && "$max_unavailable" == 0 && "$max_surge" == 1 && "$revision" -ge 3 ]]
}

verify_lab_2_2() {
  local blue green selected endpoints
  kubectl get deployments,pods -n "$NAMESPACE" -l app=traffic-ingest-bg -L version || return 1
  kubectl get service traffic-ingest-bg -n "$NAMESPACE" -o wide || return 1
  blue="$(kubectl get deployment traffic-bg-blue -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
  green="$(kubectl get deployment traffic-bg-green -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
  selected="$(kubectl get service traffic-ingest-bg -n "$NAMESPACE" -o jsonpath='{.spec.selector.version}')"
  endpoints="$(kubectl get endpoints traffic-ingest-bg -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}')"
  printf 'blueAvailable=%s greenAvailable=%s selected=%s endpoints=%s\n' "$blue" "$green" "$selected" "$endpoints"
  [[ "$blue" -eq 2 && "$green" -eq 2 && ( "$selected" == blue || "$selected" == green ) && -n "$endpoints" ]]
}

verify_lab_2_3() {
  local available min max target current
  kubectl get deployment traffic-hpa -n "$NAMESPACE" -o wide || return 1
  kubectl get hpa traffic-hpa -n "$NAMESPACE" || return 1
  kubectl top pods -n "$NAMESPACE" -l app=traffic-hpa --containers || return 1
  available="$(kubectl get deployment traffic-hpa -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
  min="$(kubectl get hpa traffic-hpa -n "$NAMESPACE" -o jsonpath='{.spec.minReplicas}')"
  max="$(kubectl get hpa traffic-hpa -n "$NAMESPACE" -o jsonpath='{.spec.maxReplicas}')"
  target="$(kubectl get hpa traffic-hpa -n "$NAMESPACE" -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}')"
  current="$(kubectl get hpa traffic-hpa -n "$NAMESPACE" -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}')"
  printf 'available=%s min=%s max=%s targetCPU=%s currentCPU=%s\n' "$available" "$min" "$max" "$target" "$current"
  [[ "${available:-0}" -ge 2 && "$min" -eq 2 && "$max" -eq 10 && "$target" -eq 25 && -n "$current" ]]
}

verify_lab_2_4() {
  local desired available image environment managed_by endpoints
  kubectl get deployment,pod,service -n "$NAMESPACE" -l app=traffic-kustomize -o wide || return 1
  desired="$(kubectl get deployment traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
  available="$(kubectl get deployment traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
  image="$(kubectl get deployment traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}')"
  environment="$(kubectl get deployment traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.metadata.labels.environment}')"
  managed_by="$(kubectl get deployment traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.metadata.labels.managed-by}')"
  endpoints="$(kubectl get endpoints traffic-kustomize -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}')"
  printf 'desired=%s available=%s image=%s environment=%s managedBy=%s endpoints=%s\n' "$desired" "$available" "$image" "$environment" "$managed_by" "$endpoints"
  [[ "$desired" -eq 3 && "$available" -eq 3 && "$image" != *':local' && "$environment" == lab && "$managed_by" == kustomize && -n "$endpoints" ]]
}

run_lab_check 'D2-L1' 'Lab 2.1 - Rolling Update and Rollback' \
  'The three-replica Deployment is available, uses zero-downtime rolling settings, and has rollout history proving an update or rollback.' \
  'kubectl get deployment/pods; kubectl rollout history deployment/traffic-rollout' \
  verify_lab_2_1 \
  'All three replicas are Ready, rolling limits are correct, and at least three revisions demonstrate update plus rollback practice.'

run_lab_check 'D2-L2' 'Lab 2.2 - Blue/Green Switch' \
  'Both blue and green Deployments are available while the Service selects exactly one color and has ready endpoints.' \
  'kubectl get deployments,pods; kubectl get service/endpoints traffic-ingest-bg' \
  verify_lab_2_2 \
  'Both colors have two available replicas and the Service selects a populated color.'

run_lab_check 'D2-L3' 'Lab 2.3 - HPA Scale Up and Down' \
  'An autoscaling/v2 HPA targets 25% CPU, allows 2-10 replicas, has current metrics, and its target Pods expose container metrics.' \
  'kubectl get hpa traffic-hpa; kubectl top pods -l app=traffic-hpa --containers' \
  verify_lab_2_3 \
  'The HPA specification and current CPU metrics are available from Metrics Server.'

run_lab_check 'D2-L4' 'Lab 2.4 - Kustomize Overlay' \
  'The lab overlay deploys three available replicas with transformed image/labels and a Service with endpoints.' \
  'kubectl get deployment,pod,service -l app=traffic-kustomize; kubectl get endpoints traffic-kustomize' \
  verify_lab_2_4 \
  'The rendered overlay effects are present in the live Deployment and Service.'

finish_verifier
