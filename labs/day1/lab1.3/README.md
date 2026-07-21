# Lab 1.3 - Jobs and CronJobs

The one-off Job and scheduled CronJob submit high-latency metrics to the live
traffic-ingest Service. Resources run in `ckad-labs` and do not modify the live
Deployments.

Each batch Pod uses the same four roles. The main container writes a completion
marker so the logging sidecar and Nginx ambassador exit and the Job can reach
the `Complete` condition.

```bash
./labs/day1/lab1.3/run.sh
```

Useful commands:

```bash
kubectl get job,cronjob,pod -n ckad-labs
kubectl logs -n ckad-labs job/metric-once
kubectl get jobs -n ckad-labs --sort-by=.metadata.creationTimestamp
```
