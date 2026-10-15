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

## Sources

- [virt-who GitHub repository](https://github.com/candlepin/virt-who)
