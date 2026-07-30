# Lab 4.2 - Ingress Routing

Duration: approximately 60 minutes. CKAD domain: Services and Networking
(20%).

Route requests for one host through an NGINX Ingress controller:

- `/` goes to the frontend Service.
- `/api/...` goes to the backend Service after removing the `/api` prefix.

Prerequisite: an NGINX Ingress controller and its `IngressClass` must already
exist in the cluster. Run the complete lab with the default class `nginx`:

```bash
./labs/day4/lab4.2/run.sh run
```

Use a different class or explicitly identify the controller Service when
automatic discovery is not suitable:

```bash
INGRESS_CLASS=nginx \
INGRESS_CONTROLLER_SERVICE=ingress-nginx/ingress-nginx-controller \
./labs/day4/lab4.2/run.sh run
```

The verification creates short-lived in-cluster probe Pods and sends requests
to the ingress-controller endpoint with `Host: day4.local`. You can provide an
endpoint directly with `INGRESS_ENDPOINT=host:port`.

Inspect the rules:

```bash
kubectl get ingress -n ckad-labs -l lab=4.2
kubectl describe ingress day4-frontend day4-backend -n ckad-labs
```

Cleanup:

```bash
./labs/day4/lab4.2/run.sh cleanup
```
