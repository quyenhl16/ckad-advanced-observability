# Lab 3.3 - ServiceAccount and RBAC

Duration: approximately 60 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Create a ServiceAccount, namespaced Role, and RoleBinding. The Pod reads its
projected ServiceAccount token and CA certificate, then calls the Kubernetes
API to list Pods in `ckad-labs`. The response is exposed through the Pod's
Nginx ambassador.

```bash
./labs/day3/lab3.3/run.sh run
```

The Role grants only `get` and `list` on Pods. Verification also confirms that
the ServiceAccount cannot read Secrets.

The application uses only Python's standard library. It validates the API
server certificate with the mounted ServiceAccount CA, reads the rotating
token before each request, writes the PodList to the shared web directory, and
serves that directory on port `18080` for the Nginx ambassador. This avoids
depending on `curl` images that do not include an HTTP server binary.

```bash
kubectl auth can-i list pods --as=system:serviceaccount:ckad-labs:pod-reader -n ckad-labs
kubectl auth can-i get secrets --as=system:serviceaccount:ckad-labs:pod-reader -n ckad-labs
kubectl logs -n ckad-labs rbac-api-client -c app
kubectl logs -n ckad-labs rbac-api-client -c log-sidecar
./labs/day3/lab3.3/run.sh cleanup
```
