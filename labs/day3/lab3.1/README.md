# Lab 3.1 - ConfigMap and Secret Injection

Duration: approximately 45 minutes. CKAD domain: Application Environment,
Configuration & Security (25%).

Create a Secret from a file and a ConfigMap from a literal, then inject both
into one four-role Pod. The Secret becomes `API_KEY`; the ConfigMap is mounted
at `/config`.

```bash
./labs/day3/lab3.1/run.sh run
```

Inspect each injection mechanism without printing the secret value:

```bash
kubectl get pod config-injection -n ckad-labs -o yaml
kubectl exec -n ckad-labs config-injection -c app -- sh -c 'test -n "$API_KEY" && echo secret-loaded'
kubectl exec -n ckad-labs config-injection -c app -- cat /config/APP_MODE
```

Cleanup:

```bash
./labs/day3/lab3.1/run.sh cleanup
```
