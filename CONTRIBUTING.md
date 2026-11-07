# Contributing

Thanks for your interest in improving virt-who for containers! This project
packages the upstream [virt-who](https://github.com/candlepin/virt-who) agent
as a container image and a Helm chart. Bug reports, documentation fixes and
pull requests are all welcome.

## Reporting issues

- **Bugs, feature requests and questions:** open an
  [issue](https://github.com/PfurtschellerP/virt-who/issues/new/choose) using
  one of the templates.
- **Security vulnerabilities:** report them privately as described in
  [SECURITY.md](SECURITY.md), never in a public issue.
- **Problems in virt-who itself** (how it talks to libvirt or Satellite)
  belong [upstream](https://github.com/candlepin/virt-who/issues). If you are
  unsure, open an issue here and we will figure it out together.

Never include passwords, tokens or Secret contents in issues, logs or pull
requests.

## Development setup

You need [just](https://github.com/casey/just), [Helm](https://helm.sh) and
Podman or Docker. All linters and tests run in pinned containers, so nothing
else has to be installed. Set `CONTAINER_ENGINE=docker` or `podman` to choose
an engine explicitly.

```sh
just              # list all recipes
just check        # everything CI runs: linters, Python tests, chart tests
```

The [Development](README.md#development) section of the README lists the
individual recipes.

## Making changes

1. Fork the repository and create a branch from `main`.
2. Make your change, together with tests and documentation (see below).
3. Run `just check` and make sure it passes.
4. Open a pull request against `main`. CI must pass and a maintainer has to
   approve it before it can be merged; `main` is protected and only accepts
   changes through pull requests.

Keep pull requests focused on one change. Larger or behaviour-changing ideas
are best discussed in an issue first.

### Where things live

| Change | Files | Also update |
| --- | --- | --- |
| Config rendering | `image/render_config.py` | Tests in `tests/`, the configuration table in `README.md` |
| Entrypoint behaviour | `image/entrypoint.sh` | `image-test` recipe in the `justfile` |
| Image contents | `image/Dockerfile` | `image-test` recipe if the change is user-visible |
| Chart values | `charts/virt-who/values.yaml` | `values.schema.json`, the values table in `charts/virt-who/README.md`, `ci/full-values.yaml` |
| Chart validation | `charts/virt-who/templates/` | An `expect_failure` case in the `chart-test` recipe |
| Workflows | `.github/workflows/` | — |

### Tests

- **Python:** `tests/` contains pytest and
  [Hypothesis](https://hypothesis.readthedocs.io) property-based tests for the
  config renderer. They read the rendered file back with a copy of virt-who's
  own parser, so add cases there when you touch `render_config.py`. Run them
  with `just test`.
- **Chart:** `just chart-test` lints the chart, renders every
  `ci/*-values.yaml` file, validates the output against the Kubernetes schemas
  and checks that invalid values are rejected.
- **Image:** `just image-build` followed by `just image-test` builds the image
  and smoke-tests it without libvirt or Satellite. CI runs the same test for
  every pull request that changes the image.

### Code style

Formatting and linting are enforced by `just lint` (actionlint, shellcheck,
hadolint and ruff). `just fmt` formats the Python code in place.

### Dependencies

[Renovate](https://docs.renovatebot.com) keeps dependencies up to date (see
`.github/renovate.json5`), so you normally do not have to bump versions by
hand. If you add a dependency, pin it the same way as the existing ones:

- **GitHub Actions** by full commit SHA with the version as a comment, e.g.
  `actions/checkout@<sha> # v7.0.1`.
- **Container images** by tag, plus digest where the file already uses one
  (`image/Dockerfile`).
- **Python test dependencies** in `tests/requirements.in`, then regenerate the
  hash-pinned lock file from the `tests/` directory with exactly the command
  recorded in the header of `tests/requirements.txt`.
- **workflow permissions** least-privilege: `contents: read` at the top level,
  anything more only on the job that needs it.

### Commit messages and pull request titles

Use [Conventional Commits](https://www.conventionalcommits.org), with a scope
where it helps:

```text
feat(chart): support an existing Secret for the credentials
fix(image): reject passwords that virt-who would strip to an empty value
docs: explain the SELinux options
```

Common types are `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `build` and
`chore`. Use the same format for the pull request title.

Release notes are generated from pull request labels. Maintainers will add
them, but you are welcome to suggest one: `breaking-change`, `enhancement`,
`bug` or `dependencies`.

## Releases

Releases are cut by maintainers with the release helper (see
[Releasing](README.md#releasing)). The image and the chart are versioned
independently, published versions are immutable, and every release is signed.
You do not need to change any version numbers in a pull request.

## License

By contributing, you agree that your contributions are licensed under the
[GPL-2.0](LICENSE), the same license as the project and virt-who itself.
