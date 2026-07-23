# Lab 3.4 - Namespace Quotas

Duration: approximately 45 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Use a dedicated `ckad-quota-lab` namespace so quota experiments cannot block
the other labs. A LimitRange injects default requests and limits into every
container, while a ResourceQuota caps aggregate namespace resources.

```bash
./labs/day3/lab3.4/run.sh run
```

`quota-accepted` fits after LimitRange defaults are applied. Creating
`quota-exceeded` would raise aggregate CPU requests above `500m`, so admission
must reject it with an `exceeded quota` message.

```bash
kubectl describe resourcequota compute-quota -n ckad-quota-lab
kubectl describe limitrange container-defaults -n ckad-quota-lab
kubectl get pod quota-accepted -n ckad-quota-lab -o yaml
./labs/day3/lab3.4/run.sh cleanup
```
