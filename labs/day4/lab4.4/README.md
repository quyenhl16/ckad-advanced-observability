# Lab 4.4 - Persistent Volume Claims

Duration: approximately 45 minutes. CKAD domains: Services and Networking,
Design and Build.

Request a dynamically provisioned 1 Gi `ReadWriteOnce` volume and mount it in a
Pod whose main container uses the deployed `traffic-ingest` image. A small
BusyBox storage helper writes a known value because the production image is
distroless. Delete the Pod, recreate it with the same claim, and verify that
the value remains.

The script uses the cluster's default StorageClass:

```bash
./labs/day4/lab4.4/run.sh run
```

Set an explicit dynamic provisioner when the cluster has no default:

```bash
STORAGE_CLASS=standard ./labs/day4/lab4.4/run.sh run
```

Run the lifecycle one stage at a time:

```bash
./labs/day4/lab4.4/run.sh deploy
kubectl get pvc day4-data -n ckad-labs
./labs/day4/lab4.4/run.sh recreate
./labs/day4/lab4.4/run.sh verify
```

Deleting the Pod does not delete the PVC, so the recreated Pod mounts the same
PV. Cleanup deletes the claim; whether the provisioned volume is retained or
deleted afterward depends on the StorageClass reclaim policy.

```bash
./labs/day4/lab4.4/run.sh cleanup
```
