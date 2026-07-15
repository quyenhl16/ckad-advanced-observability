# Lab 2.4 - Kustomize Overlay

The lab-specific base contains one cloned traffic-ingest Deployment and
Service. The overlay changes the image name/tag and replica count without
duplicating either resource.

```bash
./labs/day2/lab2.4/run.sh render
./labs/day2/lab2.4/run.sh diff
IMAGE=10.206.0.3:5000/traffic-ingest:lab-v2 ./labs/day2/lab2.4/run.sh apply
./labs/day2/lab2.4/run.sh status
./labs/day2/lab2.4/run.sh cleanup
```

Inspect `base/kustomization.yaml` and `overlays/lab/kustomization.yaml`, then
practice changing only `newTag` and `count`.
