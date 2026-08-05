# Advanced Network Observability

CKAD capstone project for collecting network-device metrics, detecting abnormal
latency, persisting alerts and subscriptions, and presenting an operator
dashboard on Kubernetes.

Repository: <https://github.com/quyenhl16/ckad-advanced-observability>

## Business domain and user story

Network operators need one place to receive telemetry from routers, switches,
servers, firewalls, and access points. As an operator, I can submit a metric,
have it evaluated against a configured latency threshold, persist an alert,
notify matching subscribers, and inspect recent events from a web dashboard.

## Services

| Service | Responsibility | Container port | Kubernetes Service |
|---|---|---:|---|
| `traffic-ingest` | Validate incoming metrics and forward them for analysis | 8080 | NodePort 30080 / ClusterIP |
| `analytics-engine` | Evaluate thresholds and keep recent analysis events | 8081 | ClusterIP |
| `alert-manager` | Own alerts, users, subscriptions and notification delivery | 8082 | ClusterIP |
| `observability-frontend` | Render the operator dashboard and subscription UI | 8083 | NodePort 30083 / Ingress |

PostgreSQL is infrastructure owned by `alert-manager`, not a fifth core
microservice. Communication is synchronous HTTP over Kubernetes DNS:
`traffic-ingest -> analytics-engine -> alert-manager`, while the frontend reads
from analytics and alert-manager. See [architecture.md](docs/architecture.md).

## CKAD capabilities

The capstone deployment includes:

- four independently tagged application images and five Deployments including
  a second canary Deployment;
- init containers, log sidecars, an Nginx ambassador and shared `emptyDir`
  volumes;
- a PostgreSQL StatefulSet backed by a retained local PV/PVC on `node-2`;
- stable/canary traffic sharing, rolling updates, HPA and PDB;
- ConfigMaps, runtime-generated Secret, restricted security contexts, custom
  ServiceAccount/RBAC, ResourceQuota and LimitRange;
- ClusterIP/NodePort Services, a two-path Ingress, default-deny and explicit
  NetworkPolicies;
- liveness/readiness probes on every long-running workload and startup probes
  on application services;
- Kustomize `dev`/`prod` overlays and a standalone Helm chart for
  `traffic-ingest`.

The evidence map for every mandatory item is in
[ckad-checklist.md](docs/ckad-checklist.md).

## Prerequisites

- Kubernetes 1.35.x or the version assigned by the instructor
- a policy-capable CNI
- Nginx Ingress controller with IngressClass `nginx`
- Metrics Server for HPA and `kubectl top`
- a default dynamic StorageClass available for the class cluster; this project
  intentionally demonstrates a static local PV for PostgreSQL
- a node named `node-2` with `/var/lib/observability-postgres` prepared for
  the PostgreSQL local PersistentVolume
- `kubectl`, Helm 3, Docker or Podman, and Bash
- permission to use the dedicated `advanced-observability` namespace

Make the Bash entrypoints executable after cloning on Linux:

```bash
chmod +x scripts/*.sh
```

Confirm the cluster prerequisites:

```bash
kubectl version
kubectl get ingressclass
kubectl get storageclass
kubectl get deployment metrics-server -n kube-system
```

## Build images

Each core service has its own multi-stage Dockerfile under `services/`. Use an
immutable version or Git SHA; do not use `latest`.

```bash
IMAGE_TAG=1.0.0 REGISTRY_PREFIX=ckad CONTAINER_ENGINE=docker \
  ./scripts/build.sh
```

The build produces four core images and a separate
`traffic-ingest-canary:<tag>-canary` reference for the canary Deployment. Set
`CANARY_IMAGE_TAG` when a different canary version such as `1.1.0` is required.

## Deploy

Secrets are never stored in Git. The deployment script reads them from the
environment, creates a temporary mode-0600 Kustomize input, applies it, and
removes it on exit.

```bash
export POSTGRES_PASSWORD='use-a-strong-value'
export ALERT_API_KEY='use-a-different-strong-value'

./scripts/deploy.sh \
  --cluster kind \
  --cluster-name observability \
  --overlay dev \
  --tag 1.0.0 \
  --canary-tag 1.1.0
```

