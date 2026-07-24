# Lab 1.4 - Label and Annotation Drill

The script applies five four-role Pods, queries them with selectors, changes one
label with `--overwrite`, and adds an annotation.

```bash
./labs/day1/lab1.4/run.sh
```

Additional selector drills:

```bash
kubectl get pods -n ckad-labs -l 'index in (1,3,5)'
kubectl get pods -n ckad-labs -l 'environment!=production'
kubectl get pods -n ckad-labs -l app=label-client --show-labels
```

Cleanup:

```bash
./labs/day1/lab1.4/run.sh cleanup
```
