# Lab 1.1 - The 60-Second Pod

Render and apply a four-role Pod with resource requests and limits, then
inspect the init, app, logging sidecar, and Nginx ambassador containers.

```bash
./labs/day1/lab1.1/run.sh
```

Exam-speed verification:

```bash
kubectl get pod traffic-pod-60 -n ckad-labs -o wide
kubectl get pod traffic-pod-60 -n ckad-labs --show-labels
kubectl describe pod traffic-pod-60 -n ckad-labs
kubectl logs traffic-pod-60 -n ckad-labs -c app
```

The image-resolved manifest is written to `/tmp/lab1.1-pod.yaml`; `pod.yaml`
is the checked-in reference.