For a remote cluster, authenticate to its registry first:

```bash
POSTGRES_PASSWORD="$POSTGRES_PASSWORD" ALERT_API_KEY="$ALERT_API_KEY" \
./scripts/deploy.sh --cluster generic --overlay prod \
  --registry registry.example.com/team --tag 1.0.0 --canary-tag 1.1.0
```

To practice Kustomize directly, create the namespace and Secret first, then
apply an overlay:

```bash
kubectl apply -f deployments/base/namespace.yaml
kubectl create secret generic observability-secrets \
  -n advanced-observability \
  --from-literal=POSTGRES_USER=observability \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB=observability \
  --from-literal=ALERT_API_KEY="$ALERT_API_KEY" \
  --from-literal=SMTP_ADDRESS=smtp.example.com:587 \
  --from-literal=SMTP_HOST=smtp.example.com \
  --from-literal=SMTP_USERNAME=unused \
  --from-literal=SMTP_PASSWORD=unused \
  --from-literal=SMTP_FROM=alerts@example.com \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k deployments/overlays/dev
```

## Full cleanup and redeploy

Use this procedure to remove and recreate the Kubernetes deployment. It removes
the project namespace, the project-specific local PV object and its
`observability-local` StorageClass. Deleting the namespace also removes any Helm
release metadata stored there. It does **not** remove shared cluster components
or the PostgreSQL files stored on `node-2`.

From `node-1`, run the cleanup script. The confirmation value is deliberately
required to prevent accidental namespace deletion:

```bash
./scripts/cleanup.sh --confirm advanced-observability
```

The script validates the Kubernetes context and exact resource names, then
deletes only the namespace, PV object and project StorageClass. It never uses
SSH and leaves `/var/lib/observability-postgres` unchanged. Because that
directory contains the existing PostgreSQL cluster, redeploy with the same
`POSTGRES_PASSWORD`; changing it does not update the password already stored in
the retained database.

To redeploy from `node-1`, authenticate to the image registry, set fresh
secrets and run:

```bash
export POSTGRES_PASSWORD='use-the-existing-database-password'
export ALERT_API_KEY='use-a-different-strong-value'

./scripts/deploy.sh \
  --cluster generic \
  --overlay prod \
  --registry registry.example.com/team

./scripts/smoke-test.sh
./scripts/verify-requirements.sh --overlay prod \
  --report requirement-verification.txt
```

## Verify and access

```bash
./scripts/smoke-test.sh
./scripts/verify-requirements.sh --overlay dev
kubectl get pods,svc,endpointslices,hpa,ingress,pvc -n advanced-observability
```

The requirement verifier prints every requirement, the command executed, its
output, evidence and a `PASS`, `FAIL` or `SKIP` result. It covers the mandatory
CKAD checklist plus microservice, cluster, deliverable and automatic-fail
criteria. Use `--static-only` before deployment or save live evidence with:

```bash
./scripts/verify-requirements.sh --overlay prod \
  --report requirement-verification.txt
```

Add the Ingress address to local DNS as `observability.local`, then use:

```bash
curl -H 'Host: observability.local' http://INGRESS_ADDRESS/
curl -H 'Host: observability.local' \
  -H 'Content-Type: application/json' \
  -d '{"device_type":"router","device_id":"edge-01","cpu_usage_percent":45,"memory_usage_percent":55,"temperature_celsius":48,"latency_ms":220,"packet_loss_percent":1}' \
  http://INGRESS_ADDRESS/api/v1/metrics
```

Port-forwarding remains available when the Ingress controller is unavailable:

```bash
kubectl port-forward -n advanced-observability service/observability-frontend 8083:8083
kubectl port-forward -n advanced-observability service/traffic-ingest 8080:8080
```

## Rolling update and rollback

```bash
kubectl set image deployment/traffic-ingest \
  app=registry.example.com/team/traffic-ingest:1.0.1 \
  -n advanced-observability
kubectl rollout status deployment/traffic-ingest -n advanced-observability
kubectl rollout history deployment/traffic-ingest -n advanced-observability

# Roll back if verification fails
kubectl rollout undo deployment/traffic-ingest -n advanced-observability
kubectl rollout status deployment/traffic-ingest -n advanced-observability
```

