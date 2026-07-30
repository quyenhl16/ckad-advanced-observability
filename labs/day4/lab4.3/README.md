# Lab 4.3 - NetworkPolicy Isolation

Duration: approximately 45 minutes. CKAD domain: Services and Networking
(20%).

Start with an unrestricted frontend client, intruder client, and HTTP backend.
Then apply policies that:

- Allow backend ingress only from Pods labeled `role: frontend` on TCP 8080.
- Select the backend for egress isolation and allow no destinations, which
  denies internet egress including `0.0.0.0/0`.

Run the complete before-and-after workflow:

```bash
./labs/day4/lab4.3/run.sh run
```

Run the stages independently:

```bash
./labs/day4/lab4.3/run.sh deploy
./labs/day4/lab4.3/run.sh baseline
./labs/day4/lab4.3/run.sh isolate
./labs/day4/lab4.3/run.sh verify
```

Kubernetes NetworkPolicy is allow-list based: there is no explicit deny rule.
An Egress policy with `egress: []` denies all backend egress. The verification
expects the frontend request to succeed, the intruder request to time out, and
an HTTP request from the backend to `1.1.1.1` to fail.

The cluster CNI must enforce NetworkPolicy. A non-enforcing CNI causes the
negative tests to fail intentionally.

Cleanup:

```bash
./labs/day4/lab4.3/run.sh cleanup
```
