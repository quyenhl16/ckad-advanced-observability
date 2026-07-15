# CKAD application labs

These labs reuse the observability application without modifying the live
workloads. Day 1 resources and the cloned Day 2 workloads run in the
`ckad-labs` namespace.

## Prerequisites

- `kubectl` is configured for the cluster.
- The application is running in `advanced-observability`.
- The application images are reachable by every Kubernetes node.
- Metrics Server is required only for Lab 2.3 HPA metrics.

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

Clean all namespaced lab resources when finished:

```bash
kubectl delete namespace ckad-labs
```

Lab 2.4 is intentionally Kustomize-based and has its own cleanup command.
