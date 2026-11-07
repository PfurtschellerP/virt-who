FROM docker.io/rockylinux/rockylinux:10-minimal@sha256:bc5c1e7a2ec7f4bcef1e51c7f0ebb2d43f05409e0108cdd34f693921d0604360

# Version of the virt-who RPM installed into the image.
ARG VIRT_WHO_VERSION=1.32.1

LABEL org.opencontainers.image.title="virt-who" \
      org.opencontainers.image.description="Containerized virt-who agent reporting libvirt/KVM guests to Red Hat Satellite" \
      org.opencontainers.image.source="https://github.com/PfurtschellerP/virt-who" \
      org.opencontainers.image.licenses="GPL-2.0-or-later" \
      io.github.pfurtschellerp.virt-who.version="${VIRT_WHO_VERSION}"

# A single layer keeps the package cache out of the final image.
# subscription-manager is listed explicitly: python3-subscription-manager-rhsm
# imports the subscription_manager module without declaring a dependency on it.
# hadolint ignore=DL3041
RUN microdnf update -y --nodocs --setopt=install_weak_deps=0 \
 && microdnf install -y --nodocs --setopt=install_weak_deps=0 \
      "virt-who-${VIRT_WHO_VERSION}" \
      subscription-manager \
 && microdnf clean all \
 && rm -rf /var/cache/dnf /var/cache/yum /var/log/dnf* /var/log/hawkey.log

COPY --chmod=0755 render_config.py /usr/local/bin/render-virt-who-config
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

# virt-who has to run as root to talk to the libvirt system socket. All
# capabilities can (and should) be dropped by the container runtime.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
