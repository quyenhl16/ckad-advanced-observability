# Kubernetes deployment layout

- `base/`: application resources shared by every environment
- `overlays/dev/`: development image tags and replica counts
- `overlays/prod/`: production image tags and replica counts

The base intentionally does not contain a Secret value. Use
`../scripts/deploy.sh`, which creates `observability-secrets` from environment
variables in a temporary Kustomize layer, or create the Secret before applying
an overlay manually. See the repository [README](../README.md) for commands.

PostgreSQL uses a StatefulSet `volumeClaimTemplate` and the cluster's default
dynamic StorageClass. No node name, host path, PersistentVolume or credentials
are embedded in the repository.

Validate and compare overlays:

```bash
kubectl kustomize deployments/overlays/dev >/tmp/observability-dev.yaml
kubectl kustomize deployments/overlays/prod >/tmp/observability-prod.yaml
kubectl diff -k deployments/overlays/dev -n advanced-observability
```
