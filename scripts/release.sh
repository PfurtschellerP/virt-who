#!/usr/bin/env bash
#
# Release helper for the virt-who container image and Helm chart.
#
# Releases are driven by git tags; CI builds, signs and publishes the artifact
# and creates the GitHub release once the tag is pushed:
#
#   image-v<version>  ->  ghcr.io/<owner>/virt-who:<version>
#   chart-v<version>  ->  oci://ghcr.io/<owner>/charts/virt-who --version <version>
#
# main is protected, so this script never pushes commits to it. Changing the
# chart's appVersion goes through a pull request (`app-version` command).

set -euo pipefail

readonly CHART_FILE="charts/virt-who/Chart.yaml"
readonly DOCKERFILE="image/Dockerfile"
readonly SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$'

remote="origin"
branch="main"
dry_run=false
assume_yes=false
skip_ci=false

usage() {
  cat <<EOF
Usage:
  $(basename "$0") image <version|major|minor|patch> [options]
  $(basename "$0") chart <version|major|minor|patch> [options]
  $(basename "$0") app-version <image-version>     [options]
  $(basename "$0") status

Commands:
  image        Tag the current main commit as image-v<version> and push the tag.
  chart        Tag the current main commit as chart-v<version> and push the tag.
  app-version  Open a pull request that points the chart's appVersion to an
               already released image version (defaults to the latest one).
  status       Show the latest releases and unreleased changes.

Options:
  -n, --dry-run   Run all checks and show what would happen, change nothing.
  -y, --yes       Do not ask for confirmation.
  --skip-ci       Do not require successful CI runs for the release commit.
  --remote NAME   Git remote to use (default: origin).
  -h, --help      Show this help.

Examples:
  $(basename "$0") image patch
  $(basename "$0") app-version
  $(basename "$0") chart minor --dry-run
EOF
}

# --- output helpers ---------------------------------------------------------

if [[ -t 1 ]]; then
  bold=$'\e[1m' red=$'\e[31m' green=$'\e[32m' yellow=$'\e[33m' reset=$'\e[0m'
else
  bold="" red="" green="" yellow="" reset=""
fi

info() { printf '%s==>%s %s\n' "$bold" "$reset" "$*"; }
ok() { printf '%s  ✓%s %s\n' "$green" "$reset" "$*"; }
warn() { printf '%s  !%s %s\n' "$yellow" "$reset" "$*" >&2; }
die() {
  printf '%serror:%s %s\n' "$red" "$reset" "$*" >&2
  exit 1
}

run() {
  if $dry_run; then
    printf '  [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

confirm() {
  $assume_yes && return 0
  $dry_run && return 0
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]] || die "aborted"
}

# --- semver helpers ---------------------------------------------------------

is_semver() { [[ "$1" =~ $SEMVER_RE ]]; }

# semver_gt A B: succeeds when A > B (pre-releases sort before the release).
semver_gt() {
  local a="$1" b="$2"
  [[ "$a" == "$b" ]] && return 1
  local a_core="${a%%-*}" b_core="${b%%-*}"
  if [[ "$a_core" != "$b_core" ]]; then
    [[ "$(printf '%s\n%s\n' "$a_core" "$b_core" | sort -V | tail -n 1)" == "$a_core" ]]
    return
  fi
  # Same core version: a release is newer than any of its pre-releases.
  [[ "$a" != *-* ]] && return 0
  [[ "$b" != *-* ]] && return 1
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -n 1)" == "$a" ]]
}

# latest_version PREFIX: highest version among tags PREFIX<semver>.
latest_version() {
  local prefix="$1" latest="" tag version
  while IFS= read -r tag; do
    version="${tag#"$prefix"}"
    is_semver "$version" || continue
    if [[ -z "$latest" ]] || semver_gt "$version" "$latest"; then
      latest="$version"
    fi
  done < <(git tag --list "${prefix}*")
  printf '%s' "$latest"
}

# next_version CURRENT BUMP|VERSION
next_version() {
  local current="${1:-0.0.0}" bump="$2" major minor patch
  case "$bump" in
    major | minor | patch)
      IFS=. read -r major minor patch <<<"${current%%-*}"
      case "$bump" in
        major) printf '%d.0.0' "$((major + 1))" ;;
        minor) printf '%d.%d.0' "$major" "$((minor + 1))" ;;
        patch)
          # Releasing a pre-release's core version counts as the patch bump.
          if [[ "$current" == *-* ]]; then
            printf '%s' "${current%%-*}"
          else
            printf '%d.%d.%d' "$major" "$minor" "$((patch + 1))"
          fi
          ;;
      esac
      ;;
    v*) printf '%s' "${bump#v}" ;;
    *) printf '%s' "$bump" ;;
  esac
}

chart_app_version() {
  sed -n 's/^appVersion: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$CHART_FILE"
}

dockerfile_virt_who_version() {
  sed -n 's/^ARG VIRT_WHO_VERSION=\(.*\)$/\1/p' "$DOCKERFILE"
}

# --- repository checks ------------------------------------------------------

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' is required but not installed"
  done
}

