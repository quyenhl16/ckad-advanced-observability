#!/usr/bin/env bash
set -uo pipefail

readonly DAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${DAY_DIR}/../.." && pwd)"
readonly NAMESPACE="ckad-labs"

source "${ROOT_DIR}/labs/common/verify.sh"
init_verifier 'CKAD Labs - Day 1 Verification' "$@"

verify_lab_1_1() {
  local ready init containers requests limits
  kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o wide --show-labels || return 1
  kubectl get pod traffic-pod-60 -n "$NAMESPACE" \
    -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status}{" init="}{.spec.initContainers[0].name}{" containers="}{range .spec.containers[*]}{.name}{" "}{end}{"\nrequests="}{.spec.containers[?(@.name=="app")].resources.requests}{" limits="}{.spec.containers[?(@.name=="app")].resources.limits}{"\n"}' || return 1
  ready="$(kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  init="$(kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[0].name}')"
  containers="$(kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}')"
  requests="$(kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="app")].resources.requests.cpu}')"
  limits="$(kubectl get pod traffic-pod-60 -n "$NAMESPACE" -o jsonpath='{.spec.containers[?(@.name=="app")].resources.limits.cpu}')"
  [[ "$ready" == True && "$init" == config-init && "$containers" == *app* && "$containers" == *log-sidecar* && "$containers" == *nginx-ambassador* && -n "$requests" && -n "$limits" ]]
}

verify_lab_1_2() {
  local ready init containers volumes
  kubectl get pod analytics-pattern -n "$NAMESPACE" -o wide || return 1
  kubectl get pod analytics-pattern -n "$NAMESPACE" \
    -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status}{" init="}{.spec.initContainers[0].name}{" containers="}{range .spec.containers[*]}{.name}{" "}{end}{" volumes="}{range .spec.volumes[*]}{.name}{" "}{end}{"\n"}' || return 1
  ready="$(kubectl get pod analytics-pattern -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  init="$(kubectl get pod analytics-pattern -n "$NAMESPACE" -o jsonpath='{.spec.initContainers[0].name}')"
  containers="$(kubectl get pod analytics-pattern -n "$NAMESPACE" -o jsonpath='{range .spec.containers[*]}{.name}{" "}{end}')"
  volumes="$(kubectl get pod analytics-pattern -n "$NAMESPACE" -o jsonpath='{range .spec.volumes[*]}{.name}{" "}{end}')"
  [[ "$ready" == True && "$init" == config-init && "$containers" == *log-sidecar* && "$containers" == *nginx-ambassador* && "$volumes" == *shared-logs* && "$volumes" == *analytics-logs* ]]
}

verify_lab_1_3() {
  local complete schedule
  kubectl get job metric-once -n "$NAMESPACE" -o wide || return 1
  kubectl get cronjob metric-every-minute -n "$NAMESPACE" -o wide || return 1
  complete="$(kubectl get job metric-once -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')"
  schedule="$(kubectl get cronjob metric-every-minute -n "$NAMESPACE" -o jsonpath='{.spec.schedule}')"
  printf 'jobComplete=%s cronSchedule=%s\n' "$complete" "$schedule"
  [[ "$complete" == True && "$schedule" == '*/1 * * * *' ]]
}

verify_lab_1_4() {
  local rows row count=0
  kubectl get pods -n "$NAMESPACE" -l app=label-client --show-labels || return 1
  rows="$(kubectl get pods -n "$NAMESPACE" -l app=label-client \
    -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.environment}{"|"}{.metadata.annotations.owner}{"|"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')" || return 1
  printf '%s\n' "$rows"
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    count=$((count + 1))
    [[ "$row" == *'|staging|platform-team|True' ]] || return 1
  done <<<"$rows"
  [[ $count -eq 5 ]]
}

run_lab_check 'D1-L1' 'Lab 1.1 - The 60-Second Pod' \
  'A Ready Pod demonstrates init, app, logging sidecar and Nginx ambassador roles with CPU requests and limits.' \
  'kubectl get pod traffic-pod-60 -n ckad-labs -o wide --show-labels; kubectl get pod ... -o jsonpath=...' \
  verify_lab_1_1 \
  'traffic-pod-60 is Ready and exposes all four roles with explicit app resources.'

run_lab_check 'D1-L2' 'Lab 1.2 - Init and Sidecar Pattern' \
  'The analytics Pod is Ready and shares generated configuration and logs between its init, app, sidecar and ambassador containers.' \
  'kubectl get pod analytics-pattern -n ckad-labs -o wide; kubectl get pod ... -o jsonpath=...' \
  verify_lab_1_2 \
  'analytics-pattern is Ready with the expected containers and shared emptyDir volumes.'

run_lab_check 'D1-L3' 'Lab 1.3 - Jobs and CronJobs' \
  'The one-off metric Job completes and the scheduled metric CronJob runs every minute.' \
  'kubectl get job metric-once; kubectl get cronjob metric-every-minute' \
  verify_lab_1_3 \
  'metric-once has Complete=True and metric-every-minute has the expected schedule.'

run_lab_check 'D1-L4' 'Lab 1.4 - Labels and Annotations' \
  'Five Ready label-client Pods have the overwritten staging label and platform-team owner annotation.' \
  "kubectl get pods -n ckad-labs -l app=label-client --show-labels" \
  verify_lab_1_4 \
  'Exactly five Pods are Ready and carry the required label and annotation.'

finish_verifier
