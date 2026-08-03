#!/usr/bin/env bash
set -Eeuo pipefail

readonly NAMESPACE="${NAMESPACE:-advanced-observability}"

cleanup_demo() {
  kubectl delete pod network-allowed network-denied -n "${NAMESPACE}" \
    --ignore-not-found >/dev/null 2>&1 || true
  if [[ -n "${audit_job:-}" ]]; then
    kubectl delete "job/${audit_job}" -n "${NAMESPACE}" \
      --ignore-not-found >/dev/null 2>&1 || true
  fi
}
trap cleanup_demo EXIT

section() {
  printf '\n== %s ==\n' "$1"
}

section '1. Workloads, Services and Endpoints'
kubectl get pods,deployments,statefulsets,services,endpointslices -n "${NAMESPACE}" -o wide

section '2. Ingress with two backends'
kubectl describe ingress advanced-observability -n "${NAMESPACE}"

section '3. ConfigMap and Secret injection without revealing values'
kubectl get configmap observability-config -n "${NAMESPACE}"
kubectl get secret observability-secrets -n "${NAMESPACE}" \
  -o jsonpath='{.metadata.name}{" keys="}{range $k,$v := .data}{$k}{" "}{end}{"\n"}'

section '4. Probes, resources and security context'
kubectl describe deployment traffic-ingest -n "${NAMESPACE}"

section '5. Stable and canary traffic-ingest versions'
kubectl get pods -n "${NAMESPACE}" -l app=traffic-ingest \
  -L deployment-track,app.kubernetes.io/version

section '6. HPA'
kubectl get hpa traffic-ingest -n "${NAMESPACE}"
kubectl describe hpa traffic-ingest -n "${NAMESPACE}"

section '7. NetworkPolicy and least-privilege RBAC'
kubectl get networkpolicy -n "${NAMESPACE}"
kubectl auth can-i list pods \
  --as="system:serviceaccount:${NAMESPACE}:observability-reader" -n "${NAMESPACE}"
if kubectl auth can-i get secrets \
  --as="system:serviceaccount:${NAMESPACE}:observability-reader" -n "${NAMESPACE}"; then
  printf 'ERROR: observability-reader unexpectedly has Secret access\n' >&2
  exit 1
else
  printf 'Expected denial: observability-reader cannot read Secrets.\n'
fi

kubectl run network-allowed -n "${NAMESPACE}" --restart=Never \
  --image=curlimages/curl:8.10.1 --labels=app=observability-frontend \
  --command -- sh -c \
  'curl --fail --silent --show-error --max-time 5 http://analytics-engine:8081/health/live'
kubectl wait pod/network-allowed -n "${NAMESPACE}" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s
kubectl logs pod/network-allowed -n "${NAMESPACE}"

kubectl run network-denied -n "${NAMESPACE}" --restart=Never \
  --image=curlimages/curl:8.10.1 --labels=app=network-denied \
  --command -- sh -c \
  'if curl --silent --max-time 5 http://analytics-engine:8081/health/live; then echo unexpected-access; exit 1; else echo expected-denial; fi'
kubectl wait pod/network-denied -n "${NAMESPACE}" \
  --for=jsonpath='{.status.phase}'=Succeeded --timeout=60s
kubectl logs pod/network-denied -n "${NAMESPACE}"
kubectl delete pod network-allowed network-denied -n "${NAMESPACE}" --ignore-not-found

section '8. CronJob and audit log'
audit_job="health-audit-demo-$(date +%s)"
kubectl create job --from=cronjob/observability-health-audit "${audit_job}" -n "${NAMESPACE}"
kubectl wait --for=condition=complete "job/${audit_job}" -n "${NAMESPACE}" --timeout=120s
kubectl logs "job/${audit_job}" -n "${NAMESPACE}"
kubectl delete "job/${audit_job}" -n "${NAMESPACE}"

section '9. PersistentVolumeClaim'
kubectl get pvc database-data-observability-db-0 -n "${NAMESPACE}"
printf 'For the persistence demonstration, create a marker row through the API, delete observability-db-0, wait for Ready, then query the marker again.\n'

section '10. Debug commands'
printf '%s\n' \
  "kubectl logs -n ${NAMESPACE} deployment/traffic-ingest -c app" \
  "kubectl describe pod -n ${NAMESPACE} POD_NAME" \
  "kubectl get events -n ${NAMESPACE} --sort-by=.metadata.creationTimestamp" \
  "kubectl top pods -n ${NAMESPACE} --containers"
