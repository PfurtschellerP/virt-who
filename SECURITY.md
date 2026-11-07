# Security policy

## Reporting a vulnerability

Please do not report security vulnerabilities in public issues.

Use [GitHub's private vulnerability reporting](https://github.com/PfurtschellerP/virt-who/security/advisories/new)
for this repository. Include the affected image or chart version, a
description of the impact and steps to reproduce the issue.

Please avoid including credentials, tokens, or other sensitive data in a
report.

## Supported versions

Only the latest published image and Helm chart versions are maintained.
Released versions are immutable and are not rebuilt; fixes, including base
image updates, ship in a new release.

## Verifying artifacts

Released images and charts are signed with the key in [`cosign.pub`](cosign.pub):

```sh
cosign verify --key cosign.pub ghcr.io/pfurtschellerp/virt-who:<version>
cosign verify --key cosign.pub ghcr.io/pfurtschellerp/charts/virt-who:<version>
```

Each GitHub release also carries a signed `virt-who-<image|chart>-<version>.json`
manifest that records the published digest and source commit:

```sh
cosign verify-blob --key cosign.pub \
  --signature virt-who-image-<version>.json.sig virt-who-image-<version>.json
```