check_repository() {
  info "Checking repository state"
  [[ -z "$(git status --porcelain)" ]] || die "working tree is not clean; commit or stash your changes"
  ok "working tree is clean"

  git fetch --quiet --tags "$remote" "$branch"
  local head upstream
  head="$(git rev-parse HEAD)"
  upstream="$(git rev-parse "${remote}/${branch}")"
  if [[ "$head" != "$upstream" ]]; then
    die "HEAD ($(git rev-parse --short HEAD)) is not ${remote}/${branch} ($(git rev-parse --short "$upstream")); run: git switch ${branch} && git pull --ff-only"
  fi
  ok "HEAD is ${remote}/${branch} ($(git log -1 --format='%h %s'))"
}

check_ci() {
  $skip_ci && {
    warn "skipping CI status check"
    return
  }
  if ! command -v gh >/dev/null 2>&1; then
    warn "gh CLI not found; cannot verify CI status (use --skip-ci to silence)"
    return
  fi

  local sha runs failed pending
  sha="$(git rev-parse HEAD)"
  runs="$(gh run list --commit "$sha" --event push --limit 50 \
    --json workflowName,status,conclusion \
    --jq '.[] | "\(.workflowName)\t\(.status)\t\(.conclusion)"')" ||
    die "could not query CI runs via gh (use --skip-ci to bypass)"

  if [[ -z "$runs" ]]; then
    warn "no CI runs found for $(git rev-parse --short HEAD)"
    return
  fi
  failed="$(awk -F'\t' '$2 == "completed" && $3 != "success" && $3 != "skipped" { print "    " $1 " (" $3 ")" }' <<<"$runs")"
  pending="$(awk -F'\t' '$2 != "completed" { print "    " $1 " (" $2 ")" }' <<<"$runs")"
  [[ -z "$failed" ]] || die "CI failed for this commit:"$'\n'"$failed"
  [[ -z "$pending" ]] || die "CI is still running for this commit:"$'\n'"$pending"
  ok "CI passed for $(git rev-parse --short HEAD)"
}

check_new_tag() {
  local tag="$1"
  git rev-parse -q --verify "refs/tags/${tag}" >/dev/null && die "tag ${tag} already exists"
  if git ls-remote --exit-code --tags "$remote" "refs/tags/${tag}" >/dev/null 2>&1; then
    die "tag ${tag} already exists on ${remote}"
  fi
  ok "tag ${tag} is available"
}

repo_slug() {
  local url
  url="$(git remote get-url "$remote")"
  url="${url%.git}"
  url="${url#*github.com[:/]}"
  printf '%s' "$url"
}

# --- commands ---------------------------------------------------------------

cmd_release() {
  local kind="$1" requested="$2" prefix title previous version tag
  case "$kind" in
    image) prefix="image-v" title="Container image" ;;
    chart) prefix="chart-v" title="Helm chart" ;;
  esac

  check_repository

  previous="$(latest_version "$prefix")"
  version="$(next_version "$previous" "$requested")"
  tag="${prefix}${version}"

  info "Validating ${title,,} version ${version}"
  is_semver "$version" || die "'${version}' is not a valid semantic version (e.g. 1.2.3 or 1.2.3-rc.1)"
  if [[ -n "$previous" ]]; then
    semver_gt "$version" "$previous" || die "${version} must be greater than the latest release ${previous}"
    ok "${version} > ${previous}"
  fi
  check_new_tag "$tag"

  case "$kind" in
    image)
      ok "image ships virt-who $(dockerfile_virt_who_version)"
      if [[ -n "$previous" ]] && git diff --quiet "${prefix}${previous}" HEAD -- image/; then
        warn "image/ has not changed since ${prefix}${previous} (a rebuild still picks up base image updates)"
      fi
      ;;
    chart)
      local app_version
      app_version="$(chart_app_version)"
      [[ -n "$app_version" ]] || die "could not read appVersion from ${CHART_FILE}"
      git rev-parse -q --verify "refs/tags/image-v${app_version}" >/dev/null ||
        die "chart appVersion ${app_version} has no matching image-v${app_version} release"
      ok "chart deploys image ${app_version}"
      local latest_image
      latest_image="$(latest_version image-v)"
      if [[ -n "$latest_image" && "$latest_image" != "$app_version" ]]; then
        warn "a newer image ${latest_image} exists; run 'just bump-app-version' first to ship it"
      fi
      if command -v helm >/dev/null 2>&1; then
        helm lint --quiet charts/virt-who -f charts/virt-who/ci/default-values.yaml >/dev/null ||
          die "helm lint failed"
        ok "helm lint passed"
      fi
      if [[ -n "$previous" ]] && git diff --quiet "${prefix}${previous}" HEAD -- charts/; then
        warn "charts/ has not changed since ${prefix}${previous}"
      fi
      ;;
  esac

  check_ci

  echo
  info "Release summary"
  printf '  %-10s %s\n' "artifact" "$title" "previous" "${previous:-<none>}" "version" "$version" \
    "tag" "$tag" "commit" "$(git log -1 --format='%h %s')"
  if [[ -n "$previous" ]]; then
    local path changes
    [[ "$kind" == image ]] && path="image/" || path="charts/"
    changes="$(git --no-pager log --format='  %h %s' "${prefix}${previous}..HEAD" -- "$path")"
    echo
    info "Changes in ${path} since ${prefix}${previous}"
    printf '%s\n' "${changes:-  (none)}"
  fi
  echo

  confirm "Create and push ${tag}?"
  run git tag --annotate "$tag" --message "${title} v${version}"
  run git push "$remote" "refs/tags/${tag}"

  local slug
  slug="$(repo_slug)"
  echo
  if $dry_run; then
    ok "dry run complete; nothing was changed"
    return
  fi
  ok "pushed ${tag}; CI is now building and publishing the release"
  if [[ "$(git remote get-url "$remote")" == *github.com* ]]; then
    echo "    https://github.com/${slug}/actions"
  fi
  if [[ "$kind" == image ]]; then
    echo
    info "Next: once the image is published, update the chart to use it:"
    echo "    just bump-app-version ${version}"
  fi
}

