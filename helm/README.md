# Service Helm charts

The main namespace is `advanced-observability`. Each runtime service has an
independent Helm release while keeping the stable in-cluster DNS names used by
the business flow.

| Release/chart | Main resources | Depends on |
|---|---|---|
| `observability-platform` | Quota, limits, default deny, audit RBAC/CronJob | Namespace |
| `observability-db` | Local PV, StorageClass, Service, StatefulSet | Runtime Secret |
| `alert-manager` | ConfigMaps, Service, Deployment, PDB, NetworkPolicy | Database, runtime Secret |
| `analytics-engine` | ConfigMaps, Service, Deployment, NetworkPolicy | Alert Manager, runtime Secret |
| `traffic-ingest` | Stable/canary Deployments, Service, HPA, PDB, NetworkPolicy | Analytics Engine |
| `observability-frontend` | Deployment, Service, Ingress, PDB, NetworkPolicy | Analytics, Alert Manager, Ingest |

The charts do not commit secret values. `scripts/deploy-helm.sh` creates or
updates `observability-secrets` from environment variables before installing
the releases in dependency order.

## Install the complete application

Remove an existing Kustomize deployment first because Helm cannot adopt those
objects safely:

```bash
./scripts/cleanup.sh --confirm advanced-observability

export POSTGRES_PASSWORD='replace-me'
export ALERT_API_KEY='replace-me'
chmod +x scripts/deploy-helm.sh scripts/verify-helm.sh
./scripts/deploy-helm.sh \
  --registry 10.206.0.3:5000 \
  --tag YOUR_IMAGE_TAG \
  --canary-tag YOUR_CANARY_TAG \
  --profile prod
```

The database chart defaults to local storage on `node-2` at
`/var/lib/observability-postgres`. Override it with `--db-node` and `--db-path`.

## Validate

```bash
./scripts/verify-helm.sh
./scripts/verify-helm.sh --live
```

## Operate one service

```bash
helm upgrade --install observability-platform helm/observability-platform \
  -n advanced-observability --create-namespace

helm upgrade traffic-ingest helm/traffic-ingest \
  -n advanced-observability --reuse-values \
  --set-string image.tag=NEW_TAG

helm history traffic-ingest -n advanced-observability
helm rollback traffic-ingest 1 -n advanced-observability
```

Install a chart alone only after its dependencies and the
`observability-secrets` Secret exist. Keep the documented release names so the
fixed service DNS names and upgrade workflow remain unambiguous.

## Uninstall

```bash
helm uninstall observability-frontend traffic-ingest analytics-engine \
  alert-manager observability-db observability-platform \
  -n advanced-observability
```

The local PV and StorageClass have `helm.sh/resource-policy: keep`. Use the
project cleanup script when they must also be removed. Files under the local
node path are intentionally not deleted over SSH.
