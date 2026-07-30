# Lab 4.1 - ClusterIP and NodePort

Duration: approximately 45 minutes. CKAD domain: Services and Networking
(20%).

Create a two-replica backend behind a ClusterIP Service and a two-replica
frontend behind a NodePort Service. The initial backend selector is
intentionally wrong, so its Endpoint set is empty even though its Pods are
Ready.

Run the complete diagnose-and-repair workflow:

```bash
./labs/day4/lab4.1/run.sh run
```

Run each exam task separately:

```bash
./labs/day4/lab4.1/run.sh deploy
./labs/day4/lab4.1/run.sh diagnose
kubectl get pod -n ckad-labs -l lab=4.1 --show-labels
kubectl get endpoints day4-backend -n ckad-labs
./labs/day4/lab4.1/run.sh fix
./labs/day4/lab4.1/run.sh verify
```

The NodePort is allocated dynamically to avoid collisions. Inspect it with:

```bash
kubectl get service day4-frontend -n ckad-labs \
  -o jsonpath='{.spec.ports[0].nodePort}{"\n"}'
kubectl get endpointslice -n ckad-labs \
  -l kubernetes.io/service-name=day4-backend
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get service day4-frontend -n ckad-labs -o jsonpath='{.spec.ports[0].nodePort}')
curl "http://${NODE_IP}:${NODE_PORT}/health/ready"
```

Cleanup:

```bash
./labs/day4/lab4.1/run.sh cleanup
```
