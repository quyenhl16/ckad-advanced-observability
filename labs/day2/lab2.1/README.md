# Lab 2.1 - Rolling Update and Rollback

This lab uses the isolated `traffic-rollout` Deployment. It has three replicas,
readiness probes, `maxUnavailable: 0`, and `maxSurge: 1`.

```bash
./labs/day2/lab2.1/run.sh deploy
IMAGE_V2=10.206.0.3:5000/traffic-ingest:v2 ./labs/day2/lab2.1/run.sh update
./labs/day2/lab2.1/run.sh fail
./labs/day2/lab2.1/run.sh undo
./labs/day2/lab2.1/run.sh history
```

The `fail` action deliberately uses an invalid image. Existing ready replicas
remain available; run `undo` to restore the previous revision.
