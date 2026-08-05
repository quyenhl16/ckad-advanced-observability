# CKAD application labs

These labs reuse the observability application without modifying the live
workloads. Day 1 resources and the cloned Day 2 workloads run in the
`ckad-labs` namespace.

## Prerequisites

- `kubectl` is configured for the cluster.
- The application is running in `advanced-observability`.
- The application images are reachable by every Kubernetes node.
- Metrics Server is required for Labs 2.3 and 5.2.
- An NGINX Ingress controller is required only for Lab 4.2.
- A CNI that enforces NetworkPolicy is required only for Lab 4.3.
- A default dynamic StorageClass, or an explicit `STORAGE_CLASS`, is required
  only for Lab 4.4.
- Helm 3 is required only for Lab 5.4.

Every lab directory contains a reference manifest and a `run.sh` exam-speed
script. Make all scripts executable on CentOS:

```bash
find labs -name '*.sh' -exec chmod +x {} +
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

Day 5 covers application observability, troubleshooting, and Helm:

- Lab 5.1: startup, HTTP liveness, and file-based readiness probes.
- Lab 5.2: container logs, previous logs, Events, and resource metrics.
- Lab 5.3: selector, image-name, and Service targetPort troubleshooting.
- Lab 5.4: Helm value overrides, upgrades, release history, and rollback.

Run each complete Day 5 workflow with its default `run` action:

```bash
./labs/day5/lab5.1/run.sh
./labs/day5/lab5.2/run.sh
./labs/day5/lab5.3/run.sh
./labs/day5/lab5.4/run.sh
```

## Verify each day

After completing all four labs for a day, run its live verifier. Every check
prints the lab requirement, commands used, raw output, evidence and a final
`VERIFY: PASS` or `VERIFY: FAIL` result:

```bash
./labs/day1/verify.sh --report day1-verification.txt
./labs/day2/verify.sh --report day2-verification.txt
./labs/day3/verify.sh --report day3-verification.txt
./labs/day4/verify.sh --report day4-verification.txt
./labs/day5/verify.sh --report day5-verification.txt
```

Run every day and create one report per day:

```bash
./labs/verify-all.sh --report-dir lab-verification-reports
```

These are live checks. Missing lab resources produce `FAIL`; run the associated
`labs/dayN/labN.X/run.sh run` workflow before rerunning the day verifier. The
Day 3 quota check performs the expected admission-rejection test, Day 4 uses
short-lived network probes, and Day 5 verifies Metrics Server and Helm output.

Clean all namespaced lab resources when finished:

```bash
kubectl delete namespace ckad-labs
```

Lab 2.4 is intentionally Kustomize-based and has its own cleanup command.
