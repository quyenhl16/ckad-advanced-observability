# Lab 1.2 - Init and Sidecar Pattern

This Pod initializes a shared log file, runs the analytics application, and
tails the file from a sidecar. All three containers share one `emptyDir`.

```bash
./labs/day1/lab1.2/run.sh
```

In one terminal:

```bash
kubectl logs -n ckad-labs analytics-pattern -c log-collector -f
```

In another terminal, expose the analytics Pod and submit a normal metric:

```bash
kubectl port-forward -n ckad-labs pod/analytics-pattern 18081:8081
curl -X POST http://127.0.0.1:18081/internal/v1/analyze \
  -H 'Content-Type: application/json' \
  -d '{"device_type":"router","device_id":"lab-sidecar","cpu_usage_percent":30,"memory_usage_percent":40,"temperature_celsius":45,"latency_ms":80,"packet_loss_percent":0}'
```
