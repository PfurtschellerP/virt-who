#!/usr/bin/env python3
"""Render the virt-who libvirt configuration from environment variables.

Usage: render-virt-who-config [OUTPUT]

The output path defaults to $VIRT_WHO_CONFIG_OUT or /run/virt-who/libvirt.conf.
Secrets can be passed directly (RHSM_USERNAME, RHSM_PASSWORD) or read from
files (RHSM_USERNAME_FILE, RHSM_PASSWORD_FILE), e.g. mounted Kubernetes or
Docker secrets.
"""

import os
import sys
import tempfile
from pathlib import Path

DEFAULT_OUTPUT = "/run/virt-who/libvirt.conf"


def env(name: str, default: str | None = None, *, required: bool = False) -> str:
    """Return an environment variable, optionally loaded from ``<name>_FILE``."""
    file_path = os.environ.get(f"{name}_FILE")
    if file_path:
        try:
            value = Path(file_path).read_text(encoding="utf-8").rstrip("\r\n")
        except OSError as exc:
            raise ValueError(f"cannot read {name}_FILE ({file_path}): {exc.strerror}") from exc
    else:
        value = os.environ.get(name, "")

    if value == "":
        if required:
            raise ValueError(f"required environment variable {name} is not set")
        if default is None:
            return ""
        return default
    return value


def ini_value(name: str, value: str) -> str:
    """Validate a value for virt-who's INI parser and escape interpolation."""
    if "\n" in value or "\r" in value:
        raise ValueError(f"{name} must not contain line breaks")
    if value != value.strip():
        raise ValueError(f"{name} must not have leading or trailing whitespace")
    # virt-who strips one pair of matching surrounding quotes from values.
    if (
        len(value) >= 2
        and value[0] in ("'", '"')
        and value[-1] == value[0]
        and value.count(value[0]) == 2
    ):
        raise ValueError(
            f"{name} cannot start and end with the same quote; "
            "use a generated rhsm_encrypted_password with its matching virt-who key"
        )
    return value.replace("%", "%%")


def port(name: str, default: str) -> str:
    raw = env(name, default)
    try:
        value = int(raw)
    except ValueError as exc:
        raise ValueError(f"{name} must be an integer, got {raw!r}") from exc
    if not 1 <= value <= 65535:
        raise ValueError(f"{name} must be between 1 and 65535, got {value}")
    return str(value)


def render() -> str:
    values = {
        "owner": env("SATELLITE_ORG", required=True),
        "hypervisor_id": env("HYPERVISOR_ID", "hostname"),
        "server": env("LIBVIRT_SERVER", "qemu+unix:///system"),
        "rhsm_hostname": env("SATELLITE_HOST", required=True),
        "rhsm_port": port("SATELLITE_PORT", "443"),
        "rhsm_prefix": env("SATELLITE_PREFIX", "/rhsm"),
        "rhsm_username": env("RHSM_USERNAME", required=True),
        "rhsm_password": env("RHSM_PASSWORD", required=True),
    }
    lines = ["[libvirt]", "type=libvirt"]
    lines += [f"{key}={ini_value(key, value)}" for key, value in values.items()]
    return "\n".join(lines) + "\n"


def write_private(path: Path, content: str) -> None:
    """Atomically write ``content`` to ``path`` with 0600 permissions."""
    os.umask(0o077)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def main() -> int:
    output = Path(
        sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VIRT_WHO_CONFIG_OUT", DEFAULT_OUTPUT)
    )
    try:
        write_private(output, render())
    except (OSError, ValueError) as exc:
        print(f"virt-who config generation failed: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
