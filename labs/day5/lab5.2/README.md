# Lab 5.2 - CLI Observability

Duration: approximately 45 minutes. CKAD domain: Application Observability
and Maintenance (15%).

The main `app` container uses the deployed `traffic-ingest` image. A small
`log-helper` exits once; a marker in `emptyDir` survives its restart, so the
next instance remains running. This creates deterministic previous logs
without intentionally crashing the real application.

Run the complete workflow:

```bash
./labs/day5/lab5.2/run.sh run
```

Practice each observability command separately:

```bash
kubectl logs cli-observer -n ckad-labs -c app
kubectl logs cli-observer -n ckad-labs -c log-helper
kubectl logs cli-observer -n ckad-labs -c log-helper --previous
kubectl describe pod cli-observer -n ckad-labs
kubectl get events -n ckad-labs \
  --field-selector involvedObject.name=cli-observer \
  --sort-by=.lastTimestamp
kubectl top pod cli-observer -n ckad-labs --containers
```

Metrics Server is required for `kubectl top`. The lab retries for approximately
one minute while the first resource sample becomes available.

```bash
./labs/day5/lab5.2/run.sh cleanup
```
