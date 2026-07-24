# Lab 1.2 - Init and Sidecar Pattern

This Pod renders proxy configuration in an init container, runs analytics on
an internal port, tails shared application and proxy logs from a sidecar, and
exposes the Pod through an Nginx ambassador.

```bash
./labs/day1/lab1.2/run.sh
```

In one terminal:

```bash
kubectl logs -n ckad-labs analytics-pattern -c log-sidecar -f
```

In another terminal, expose the analytics Pod and submit a normal metric:

```bash
kubectl port-forward -n ckad-labs pod/analytics-pattern 18081:8081
curl -X POST http://127.0.0.1:18081/internal/v1/analyze \
  -H 'Content-Type: application/json' \
  -d '{"device_type":"router","device_id":"lab-sidecar","cpu_usage_percent":30,"memory_usage_percent":40,"temperature_celsius":45,"latency_ms":80,"packet_loss_percent":0}'
```

Cleanup:

```bash
./labs/day1/lab1.2/run.sh cleanup
```
