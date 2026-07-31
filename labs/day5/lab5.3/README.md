# Lab 5.3 - Broken YAML Triage

Duration: approximately 45 minutes. CKAD domain: Application Observability
and Maintenance (15%).

Troubleshoot three faults in sequence:

1. `broken-selector.yaml` has a Deployment selector that does not match its
   Pod template labels, so the API server rejects it.
2. `broken-runtime.yaml` fixes the selector but uses `INVALID_IMAGE_NAME`, so
   kubelet reports `InvalidImageName`.
3. The Service uses `targetPort: web`, while the container port is named
   `http`, so it cannot route traffic correctly.

The fixed Deployment uses the real `traffic-ingest` image discovered from the
running production workload. BusyBox remains only as a short-lived Service
probe.

Run the complete triage and repair:

```bash
./labs/day5/lab5.3/run.sh run
```

Practice one stage at a time:

```bash
./labs/day5/lab5.3/run.sh diagnose
./labs/day5/lab5.3/run.sh runtime
kubectl get pod -n ckad-labs -l app=triage-app
kubectl describe pod -n ckad-labs -l app=triage-app
diff -u labs/day5/lab5.3/broken-runtime.yaml labs/day5/lab5.3/fixed.yaml
./labs/day5/lab5.3/run.sh fix
./labs/day5/lab5.3/run.sh verify
```

Cleanup:

```bash
./labs/day5/lab5.3/run.sh cleanup
```
