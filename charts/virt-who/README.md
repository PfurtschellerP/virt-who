# virt-who Helm chart

Deploys the [virt-who](https://github.com/candlepin/virt-who) agent as a
DaemonSet on Kubernetes nodes that act as KVM/libvirt hypervisors (for example
KubeVirt or bare-metal libvirt nodes). Each pod reads the local libvirt socket
and reports the node's guests to Red Hat Satellite.

## Install

```sh
helm upgrade --install virt-who oci://ghcr.io/pfurtschellerp/charts/virt-who \
  --namespace virt-who --create-namespace \
  --set satellite.organization=MY_ORG \
  --set satellite.host=satellite.example.com \
  --set rhsm.username=virt-who-reporter \
  --set rhsm.password='s3cr3t'
```

Label the hypervisor nodes (only the label key matters):

```sh
kubectl label node <node> compute=true
```

### Using an existing Secret

```sh
kubectl -n virt-who create secret generic virt-who-credentials \
  --from-literal=RHSM_USERNAME=virt-who-reporter \
  --from-literal=RHSM_PASSWORD='s3cr3t'

helm upgrade --install virt-who oci://ghcr.io/pfurtschellerp/charts/virt-who \
  --namespace virt-who \
  --set satellite.organization=MY_ORG \
  --set satellite.host=satellite.example.com \
  --set rhsm.existingSecret=virt-who-credentials
```

### SELinux

On SELinux-enforcing nodes the default `container_t` domain cannot connect to
the libvirt socket. Run the pod with a domain that can:

```yaml
podSecurityContext:
  seLinuxOptions:
    type: spc_t
```

## Values

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `ghcr.io/pfurtschellerp/virt-who` | Container image repository. |
| `image.tag` | `""` (chart `appVersion`) | Image tag. |
| `image.digest` | `""` | Image digest (`sha256:…`); takes precedence over the tag. |
| `image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `imagePullSecrets` | `[]` | Pull secrets for private registries. |
| `computeNodeLabel` | `compute` | Node label key required for scheduling. `""` disables the node affinity. |
| `satellite.organization` | `""` | **Required.** Satellite organization label. |
| `satellite.host` | `""` | **Required.** Satellite or Capsule host name. |
| `satellite.port` | `443` | Satellite port. |
| `satellite.prefix` | `/rhsm` | Candlepin API prefix. |
| `rhsm.existingSecret` | `""` | Existing Secret with the reporter credentials. |
| `rhsm.usernameKey` / `rhsm.passwordKey` | `RHSM_USERNAME` / `RHSM_PASSWORD` | Keys inside the Secret. |
| `rhsm.username` / `rhsm.password` | `""` | **Required** unless `rhsm.existingSecret` is set. |
| `virtWho.hypervisorId` | `hostname` | `hostname`, `uuid` or `hwuuid`. |
| `virtWho.libvirtServer` | `qemu+unix:///system` | libvirt connection URI. |
| `virtWho.intervalSeconds` | `60` | Reporting interval (minimum `60`). |
| `virtWho.debug` | `false` | Enable debug logging. |
| `libvirtSocketDir` | `/run/libvirt` | Host directory containing the libvirt sockets. |
| `extraEnv` | `[]` | Additional environment variables (e.g. `HTTPS_PROXY`). |
| `podAnnotations` / `podLabels` | `{}` | Extra pod metadata. |
| `priorityClassName` | `""` | Pod priority class. |
| `terminationGracePeriodSeconds` | `30` | Grace period on shutdown. |
| `updateStrategy` | `RollingUpdate`, `maxUnavailable: 1` | DaemonSet update strategy. |
| `podSecurityContext` | `seccompProfile: RuntimeDefault` | Pod security context. |
| `containerSecurityContext` | root, read-only root FS, no capabilities | Container security context. |
| `resources` | `10m`/`64Mi` requests, `256Mi` limit | Container resources. |
| `nodeSelector` / `tolerations` | `{}` / `[]` | Additional scheduling constraints. |
| `podAffinity` / `podAntiAffinity` | `{}` | Pod (anti-)affinity rules. |
| `volumes` / `volumeMounts` | `[]` | Extra volumes, e.g. a custom Satellite CA. |

The values are validated by [`values.schema.json`](values.schema.json).
