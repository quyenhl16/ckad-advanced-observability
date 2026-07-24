# Lab 2.1 - Rolling Update and Rollback

This lab uses the isolated `traffic-rollout` Deployment. It has three replicas,
readiness probes, `maxUnavailable: 0`, and `maxSurge: 1`.

```bash
VERSION_V1=v1 ./labs/day2/lab2.1/run.sh deploy
IMAGE_V2=10.206.0.3:5000/traffic-ingest:v2 VERSION_V2=v2 \
  ./labs/day2/lab2.1/run.sh update
./labs/day2/lab2.1/run.sh fail
./labs/day2/lab2.1/run.sh undo
./labs/day2/lab2.1/run.sh history
./labs/day2/lab2.1/run.sh status
```

The update changes the application image and Pod label `version` in one patch,
so Kubernetes creates one new ReplicaSet for the release. Watch both versions:

```bash
kubectl get pods -n ckad-labs -l app=traffic-rollout -L version -w
```

The Deployment selector intentionally contains only `app: traffic-rollout`.
The `version` label is kept in the Pod template so the Deployment can manage
both old and new versions during the rolling update.

The `fail` action deliberately uses an invalid image. Existing ready replicas
remain available; run `undo` to restore both the previous image and version.
