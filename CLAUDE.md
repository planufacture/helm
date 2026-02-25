# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single Helm chart (`charts/planufacture/`) deploying a microservices-based Kubernetes application. The chart manages multiple microservices (UI, domain, gateway, configServer, diomacConnector), MongoDB and AxonServer StatefulSets, secrets, ingress, and CronJobs.

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
The core design pattern is a **single deployment template** (`templates/deployment.yaml`) that loops over `values.microServices` to generate one Deployment per service. The same pattern applies to `service.yaml` and `secret-mongo-micro-services.yaml`. Each microservice entry in values can declare `.service`, `.mongo`, `.rabbit`, `.axon` flags to conditionally attach environment variables and dependencies.

### Context Merging
Templates use a context-merging pattern to pass the current microservice key into shared helpers:
```
{{- $context := merge (dict "key" "service-name") $ }}
{{- include "planufacture.fullname" $context }}
```
This allows `_helpers.tpl` functions to append the service key as a suffix for unique resource naming.

### Helm Hooks
- **pre-install/pre-upgrade**: MongoDB root secret creation
- **post-install/post-upgrade**: Job that creates MongoDB user accounts per microservice
- **test**: Connection test to the UI service

### StatefulSets
- **MongoDB 8**: Replica set with keyfile auth, `gp3-xfs-backup` storage class, init container for keyfile permissions
- **AxonServer**: Event sourcing server with separate PVCs for data, events, and logs

### CronJobs
- **Diomac Connector**: Scheduled every 5 minutes within a time window (5-20 hours, Europe/Dublin)

### Environment-Specific Values
- `values/values-dev.yaml` and `values/values-staging.yaml` provide overrides per environment
- Production values are stored as a GitHub secret (`HELM_VALUES`)

## CI/CD Workflows

- **`lint-test.yaml`**: Runs `ct lint` on PRs
- **`release.yaml`**: Packages and releases chart on pushes to `main` using chart-releaser
- **`update-helm-chart.yaml`**: Triggered by `repository_dispatch` from other repos when a microservice publishes a new version. Uses `yq` to update the image tag in `values.yaml`, auto-increments the chart patch version, and creates a PR
- **`deploy-eks.yaml`**: Deploys to AWS EKS via `helm upgrade --install`

## Versioning

Chart version (currently `0.1.x`) auto-increments its patch number on each microservice update. Individual microservice image tags are in `values.yaml` under `microServices.<name>.image.tag`. The `appVersion` in Chart.yaml is fixed at `v0.0.1` and not actively tracked.

## Conventions

- All container images are in `ghcr.io/planufacture/`
- Security context: non-root user (UID 65532)
- Image pull secret: `planufacture-credentials`
- Spring Cloud Config: services use `SPRING_PROFILES_ACTIVE` and `SPRING_CLOUD_CONFIG_LABEL` for profile-based configuration
- RabbitMQ virtual host and user are set to the release namespace
- Template file naming: `config-map-*.yaml`, `secret-*.yaml`, `stateful-set-*.yaml`, `cronjob-*.yaml`, `job-*.yaml`
