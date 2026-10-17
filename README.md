# Containerized virt-who Agent

[![Image build](https://img.shields.io/github/actions/workflow/status/PfurtschellerP/virt-who/publish-image.yaml?branch=main&label=image%20build&logo=github)](https://github.com/PfurtschellerP/virt-who/actions/workflows/publish-image.yaml)
[![Chart validation](https://img.shields.io/github/actions/workflow/status/PfurtschellerP/virt-who/validate-chart.yaml?branch=main&label=chart%20validation&logo=helm)](https://github.com/PfurtschellerP/virt-who/actions/workflows/validate-chart.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/PfurtschellerP/virt-who/badge)](https://securityscorecards.dev/viewer/?uri=github.com/PfurtschellerP/virt-who)
[![License](https://img.shields.io/github/license/PfurtschellerP/virt-who)](https://github.com/PfurtschellerP/virt-who/blob/main/LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/pfurtschellerp/virt-who/main)](https://github.com/PfurtschellerP/virt-who/commits/main)
[![Docker](https://img.shields.io/badge/container-GHCR-2496ED?logo=docker&logoColor=white)](https://github.com/PfurtschellerP/virt-who/pkgs/container/virt-who)
[![Helm](https://img.shields.io/badge/Helm-OCI-0F1689?logo=helm&logoColor=white)](https://github.com/PfurtschellerP/virt-who/pkgs/container/virt-who)

This repository contains Dockerfiles and Helm charts for deploying the virt-who agent in a containerized environment. The virt-who agent is responsible for reporting virtual machine information to the subscription management service.

## Contents

- `docker/`: Docker compose example for deploying the virt-who container on a standalone KVM host.
- `image/`: Dockerfile and related scripts for building the virt-who container image.
- `charts/virt-who/`: Helm chart for deploying the virt-who agent on Kubernetes.

## Kubernetes deployment

The chart schedules one virt-who pod on every node with the `compute` label
key, regardless of its value. Set `computeNodeLabel` to use a different label
key. The chart creates and manages a credentials Secret from `rhsm.username`
and `rhsm.password` in the values.

```sh
helm upgrade --install virt-who ./charts/virt-who \
  --set image.repository=registry.example.com/virt-who \
  --set image.tag=1.0 \
  --set satellite.organization=YOUR_ORGANIZATION \
  --set satellite.host=satellite.example.com \
  --set rhsm.username=YOUR_REPORTER_USERNAME \
  --set rhsm.password=YOUR_REPORTER_PASSWORD
```

## Releases

Images and charts have independent release lifecycles. Versioned releases are
immutable and are published only once; historical releases are not rebuilt by
scheduled jobs.

Pushing an artifact-specific tag also creates a GitHub Release with generated
release notes and a link to the published GHCR artifact.

### Container image releases

Create an image-specific tag and push it:

```sh
git tag image-v1.32.2
git push origin image-v1.32.2
```

This publishes:

```text
ghcr.io/pfurtschellerp/virt-who:1.32.2
```

It also creates a GitHub Release named `Container image v1.32.2`.

Changes pushed to `main` publish the moving `latest` image. Production
deployments should use a version tag or, preferably, the image digest.

### Helm chart releases

Create a chart-specific tag and push it:

```sh
git tag chart-virt-who-v0.1.0
git push origin chart-virt-who-v0.1.0
```

The workflow derives the Helm chart version from the tag, so
`charts/virt-who/Chart.yaml` does not need to be edited for every release.
The chart is published to GHCR as an OCI artifact:

```sh
helm upgrade --install virt-who \
  oci://ghcr.io/pfurtschellerp/virt-who \
  --version 0.1.0
```

It also creates a GitHub Release named `Helm chart v0.1.0`.

The chart's `image.tag` defaults to `latest`. For reproducible deployments,
override it with a versioned image tag or configure the image repository and
digest in your deployment values.

## Sources

- [virt-who GitHub repository](https://github.com/candlepin/virt-who)
