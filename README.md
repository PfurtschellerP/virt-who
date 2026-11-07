<div align="center">

# virt-who for containers

**Run the [virt-who](https://github.com/candlepin/virt-who) agent as a container or Kubernetes DaemonSet and report KVM/libvirt guests to Red Hat Satellite.**

[![CI](https://img.shields.io/github/actions/workflow/status/PfurtschellerP/virt-who/ci.yaml?branch=main&label=CI&logo=github)](https://github.com/PfurtschellerP/virt-who/actions/workflows/ci.yaml)
[![Image build](https://img.shields.io/github/actions/workflow/status/PfurtschellerP/virt-who/publish-image.yaml?branch=main&label=image&logo=docker&logoColor=white)](https://github.com/PfurtschellerP/virt-who/actions/workflows/publish-image.yaml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/PfurtschellerP/virt-who/badge)](https://securityscorecards.dev/viewer/?uri=github.com/PfurtschellerP/virt-who)
[![Image release](https://img.shields.io/github/v/tag/PfurtschellerP/virt-who?filter=image-v*&label=image&color=2496ED)](https://github.com/PfurtschellerP/virt-who/pkgs/container/virt-who)
[![Chart release](https://img.shields.io/github/v/tag/PfurtschellerP/virt-who?filter=chart-v*&label=chart&color=0F1689&logo=helm)](https://github.com/PfurtschellerP/virt-who/pkgs/container/charts%2Fvirt-who)
[![License](https://img.shields.io/github/license/PfurtschellerP/virt-who)](LICENSE)

</div>

---

virt-who reads the guests running on a hypervisor and reports the
host-to-guest mapping to Satellite, so that virtual data center (VDC)
subscriptions can be applied to the guests. This project packages virt-who in
a minimal, hardened container image and provides a Helm chart to run it on
every hypervisor node of a Kubernetes cluster.

## Features

- **Minimal image** based on Rocky Linux 10 minimal with a pinned virt-who version
- **Configured through environment variables**, no config files to mount
- **Hardened by default**: read-only root filesystem, no Linux capabilities,
  `no-new-privileges`, RuntimeDefault seccomp profile
- **Helm chart** deploying a DaemonSet onto labelled hypervisor nodes, with
  support for existing Secrets, image digests and a validated values schema
- **Supply-chain security**: images and charts are signed with Cosign, images
  ship with SBOM and SLSA provenance attestations, all actions are pinned

## How it works

```text
┌──────────── hypervisor node ────────────┐
│                                         │
│  libvirtd ── /run/libvirt/libvirt-sock  │
│                     │  (read-only)      │         ┌───────────────┐
│             ┌───────┴───────┐           │  HTTPS  │ Red Hat       │
│             │   virt-who    │ ──────────┼────────▶│ Satellite     │
│             │   container   │           │         │ (Candlepin)   │
│             └───────────────┘           │         └───────────────┘
└─────────────────────────────────────────┘
```

On start the container renders a virt-who `libvirt` configuration from its
environment, then runs virt-who in the foreground. virt-who connects to the
host's libvirt socket and reports to Satellite every
`VIRTWHO_INTERVAL_SECONDS`. Logs go to stdout.

## Quick start

### Kubernetes (Helm)

```sh
helm upgrade --install virt-who oci://ghcr.io/pfurtschellerp/charts/virt-who \
  --namespace virt-who --create-namespace \
  --set satellite.organization=MY_ORG \
  --set satellite.host=satellite.example.com \
  --set rhsm.username=virt-who-reporter \
  --set rhsm.password='s3cr3t'

# Schedule virt-who on the hypervisor nodes (only the label key matters).
kubectl label node <node> compute=true
```

See the [chart README](charts/virt-who/README.md) for all values, existing
Secrets and SELinux settings.

### Docker / Podman Compose

```sh
cd docker
cp .env.example .env   # fill in your Satellite settings
docker compose up -d   # or: podman compose up -d
```

### Plain container

```sh
docker run -d --name virt-who --restart unless-stopped \
  --read-only --tmpfs /run --tmpfs /tmp --tmpfs /var/log/rhsm \
  --cap-drop ALL --security-opt no-new-privileges --security-opt label=disable \
  -v /run/libvirt:/run/libvirt:ro \
  -e SATELLITE_ORG=MY_ORG \
  -e SATELLITE_HOST=satellite.example.com \
  -e RHSM_USERNAME=virt-who-reporter \
  -e RHSM_PASSWORD='s3cr3t' \
  ghcr.io/pfurtschellerp/virt-who:latest
```

> [!NOTE]
> On SELinux-enforcing hosts (RHEL, Rocky, Alma, Fedora) the default container
> label is not allowed to connect to the libvirt socket. Use
> `--security-opt label=disable` (Docker/Podman) or
> `seLinuxOptions.type: spc_t` (Kubernetes).

## Configuration

| Variable | Default | Description |
| --- | --- | --- |
| `SATELLITE_ORG` | — | **Required.** Organization label the hypervisor is reported to. |
| `SATELLITE_HOST` | — | **Required.** Satellite or Capsule host name. |
| `SATELLITE_PORT` | `443` | Satellite port. |
| `SATELLITE_PREFIX` | `/rhsm` | Candlepin API prefix. |
| `RHSM_USERNAME` | — | **Required.** Satellite user reporting virt-who data. |
| `RHSM_PASSWORD` | — | **Required.** Password of that user. |
| `RHSM_USERNAME_FILE`, `RHSM_PASSWORD_FILE` | — | Read the credentials from files (e.g. mounted secrets) instead. |
| `HYPERVISOR_ID` | `hostname` | Hypervisor identifier: `hostname`, `uuid` or `hwuuid`. |
| `LIBVIRT_SERVER` | `qemu+unix:///system` | libvirt connection URI. |
| `VIRTWHO_INTERVAL_SECONDS` | `60` | Reporting interval in seconds (virt-who enforces at least 60). |
| `VIRTWHO_DEBUG` | `0` | Set to `1`/`true` for debug logging. |

Additional arguments passed to the container are forwarded to virt-who, e.g.
`--print` to print the detected guests once and exit.

## Images and charts

| Artifact | Location | Tags |
| --- | --- | --- |
| Container image | `ghcr.io/pfurtschellerp/virt-who` | `X.Y.Z`, `X.Y`, `latest` (main), `sha-<commit>` (main) |
| Helm chart | `oci://ghcr.io/pfurtschellerp/charts/virt-who` | `X.Y.Z` |

Versioned releases are immutable. For production, pin a version or, better,
a digest (`image.digest` in the chart).

Releases are signed with the key in [`cosign.pub`](cosign.pub):

```sh
cosign verify --key cosign.pub ghcr.io/pfurtschellerp/virt-who:<version>
cosign verify --key cosign.pub ghcr.io/pfurtschellerp/charts/virt-who:<version>
```

## Repository layout

```text
.
├── image/            Container image (Dockerfile, entrypoint, config renderer)
├── charts/virt-who/  Helm chart
├── docker/           Docker/Podman Compose example
├── scripts/          Release tooling
└── justfile          Development and release tasks
```

## Development

Requirements: [just](https://github.com/casey/just), [Helm](https://helm.sh)
and Podman or Docker. Linters run in pinned containers, so nothing else needs
to be installed.

```sh
just                 # list all recipes
just check           # run all linters and chart tests (same as CI)
just lint            # actionlint, shellcheck, hadolint, ruff
just chart-test      # helm lint, render, kubeconform and negative tests
just image-build     # build the image locally
just image-test      # smoke-test an image (no libvirt or Satellite needed)
```

## Releasing

The image and the chart are versioned independently with
[SemVer](https://semver.org) and released by pushing a tag. CI then builds,
tests, signs and publishes the artifact, and creates a GitHub Release with
generated notes.

| Tag | Publishes |
| --- | --- |
| `image-v<version>` | `ghcr.io/pfurtschellerp/virt-who:<version>` |
| `chart-v<version>` | `oci://ghcr.io/pfurtschellerp/charts/virt-who` version `<version>` |

Use the release helper instead of tagging by hand. It checks that you are on
an up-to-date, clean `main`, that CI passed for the commit, that the version
is valid and newer than the last release, and shows the changes before it
pushes the tag:

```sh
just status                       # latest releases and unreleased changes

just release-image minor          # 1. release a new image (major|minor|patch|X.Y.Z)
just bump-app-version             # 2. open a PR pointing the chart at that image, merge it
just release-chart patch          # 3. release the chart

just release-chart 1.0.0-rc.1 --dry-run   # check everything without changing anything
```

The chart version is taken from the tag, so `Chart.yaml` only has to change
when the default image (`appVersion`) changes, which `just bump-app-version`
does through a pull request because `main` is protected.

## Security

Please report vulnerabilities privately, see [SECURITY.md](SECURITY.md).

## License

[GPL-2.0](LICENSE), the same license as virt-who itself.
