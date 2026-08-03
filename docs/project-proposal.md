# Project proposal

## Business domain

Advanced network observability for receiving device telemetry, detecting
latency anomalies, storing alerts and managing notification subscriptions.

## Core microservices

1. `traffic-ingest`: metric validation and ingestion gateway
2. `analytics-engine`: threshold analysis and event query API
3. `alert-manager`: alert persistence, users, subscriptions and notifications
4. `observability-frontend`: operator dashboard

## Technical stack

- Go 1.24 with HTTP/JSON APIs and structured `slog` output
- PostgreSQL 17 for alert-manager-owned persistent data
- Kubernetes Deployments, StatefulSet, CronJob, Services, Ingress,
  NetworkPolicy, HPA, PVC, RBAC and namespace quotas
- Docker/Podman multi-stage builds, Kustomize overlays and Helm 3

## Repository

<https://github.com/quyenhl16/ckad-advanced-observability>
