#!/usr/bin/env python3

import os
import sys
from pathlib import Path


def required_env(name: str) -> str:
    value = os.environ.get(name)
    if value is None or value == "":
        raise ValueError(f"Required environment variable {name} is not set")
    return value


def ini_value(name: str, value: str) -> str:
    if "\n" in value or "\r" in value:
        raise ValueError(f"{name} must not contain line breaks")
    if value != value.strip():
        raise ValueError(f"{name} must not have leading or trailing whitespace")
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


def main() -> None:
    output = Path(
        sys.argv[1]
        if len(sys.argv) > 1
        else os.environ.get("VIRT_WHO_CONFIG_OUT", "/run/virt-who/libvirt.conf")
    )
    password_file = os.environ.get("RHSM_PASSWORD_FILE")
    if password_file:
        password = Path(password_file).read_text(encoding="utf-8").rstrip("\r\n")
    else:
        password = required_env("RHSM_PASSWORD")

    try:
        port = int(os.environ.get("SATELLITE_PORT", "443"))
    except ValueError as exc:
        raise ValueError("SATELLITE_PORT must be an integer") from exc

    values = {
        "owner": required_env("SATELLITE_ORG"),
        "hypervisor_id": os.environ.get("HYPERVISOR_ID", "hostname"),
        "server": os.environ.get("LIBVIRT_SERVER", "qemu+unix:///system"),
        "rhsm_hostname": required_env("SATELLITE_HOST"),
        "rhsm_port": str(port),
        "rhsm_username": required_env("RHSM_USERNAME"),
        "rhsm_password": password,
        "rhsm_prefix": os.environ.get("SATELLITE_PREFIX", "/rhsm"),
    }
    rendered = [
        "[libvirt]",
        "type=libvirt",
        *(f"{name}={ini_value(name, value)}" for name, value in values.items()),
        "",
    ]

    output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.umask(0o077)
    output.write_text("\n".join(rendered), encoding="utf-8")
    output.chmod(0o600)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as exc:
        print(f"virt-who config generation failed: {exc}", file=sys.stderr)
        sys.exit(2)
