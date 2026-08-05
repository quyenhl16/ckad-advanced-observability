#!/usr/bin/env bash
set -uo pipefail

readonly DAY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${DAY_DIR}/../.." && pwd)"
readonly NAMESPACE="ckad-labs"
readonly QUOTA_NAMESPACE="ckad-quota-lab"

source "${ROOT_DIR}/labs/common/verify.sh"
init_verifier 'CKAD Labs - Day 3 Verification' "$@"

verify_lab_3_1() {
  kubectl get pod/config-injection configmap/lab3-1-config secret/lab3-1-secret \
    -n "$NAMESPACE" || return 1
  kubectl get pod config-injection -n "$NAMESPACE" \
    -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status}{" secretEnv="}{.spec.containers[?(@.name=="app")].env[?(@.name=="API_KEY")].valueFrom.secretKeyRef.name}{" configEnv="}{.spec.containers[?(@.name=="app")].env[?(@.name=="APP_MODE")].valueFrom.configMapKeyRef.name}{" configVolume="}{.spec.volumes[?(@.name=="app-config")].configMap.name}{" mount="}{.spec.containers[?(@.name=="app")].volumeMounts[?(@.name=="app-config")].mountPath}{"\n"}' || return 1
  bash "${DAY_DIR}/lab3.1/run.sh" verify
}

verify_lab_3_2() {
  kubectl get pod security-lockdown -n "$NAMESPACE" -o wide || return 1
  kubectl get pod security-lockdown -n "$NAMESPACE" \
    -o jsonpath='{range .spec.containers[*]}{.name}{" nonRoot="}{.securityContext.runAsNonRoot}{" readOnly="}{.securityContext.readOnlyRootFilesystem}{" noEscalation="}{.securityContext.allowPrivilegeEscalation}{" drop="}{.securityContext.capabilities.drop}{"\n"}{end}' || return 1
  bash "${DAY_DIR}/lab3.2/run.sh" verify
}

verify_lab_3_3() {
  local can_list_pods can_get_secrets
  kubectl get serviceaccount,pod -n "$NAMESPACE" -l lab=3.3 || return 1
  kubectl get role,rolebinding pod-reader -n "$NAMESPACE" || return 1
  can_list_pods="$(kubectl auth can-i list pods \
    --as=system:serviceaccount:${NAMESPACE}:pod-reader \
    -n "$NAMESPACE" 2>/dev/null || true)"
  can_get_secrets="$(kubectl auth can-i get secrets \
    --as=system:serviceaccount:${NAMESPACE}:pod-reader \
    -n "$NAMESPACE" 2>/dev/null || true)"
  printf 'listPods=%s\ngetSecrets=%s\n' "$can_list_pods" "$can_get_secrets"
  [[ "$can_list_pods" == yes && "$can_get_secrets" == no ]] || return 1
  bash "${DAY_DIR}/lab3.3/run.sh" verify
}

verify_lab_3_4() {
  local accepted defaults quota
  kubectl get pod/quota-accepted resourcequota/compute-quota limitrange/container-defaults \
    -n "$QUOTA_NAMESPACE" || return 1
  accepted="$(kubectl get pod quota-accepted -n "$QUOTA_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  defaults="$(kubectl get limitrange container-defaults -n "$QUOTA_NAMESPACE" -o jsonpath='{.spec.limits[0].defaultRequest.cpu}{"/"}{.spec.limits[0].default.cpu}')"
  quota="$(kubectl get resourcequota compute-quota -n "$QUOTA_NAMESPACE" -o jsonpath='{.spec.hard.requests\.cpu}')"
  printf 'acceptedReady=%s defaultRequest/defaultLimit=%s quotaRequestsCPU=%s\n' "$accepted" "$defaults" "$quota"
  [[ "$accepted" == True && -n "$defaults" && "$quota" == 500m ]] || return 1
  bash "${DAY_DIR}/lab3.4/run.sh" reject
}

run_lab_check 'D3-L1' 'Lab 3.1 - ConfigMap and Secret Injection' \
  'A Ready application Pod consumes a runtime Secret as an environment variable and a ConfigMap through both env and a /config volume without printing secret data.' \
  'kubectl get pod/configmap/secret; ./labs/day3/lab3.1/run.sh verify' \
  verify_lab_3_1 \
  'Secret and ConfigMap references, volume mount and application health are verified without exposing the secret value.'

run_lab_check 'D3-L2' 'Lab 3.2 - Security Context Lockdown' \
  'Containers run non-root with read-only root filesystems, no privilege escalation, dropped capabilities and a blocked root-filesystem write.' \
  'kubectl get pod security-lockdown -o jsonpath=...; ./labs/day3/lab3.2/run.sh verify' \
  verify_lab_3_2 \
  'The live security contexts and runtime filesystem evidence satisfy the lockdown requirement.'

run_lab_check 'D3-L3' 'Lab 3.3 - ServiceAccount and RBAC' \
  'The pod-reader ServiceAccount can list Pods through the API but cannot read Secrets, and the API client produces a PodList response.' \
  'kubectl auth can-i list pods/get secrets; ./labs/day3/lab3.3/run.sh verify' \
  verify_lab_3_3 \
  'Least-privilege RBAC and the authenticated in-Pod Kubernetes API call are verified.'

run_lab_check 'D3-L4' 'Lab 3.4 - Namespace Quotas' \
  'LimitRange defaults are applied, the accepted Pod is Ready, and ResourceQuota rejects the excessive Pod with an exceeded-quota response.' \
  'kubectl get pod/resourcequota/limitrange; ./labs/day3/lab3.4/run.sh reject' \
  verify_lab_3_4 \
  'The accepted workload fits the 500m request quota and the excessive workload is rejected by admission.'

finish_verifier
