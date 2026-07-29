# Lab 3.1 - ConfigMap and Secret Injection

Duration: approximately 45 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Define a Secret and a ConfigMap as declarative manifests, then inject both into
an application Pod. The Secret becomes `API_KEY`; the ConfigMap becomes
`APP_MODE` and is also mounted at `/config`. The `app` container uses the
deployed `traffic-ingest` service image.

```bash
./labs/day3/lab3.1/run.sh run
```

Inspect each injection mechanism without printing the secret value:

```bash
kubectl get pod config-injection -n ckad-labs -o yaml
kubectl get configmap lab3-1-config -n ckad-labs -o yaml
kubectl get secret lab3-1-secret -n ckad-labs -o jsonpath='{.metadata.name}{"\n"}'
```

Cleanup:

```bash
./labs/day3/lab3.1/run.sh cleanup
```
