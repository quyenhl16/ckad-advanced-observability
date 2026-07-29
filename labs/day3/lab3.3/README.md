# Lab 3.3 - ServiceAccount and RBAC

Duration: approximately 60 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Create a ServiceAccount, namespaced Role, and RoleBinding. The Pod reads its
projected ServiceAccount token and CA certificate, then calls the Kubernetes
API to list Pods in `ckad-labs`. The main `app` container uses the deployed
`traffic-ingest` service image and is exposed through the Nginx ambassador.

```bash
./labs/day3/lab3.3/run.sh run
```

The Role grants only `get` and `list` on Pods. Verification also confirms that
the ServiceAccount cannot read Secrets.

The `api-client` helper uses only Python's standard library. It validates the API
server certificate with the mounted ServiceAccount CA, reads the rotating
token before each request, and writes the response to `/api-data/pods.json`
for verification.

```bash
kubectl auth can-i list pods --as=system:serviceaccount:ckad-labs:pod-reader -n ckad-labs
kubectl auth can-i get secrets --as=system:serviceaccount:ckad-labs:pod-reader -n ckad-labs
kubectl logs -n ckad-labs rbac-api-client -c api-client
kubectl logs -n ckad-labs rbac-api-client -c log-sidecar
./labs/day3/lab3.3/run.sh cleanup
```
