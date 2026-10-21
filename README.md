# Clarteon CI/CD

Organization-wide continuous integration and release workflows for Clarteon repositories.
Application code stays in its own repository; this repository contains only pipeline definitions and
starter templates.

## Pipelines

| Workflow                       | Trigger                                   | What it does                                                                                                       |
| ------------------------------ | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `.github/workflows/ci.yml`     | `workflow_call`                           | Installs from the lockfile, then runs lint, formatting, type check, tests, placeholder check, audit and build.     |
| `.github/workflows/release.yml` | `workflow_call`                          | Publishes a GitHub release with generated notes for a `v1.2.3` tag, and does nothing if the release already exists. |

Both workflows are reusable. Callers pin the `v1` tag, so changes to `main` do not reach repositories
until a reviewed commit is tagged. Full version tags such as `v1.0.0` record each release, and the `v1`
tag follows the latest compatible one, in the same way GitHub's own actions are versioned.

## Adopting the pipelines

The starter templates appear under **Actions → New workflow** for repositories in the Clarteon
organization. Choose **Clarteon CI** and commit the generated file.

To add a caller by hand, create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  ci:
    uses: Clarteon/.github/.github/workflows/ci.yml@v1
```

For releases, create `.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: read

jobs:
  ci:
    uses: Clarteon/.github/.github/workflows/ci.yml@v1

  release:
    needs: ci
    permissions:
      contents: write
    uses: Clarteon/.github/.github/workflows/release.yml@v1
    with:
      tag: ${{ github.ref_name }}
```

The release job runs CI on the tagged commit first, so a release is only published when the same checks
pass.

## Repository requirements

- Node.js 24 is the default. Pass `node-version` to the CI workflow to override it.
- `package.json` and `package-lock.json` live at the repository root.
- The workflow runs a script only when it exists: `lint`, `format:check`, `typecheck`, `test`,
  `check:placeholders` and `build`. Missing scripts are skipped, not failed.
- The audit runs with `npm audit --omit=dev --audit-level=high` and retries transient registry failures.
  Pass `run-audit: false` or a different `audit-level` when a repository needs an exception.

Monorepos are not supported yet. Add a `working-directory` input before adopting this for one.

## Deployments

Deployment stays with Vercel's Git integration:

- every pull request gets a preview deployment;
- a merge to `main` deploys production.

This repository does not deploy anything and holds no secrets. A GitHub release records the version; it
does not trigger a deployment.

## Enforcement

GitHub Free does not allow required status checks on private repositories. CI therefore reports on every
push and pull request, but a direct push to `main` is not blocked by GitHub, and Vercel can deploy a commit
whose checks failed.

Until the organization upgrades to GitHub Team or makes a repository public, treat checks as mandatory by
convention:

1. Open a pull request for every change.
2. Wait for the CI check to pass before merging.
3. Keep `main` deployable at all times.

Even without enforcement, the check history in the Actions tab makes a failing change visible before or
immediately after merge.

## Security

- No secrets are stored in this repository or needed by the pipelines.
- Workflows declare `permissions: contents: read`, except the release job, which needs `contents: write`
  to create a release.
- Callers reference the reviewed `v1` tag. Moving the tag is an intentional change made from `main`
  after a consumer run passes.
- This repository is public so GitHub can offer the starter templates to the organization. It contains no
  application code, credentials or visitor data.

## Maintaining the workflows

1. Make the change on a branch and open a pull request in this repository.
2. Test it from a pull request in a consumer repository by pointing one caller at `@main` temporarily.
3. Once the consumer run is green, merge, then tag the release and move the major tag:

```bash
git tag -a v1.1.0 -m "CI: describe the change"
git tag -f -a v1 -m "CI v1"
git push origin v1.1.0
git push --force origin v1
```

Use a new major tag (`v2`) for a breaking change, and update callers deliberately. Moving `v1` rewrites
what every caller runs, so treat it as a reviewed release step, not a convenience.
