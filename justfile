# Task runner for the virt-who image and Helm chart. Run `just` to list recipes.
#
# Linters run in pinned containers, so only just, helm and podman or docker
# are needed locally. Set CONTAINER_ENGINE to force podman or docker.

set shell := ["bash", "-euo", "pipefail", "-c"]

container := env("CONTAINER_ENGINE", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)
# label=disable avoids relabelling the checkout on SELinux hosts.
run := container + " run --rm --security-opt label=disable -v " + quote(justfile_directory()) + ":/src:ro -w /src"

chart := "charts/virt-who"
dev_image := "localhost/virt-who:dev"

actionlint := "docker.io/rhysd/actionlint:1.7.12@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667"
hadolint := "docker.io/hadolint/hadolint:v2.15.1@sha256:32dac94127fd60b7b7e3fbfc65e1383b9b5e25c9bfd7b8536de7a539fe68a12d"
shellcheck := "docker.io/koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d"
ruff := "ghcr.io/astral-sh/ruff:0.17.4@sha256:c4b7e7a87e4b07d66b569dd2e6b2ce5a25e38be91dd664dc49b9882be27acd9b"
kubeconform := "ghcr.io/yannh/kubeconform:v0.8.0@sha256:faffaf43f95aa6425306e1ab8d6fcad72acb9049158f38e574c085ea1ec0f64e"
python := "docker.io/library/python:3.12-slim@sha256:4840d514c583a4d3d8cad3940e68dee6f0f6f3635c12fcd0a3d74c21a5b93a54"

# List available recipes
[private]
default:
    @just --list --unsorted

# Run all linters and tests
check: lint test chart-test

# Lint workflows, shell scripts, the Dockerfile and Python code
lint: lint-actions lint-shell lint-dockerfile lint-python

# Lint GitHub Actions workflows
lint-actions:
    {{ run }} {{ actionlint }} -color

# Lint shell scripts
lint-shell:
    {{ run }} {{ shellcheck }} --severity=style image/entrypoint.sh scripts/release.sh

# Lint the Dockerfile
lint-dockerfile:
    {{ run }} --entrypoint /bin/hadolint {{ hadolint }} image/Dockerfile

# Lint and format-check Python code
lint-python:
    {{ run }} {{ ruff }} check --no-cache image/ tests/
    {{ run }} {{ ruff }} format --no-cache --check --diff image/ tests/

# Format Python code in place
fmt:
    {{ container }} run --rm --security-opt label=disable -v {{ quote(justfile_directory()) }}:/src -w /src {{ ruff }} format --no-cache image/ tests/

# Run the Python unit and property-based (fuzz) tests
test:
    {{ container }} run --rm --security-opt label=disable -v {{ quote(justfile_directory()) }}:/src:ro -w /src \
      -e PYTHONDONTWRITEBYTECODE=1 {{ python }} sh -euc \
      'pip install --quiet --disable-pip-version-check --root-user-action=ignore --require-hashes -r tests/requirements.txt \
       && python -m pytest -p no:cacheprovider tests'

# Lint the Helm chart
chart-lint:
    helm lint --strict {{ chart }} -f {{ chart }}/ci/default-values.yaml
    helm lint --strict {{ chart }} -f {{ chart }}/ci/full-values.yaml

# Render the Helm chart (pass extra helm arguments, e.g. --set key=value)
chart-template *args:
    helm template virt-who {{ chart }} -f {{ chart }}/ci/default-values.yaml {{ args }}

