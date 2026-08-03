#!/usr/bin/env bash
set -Eeuo pipefail

readonly NAMESPACE="${NAMESPACE:-advanced-observability}"
readonly SERVICES=(traffic-ingest analytics-engine alert-manager observability-frontend observability-db)

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

require_command kubectl

printf 'Checking rollouts in namespace %s\n' "${NAMESPACE}"
kubectl rollout status statefulset/observability-db -n "${NAMESPACE}" --timeout=180s
for deployment in traffic-ingest traffic-ingest-canary analytics-engine alert-manager observability-frontend; do
  kubectl rollout status "deployment/${deployment}" -n "${NAMESPACE}" --timeout=180s
done

printf 'Checking Service EndpointSlices\n'
for service in "${SERVICES[@]}"; do
  addresses="$(kubectl get endpointslices -n "${NAMESPACE}" \
    -l "kubernetes.io/service-name=${service}" \
    -o jsonpath='{.items[*].endpoints[*].addresses[*]}')"
  [[ -n "${addresses}" ]] || {
    printf 'Service has no endpoints: %s\n' "${service}" >&2
    exit 1
  }
  printf '  %-28s %s\n' "${service}" "${addresses}"
done

printf 'Checking required CKAD resources\n'
kubectl get configmap observability-config -n "${NAMESPACE}" >/dev/null
kubectl get secret observability-secrets -n "${NAMESPACE}" >/dev/null
kubectl get hpa traffic-ingest -n "${NAMESPACE}" >/dev/null
kubectl get ingress advanced-observability -n "${NAMESPACE}" >/dev/null
kubectl get cronjob observability-health-audit -n "${NAMESPACE}" >/dev/null
kubectl get resourcequota observability-quota -n "${NAMESPACE}" >/dev/null
kubectl get limitrange observability-container-defaults -n "${NAMESPACE}" >/dev/null
kubectl get networkpolicy default-deny -n "${NAMESPACE}" >/dev/null

pvc_phase="$(kubectl get pvc database-data-observability-db-0 -n "${NAMESPACE}" -o jsonpath='{.status.phase}')"
[[ "${pvc_phase}" == "Bound" ]] || {
  printf 'Database PVC is not Bound: %s\n' "${pvc_phase}" >&2
  exit 1
}

reader_pod_access="$(kubectl auth can-i list pods \
  --as="system:serviceaccount:${NAMESPACE}:observability-reader" \
  -n "${NAMESPACE}" || true)"
reader_secret_access="$(kubectl auth can-i get secrets \
  --as="system:serviceaccount:${NAMESPACE}:observability-reader" \
  -n "${NAMESPACE}" || true)"
[[ "${reader_pod_access}" == "yes" ]]
[[ "${reader_secret_access}" == "no" ]]

path_count="$(kubectl get ingress advanced-observability -n "${NAMESPACE}" \
  -o jsonpath='{.spec.rules[0].http.paths[*].path}' | wc -w | tr -d ' ')"
[[ "${path_count}" -ge 2 ]] || {
  printf 'Ingress does not contain two paths\n' >&2
  exit 1
}

printf 'Smoke test passed. Pods, endpoints, storage, RBAC, HPA, Ingress and policies are present.\n'
