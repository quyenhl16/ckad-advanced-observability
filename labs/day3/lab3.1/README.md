# Lab 3.1 - ConfigMap and Secret Injection

Duration: approximately 45 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Create a Secret from a runtime environment value and apply a declarative
ConfigMap, then inject both into an application Pod. No Secret value is stored
in Git. The Secret becomes `API_KEY`; the ConfigMap becomes
`APP_MODE` and is also mounted at `/config`. The `app` container uses the
deployed `traffic-ingest` service image.

```bash
LAB_API_KEY='use-a-temporary-lab-value' ./labs/day3/lab3.1/run.sh run
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
