# Containerized virt-who Agent

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

The chart's `image.tag` defaults to `latest`. For reproducible deployments,
override it with a versioned image tag or configure the image repository and
digest in your deployment values.

## Sources

- [virt-who GitHub repository](https://github.com/candlepin/virt-who)
