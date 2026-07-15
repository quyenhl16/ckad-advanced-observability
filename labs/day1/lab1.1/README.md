# Lab 1.1 - The 60-Second Pod

Generate a Pod imperatively, add resource requests and limits without opening
an editor, apply it, and inspect its state.

```bash
./labs/day1/lab1.1/run.sh
```

Exam-speed verification:

```bash
kubectl get pod traffic-pod-60 -n ckad-labs -o wide
kubectl get pod traffic-pod-60 -n ckad-labs --show-labels
kubectl describe pod traffic-pod-60 -n ckad-labs
kubectl logs traffic-pod-60 -n ckad-labs
```

The generated manifest is written to `/tmp/lab1.1-pod.yaml`. `pod.yaml` is the
checked-in reference result.
