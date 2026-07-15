# Lab 2.2 - Blue/Green Switch

Two cloned traffic-ingest Deployments run simultaneously. One Service selects
either `version: blue` or `version: green`.

```bash
./labs/day2/lab2.2/run.sh deploy
./labs/day2/lab2.2/run.sh status
./labs/day2/lab2.2/run.sh green
./labs/day2/lab2.2/run.sh blue
```

Optionally use different images:

```bash
BLUE_IMAGE=10.206.0.3:5000/traffic-ingest:v1 \
GREEN_IMAGE=10.206.0.3:5000/traffic-ingest:v2 \
./labs/day2/lab2.2/run.sh deploy
```

Test the selected color through a local port-forward:

```bash
kubectl port-forward -n ckad-labs service/traffic-ingest-bg 18080:8080
curl http://127.0.0.1:18080/health/ready
```
