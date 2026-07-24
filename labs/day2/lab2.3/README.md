# Lab 2.3 - Observable HPA Scale Up and Down

This lab uses a cloned Deployment with CPU requests and an
`autoscaling/v2` HPA. The CPU resource metric covers the entire multi-container
Pod: app, logging sidecar, and Nginx ambassador. This makes proxying and log
processing visible in the scaling decision instead of measuring only the very
lightweight Go health handler.

The HPA keeps 2-10 replicas and targets 25% CPU utilization. Scale-up has no
stabilization delay and may add two Pods or double the replica count every 15
seconds. Scale-down waits for 60 seconds of stable low usage, then removes at
most one Pod every 30 seconds.

## Run the experiment

```bash
./labs/day2/lab2.3/run.sh deploy
./labs/day2/lab2.3/run.sh hpa
./labs/day2/lab2.3/run.sh load
```

The default generator uses 3 Pods with 32 workers each. Increase it when
necessary:

```bash
LOAD_REPLICAS=5 WORKERS=64 ./labs/day2/lab2.3/run.sh load
```

In another terminal:

```bash
./labs/day2/lab2.3/run.sh watch
```

Watch `TARGETS`, `REPLICAS`, and the number of `traffic-hpa` Pods increase.
Then remove the load:

```bash
./labs/day2/lab2.3/run.sh stop-load
```

The HPA retains the recent high recommendation for 60 seconds, then scales down
one Pod every 30 seconds until it reaches `minReplicas: 2`.

Inspect container-level CPU and HPA events:

```bash
./labs/day2/lab2.3/run.sh status
kubectl describe hpa traffic-hpa -n ckad-labs
```

The existing `scale` action remains available for a manual-scaling comparison,
but an active HPA will subsequently override that replica count.

Metrics Server normally needs several scrape/sync intervals, so allow 30-90
seconds for the first scale-up. If HPA shows `<unknown>/25%`, install or repair
Metrics Server. Cleanup removes
the target Deployment, Service, HPA, and load generator:

```bash
./labs/day2/lab2.3/run.sh cleanup
```
