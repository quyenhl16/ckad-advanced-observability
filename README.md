# Advanced Network Observability

A Kubernetes observability capstone that receives network-device telemetry,
detects latency anomalies, persists alerts and subscriptions, and presents
correlated events through an operator dashboard.

Repository: <https://github.com/quyenhl16/ckad-advanced-observability>

> Start here for the project flow and the shortest path to a working deployment.
> Use the [operations guide](docs/operations-guide.md) for complete cleanup,
> Ingress, persistence, canary, Helm and troubleshooting procedures.

## Business domain and user story

Network operators need one place to observe routers, switches, servers,
firewalls and access points. As an operator, I can submit a device metric, have
it evaluated against a latency threshold, persist an alert when the threshold
is exceeded, notify matching subscribers and inspect the correlated trace in a
web dashboard.

## Business flow

```mermaid
flowchart LR
    Client[Device client / operator]
    Ingress[NGINX Ingress]
    Frontend[Web dashboard]
    Ingest[traffic-ingest\nstable + canary]
    Analytics[analytics-engine]
    Alert[alert-manager]
    DB[(PostgreSQL PVC)]

    Client -->|GET /| Ingress
    Client -->|POST /api/v1/metrics| Ingress
    Ingress --> Frontend
    Ingress --> Ingest
    Ingest -->|validate + forward| Analytics
    Analytics -->|threshold exceeded| Alert
    Alert --> DB
    Frontend -->|events| Analytics
    Frontend -->|alerts + subscriptions| Alert
```

One accepted metric receives a `trace_id`. `analytics-engine` records an event;
latency above `150 ms` creates a durable alert in PostgreSQL. The same trace ID
links ingestion, analysis and alert data in the dashboard.

## Services

| Service | Responsibility | Port | Data ownership |
|---|---|---:|---|
| `traffic-ingest` | Validate metrics and start the trace | 8080 | Stateless |
| `analytics-engine` | Evaluate thresholds and expose recent events | 8081 | Pod-local event stream |
| `alert-manager` | Manage alerts, users, subscriptions and notifications | 8082 | PostgreSQL schema |
| `observability-frontend` | Render the operator dashboard and forms | 8083 | Stateless |

PostgreSQL is supporting infrastructure owned by `alert-manager`, not a fifth
core microservice. Communication is synchronous HTTP over Kubernetes DNS. See
[architecture.md](docs/architecture.md) for boundaries, contracts, data
ownership and failure behavior.

## Kubernetes design at a glance

- Four Go services, five Deployments including canary, one PostgreSQL
  StatefulSet and one health-audit CronJob.
- Nginx ambassador, init containers, log sidecars and shared `emptyDir` volumes.
- Stable/canary Service traffic, rolling updates, HPA, PDB and health probes.
- Runtime Secret generation, ConfigMaps, non-root security contexts, RBAC,
  ResourceQuota and LimitRange.
- Default-deny NetworkPolicies with explicit application and DNS flows.
- Kustomize `dev`/`prod` overlays plus an independent Helm chart for every
  application service and PostgreSQL.
- Retained local PV/PVC for PostgreSQL on `node-2`.

The complete requirement-to-evidence map is in
[ckad-checklist.md](docs/ckad-checklist.md).

## Prerequisites

- Kubernetes 1.35.x or the instructor-assigned version.
- A policy-capable CNI with working cross-node Pod networking.
- Nginx Ingress controller and an IngressClass named `nginx`.
- Metrics Server with an available `metrics.k8s.io` API.
- A default dynamic StorageClass for cluster prerequisites; PostgreSQL itself
  demonstrates a static local StorageClass and PV.
- A node named `node-2` with `/var/lib/observability-postgres` prepared.
- `kubectl`, Helm 3, Bash, and Docker or Podman.

Quick prerequisite check:

```bash
kubectl get nodes
kubectl get ingressclass
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl get storageclass
helm version --short
```

## Build images

Each service has a non-root multi-stage Dockerfile under `services/`. Use an
immutable version or Git SHA instead of `latest`.

```bash
chmod +x scripts/*.sh

IMAGE_TAG=1.0.0 \
REGISTRY_PREFIX=registry.example.com/team \
CONTAINER_ENGINE=docker \
./scripts/build.sh
```

## Deploy

The deployment script generates the Kubernetes Secret from environment values;
credentials are not committed to Git.

```bash
export POSTGRES_PASSWORD='replace-with-a-strong-password'
export ALERT_API_KEY='replace-with-a-different-strong-value'

./scripts/deploy.sh \
  --cluster generic \
  --overlay prod \
  --registry registry.example.com/team \
  --tag 1.0.0 \
  --canary-tag 1.1.0
```

For a local kind cluster:

```bash
./scripts/deploy.sh \
  --cluster kind \
  --cluster-name observability \
  --overlay dev \
  --tag 1.0.0 \
  --canary-tag 1.1.0
```

