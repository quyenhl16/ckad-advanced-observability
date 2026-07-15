# Lab 2.3 - Scale and HPA

This lab uses a cloned Deployment with CPU requests so HPA utilization can be
calculated.

```bash
./labs/day2/lab2.3/run.sh deploy
./labs/day2/lab2.3/run.sh scale
./labs/day2/lab2.3/run.sh hpa
./labs/day2/lab2.3/run.sh status
```

If HPA shows `<unknown>/50%`, install or repair Metrics Server. Once HPA is
active, it owns the replica count and can override a manual scale operation.
