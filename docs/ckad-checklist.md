# CKAD capstone checklist

Namespace: `advanced-observability`.

Audit status on 2026-08-05: all 28 CKAD items below and six supporting
microservice/deliverable safeguards pass the repository-only verifier (34/34).
The repository satisfies the declarative requirements; live acceptance still
depends on cluster prerequisites and Ready Pods, which are checked by running
the same verifier without `--static-only`.

## Application Design and Build

| ID | Implementation | Evidence / verification |
|---|---|---|
| D1 | Four service-specific multi-stage Dockerfiles and explicit tags | `services/*/Dockerfile`, `scripts/build.sh` |
| D2 | Four API Deployments, one canary Deployment, PostgreSQL StatefulSet and health-audit CronJob | `deployments/base/*yaml`; `kubectl get deploy,sts,cronjob -n advanced-observability` |
| D3 | `config-init`, `log-sidecar` and Nginx ambassador | `traffic-ingest.yaml` and the other core Deployment manifests |
| D4 | Shared generated config, logs and Nginx temp directories | `emptyDir` volumes in each multi-container Deployment |
| D5 | Retained local PV/PVC mounted by PostgreSQL on `node-2` | `postgres-pv.yaml`, `database.yaml`; `kubectl get pv,pvc` |
| D6 | Selection, semantic version and stable/canary track labels | `traffic-ingest.yaml`, `traffic-ingest-canary.yaml` |

## Application Deployment

| ID | Implementation | Evidence / verification |
|---|---|---|
| P1 | Every core long-running service is a Deployment | `kubectl get deploy -n advanced-observability` |
| P2 | Zero-unavailable rolling update plus documented update/status/history/undo commands | Root README, “Rolling update and rollback” |
| P3 | Replica-weighted stable/canary with a shared Service | `traffic-ingest-canary.yaml`; README canary procedure |
| P4 | CPU HPA, 2–6 stable ingestion replicas at 60% | `hpa.yaml`; `kubectl get hpa` |
| P5 | Committed base, dev overlay and prod overlay patching tags/replicas | `deployments/base`, `deployments/overlays/*` |
| P6 | Installable traffic-ingest Helm chart with override/upgrade/history/rollback | `helm/traffic-ingest`; README Helm procedure |

## Environment, Configuration and Security

| ID | Implementation | Evidence / verification |
|---|---|---|
| C1 | ConfigMaps injected by env, key reference and volume | `config.yaml` and Deployment manifests |
| C2 | `observability-secrets` generated from runtime environment; no value committed | `scripts/deploy-k8s.sh`; `kubectl get secret observability-secrets` |
| C3 | Non-root, RuntimeDefault seccomp, no privilege escalation, drop ALL, read-only root | Core Deployments, canary, database and CronJob |
| C4 | Pod-reader ServiceAccount, Role and RoleBinding used by audit CronJob | `rbac.yaml`, `health-audit-cronjob.yaml`; `kubectl auth can-i` commands |
| C5 | ResourceQuota and LimitRange | `quota.yaml`; `kubectl describe quota,limitrange -n advanced-observability` |
| C6 | CPU/memory requests and limits on every explicit container | All base and Helm container definitions |

## Services and Networking

| ID | Implementation | Evidence / verification |
|---|---|---|
| N1 | Internal ClusterIP Services and a headless database Service | Core service manifests; `kubectl get svc` |
| N2 | Frontend and ingestion NodePorts for fallback exposure | `observability-frontend.yaml`, `traffic-ingest.yaml` |
| N3 | `observability.local` routes `/` and `/api/v1/metrics` to different backends | `ingress.yaml`; `kubectl describe ingress` |
| N4 | Default deny, DNS and explicit per-flow allow policies | `network-policies.yaml` |
| N5 | Named target ports and matching selectors; smoke test requires every EndpointSlice to have addresses | `scripts/smoke-test.sh` |

## Observability and Maintenance

| ID | Implementation | Evidence / verification |
|---|---|---|
| O1 | Liveness on every core Deployment and database | Core workload manifests |
| O2 | Readiness on every core Deployment and database | Core workload manifests |
| O3 | Startup probe on all application service Deployments | Core workload manifests and Helm chart |
| O4 | Logs, describe, events, top, endpoint, HPA and PVC runbook | Root README, “Debug runbook” |
| O5 | Stable APIs: apps/v1, batch/v1, networking.k8s.io/v1, autoscaling/v2, policy/v1 | All Kubernetes manifests |

## 5–10 minute live demonstration

1. Run `scripts/smoke-test.sh`; show Pods Ready and EndpointSlice addresses.
2. Describe Ingress and send requests to `/` and `/api/v1/metrics`.
3. Show ConfigMap keys and Secret metadata without decoding values.
4. Describe a Deployment to show init/sidecar, probes, resources and security.
5. Show stable/canary labels and the shared traffic-ingest EndpointSlice.
6. Show HPA, ResourceQuota and LimitRange.
7. Run the allowed and denied client Pods in `scripts/demo.sh` to show the
   NetworkPolicy effect, then use `kubectl auth can-i` to prove the reader can
   list Pods but cannot read Secrets.
8. Create a one-off Job from the audit CronJob and show its structured log.
9. Create a user, delete `observability-db-0`, and show the user still exists.
10. Show `helm history`, perform a rollback, and finish with debug commands.

`scripts/demo.sh` automates the non-interactive inspection portion.

## Automated requirement evidence

Run the comprehensive verifier against a deployed cluster:

```bash
./scripts/verify-requirements.sh --overlay prod \
  --report requirement-verification.txt
```

Each check prints the requirement text, exact command, command output, evidence
and `PASS`, `FAIL` or `SKIP`. Use `--static-only` to audit repository evidence
without cluster access. The script covers every D1-O5 item above plus service
scope, cluster prerequisites, repository deliverables and automatic-fail
safeguards from the Capstone description.
