# CKAD application labs

These labs reuse the observability application without modifying the live
workloads. Day 1 resources and the cloned Day 2 workloads run in the
`ckad-labs` namespace.

## Prerequisites

- `kubectl` is configured for the cluster.
- The application is running in `advanced-observability`.
- The application images are reachable by every Kubernetes node.
- Metrics Server is required only for Lab 2.3 HPA metrics.
- An NGINX Ingress controller is required only for Lab 4.2.
- A CNI that enforces NetworkPolicy is required only for Lab 4.3.
- A default dynamic StorageClass, or an explicit `STORAGE_CLASS`, is required
  only for Lab 4.4.

Every lab directory contains a reference manifest and a `run.sh` exam-speed
script. Make all scripts executable on CentOS:

```bash
find labs -name run.sh -exec chmod +x {} +
```

The scripts first use an explicit `IMAGE`, otherwise they copy the image from a
currently Running production Pod. They use the Deployment spec only when it is
not a `ckad/...:local` placeholder. This prevents accidental Docker Hub pulls
after a failed production rollout. You can override image discovery explicitly:

```bash
IMAGE=10.206.0.3:5000/traffic-ingest:my-tag ./labs/day1/lab1.1/run.sh
```

Start with Day 1. Day 2 scripts use separate names such as `traffic-rollout`,
`traffic-bg-blue`, and `traffic-hpa`, so Service selectors from the live
application do not select lab Pods.

Day 3 covers the Application Environment, Configuration & Security domain:

- Lab 3.1: declarative Secret and ConfigMap manifests, env and volume injection.
- Lab 3.2: non-root security context, read-only root filesystem, dropped
  capabilities, and disabled privilege escalation.
- Lab 3.3: ServiceAccount, Role, RoleBinding, and an in-Pod Kubernetes API call.
- Lab 3.4: LimitRange defaults and ResourceQuota admission rejection in an
  isolated namespace.

Run a complete Day 3 lab with its default `run` action, for example:

```bash
./labs/day3/lab3.1/run.sh
./labs/day3/lab3.2/run.sh
./labs/day3/lab3.3/run.sh
./labs/day3/lab3.4/run.sh
```

Day 4 covers networking and persistent storage:

- Lab 4.1: ClusterIP and NodePort Services, selector diagnosis, and Endpoints.
- Lab 4.2: NGINX Ingress host/path routing to frontend and backend Services.
- Lab 4.3: frontend-only backend ingress and deny-all backend egress policies.
- Lab 4.4: dynamic 1 Gi PVC provisioning and data persistence across Pods.

Run each complete Day 4 workflow with its default `run` action:

```bash
./labs/day4/lab4.1/run.sh
./labs/day4/lab4.2/run.sh
./labs/day4/lab4.3/run.sh
./labs/day4/lab4.4/run.sh
```

Clean all namespaced lab resources when finished:

```bash
kubectl delete namespace ckad-labs
```

Lab 2.4 is intentionally Kustomize-based and has its own cleanup command.
