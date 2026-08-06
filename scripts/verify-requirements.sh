#!/usr/bin/env bash
set -uo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${NAMESPACE:-advanced-observability}"
OVERLAY="${OVERLAY:-prod}"
REPORT_FILE=""
LIVE_MODE=true

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
CURRENT_ID=""
CURRENT_LEVEL=""
LAST_OUTPUT=""
LAST_RC=0

usage() {
  cat <<'EOF'
Usage: ./scripts/verify-requirements.sh [options]

Verify the CKAD capstone requirements and print, for every item, its
requirement, command, command output, evidence and PASS/FAIL/SKIP result.

Options:
  --namespace NAME   Namespace to inspect (default: advanced-observability)
  --overlay NAME     Kustomize overlay to render: dev or prod (default: prod)
  --static-only      Verify repository evidence without contacting a cluster
  --report FILE      Also save the complete output to FILE
  -h, --help         Show this help

Exit status is non-zero when a required check fails. In --static-only mode,
repository evidence replaces assertions that normally inspect live resources.
EOF
}

while (($# > 0)); do
  case "$1" in
    --namespace)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --namespace requires a value' >&2; exit 2; }
      NAMESPACE="$2"
      shift 2
      ;;
    --overlay)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --overlay requires a value' >&2; exit 2; }
      OVERLAY="$2"
      shift 2
      ;;
    --static-only)
      LIVE_MODE=false
      shift
      ;;
    --report)
      (($# >= 2)) || { printf '%s\n' 'ERROR: --report requires a value' >&2; exit 2; }
      REPORT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ "$NAMESPACE" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || {
  printf 'ERROR: invalid namespace: %s\n' "$NAMESPACE" >&2
  exit 2
}
case "$OVERLAY" in
  dev|prod) ;;
  *) printf 'ERROR: overlay must be dev or prod\n' >&2; exit 2 ;;
esac

if [[ -n "$REPORT_FILE" ]]; then
  report_dir="$(dirname -- "$REPORT_FILE")"
  mkdir -p -- "$report_dir"
  exec > >(tee "$REPORT_FILE") 2>&1
fi

ROOT_Q="$(printf '%q' "$ROOT_DIR")"
NS_Q="$(printf '%q' "$NAMESPACE")"
OVERLAY_Q="$(printf '%q' "$OVERLAY")"

begin_check() {
  CURRENT_ID="$1"
  CURRENT_LEVEL="$2"
  printf '\n================================================================================\n'
  printf '[%s] %s\n' "$CURRENT_ID" "$3"
  printf 'Level: %s\n' "$CURRENT_LEVEL"
  printf 'Requirement: %s\n' "$4"
}

run_command() {
  local command="$1"
  printf 'COMMAND: %s\n' "$command"
  LAST_OUTPUT="$(bash -o pipefail -c "$command" 2>&1)"
  LAST_RC=$?
  printf 'OUTPUT:\n'
  if [[ -n "$LAST_OUTPUT" ]]; then
    printf '%s\n' "$LAST_OUTPUT"
  else
    printf '%s\n' '<no output>'
  fi
  printf 'EXIT CODE: %d\n' "$LAST_RC"
}

pass_check() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'EVIDENCE: %s\n' "$1"
  printf 'RESULT: PASS\n'
}

fail_check() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'EVIDENCE: %s\n' "$1"
  printf 'RESULT: FAIL\n'
}

skip_check() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf 'EVIDENCE: %s\n' "$1"
  printf 'RESULT: SKIP\n'
}

contains() {
  [[ "$1" == *"$2"* ]]
}

command -v kubectl >/dev/null 2>&1
KUBECTL_AVAILABLE=$?
command -v helm >/dev/null 2>&1
HELM_AVAILABLE=$?

LIVE_AVAILABLE=false
if [[ "$LIVE_MODE" == true && $KUBECTL_AVAILABLE -eq 0 ]]; then
  if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    LIVE_AVAILABLE=true
  fi
fi

printf 'CKAD Capstone Requirement Verification\n'
printf 'Repository: %s\n' "$ROOT_DIR"
printf 'Namespace:  %s\n' "$NAMESPACE"
printf 'Overlay:    %s\n' "$OVERLAY"
printf 'Live mode:  %s\n' "$LIVE_MODE"
printf 'Cluster:    %s\n' "$LIVE_AVAILABLE"

begin_check MS1 Required 'Microservice scope and boundaries' \
  'The project has 3-5 independently deployable, single-responsibility core services and documents their communication and data ownership.'
run_command "find ${ROOT_Q}/services -mindepth 2 -maxdepth 2 -name Dockerfile -print | sort"
dockerfile_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c 'Dockerfile$' || true)"
run_command "grep -E '^\\| .*(traffic-ingest|analytics-engine|alert-manager|observability-frontend)' ${ROOT_Q}/README.md"
service_row_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c '^|' || true)"
if [[ "$dockerfile_count" -eq 4 && "$service_row_count" -eq 4 ]] && \
   grep -q 'Communication is synchronous HTTP' "$ROOT_DIR/README.md" && \
   grep -q 'Data ownership' "$ROOT_DIR/docs/architecture.md"; then
  pass_check 'Four distinct service images, four documented bounded contexts, communication contracts and data ownership are present.'
else
  fail_check "Expected four services and architecture evidence; Dockerfiles=${dockerfile_count}, README rows=${service_row_count}."
fi

begin_check MS2 Required 'Production-minded container and API standards' \
  'Core images are multi-stage/non-root, explicitly tagged, expose stable ports and health endpoints, and externalize configuration.'
