# Lab 2.3 - Observable HPA Scale Up and Down

This lab uses a cloned Deployment with CPU requests and an
`autoscaling/v2` HPA. The metric targets only the `app` container, so CPU from
the logging sidecar and Nginx ambassador does not distort the decision.

The HPA keeps 2-10 replicas and targets 30% of the app container's `50m` CPU
request. Scale-up has no stabilization delay and may add two Pods or double the
replica count every 15 seconds. Scale-down waits for 60 seconds of stable low
usage, then removes at most one Pod every 30 seconds.

## Run the experiment

```bash
./labs/day2/lab2.3/run.sh deploy
./labs/day2/lab2.3/run.sh hpa
./labs/day2/lab2.3/run.sh load
```

Increase the load when necessary:

```bash
WORKERS=32 ./labs/day2/lab2.3/run.sh load
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

If HPA shows `<unknown>/30%`, install or repair Metrics Server. Cleanup removes
the target Deployment, Service, HPA, and load generator:

```bash
./labs/day2/lab2.3/run.sh cleanup
```