# Lint, render and validate the Helm chart against the Kubernetes schemas
chart-test: chart-lint
    #!/usr/bin/env bash
    set -euo pipefail
    for values in {{ chart }}/ci/*-values.yaml; do
      echo "==> kubeconform: ${values}"
      helm template virt-who {{ chart }} -f "$values" \
        | {{ container }} run --rm -i {{ kubeconform }} -strict -summary -
    done

    expect_failure() {
      local description="$1" pattern="$2"; shift 2
      local output
      if output="$(helm template virt-who {{ chart }} "$@" 2>&1)"; then
        echo "FAIL: rendering should fail: ${description}" >&2
        exit 1
      fi
      grep -q -- "$pattern" <<<"$output" || {
        echo "FAIL: unexpected error for ${description}:" >&2
        echo "$output" >&2
        exit 1
      }
      echo "ok: rejects ${description}"
    }
    defaults=(-f {{ chart }}/ci/default-values.yaml)
    expect_failure "missing satellite settings" "satellite.organization is required" \
      --set rhsm.username=u --set rhsm.password=p
    expect_failure "missing credentials" "rhsm.username is required"
    expect_failure "interval below 60s" "intervalSeconds" "${defaults[@]}" --set virtWho.intervalSeconds=30
    expect_failure "invalid hypervisor id" "hypervisorId" "${defaults[@]}" --set virtWho.hypervisorId=name
    expect_failure "invalid digest" "digest" "${defaults[@]}" --set image.digest=latest

# Package the chart locally into dist/
chart-package version="0.0.0-dev":
    helm package {{ chart }} --version {{ version }} --destination dist

# Build the container image locally
image-build tag=dev_image:
    {{ container }} build -t {{ tag }} image

# Smoke test a container image (no libvirt or Satellite needed)
image-test tag=dev_image:
    #!/usr/bin/env bash
    set -euo pipefail
    c=({{ container }} run --rm --read-only --tmpfs /run --tmpfs /tmp)
    expected="$(sed -n 's/^ARG VIRT_WHO_VERSION=//p' image/Dockerfile)"

    version="$("${c[@]}" --entrypoint /usr/bin/virt-who {{ tag }} --version)"
    echo "$version"
    [[ "$version" == "virt-who ${expected}-"* ]] || { echo "FAIL: expected virt-who ${expected}" >&2; exit 1; }

    "${c[@]}" --entrypoint python3 {{ tag }} -c 'import virtwho, rhsm.connection, subscription_manager'
    echo "ok: python modules import"

    env=(-e SATELLITE_ORG=org -e SATELLITE_HOST=satellite.example.com -e RHSM_USERNAME=reporter -e 'RHSM_PASSWORD=pa%ss')
    config="$("${c[@]}" "${env[@]}" --entrypoint bash {{ tag }} -c \
      'render-virt-who-config && stat -c "mode=%a" /run/virt-who/libvirt.conf && cat /run/virt-who/libvirt.conf')"
    for line in mode=600 '[libvirt]' type=libvirt owner=org rhsm_hostname=satellite.example.com \
                rhsm_port=443 rhsm_prefix=/rhsm rhsm_username=reporter 'rhsm_password=pa%%ss'; do
      grep -qxF -- "$line" <<<"$config" || { echo "FAIL: '${line}' missing from rendered config:" >&2; echo "$config" >&2; exit 1; }
    done
    echo "ok: config rendering"

    status=0
    "${c[@]}" {{ tag }} >/dev/null 2>&1 || status=$?
    [[ $status -eq 2 ]] || { echo "FAIL: missing settings should exit with 2, got ${status}" >&2; exit 1; }
    status=0
    "${c[@]}" "${env[@]}" -e VIRTWHO_DEBUG=maybe {{ tag }} >/dev/null 2>&1 || status=$?
    [[ $status -eq 2 ]] || { echo "FAIL: invalid VIRTWHO_DEBUG should exit with 2, got ${status}" >&2; exit 1; }
    echo "ok: entrypoint validation"

# Show the latest releases and unreleased changes
status:
    @scripts/release.sh status

# Release the container image: just release-image <version|major|minor|patch> [--dry-run]
release-image version *flags:
    scripts/release.sh image {{ version }} {{ flags }}

# Release the Helm chart: just release-chart <version|major|minor|patch> [--dry-run]
release-chart version *flags:
    scripts/release.sh chart {{ version }} {{ flags }}

# Open a PR pointing the chart appVersion to a released image (default: latest)
bump-app-version version="" *flags:
    scripts/release.sh app-version {{ version }} {{ flags }}