cmd_app_version() {
  local version="${1:-}" current slug work_branch
  require_tools gh
  check_repository

  [[ -n "$version" ]] || version="$(latest_version image-v)"
  version="${version#v}"
  version="${version#image-v}"
  [[ -n "$version" ]] || die "no image release found"
  is_semver "$version" || die "'${version}' is not a valid semantic version"
  git rev-parse -q --verify "refs/tags/image-v${version}" >/dev/null ||
    die "image-v${version} has not been released yet"

  current="$(chart_app_version)"
  [[ "$current" != "$version" ]] || die "chart appVersion is already ${version}"
  ok "appVersion ${current} -> ${version}"

  work_branch="release/chart-app-version-${version}"
  git rev-parse -q --verify "refs/heads/${work_branch}" >/dev/null && die "branch ${work_branch} already exists"

  confirm "Open a pull request updating the chart appVersion to ${version}?"
  run git switch --create "$work_branch"
  if $dry_run; then
    printf '  [dry-run] set appVersion: "%s" in %s\n' "$version" "$CHART_FILE"
  else
    sed -i.bak "s/^appVersion:.*/appVersion: \"${version}\"/" "$CHART_FILE" && rm -f "${CHART_FILE}.bak"
  fi
  run git commit --quiet --message "feat(chart): deploy image ${version} by default" -- "$CHART_FILE"
  run git push --set-upstream "$remote" "$work_branch"
  slug="$(repo_slug)"
  run gh pr create --repo "$slug" --base "$branch" --head "$work_branch" \
    --title "feat(chart): deploy image ${version} by default" \
    --body "Points the chart's \`appVersion\` to the released image \`image-v${version}\`. Release the chart afterwards with \`just release-chart <version>\`."
  run git switch --quiet "$branch"
  $dry_run && ok "dry run complete; nothing was changed"
  return 0
}

cmd_status() {
  git fetch --quiet --tags "$remote" 2>/dev/null || warn "could not fetch tags from ${remote}"
  local kind prefix latest path
  for kind in image chart; do
    prefix="${kind}-v"
    [[ "$kind" == image ]] && path="image/" || path="charts/"
    latest="$(latest_version "$prefix")"
    if [[ -z "$latest" ]]; then
      printf '%s%-6s%s no releases yet\n' "$bold" "$kind" "$reset"
      continue
    fi
    printf '%s%-6s%s %s (%s)\n' "$bold" "$kind" "$reset" "$latest" \
      "$(git log -1 --format='%cs' "${prefix}${latest}")"
    git --no-pager log --format='         %h %s' "${prefix}${latest}..${remote}/${branch}" -- "$path" | head -n 20
  done
  printf '%s%-6s%s appVersion %s, virt-who %s\n' "$bold" "repo" "$reset" \
    "$(chart_app_version)" "$(dockerfile_virt_who_version)"
}

# --- main -------------------------------------------------------------------

main() {
  local positional=()
  while (($#)); do
    case "$1" in
      -n | --dry-run) dry_run=true ;;
      -y | --yes) assume_yes=true ;;
      --skip-ci) skip_ci=true ;;
      --remote)
        [[ $# -ge 2 ]] || die "--remote requires a value"
        remote="$2"
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -*) die "unknown option: $1 (see --help)" ;;
      *) positional+=("$1") ;;
    esac
    shift
  done

  require_tools git
  cd "$(git rev-parse --show-toplevel)"

  case "${positional[0]:-}" in
    image | chart)
      [[ ${#positional[@]} -eq 2 ]] || die "usage: $(basename "$0") ${positional[0]} <version|major|minor|patch>"
      cmd_release "${positional[0]}" "${positional[1]}"
      ;;
    app-version)
      [[ ${#positional[@]} -le 2 ]] || die "usage: $(basename "$0") app-version [image-version]"
      cmd_app_version "${positional[1]:-}"
      ;;
    status) cmd_status ;;
    "")
      usage
      exit 1
      ;;
    *) die "unknown command: ${positional[0]} (see --help)" ;;
  esac
}

main "$@"