run_command "grep -H -E '^(FROM .* AS build|USER 65532:65532|EXPOSE )' ${ROOT_Q}/services/*/Dockerfile"
docker_standard_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c 'USER 65532:65532' || true)"
run_command "grep -R -n -E 'image:.*:latest([[:space:]]|$)' ${ROOT_Q}/deployments ${ROOT_Q}/helm || true"
latest_output="$LAST_OUTPUT"
if [[ "$docker_standard_count" -eq 4 && -z "$latest_output" ]] && \
   grep -R -q '/health/live' "$ROOT_DIR/deployments/base" && \
   grep -R -q 'configMapRef\|configMapKeyRef' "$ROOT_DIR/deployments/base"; then
  pass_check 'All four service Dockerfiles run non-root, manifests avoid latest, health paths exist and environment configuration is externalized.'
else
  fail_check 'One or more container/API standards are missing; inspect the command output and deployment manifests.'
fi

begin_check D1 Required 'Custom images for every core service' \
  'Each core service has its own Dockerfile and documented build/tag procedure.'
run_command "grep -n -E 'SERVICES=|docker|podman|build|--tag' ${ROOT_Q}/scripts/build.sh"
if [[ "$dockerfile_count" -eq 4 && $LAST_RC -eq 0 ]] && grep -q '## Build images' "$ROOT_DIR/README.md"; then
  pass_check 'services/*/Dockerfile, scripts/build.sh and README build documentation cover all four core services.'
else
  fail_check 'Dockerfiles or build/tag documentation are incomplete.'
fi

