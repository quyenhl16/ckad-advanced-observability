# Lab 5.1 - Self-Healing App

Duration: approximately 45 minutes. CKAD domain: Application Observability
and Maintenance (15%).

Deploy the real `traffic-ingest` image as the main application container with:

- A startup probe that gives the application up to 60 seconds to start.
- HTTP liveness and readiness probes on its real health endpoints.
- A small BusyBox readiness helper with a file-based exec probe on
  `/tmp/ready`.

Run the complete workflow:

```bash
./labs/day5/lab5.1/run.sh run
```

The production image is distroless, so it has no shell or `test` binary for a
file probe. The helper supplies only that capability. The `break` action
deletes the helper's HTTP health file; kubelet restarts it while the real
application remains running, then the script waits until the helper becomes
Ready again.

```bash
./labs/day5/lab5.1/run.sh deploy
./labs/day5/lab5.1/run.sh verify
./labs/day5/lab5.1/run.sh break
kubectl describe pod -n ckad-labs -l app=self-healing-app
./labs/day5/lab5.1/run.sh cleanup
```
