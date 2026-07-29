# Lab 3.2 - Security Context Lockdown

Duration: approximately 45 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Run every container as UID/GID `65532` with a read-only root filesystem,
RuntimeDefault seccomp, all Linux capabilities dropped, and privilege
escalation disabled.

The `app` container uses the deployed `traffic-ingest` image. Because that
production image is distroless, the init container records the UID and the
result of a root-filesystem write attempt in a shared evidence volume.

```bash
./labs/day3/lab3.2/run.sh run
```

The verification confirms the app is non-root and that writing to `/` fails.
Writable `emptyDir` mounts remain available for generated configuration, logs,
security evidence, and Nginx temporary files.

```bash
kubectl exec -n ckad-labs security-lockdown -c log-sidecar -- cat /evidence/uid
kubectl get pod security-lockdown -n ckad-labs -o yaml
./labs/day3/lab3.2/run.sh cleanup
```
