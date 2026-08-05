# Kubernetes deployment layout

- `base/`: application resources shared by every environment
- `overlays/dev/`: development image tags and replica counts
- `overlays/prod/`: production image tags and replica counts

The base intentionally does not contain a Secret value. Use
`../scripts/deploy.sh`, which creates `observability-secrets` from environment
variables in a temporary Kustomize layer, or create the Secret before applying
an overlay manually. See the repository [README](../README.md) for commands.

The alert manager receives PostgreSQL credentials through the standard `PG*`
environment variables instead of embedding them in a connection URL. Passwords
containing URL-reserved characters therefore do not require URL encoding.

PostgreSQL uses a static local PersistentVolume on the node whose hostname is
`node-2`. Before deploying, create its backing directory on that node:

```bash
sudo install -d -o 70 -g 70 -m 700 /var/lib/observability-postgres
kubectl get node node-2
```

If the target node has another hostname, update `spec.nodeAffinity` in
`base/postgres-pv.yaml`. The PV uses the `Retain` policy; deleting the namespace
does not delete the database files from the node.

After deleting and recreating the namespace, make a retained PV available to
the newly created PVC by removing its old claim reference:

```bash
kubectl patch pv observability-db-pv-node2 --type=json \
  -p='[{"op":"remove","path":"/spec/claimRef"}]'
```

Validate and compare overlays:

```bash
kubectl kustomize deployments/overlays/dev >/tmp/observability-dev.yaml
kubectl kustomize deployments/overlays/prod >/tmp/observability-prod.yaml
kubectl diff -k deployments/overlays/dev -n advanced-observability
```