Full cleanup/redeploy and manual Kustomize procedures are documented in the
[operations guide](docs/operations-guide.md#full-cleanup-and-redeploy).

To deploy the same application as six Helm releases (platform controls plus
five runtime components) in the main namespace:

```bash
./scripts/cleanup.sh --confirm advanced-observability
export POSTGRES_PASSWORD='replace-with-a-strong-password'
export ALERT_API_KEY='replace-with-a-different-strong-value'
./scripts/deploy-helm.sh \
  --registry registry.example.com/team \
  --tag 1.0.0 --canary-tag 1.1.0 --profile prod
./scripts/verify-helm.sh --live
```

See [helm/README.md](helm/README.md) for chart dependencies and per-service
upgrade, rollback and uninstall commands.

## Verify and access

Validate rollouts, Service endpoints, storage and all capstone requirements:

```bash
./scripts/smoke-test.sh
./scripts/verify-requirements.sh --overlay prod \
  --report requirement-verification.txt

kubectl get pods,svc,endpointslices,hpa,ingress,pvc \
  -n advanced-observability
```

Resolve the Ingress endpoint and test the two public flows:

```bash
NODE_IP="$(kubectl get node node-1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')"
INGRESS_PORT="$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')"

# Dashboard: expect HTTP 200
curl -i -H 'Host: observability.local' \
  "http://${NODE_IP}:${INGRESS_PORT}/"

# Metric pipeline: expect HTTP 202 and a trace_id
curl -i -H 'Host: observability.local' \
  -H 'Content-Type: application/json' \
  -d '{"device_type":"router","device_id":"readme-check","cpu_usage_percent":65,"memory_usage_percent":58,"temperature_celsius":52,"latency_ms":220,"packet_loss_percent":1}' \
  "http://${NODE_IP}:${INGRESS_PORT}/api/v1/metrics"
```

Add `NODE_IP observability.local` to the browser machine's hosts file, then
open `http://observability.local:INGRESS_PORT/`. To populate the dashboard:

```bash
./scripts/generate-traces.sh
```

The generator submits 300 metrics by default and writes every returned trace ID
to a timestamped CSV under `data/`. It creates 264 one-request devices followed
by five history devices with 5, 6, 7, 8 and 10 requests, so their complete
history remains visible in the dashboard's latest-100 event window.

## Essential operations

### Clear PostgreSQL data

Delete every row from the application database while retaining its schema,
roles and credentials. This operation creates no backup and requires an
explicit confirmation token:

```bash
chmod +x scripts/clear-database.sh
./scripts/clear-database.sh --confirm DELETE-ALL-DATA
```

The script keeps all workloads running, truncates every non-system table,
restarts its sequences and verifies zero rows inside the cleanup transaction.
New rows can appear immediately afterward if traffic remains active. Analytics
event history is separate because it lives in Pod-local `emptyDir`. See the
[operations guide](docs/operations-guide.md#clear-postgresql-data).

### Rolling update and rollback

```bash
kubectl set image deployment/traffic-ingest \
  app=registry.example.com/team/traffic-ingest:1.0.1 \
  -n advanced-observability
kubectl rollout status deployment/traffic-ingest -n advanced-observability
kubectl rollout history deployment/traffic-ingest -n advanced-observability
kubectl rollout undo deployment/traffic-ingest -n advanced-observability
```

## Canary demonstration

The stable and canary Deployments share the `traffic-ingest` Service. Inspect
their endpoints, promote a validated image, or remove canary traffic:

```bash
kubectl get pods -n advanced-observability -l app=traffic-ingest \
  -L deployment-track,app.kubernetes.io/version
kubectl set image deployment/traffic-ingest \
  app=registry.example.com/team/traffic-ingest:1.1.0 \
  -n advanced-observability
kubectl scale deployment/traffic-ingest-canary --replicas=0 \
  -n advanced-observability
```

### Helm workflow

```bash
./scripts/deploy-helm.sh --registry registry.example.com/team \
  --tag 1.0.0 --canary-tag 1.1.0 --profile prod
./scripts/verify-helm.sh --live

helm upgrade traffic-ingest helm/traffic-ingest \
  -n advanced-observability --reuse-values --set-string image.tag=1.0.1
helm history traffic-ingest -n advanced-observability
helm rollback traffic-ingest 1 -n advanced-observability
```

### Debug essentials

```bash
kubectl logs deployment/traffic-ingest -n advanced-observability -c app
kubectl describe pod POD_NAME -n advanced-observability
kubectl get events -n advanced-observability --sort-by=.metadata.creationTimestamp
kubectl top pods -n advanced-observability --containers
```

See the [operations guide](docs/operations-guide.md) for complete Ingress,
PVC, canary, Helm, cleanup and debugging runbooks.

## Demo script

Run the guided cluster inspection and requirement evidence collection:

```bash
./scripts/demo.sh
./scripts/verify-requirements.sh --overlay prod
```

The repository also contains 20 hands-on CKAD exercises. See the
[five-day lab guide](labs/README.md) and generate per-day verification reports
with `./labs/verify-all.sh --report-dir lab-verification-reports`.

## Repository map

| Path | Purpose |
|---|---|
| `cmd/`, `internal/` | Go service entrypoints and domain/application adapters |
| `services/` | Service-specific multi-stage Dockerfiles |
| `deployments/` | Kustomize base, overlays and Kubernetes manifests |
| `helm/` | Independent charts for the database and all four application services |
| `scripts/` | Build, deploy, cleanup, smoke, trace and verification automation |
| `labs/` | Five days of hands-on CKAD labs and verifiers |
| `docs/` | Architecture, requirements, proposal and detailed operations |

## Documentation

- [Operations guide](docs/operations-guide.md): complete command reference and
  troubleshooting runbook.
- [Architecture](docs/architecture.md): boundaries, communication contracts,
  Kubernetes design and failure behavior.
- [CKAD checklist](docs/ckad-checklist.md): requirement-to-evidence mapping.
- [Project proposal](docs/project-proposal.md): original scope and stack.
- [Labs](labs/README.md): execution order and per-day verification.

## Known limitations

- `analytics-engine` stores recent events in Pod-local `emptyDir`; restarting
  the Pod removes event history.
- PostgreSQL demonstrates persistence but not database high availability; its
  local PV pins it to `node-2`.
- Canary distribution is replica-based rather than weighted traffic splitting.
- SMTP defaults to log-only notifications.
- Ingress uses HTTP; TLS and cert-manager are outside the capstone scope.