The strategy uses `maxUnavailable: 0` and `maxSurge: 1`.

## Canary demonstration

The `traffic-ingest` Service selects both the stable Deployment and
`traffic-ingest-canary`. With two stable Pods and one canary Pod, approximately
one third of new connections reach the canary. The stable HPA can change the
ratio under load.

```bash
kubectl get pods -n advanced-observability -l app=traffic-ingest \
  -L deployment-track,app.kubernetes.io/version
kubectl get endpointslices -n advanced-observability \
  -l kubernetes.io/service-name=traffic-ingest -o wide

# Promote by updating the stable image after validation
kubectl set image deployment/traffic-ingest app=ckad/traffic-ingest:1.1.0 \
  -n advanced-observability

# Remove canary traffic without deleting its manifest
kubectl scale deployment/traffic-ingest-canary --replicas=0 \
  -n advanced-observability
```

Reapply the chosen overlay after the demo to restore the declared replica
count.

## Helm install, upgrade and rollback

The chart packages the critical ingestion service independently. Install it
with a release name that does not collide with the Kustomize workload:

```bash
helm upgrade --install capstone-ingest helm/traffic-ingest \
  -n advanced-observability \
  --set image.repository=ckad/traffic-ingest \
  --set-string image.tag=1.0.0 \
  --set replicaCount=2

helm upgrade capstone-ingest helm/traffic-ingest \
  -n advanced-observability --reuse-values \
  --set-string image.tag=1.0.1 --set replicaCount=3
helm history capstone-ingest -n advanced-observability
helm rollback capstone-ingest 1 -n advanced-observability
```

## PVC persistence demo

In terminal one:

```bash
kubectl port-forward -n advanced-observability service/alert-manager 8082:8082
```

In terminal two, create data, recreate the database Pod, and query it again:

```bash
curl -X POST -H 'Content-Type: application/json' \
  -d '{"name":"Persistence Demo","email":"persistence@example.com"}' \
  http://localhost:8082/api/v1/users
curl http://localhost:8082/api/v1/users
kubectl delete pod observability-db-0 -n advanced-observability
kubectl wait --for=condition=Ready pod/observability-db-0 \
  -n advanced-observability --timeout=180s
curl http://localhost:8082/api/v1/users
```

The same user must still be returned after the Pod recreation.

## Debug runbook

```bash
# Application and sidecar logs
kubectl logs -n advanced-observability deployment/traffic-ingest -c app
kubectl logs -n advanced-observability deployment/traffic-ingest -c log-sidecar
kubectl logs -n advanced-observability POD_NAME -c app --previous

# Configuration, scheduling, probes and failures
kubectl describe pod POD_NAME -n advanced-observability
kubectl describe deployment traffic-ingest -n advanced-observability
kubectl get events -n advanced-observability \
  --sort-by=.metadata.creationTimestamp

# Resource use and autoscaling
kubectl top pods -n advanced-observability --containers
kubectl describe hpa traffic-ingest -n advanced-observability

# Networking and storage
kubectl get svc,endpointslices,ingress,networkpolicy -n advanced-observability
kubectl get pvc -n advanced-observability
```

If an endpoint is empty, compare the Service selector with Pod labels and the
Service `targetPort` with the named container port. If HPA displays `unknown`,
verify Metrics Server and container CPU requests.

## Demo script

Run `./scripts/demo.sh` for the 5–10 minute guided inspection. The complete
manual presentation order is documented in [ckad-checklist.md](docs/ckad-checklist.md).

## Known limitations

- `analytics-engine` keeps recent event history in Pod-local `emptyDir`; a
  production version would send this stream to object storage or a dedicated
  time-series database.
- PostgreSQL demonstrates persistence, not database high availability.
- Its local PV pins the database to `node-2`; node loss requires manual data
  recovery and the retained PV claim must be released before namespace reuse.
- SMTP defaults to log-only notification; real mail requires SMTP credentials
  and a narrowly scoped egress destination.
- The canary ratio is replica-based rather than request-weighted and changes
  when HPA scales the stable Deployment.
- TLS and cert-manager are outside this capstone; Ingress uses HTTP for the
  classroom demonstration.
