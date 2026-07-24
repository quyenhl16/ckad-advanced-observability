# Kubernetes deployment

The base deploys four Go services and one PostgreSQL StatefulSet into the
`advanced-observability` namespace.

## Automated deployment on CentOS Stream 10

The repository includes an end-to-end Bash script for a CentOS Stream 10 host.
It requires access to an existing Kubernetes cluster, `kubectl`, and either
Docker or Podman. Kind and Minikube also require their respective CLI.

Make the script executable, then choose the example matching the cluster.

```bash
chmod +x scripts/deploy-k8s.sh
```

For Kind:

```bash
POSTGRES_PASSWORD='replace-with-a-strong-value' \
ALERT_API_KEY='replace-with-a-strong-value' \
./scripts/deploy-k8s.sh --cluster kind --cluster-name observability
```

For Minikube:

```bash
POSTGRES_PASSWORD='replace-with-a-strong-value' \
ALERT_API_KEY='replace-with-a-strong-value' \
./scripts/deploy-k8s.sh --cluster minikube --cluster-name minikube
```

For a remote or multi-node cluster, authenticate the container engine to a
registry that every Kubernetes node can pull from, then run. For a private
registry, the nodes or Kubernetes workload must already have pull credentials.

```bash
podman login registry.example.com
POSTGRES_PASSWORD='replace-with-a-strong-value' \
ALERT_API_KEY='replace-with-a-strong-value' \
./scripts/deploy-k8s.sh \
  --cluster generic \
  --engine podman \
  --registry registry.example.com/my-team
```

Run `./scripts/deploy-k8s.sh --help` for all options. The script performs these
steps: validates cluster access, builds four service images, loads or pushes
the images, generates a temporary Kustomize overlay with secrets and image
tags, applies the manifests, waits for all rollouts, and prints access commands.

For a generic/shared cluster, `POSTGRES_PASSWORD` and `ALERT_API_KEY` are
mandatory. Avoid changing the PostgreSQL credentials after the database PVC
has already been initialized.

## 1. Build the application images

Run these commands from the repository root:

```powershell
docker build --build-arg SERVICE=traffic-ingest -t ckad/traffic-ingest:local .
docker build --build-arg SERVICE=analytics-engine -t ckad/analytics-engine:local .
docker build --build-arg SERVICE=alert-manager -t ckad/alert-manager:local .
docker build --build-arg SERVICE=observability-frontend -t ckad/observability-frontend:local .
```

For Kind, load the images into the cluster:

```powershell
kind load docker-image ckad/traffic-ingest:local
kind load docker-image ckad/analytics-engine:local
kind load docker-image ckad/alert-manager:local
kind load docker-image ckad/observability-frontend:local
```

For Minikube, replace `kind load docker-image` with `minikube image load`.

## 2. Configure secrets

The values in `base/config.yaml` are safe placeholders for a local learning
cluster only. Change at least `POSTGRES_PASSWORD` and `ALERT_API_KEY` before
deploying to a shared cluster.

The default `ALERT_NOTIFIER=log` writes simulated email deliveries to the
`alert-manager` log. To send real mail, change it to `smtp` and set all SMTP
keys in `observability-secrets`.

## 3. Apply and verify

The base uses a static local PersistentVolume on the node whose hostname is
`node-2`. Before applying the manifests, create its backing directory on that
node:

```bash
sudo install -d -o 70 -g 70 -m 700 /var/lib/observability-postgres
kubectl get node node-2
```

If the database should run on another node, change the hostname under
`spec.nodeAffinity` in `base/postgres-pv.yaml` and create the same directory on
that node. A local PV ties PostgreSQL to that node; it does not provide storage
replication.

```powershell
kubectl apply -k deployments/base
kubectl get pods,svc,pvc -n advanced-observability
kubectl rollout status statefulset/observability-db -n advanced-observability
kubectl rollout status deployment/alert-manager -n advanced-observability
kubectl rollout status deployment/analytics-engine -n advanced-observability
kubectl rollout status deployment/traffic-ingest -n advanced-observability
kubectl rollout status deployment/observability-frontend -n advanced-observability
```

## 4. Open the frontend and ingestion endpoint

```powershell
kubectl port-forward -n advanced-observability service/observability-frontend 8083:8083
kubectl port-forward -n advanced-observability service/traffic-ingest 8080:8080
```

Open `http://localhost:8083` and send test traffic to
`http://localhost:8080/api/v1/metrics`.

## Workload notes

- Every Go application Pod uses four roles: a completed `config-init`, the
  main `app`, a `log-sidecar`, and an `nginx-ambassador`. Services target Nginx
  on ports 8080-8083; applications listen internally on ports 18080-18083.
- The log sidecar tails Nginx access logs from a shared `emptyDir`. The Go
  process continues to emit its structured application logs to stdout.
- `analytics-engine` intentionally has one replica because its query API reads
  a Pod-local `emptyDir`. Scale it only after logs are moved to centralized
  storage.
- PostgreSQL uses one replica and a `ReadWriteOnce` PVC. This demonstrates
  persistence, not database high availability. Its static local PV has the
  `Retain` reclaim policy, so deleting the namespace does not erase the files
  under `/var/lib/observability-postgres`.
- NetworkPolicies require a CNI implementation that enforces them.
- The traffic-ingest PodDisruptionBudget keeps one of its two replicas
  available during voluntary disruptions.
