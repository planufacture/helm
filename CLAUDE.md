# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single Helm chart (`charts/planufacture/`) deploying a microservices-based Kubernetes application. The chart manages multiple microservices (UI, domain, gateway, configServer, diomacConnector), optional MongoDB and AxonServer StatefulSets, secrets, ingress, and CronJobs.

## Commands

### Lint
```bash
# Requires: helm, python3 (for yamllint/yamale), chart-testing CLI
ct lint --config ct.yaml
```

### Helm Template Rendering (local validation)
```bash
helm template my-release charts/planufacture/ -f values/values-dev.yaml
```

### Install/Upgrade (requires cluster access)
```bash
helm upgrade --install <release-name> charts/planufacture/ \
  -f values/values-dev.yaml \
  --namespace <namespace> \
  --timeout 10m
```

### Test
```bash
helm test <release-name> --namespace <namespace>
```

There is no Makefile or package.json. All CI automation is in GitHub Actions workflows.

## Architecture

### Multi-Service Template Pattern
The core design pattern is a **single deployment template** (`templates/deployment.yaml`) that loops over `values.microServices` to generate one Deployment per service. The same pattern applies to `service.yaml` and `secret-mongo-micro-services.yaml`. Each microservice entry in values can declare `.service`, `.mongo`, `.rabbit`, `.axon` flags to conditionally attach environment variables and dependencies. Per-service `resources` can be set with a fallback to the global `resources` default.

### Context Merging
Templates use a context-merging pattern to pass the current microservice key into shared helpers:
```
{{- $context := merge (dict "key" "service-name") $ }}
{{- include "planufacture.fullname" $context }}
```
This allows `_helpers.tpl` functions to append the service key as a suffix for unique resource naming.

### Helm Hooks
- **pre-install/pre-upgrade**: MongoDB root secret and per-microservice secrets (only when `mongo.enabled: true`)
- **post-install/post-upgrade**: Job that creates MongoDB user accounts per microservice (only when `mongo.enabled: true`)
- **test**: Connection test to the UI service

### MongoDB (Optional)
Controlled by `mongo.enabled`. When enabled, deploys a MongoDB 8 replica set StatefulSet with keyfile auth, configurable storage class (`mongo.storageClassName`, default `gp3-xfs-backup`), liveness/readiness probes, and auto-creates per-microservice database users. Image is parameterized via `mongo.image.repository`/`mongo.image.tag`.

When disabled (e.g. using MongoDB Atlas), each microservice with `.mongo` must provide `.mongo.existingSecret` and `.mongo.existingSecretKey` pointing to a pre-created Kubernetes secret containing the connection URI. The chart will fail with a clear error if `existingSecret` is missing when `mongo.enabled: false`.

### AxonServer
Event sourcing server with separate PVCs for data, events, and logs. Controlled by `axonserver.enabled`. **Note**: StatefulSet `volumeClaimTemplates` are immutable — storage sizes cannot be changed via `helm upgrade`. Resize existing PVCs with `kubectl patch pvc` instead.

### CronJobs
- **Diomac Connector**: Schedule and timezone are configurable via `microServices.diomacConnector.schedule` and `.timeZone`. The `wait-mongo` init container is only included when `mongo.enabled: true`.

### Monitoring
ServiceMonitor resources (Prometheus Operator CRD) can be created per microservice by setting `metrics.enabled: true`. Each service opts in via `metrics.enabled: true` in its values block. Default scrape path is `/actuator/prometheus` at 30s intervals. Extra labels for Prometheus discovery can be set via `metrics.serviceMonitor.labels`.

### Environment-Specific Values
- `values/` directory is gitignored — environment values are local only
- Production values are stored as a GitHub secret (`HELM_VALUES`)
- 5 GitHub environments: dearboy, demo, dev, github-pages, staging

## CI/CD Workflows

- **`lint-test.yaml`**: Runs `ct lint --check-version-increment=false` on PRs (version bumping is handled at release time)
- **`release.yaml`**: Auto-bumps chart patch version, then packages and releases chart on pushes to `main` using chart-releaser
- **`update-helm-chart.yaml`**: Triggered by `repository_dispatch` from other repos when a microservice publishes a new version. Uses `yq` to update the image tag in `values.yaml` and updates `appVersion` when the UI service is released. Creates a PR.
- **`deploy-eks.yaml`**: Deploys to AWS EKS via `helm upgrade --install`

## Versioning

Chart version (`0.1.x`) auto-increments its patch number at release time in `release.yaml`. Individual microservice image tags are in `values.yaml` under `microServices.<name>.image.tag`. The `appVersion` in Chart.yaml tracks the UI version and is auto-updated when the UI service is released.

## Conventions

- All container images are in `ghcr.io/planufacture/`
- Security context: non-root user (UID 65532) with `capabilities.drop: [ALL]` and `allowPrivilegeEscalation: false` on all containers
- Image pull secret: `planufacture-credentials`
- Spring Cloud Config: services use `SPRING_PROFILES_ACTIVE` and `SPRING_CLOUD_CONFIG_LABEL` for profile-based configuration
- RabbitMQ virtual host and user are set to the release namespace
- Template file naming: `config-map-*.yaml`, `secret-*.yaml`, `stateful-set-*.yaml`, `cronjob-*.yaml`, `job-*.yaml`
