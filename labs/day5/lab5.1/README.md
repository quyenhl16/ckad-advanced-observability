# Lab 5.1 - Self-Healing App

Duration: approximately 45 minutes. CKAD domain: Application Observability
and Maintenance (15%).

Deploy a slow-starting HTTP container with:

- A startup probe that gives the process up to 60 seconds to start.
- An HTTP liveness probe on `/health`.
- A file-based exec readiness probe on `/tmp/ready`.

Run the complete workflow:

```bash
./labs/day5/lab5.1/run.sh run
```

The `break` action deletes the HTTP health file. After two failed liveness
checks, kubelet restarts the container. The startup command recreates both
health files, and the script waits until `restartCount` increases and the
container becomes Ready again.

```bash
./labs/day5/lab5.1/run.sh deploy
./labs/day5/lab5.1/run.sh verify
./labs/day5/lab5.1/run.sh break
kubectl describe pod -n ckad-labs -l app=self-healing-app
./labs/day5/lab5.1/run.sh cleanup
```
