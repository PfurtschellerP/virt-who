#!/usr/bin/env bash

set -euo pipefail

config_path="${VIRT_WHO_CONFIG_OUT:-/run/virt-who/libvirt.conf}"
python3 /usr/local/bin/render-virt-who-config "$config_path"

args=(--config "$config_path" --interval "${VIRTWHO_INTERVAL_SECONDS:-60}")
case "${VIRTWHO_DEBUG:-0}" in
  1|true|TRUE|yes|YES)
    args+=(--debug)
    ;;
  0|false|FALSE|no|NO)
    ;;
  *)
    echo "VIRTWHO_DEBUG must be a boolean value" >&2
    exit 2
    ;;
esac

exec /usr/bin/virt-who "${args[@]}" "$@" &

tail -f /var/log/rhsm/rhsm.log