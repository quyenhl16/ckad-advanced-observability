# Lab 5.4 - Helm Deploy and Rollback

Duration: approximately 45 minutes. CKAD domain: Application Deployment
(20%).

Install the bundled Helm chart with value overrides, upgrade the release, and
roll back to the preceding revision. A ConfigMap supplies the served message,
and a checksum annotation triggers a Deployment rollout when that value
changes.

Run the complete workflow:

```bash
./labs/day5/lab5.4/run.sh run
```

Practice the Helm commands separately:

```bash
REPLICAS=1 MESSAGE=release-v1 ./labs/day5/lab5.4/run.sh install
REPLICAS=2 MESSAGE=release-v2 ./labs/day5/lab5.4/run.sh upgrade
./labs/day5/lab5.4/run.sh history
./labs/day5/lab5.4/run.sh rollback
./labs/day5/lab5.4/run.sh verify
```

Equivalent direct commands:

```bash
helm upgrade --install day5-observer labs/day5/lab5.4/chart/observer-demo \
  -n ckad-labs --create-namespace \
  --set replicaCount=1 --set-string message=release-v1
helm upgrade day5-observer labs/day5/lab5.4/chart/observer-demo \
  -n ckad-labs --reuse-values \
  --set replicaCount=2 --set-string message=release-v2
helm history day5-observer -n ckad-labs
helm rollback day5-observer 1 -n ckad-labs
```

Cleanup:

```bash
./labs/day5/lab5.4/run.sh cleanup
```