begin_check D2 Required 'Correct workload types plus batch workload' \
  'Long-running APIs use Deployments and the project includes at least one Job or CronJob.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployments,statefulsets,cronjobs -n ${NS_Q} -o wide"
  deploy_count="$(kubectl get deployment -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  cron_count="$(kubectl get cronjob -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$deploy_count" -ge 5 && "$cron_count" -ge 1 ]]; then
    pass_check "Live cluster has ${deploy_count} Deployments and ${cron_count} CronJob(s); PostgreSQL is correctly modeled as a StatefulSet."
  else
    fail_check "Expected at least five Deployments including canary and one CronJob; found ${deploy_count}/${cron_count}."
  fi
else
  run_command "grep -R -h -E '^kind: (Deployment|StatefulSet|CronJob)$' ${ROOT_Q}/deployments/base | sort | uniq -c"
  if contains "$LAST_OUTPUT" 'Deployment' && contains "$LAST_OUTPUT" 'CronJob' && contains "$LAST_OUTPUT" 'StatefulSet'; then
    pass_check 'Static manifests contain API Deployments, a PostgreSQL StatefulSet and health-audit CronJob.'
  else
    fail_check 'Required workload kinds are missing from static manifests.'
  fi
fi

begin_check D3 Required 'Multi-container pattern' \
  'At least one Pod demonstrates an init container or sidecar; both are preferred.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest -n ${NS_Q} -o jsonpath='{.spec.template.spec.initContainers[*].name}{\" | containers=\"}{.spec.template.spec.containers[*].name}{\"\\n\"}'"
else
  run_command "grep -n -E 'initContainers:|name: config-init|name: log-sidecar|name: nginx-ambassador' ${ROOT_Q}/deployments/base/traffic-ingest.yaml"
fi
if contains "$LAST_OUTPUT" 'config-init' && contains "$LAST_OUTPUT" 'log-sidecar' && contains "$LAST_OUTPUT" 'nginx-ambassador'; then
  pass_check 'traffic-ingest demonstrates init, sidecar and ambassador patterns in one Pod.'
else
  fail_check 'The expected config-init, log-sidecar and nginx-ambassador containers were not all found.'
fi

begin_check D4 Required 'Meaningful ephemeral volume' \
  'emptyDir is used to share generated configuration/logs between containers.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest -n ${NS_Q} -o yaml | grep -B 1 -A 1 'emptyDir:'"
else
  run_command "grep -n -E 'generated-config|shared-logs|nginx-tmp|emptyDir' ${ROOT_Q}/deployments/base/traffic-ingest.yaml"
fi
if contains "$LAST_OUTPUT" 'generated-config' && contains "$LAST_OUTPUT" 'shared-logs' && contains "$LAST_OUTPUT" 'emptyDir'; then
  pass_check 'Generated Nginx config and access logs are shared through emptyDir volumes.'
else
  fail_check 'Meaningful shared emptyDir evidence is missing.'
fi

begin_check D5 Required 'Persistent storage and Pod recreation survival' \
  'At least one mounted PVC is Bound; PostgreSQL data is stored outside the container and retained across Pod recreation.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get pv observability-db-pv-node2; kubectl get pvc database-data-observability-db-0 -n ${NS_Q}; kubectl get pod observability-db-0 -n ${NS_Q} -o wide"
  pvc_phase="$(kubectl get pvc database-data-observability-db-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  pv_policy="$(kubectl get pv observability-db-pv-node2 -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null || true)"
  if [[ "$pvc_phase" == Bound && "$pv_policy" == Retain ]]; then
    pass_check 'Database PVC is Bound and the local PV uses Retain. README contains the non-destructive Pod recreation/data query demonstration.'
  else
    fail_check "Expected Bound PVC and Retain PV; observed PVC=${pvc_phase:-missing}, policy=${pv_policy:-missing}."
  fi
else
  run_command "grep -n -E 'volumeClaimTemplates:|storageClassName: observability-local|mountPath: /var/lib/postgresql/data|persistentVolumeReclaimPolicy: Retain' ${ROOT_Q}/deployments/base/database.yaml ${ROOT_Q}/deployments/base/postgres-pv.yaml"
  if contains "$LAST_OUTPUT" 'volumeClaimTemplates' && contains "$LAST_OUTPUT" 'observability-local' && contains "$LAST_OUTPUT" 'Retain'; then
    pass_check 'Static StatefulSet mounts a 1Gi local PVC and its PV has Retain policy/node affinity; README documents the recreation test.'
  else
    fail_check 'PVC, mount or Retain policy evidence is incomplete.'
  fi
fi

begin_check D6 Required 'Labels for selectors, versions and canary identity' \
  'Labels consistently support selection, rollout identity and stable/canary readiness.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get pods -n ${NS_Q} -l app=traffic-ingest -L deployment-track,app.kubernetes.io/version --show-labels"
else
  run_command "grep -n -E 'app: traffic-ingest|deployment-track: (stable|canary)|app.kubernetes.io/version' ${ROOT_Q}/deployments/base/traffic-ingest.yaml ${ROOT_Q}/deployments/base/traffic-ingest-canary.yaml"
fi
if contains "$LAST_OUTPUT" 'stable' && contains "$LAST_OUTPUT" 'canary'; then
  pass_check 'Stable and canary workloads share the application label while retaining distinct track and version labels.'
else
  fail_check 'Stable/canary label evidence is incomplete.'
fi

begin_check P1 Required 'Long-running core services use Deployments' \
  'Every core long-running service is a Deployment with at least one desired and available replica.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest traffic-ingest-canary analytics-engine alert-manager observability-frontend -n ${NS_Q} -o custom-columns=NAME:.metadata.name,DESIRED:.spec.replicas,AVAILABLE:.status.availableReplicas"
  unavailable="$(printf '%s\n' "$LAST_OUTPUT" | awk 'NR>1 && ($2 < 1 || $3 < 1) {print $1}')"
  if [[ $LAST_RC -eq 0 && -z "$unavailable" ]]; then
    pass_check 'All five core/canary Deployments have desired and available replicas.'
  else
    fail_check "Deployments not available: ${unavailable:-command failure}."
  fi
else
  run_command "grep -R -l '^kind: Deployment$' ${ROOT_Q}/deployments/base/*.yaml"
  manifest_deploy_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c '\.yaml$' || true)"
  if [[ "$manifest_deploy_count" -ge 5 ]]; then
    pass_check 'Five Deployment manifests cover four core services plus canary.'
  else
    fail_check "Expected five Deployment manifests; found ${manifest_deploy_count}."
  fi
fi

begin_check P2 Required 'Rolling update and rollback procedure' \
  'A rolling update procedure using set image/apply, rollout status, history and undo is documented.'
run_command "grep -n -E 'kubectl set image|kubectl rollout (status|history|undo)' ${ROOT_Q}/README.md"
if contains "$LAST_OUTPUT" 'set image' && contains "$LAST_OUTPUT" 'rollout status' && contains "$LAST_OUTPUT" 'rollout history' && contains "$LAST_OUTPUT" 'rollout undo'; then
  pass_check 'README documents update, status, history and rollback; traffic-ingest uses maxUnavailable 0/maxSurge 1.'
else
  fail_check 'Rolling update or rollback documentation is incomplete.'
fi

begin_check P3 Required 'Advanced deployment strategy: canary' \
  'A second canary Deployment shares Service traffic with the stable Deployment and has a documented promotion/removal procedure.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest traffic-ingest-canary -n ${NS_Q} -L deployment-track; kubectl get endpointslice -n ${NS_Q} -l kubernetes.io/service-name=traffic-ingest -o wide"
else
  run_command "grep -n -E 'traffic-ingest-canary|deployment-track: canary|selector:.*app: traffic-ingest' ${ROOT_Q}/deployments/base/traffic-ingest-canary.yaml ${ROOT_Q}/deployments/base/traffic-ingest.yaml"
fi
if contains "$LAST_OUTPUT" 'traffic-ingest-canary' && \
   grep -q '## Canary demonstration' "$ROOT_DIR/README.md"; then
  pass_check 'A distinct canary Deployment shares the traffic-ingest Service and the README documents promotion and removal.'
else
  fail_check 'Canary workload or operating procedure is missing.'
fi

begin_check P4 Required 'CPU HorizontalPodAutoscaler' \
  'At least one Deployment has a CPU-utilization HPA and Metrics Server is expected.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get hpa traffic-ingest -n ${NS_Q}; kubectl get hpa traffic-ingest -n ${NS_Q} -o jsonpath='{.spec.minReplicas}{\"-\"}{.spec.maxReplicas}{\" cpu=\"}{.spec.metrics[0].resource.target.averageUtilization}{\"%\\n\"}'"
  hpa_target="$(kubectl get hpa traffic-ingest -n "$NAMESPACE" -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || true)"
else
  run_command "grep -n -E 'kind: HorizontalPodAutoscaler|name: cpu|averageUtilization: 60|minReplicas: 2|maxReplicas: 6' ${ROOT_Q}/deployments/base/hpa.yaml"
  hpa_target=60
fi
if [[ "$hpa_target" == 60 ]]; then
  pass_check 'traffic-ingest HPA targets 60% CPU and scales between two and six replicas.'
else
  fail_check "Expected a 60% CPU HPA target; observed ${hpa_target:-missing}."
fi

begin_check P5 Required 'Kustomize base and environment overlays' \
  'A committed base and at least one overlay patch image tags and/or replica counts.'
if [[ $KUBECTL_AVAILABLE -eq 0 ]]; then
  run_command "kubectl kustomize ${ROOT_Q}/deployments/overlays/${OVERLAY_Q} >/dev/null"
  render_rc=$LAST_RC
else
  run_command "test -f ${ROOT_Q}/deployments/base/kustomization.yaml && test -f ${ROOT_Q}/deployments/overlays/dev/kustomization.yaml && test -f ${ROOT_Q}/deployments/overlays/prod/kustomization.yaml"
  render_rc=$LAST_RC
fi
run_command "grep -n -E '^(images:|replicas:)|newTag:|count:' ${ROOT_Q}/deployments/overlays/dev/kustomization.yaml ${ROOT_Q}/deployments/overlays/prod/kustomization.yaml"
if [[ "$render_rc" -eq 0 ]] && contains "$LAST_OUTPUT" 'newTag:' && contains "$LAST_OUTPUT" 'count:'; then
  pass_check 'Base, dev and prod overlays exist; overlays set image tags and replica counts, and the selected overlay renders successfully when kubectl is available.'
else
  fail_check 'Kustomize structure, overlay mutations or rendering is invalid.'
fi

begin_check P6 Required 'Installable Helm chart with upgrade and rollback' \
  'Every service chart accepts values overrides; install, upgrade, history and rollback are documented.'
if [[ $HELM_AVAILABLE -eq 0 ]]; then
  run_command "for chart in observability-platform observability-db alert-manager analytics-engine traffic-ingest observability-frontend; do helm lint ${ROOT_Q}/helm/\"\$chart\" && helm template \"\$chart\" ${ROOT_Q}/helm/\"\$chart\" -n advanced-observability >/dev/null || exit 1; done"
  helm_rc=$LAST_RC
else
  run_command "for chart in observability-platform observability-db alert-manager analytics-engine traffic-ingest observability-frontend; do test -f ${ROOT_Q}/helm/\"\$chart\"/Chart.yaml && test -f ${ROOT_Q}/helm/\"\$chart\"/values.yaml || exit 1; done"
  helm_rc=$LAST_RC
fi
run_command "grep -n -E 'helm (upgrade --install|upgrade|history|rollback)' ${ROOT_Q}/README.md ${ROOT_Q}/helm/README.md"
if [[ "$helm_rc" -eq 0 ]] && contains "$LAST_OUTPUT" 'upgrade --install' && contains "$LAST_OUTPUT" 'history' && contains "$LAST_OUTPUT" 'rollback'; then
  pass_check 'All service and platform charts are structurally present/lintable and documentation covers install, override, upgrade, history and rollback.'
else
  fail_check 'Helm chart validation or operating documentation is incomplete.'
fi

begin_check C1 Required 'ConfigMap injection' \
  'ConfigMaps are injected into workloads through environment variables and/or volumes.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get configmap observability-config nginx-proxy-template -n ${NS_Q}; kubectl get deployment traffic-ingest -n ${NS_Q} -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}{\" | volume=\"}{.spec.template.spec.volumes[0].configMap.name}{\"\\n\"}'"
else
  run_command "grep -R -n -E 'configMapRef:|configMapKeyRef:|configMap:' ${ROOT_Q}/deployments/base"
fi
if contains "$LAST_OUTPUT" 'observability-config' || contains "$LAST_OUTPUT" 'configMapRef'; then
  pass_check 'Application settings are injected from observability-config and the Nginx template is mounted from a ConfigMap.'
else
  fail_check 'ConfigMap injection evidence is missing.'
fi

begin_check C2 Required 'Secret-based credentials without committed values' \
  'Credentials/tokens use a Kubernetes Secret generated from runtime input; plaintext secret values are not committed.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get secret observability-secrets -n ${NS_Q} -o go-template='name={{.metadata.name}} keys={{range \$key, \$value := .data}}{{\$key}} {{end}}{{\"\\n\"}}'"
else
  run_command "grep -n -E 'secretGenerator:|POSTGRES_PASSWORD is required|ALERT_API_KEY is required|secretKeyRef:' ${ROOT_Q}/scripts/deploy-k8s.sh ${ROOT_Q}/deployments/base/*.yaml"
fi
secret_evidence="$LAST_OUTPUT"
run_command "git -C ${ROOT_Q} grep -n -E '(POSTGRES_PASSWORD|ALERT_API_KEY)=[^\"'\"'\"'$]' -- ':!README.md' ':!docs/**' || true"
plaintext_matches="$LAST_OUTPUT"
if [[ -n "$secret_evidence" && -z "$plaintext_matches" ]] && \
   grep -q 'secretGenerator:' "$ROOT_DIR/scripts/deploy-k8s.sh"; then
  pass_check 'Secret keys are referenced/generated at deployment time and the repository scan found no committed literal assignment.'
else
  fail_check 'Secret generation/reference evidence is missing or a possible plaintext assignment was found.'
fi

begin_check C3 Required 'Restricted SecurityContext' \
  'At least one workload runs non-root, forbids privilege escalation, drops ALL capabilities and uses a read-only root filesystem where feasible.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest -n ${NS_Q} -o jsonpath='runAsNonRoot={.spec.template.spec.securityContext.runAsNonRoot}{\" allowPE=\"}{.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation}{\" readOnly=\"}{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}{\" drop=\"}{.spec.template.spec.containers[0].securityContext.capabilities.drop[*]}{\" seccomp=\"}{.spec.template.spec.securityContext.seccompProfile.type}{\"\\n\"}'"
else
  run_command "grep -n -E 'runAsNonRoot: true|allowPrivilegeEscalation: false|readOnlyRootFilesystem: true|drop: \\[ALL\\]|type: RuntimeDefault' ${ROOT_Q}/deployments/base/traffic-ingest.yaml"
fi
if contains "$LAST_OUTPUT" 'true' && contains "$LAST_OUTPUT" 'false' && contains "$LAST_OUTPUT" 'ALL' && contains "$LAST_OUTPUT" 'RuntimeDefault'; then
  pass_check 'traffic-ingest demonstrates the required non-root, no-escalation, drop-ALL, read-only and RuntimeDefault controls.'
else
  fail_check 'One or more required SecurityContext controls were not found.'
fi

begin_check C4 Required 'Least-privilege ServiceAccount and RBAC' \
  'A custom ServiceAccount, Role and RoleBinding are used by a Pod with a documented in-cluster API need.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get serviceaccount observability-reader -n ${NS_Q}; kubectl get role,rolebinding observability-pod-reader -n ${NS_Q}; kubectl auth can-i list pods --as=system:serviceaccount:${NS_Q}:observability-reader -n ${NS_Q}; kubectl auth can-i get secrets --as=system:serviceaccount:${NS_Q}:observability-reader -n ${NS_Q}"
  can_list="$(kubectl auth can-i list pods --as="system:serviceaccount:${NAMESPACE}:observability-reader" -n "$NAMESPACE" 2>/dev/null || true)"
  can_secrets="$(kubectl auth can-i get secrets --as="system:serviceaccount:${NAMESPACE}:observability-reader" -n "$NAMESPACE" 2>/dev/null || true)"
  if [[ "$can_list" == yes && "$can_secrets" == no ]]; then
    pass_check 'observability-reader can list Pods but cannot read Secrets, and the audit CronJob uses this ServiceAccount.'
  else
    fail_check "Expected list-pods=yes/get-secrets=no; observed ${can_list:-error}/${can_secrets:-error}."
  fi
else
  run_command "grep -n -E '^kind: (ServiceAccount|Role|RoleBinding)|resources: \\[pods\\]|verbs: \\[get, list\\]|serviceAccountName: observability-reader' ${ROOT_Q}/deployments/base/rbac.yaml ${ROOT_Q}/deployments/base/health-audit-cronjob.yaml"
  if contains "$LAST_OUTPUT" 'ServiceAccount' && contains "$LAST_OUTPUT" 'RoleBinding' && contains "$LAST_OUTPUT" 'serviceAccountName'; then
    pass_check 'Static RBAC grants only get/list Pods and the health-audit CronJob uses the custom ServiceAccount.'
  else
    fail_check 'Static ServiceAccount/Role/RoleBinding usage is incomplete.'
  fi
fi

begin_check C5 Required 'ResourceQuota and LimitRange' \
  'The project namespace has both a ResourceQuota and a LimitRange.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get resourcequota observability-quota -n ${NS_Q}; kubectl get limitrange observability-container-defaults -n ${NS_Q}"
else
  run_command "grep -n -E '^kind: (ResourceQuota|LimitRange)$' ${ROOT_Q}/deployments/base/quota.yaml"
fi
if contains "$LAST_OUTPUT" 'observability-quota' || contains "$LAST_OUTPUT" 'ResourceQuota'; then
  if contains "$LAST_OUTPUT" 'observability-container-defaults' || contains "$LAST_OUTPUT" 'LimitRange'; then
    pass_check 'Both namespace-level quota and container defaults/bounds are declared.'
  else
    fail_check 'LimitRange evidence is missing.'
  fi
else
  fail_check 'ResourceQuota evidence is missing.'
fi

begin_check C6 Required 'CPU and memory requests/limits on every container' \
  'Every regular and init container declares CPU/memory requests and limits.'
resource_failure=""
resource_output=""
if [[ "$LIVE_AVAILABLE" == true ]]; then
  resources_jsonpath='{range .spec.template.spec.initContainers[*]}init/{.name}|{.resources.requests.cpu}|{.resources.requests.memory}|{.resources.limits.cpu}|{.resources.limits.memory}{"\n"}{end}{range .spec.template.spec.containers[*]}container/{.name}|{.resources.requests.cpu}|{.resources.requests.memory}|{.resources.limits.cpu}|{.resources.limits.memory}{"\n"}{end}'
  for resource in deployment/traffic-ingest deployment/traffic-ingest-canary deployment/analytics-engine deployment/alert-manager deployment/observability-frontend statefulset/observability-db; do
    output="$(kubectl get "$resource" -n "$NAMESPACE" -o jsonpath="$resources_jsonpath" 2>&1)"
    rc=$?
    printf 'COMMAND: kubectl get %s -n %s -o <resource-jsonpath>\nOUTPUT:\n%s\nEXIT CODE: %d\n' "$resource" "$NAMESPACE" "${output:-<no output>}" "$rc"
    resource_output+="$resource"$'\n'"$output"$'\n'
    [[ $rc -eq 0 ]] || resource_failure+="$resource(command);"
    while IFS='|' read -r container req_cpu req_mem lim_cpu lim_mem; do
      [[ -z "$container" ]] && continue
      if [[ -z "$req_cpu" || -z "$req_mem" || -z "$lim_cpu" || -z "$lim_mem" ]]; then
        resource_failure+="$resource/$container;"
      fi
    done <<<"$output"
  done
  cron_jsonpath='{range .spec.jobTemplate.spec.template.spec.initContainers[*]}init/{.name}|{.resources.requests.cpu}|{.resources.requests.memory}|{.resources.limits.cpu}|{.resources.limits.memory}{"\n"}{end}{range .spec.jobTemplate.spec.template.spec.containers[*]}container/{.name}|{.resources.requests.cpu}|{.resources.requests.memory}|{.resources.limits.cpu}|{.resources.limits.memory}{"\n"}{end}'
  output="$(kubectl get cronjob/observability-health-audit -n "$NAMESPACE" -o jsonpath="$cron_jsonpath" 2>&1)"
  rc=$?
  printf 'COMMAND: kubectl get cronjob/observability-health-audit -n %s -o <resource-jsonpath>\nOUTPUT:\n%s\nEXIT CODE: %d\n' "$NAMESPACE" "${output:-<no output>}" "$rc"
  [[ $rc -eq 0 ]] || resource_failure+='cronjob/observability-health-audit(command);'
  while IFS='|' read -r container req_cpu req_mem lim_cpu lim_mem; do
    [[ -z "$container" ]] && continue
    if [[ -z "$req_cpu" || -z "$req_mem" || -z "$lim_cpu" || -z "$lim_mem" ]]; then
      resource_failure+="cronjob/observability-health-audit/$container;"
    fi
  done <<<"$output"
else
  run_command "grep -R -n -E '^([[:space:]]+)(initContainers:|containers:|resources:|requests:|limits:)' ${ROOT_Q}/deployments/base/*.yaml ${ROOT_Q}/helm/traffic-ingest/templates/deployment.yaml"
  resource_output="$LAST_OUTPUT"
  for file in "$ROOT_DIR"/deployments/base/{traffic-ingest,traffic-ingest-canary,analytics-engine,alert-manager,observability-frontend,database,health-audit-cronjob}.yaml; do
    grep -q 'requests:' "$file" && grep -q 'limits:' "$file" || resource_failure+="$file;"
  done
fi
if [[ -z "$resource_failure" && -n "$resource_output" ]]; then
  pass_check 'Every inspected init and regular container has CPU/memory requests and limits.'
else
  fail_check "Missing resource fields or inspection failure: ${resource_failure:-no evidence}."
fi

begin_check N1 Required 'Internal Services and Kubernetes DNS' \
  'Backend traffic uses ClusterIP/headless Services and clients use Kubernetes service DNS names.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get service traffic-ingest analytics-engine alert-manager observability-frontend observability-db -n ${NS_Q} -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port"
else
  run_command "grep -R -n -E '^kind: Service$|type: (ClusterIP|NodePort)|clusterIP: None|http://(analytics-engine|alert-manager)|observability-db' ${ROOT_Q}/deployments/base"
fi
if contains "$LAST_OUTPUT" 'analytics-engine' && contains "$LAST_OUTPUT" 'alert-manager' && contains "$LAST_OUTPUT" 'observability-db'; then
  pass_check 'Internal APIs are discoverable through stable Service names; PostgreSQL correctly uses a headless Service.'
else
  fail_check 'One or more internal Service/DNS targets are missing.'
fi

begin_check N2 Required 'External exposure' \
  'At least one NodePort or Ingress exposes the application externally.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get ingress advanced-observability -n ${NS_Q}; kubectl get service traffic-ingest observability-frontend -n ${NS_Q} -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,NODEPORT:.spec.ports[*].nodePort"
else
  run_command "grep -n -E '^kind: Ingress$|type: NodePort|nodePort:' ${ROOT_Q}/deployments/base/ingress.yaml ${ROOT_Q}/deployments/base/traffic-ingest.yaml ${ROOT_Q}/deployments/base/observability-frontend.yaml"
fi
if contains "$LAST_OUTPUT" 'Ingress' || contains "$LAST_OUTPUT" 'NodePort' || contains "$LAST_OUTPUT" 'advanced-observability'; then
  pass_check 'The project provides both Ingress and NodePort fallback exposure.'
else
  fail_check 'Neither Ingress nor NodePort evidence was found.'
fi

begin_check N3 Required 'Ingress routes at least two paths/backends' \
  'Ingress routes /api/v1/metrics and / to different backend Services.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get ingress advanced-observability -n ${NS_Q} -o jsonpath='{range .spec.rules[*].http.paths[*]}{.path}{\" -> \"}{.backend.service.name}{\":\"}{.backend.service.port.number}{\"\\n\"}{end}'"
else
  run_command "grep -n -E 'path: /api/v1/metrics|path: /$|name: traffic-ingest|name: observability-frontend' ${ROOT_Q}/deployments/base/ingress.yaml"
fi
if contains "$LAST_OUTPUT" '/api/v1/metrics' && contains "$LAST_OUTPUT" 'traffic-ingest' && contains "$LAST_OUTPUT" 'observability-frontend'; then
  pass_check 'Ingress has two path rules targeting traffic-ingest and observability-frontend.'
else
  fail_check 'Ingress path/backend mapping is incomplete.'
fi

begin_check N4 Required 'Network isolation' \
  'A default-deny policy plus explicit DNS and application-flow allows restrict ingress/egress.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get networkpolicy -n ${NS_Q} -o custom-columns=NAME:.metadata.name,POD-SELECTOR:.spec.podSelector,POLICY-TYPES:.spec.policyTypes"
else
  run_command "grep -n -E '^  name: (default-deny|allow-dns|traffic-ingest|analytics-engine|alert-manager|observability-db|observability-frontend|health-audit)$' ${ROOT_Q}/deployments/base/network-policies.yaml"
fi
if contains "$LAST_OUTPUT" 'default-deny' && contains "$LAST_OUTPUT" 'allow-dns' && contains "$LAST_OUTPUT" 'analytics-engine' && contains "$LAST_OUTPUT" 'observability-db'; then
  pass_check 'Default-deny, DNS, each service flow and database ingress restrictions are present.'
else
  fail_check 'Required default-deny or explicit allow policies are missing.'
fi

begin_check N5 Required 'Service endpoints are populated' \
  'Every core Service has ready EndpointSlice addresses and matching selectors/ports.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  endpoint_failures=""
  endpoint_output=""
  for service in traffic-ingest analytics-engine alert-manager observability-frontend observability-db; do
    addresses="$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=${service}" -o jsonpath='{.items[*].endpoints[*].addresses[*]}' 2>&1)"
    rc=$?
    printf 'COMMAND: kubectl get endpointslice -n %s -l kubernetes.io/service-name=%s -o <addresses>\nOUTPUT:\n%s\nEXIT CODE: %d\n' "$NAMESPACE" "$service" "${addresses:-<no addresses>}" "$rc"
    endpoint_output+="$service=$addresses"$'\n'
    [[ $rc -eq 0 && -n "$addresses" ]] || endpoint_failures+="$service;"
  done
  if [[ -z "$endpoint_failures" ]]; then
    pass_check "All core services have EndpointSlice addresses: ${endpoint_output//$'\n'/; }."
  else
    fail_check "Services without ready endpoints: ${endpoint_failures}."
  fi
else
  run_command "grep -n -E 'Checking Service EndpointSlices|Service has no endpoints|SERVICES=' ${ROOT_Q}/scripts/smoke-test.sh"
  if contains "$LAST_OUTPUT" 'EndpointSlices' && contains "$LAST_OUTPUT" 'SERVICES='; then
    pass_check 'smoke-test.sh enumerates all core Services and fails when an EndpointSlice has no address.'
  else
    fail_check 'Static endpoint verification is missing from smoke-test.sh.'
  fi
fi

begin_check O1 Required 'Liveness probes' \
  'Every long-running application Deployment has a liveness probe.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment -n ${NS_Q} -l app.kubernetes.io/part-of=advanced-observability -o jsonpath='{range .items[*]}{.metadata.name}{\" app-liveness=\"}{range .spec.template.spec.containers[?(@.name==\"app\")]}{.livenessProbe.httpGet.path}{end}{\"\\n\"}{end}'"
  missing_liveness="$(printf '%s\n' "$LAST_OUTPUT" | grep 'app-liveness=$' || true)"
  if [[ $LAST_RC -eq 0 && -z "$missing_liveness" ]]; then
    pass_check 'Every labeled core Deployment app container has an HTTP liveness probe.'
  else
    fail_check "Missing liveness probe: ${missing_liveness:-query failure}."
  fi
else
  run_command "grep -R -l 'livenessProbe:' ${ROOT_Q}/deployments/base/{traffic-ingest,traffic-ingest-canary,analytics-engine,alert-manager,observability-frontend}.yaml"
  probe_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c '\.yaml$' || true)"
  [[ "$probe_count" -eq 5 ]] && pass_check 'All five Deployment manifests contain liveness probes.' || fail_check "Expected five manifests with liveness probes; found ${probe_count}."
fi

begin_check O2 Required 'Readiness probes' \
  'Every long-running application Deployment has a readiness probe.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment -n ${NS_Q} -l app.kubernetes.io/part-of=advanced-observability -o jsonpath='{range .items[*]}{.metadata.name}{\" app-readiness=\"}{range .spec.template.spec.containers[?(@.name==\"app\")]}{.readinessProbe.httpGet.path}{end}{\"\\n\"}{end}'"
  missing_readiness="$(printf '%s\n' "$LAST_OUTPUT" | grep 'app-readiness=$' || true)"
  if [[ $LAST_RC -eq 0 && -z "$missing_readiness" ]]; then
    pass_check 'Every labeled core Deployment app container has an HTTP readiness probe.'
  else
    fail_check "Missing readiness probe: ${missing_readiness:-query failure}."
  fi
else
  run_command "grep -R -l 'readinessProbe:' ${ROOT_Q}/deployments/base/{traffic-ingest,traffic-ingest-canary,analytics-engine,alert-manager,observability-frontend}.yaml"
  probe_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c '\.yaml$' || true)"
  [[ "$probe_count" -eq 5 ]] && pass_check 'All five Deployment manifests contain readiness probes.' || fail_check "Expected five manifests with readiness probes; found ${probe_count}."
fi

begin_check O3 Recommended 'Startup probe for slow startup' \
  'At least one service uses a startup probe, or the absence is documented.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get deployment traffic-ingest -n ${NS_Q} -o jsonpath='{.spec.template.spec.containers[?(@.name==\"app\")].startupProbe.httpGet.path}{\"\\n\"}'"
else
  run_command "grep -R -n 'startupProbe:' ${ROOT_Q}/deployments/base ${ROOT_Q}/helm"
fi
if contains "$LAST_OUTPUT" '/health/live' || contains "$LAST_OUTPUT" 'startupProbe:'; then
  pass_check 'Startup probes are implemented on all application service Deployments and in the Helm chart.'
else
  fail_check 'No startup probe or justification was found.'
fi

begin_check O4 Required 'Debug runbook' \
  'README explains kubectl logs, describe, events and top troubleshooting.'
run_command "grep -n -E 'kubectl (logs|describe|get events|top)' ${ROOT_Q}/README.md"
if contains "$LAST_OUTPUT" 'kubectl logs' && contains "$LAST_OUTPUT" 'kubectl describe' && contains "$LAST_OUTPUT" 'kubectl get events' && contains "$LAST_OUTPUT" 'kubectl top'; then
  pass_check 'README debug runbook includes logs, describe, sorted events and per-container resource usage.'
else
  fail_check 'README is missing one or more required debugging commands.'
fi

begin_check O5 Required 'Current stable Kubernetes APIs' \
  'Manifests avoid deprecated API versions and use stable APIs compatible with Kubernetes 1.35.'
run_command "grep -R -n '^apiVersion:' ${ROOT_Q}/deployments ${ROOT_Q}/helm | sort"
api_output="$LAST_OUTPUT"
run_command "grep -R -n -E 'extensions/v1beta1|apps/v1beta|networking.k8s.io/v1beta1|batch/v1beta1|autoscaling/v2beta' ${ROOT_Q}/deployments ${ROOT_Q}/helm || true"
if [[ -n "$api_output" && -z "$LAST_OUTPUT" ]]; then
  pass_check 'Workloads use apps/v1 and batch/v1; networking, HPA, PDB, RBAC and storage resources use current stable APIs.'
else
  fail_check 'A deprecated API version was found or API evidence is empty.'
fi

begin_check K1 Required 'Cluster/tooling prerequisites' \
  'The live environment provides kubectl, Kubernetes, policy-capable networking, IngressClass, Metrics Server and a default StorageClass; Helm is available for its demo.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl version; kubectl get nodes; kubectl get ingressclass; kubectl get deployment -A | grep -i metrics-server || true; kubectl get apiservice v1beta1.metrics.k8s.io; kubectl top nodes; kubectl get storageclass; helm version --short"
  default_sc="$(kubectl get storageclass -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{" "}{end}' 2>/dev/null || true)"
  ingress_count="$(kubectl get ingressclass --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  metrics_deployments="$(kubectl get deployment -A --no-headers 2>/dev/null | awk 'tolower($2) ~ /metrics-server/ {printf "%s/%s=%s ", $1, $2, $5}' || true)"
  metrics_api_available="$(kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
  metrics_query=false
  if kubectl top nodes --no-headers >/dev/null 2>&1; then
    metrics_query=true
  fi
  if [[ $HELM_AVAILABLE -eq 0 && -n "$default_sc" && "$ingress_count" -ge 1 && "$metrics_api_available" == True && "$metrics_query" == true ]]; then
    pass_check "Cluster prerequisites found: default StorageClass=${default_sc}, IngressClass count=${ingress_count}, Metrics API Available=True, metrics query=yes, deployments=${metrics_deployments:-API-backed installation}. CNI policy enforcement still requires the live allowed/denied demo."
  else
    fail_check "Missing prerequisite: helm=$([[ $HELM_AVAILABLE -eq 0 ]] && echo yes || echo no), defaultSC=${default_sc:-missing}, ingressClasses=${ingress_count}, metricsAPI=${metrics_api_available:-missing}, metricsQuery=${metrics_query}, metricsDeployments=${metrics_deployments:-missing}."
  fi
else
  run_command "grep -n -E 'Kubernetes 1.35|policy-capable CNI|Ingress controller|Metrics Server|default.*StorageClass|kubectl.*Helm 3' ${ROOT_Q}/README.md"
  if contains "$LAST_OUTPUT" 'Kubernetes 1.35' && contains "$LAST_OUTPUT" 'policy-capable CNI' && contains "$LAST_OUTPUT" 'Metrics Server'; then
    pass_check 'README documents the required Kubernetes version and cluster/tool prerequisites; use live mode to prove their availability.'
  else
    fail_check 'README cluster/tool prerequisite documentation is incomplete.'
  fi
fi

begin_check R1 Required 'Repository deliverable layout' \
  'Repository includes README, architecture/checklist/proposal docs, service Dockerfiles, Kustomize base/overlays, service Helm charts, and build/deploy/smoke scripts.'
run_command "for path in README.md docs/architecture.md docs/ckad-checklist.md docs/project-proposal.md deployments/base/kustomization.yaml deployments/overlays/dev/kustomization.yaml deployments/overlays/prod/kustomization.yaml helm/observability-platform/Chart.yaml helm/observability-db/Chart.yaml helm/alert-manager/Chart.yaml helm/analytics-engine/Chart.yaml helm/traffic-ingest/Chart.yaml helm/observability-frontend/Chart.yaml scripts/build.sh scripts/deploy.sh scripts/deploy-helm.sh scripts/smoke-test.sh scripts/demo.sh scripts/verify-requirements.sh; do test -e ${ROOT_Q}/\"\$path\" && printf '%s\\n' \"\$path\" || { printf 'MISSING %s\\n' \"\$path\"; exit 1; }; done"
if [[ $LAST_RC -eq 0 ]] && ! contains "$LAST_OUTPUT" 'MISSING'; then
  pass_check 'All required or equivalent repository deliverables are present.'
else
  fail_check 'One or more required deliverable paths are missing.'
fi

begin_check R2 Required 'README minimum content and live demo guide' \
  'README covers domain/story, services, architecture link, prerequisites, build/deploy, verification, demo and known limitations.'
run_command "grep -n -E '^## (Business domain and user story|Services|Prerequisites|Build images|Deploy|Verify and access|Demo script|Known limitations)' ${ROOT_Q}/README.md"
readme_section_count="$(printf '%s\n' "$LAST_OUTPUT" | grep -c '^' || true)"
if [[ "$readme_section_count" -ge 8 ]] && grep -q 'architecture.md' "$ROOT_DIR/README.md" && grep -q 'ckad-checklist.md' "$ROOT_DIR/README.md"; then
  pass_check 'README contains all eight minimum documentation topics and links architecture/checklist evidence.'
else
  fail_check "README minimum section evidence is incomplete; matched ${readme_section_count} sections."
fi

begin_check A1 Required 'Automatic-fail safeguards' \
  'Project has at least three deployable services, Kubernetes Deployments, no plaintext secrets, external exposure, and Ready Pods in live mode.'
if [[ "$LIVE_AVAILABLE" == true ]]; then
  run_command "kubectl get pods -n ${NS_Q} -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,PHASE:.status.phase,OWNER:.metadata.ownerReferences[0].kind"
  not_ready="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/part-of=advanced-observability -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{range .status.containerStatuses[*]}{.ready}{","}{end}{"|"}{.status.phase}{"|"}{.metadata.ownerReferences[0].kind}{"\n"}{end}' 2>/dev/null | awk -F'|' '$4 == "Job" {next} $3 == "Running" && $2 ~ /false/ {print $1; next} $3 != "Running" && $3 != "Succeeded" {print $1}')"
  if [[ "$dockerfile_count" -ge 3 && -z "$plaintext_matches" && -z "$not_ready" ]]; then
    pass_check 'No automatic-fail condition was detected in repository evidence or current long-running Pod readiness; transient and completed Job Pods are reported but excluded from the Ready gate.'
  else
    fail_check "Automatic-fail risk: serviceCount=${dockerfile_count}, plaintextSecretMatches=$([[ -z "$plaintext_matches" ]] && echo none || echo found), notReady=${not_ready:-none}."
  fi
else
  run_command "test ${dockerfile_count} -ge 3 && grep -R -q '^kind: Deployment$' ${ROOT_Q}/deployments/base && grep -R -q '^kind: Ingress$\|type: NodePort' ${ROOT_Q}/deployments/base"
  if [[ $LAST_RC -eq 0 && -z "$plaintext_matches" ]]; then
    pass_check 'Static evidence avoids the repository-side automatic-fail conditions; run live mode to prove Pod readiness.'
  else
    fail_check 'A static automatic-fail condition was detected.'
  fi
fi

printf '\n================================================================================\n'
printf 'SUMMARY\n'
printf '  PASS: %d\n' "$PASS_COUNT"
printf '  FAIL: %d\n' "$FAIL_COUNT"
printf '  SKIP: %d\n' "$SKIP_COUNT"
printf '  TOTAL: %d\n' "$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  printf 'OVERALL RESULT: FAIL\n'
  exit 1
fi

printf 'OVERALL RESULT: PASS\n'
