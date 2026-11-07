#!/usr/bin/env bash
#
# Container entrypoint: renders the virt-who libvirt configuration from
# environment variables and runs virt-who in the foreground.

set -euo pipefail

die() {
  echo "entrypoint: $*" >&2
  exit 2
}

config_path="${VIRT_WHO_CONFIG_OUT:-/run/virt-who/libvirt.conf}"
interval="${VIRTWHO_INTERVAL_SECONDS:-60}"

[[ "$interval" =~ ^[0-9]+$ ]] || die "VIRTWHO_INTERVAL_SECONDS must be a positive integer"

args=(--config "$config_path" --interval "$interval")
case "${VIRTWHO_DEBUG:-0}" in
  1 | true | TRUE | True | yes | YES | on | ON) args+=(--debug) ;;
  0 | false | FALSE | False | no | NO | off | OFF | "") ;;
  *) die "VIRTWHO_DEBUG must be a boolean value" ;;
esac

/usr/local/bin/render-virt-who-config "$config_path"

# virt-who assumes it runs under systemd when its parent PID is 1 and then
# logs to the journal instead of stderr. Keep its parent PID != 1 so that
# logs always reach the container runtime:
#
#  * We are PID 1 (plain `docker run`, Kubernetes): exec virt-who so it
#    becomes PID 1 itself (parent PID 0) and receives signals directly.
#  * We run below an init process (`docker run --init`, tini, catatonit):
#    stay in the foreground as virt-who's parent and forward signals.
if [[ $$ -eq 1 ]]; then
  exec /usr/bin/virt-who "${args[@]}" "$@"
fi

/usr/bin/virt-who "${args[@]}" "$@" &
child=$!

# shellcheck disable=SC2329 # invoked via trap
forward() {
  kill -s "$1" "$child" 2>/dev/null || true
}
trap 'forward TERM' TERM
trap 'forward INT' INT
trap 'forward HUP' HUP

# `wait` returns early when a trapped signal arrives; keep waiting until the
# child has actually exited and propagate its exit status.
status=0
while :; do
  wait "$child" && status=0 || status=$?
  kill -0 "$child" 2>/dev/null || break
done
exit "$status"
