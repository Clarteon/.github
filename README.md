# Clarteon CI/CD

Organization-wide continuous integration and release workflows for Clarteon repositories.
Application code stays in its own repository; this repository contains only pipeline definitions and
starter templates.

## Pipelines

| Workflow                       | Trigger                                   | What it does                                                                                                       |
| ------------------------------ | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `.github/workflows/ci.yml`     | `workflow_call`                           | Installs from the lockfile, then runs lint, formatting, type check, tests, placeholder check, audit and build.     |
| `.github/workflows/release.yml` | `workflow_call`                          | Publishes a GitHub release with generated notes for a `v1.2.3` tag, and does nothing if the release already exists. |
| `.github/workflows/vercel-deploy.yml` | `workflow_call`                   | Builds in Actions and uploads to Vercel: production for pushes to `main`, a preview with a PR comment otherwise. Added in `v1.1.0`. |

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

Vercel's Git integration does not support private organization repositories on the Hobby plan, so
repositories deploy from GitHub Actions with `vercel-deploy.yml` instead:

- a push to `main` deploys production, after CI passes;
- a pull request from a branch in the same repository gets a preview deployment, and its URL is posted
  as a pull request comment (updated on each push);
- pull requests from forks are skipped, because they cannot read secrets;
- production deploys queue instead of cancelling each other;
- the Vercel CLI version is pinned, and the deployment URL is written to the run summary.

### Connect a repository

Run once from the root of the app repository, with `gh` signed in as someone who can manage the
repository's secrets:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Clarteon/.github/v1.1.0/scripts/setup-vercel-deploy.sh)
```

The script links the Vercel project, stores `VERCEL_ORG_ID` and `VERCEL_PROJECT_ID` as repository
variables, and stores a Vercel token as the `VERCEL_TOKEN` repository secret without printing it. GitHub
Free does not share organization secrets with private repositories, so each private repository keeps its
own token. Create the token in Vercel under **Account Settings → Tokens**, scoped to the team that owns
the project, with an expiry of 90 days or less.

Then disconnect any Git repository in the Vercel project (**Settings → Git**) so a push does not deploy
twice, and add a deploy job to the repository's CI caller:

```yaml
jobs:
  ci:
    uses: Clarteon/.github/.github/workflows/ci.yml@v1

  deploy:
    needs: ci
    if: github.event_name != 'workflow_dispatch'
    permissions:
      contents: read
      pull-requests: write
    uses: Clarteon/.github/.github/workflows/vercel-deploy.yml@v1.1.0
    secrets:
      VERCEL_TOKEN: ${{ secrets.VERCEL_TOKEN }}
```

The `pull-requests: write` permission is only used to post the preview comment. Inputs:
`production-branch` (default `main`), `node-version` (default `24`) and `vercel-cli-version`.

### Roll back

Use **Instant Rollback** on a previous production deployment in the Vercel dashboard. It takes effect
immediately. Then revert the bad commit on `main` so the next push does not redeploy it.

### Rotate the token

Create a new token, run `gh secret set VERCEL_TOKEN --repo Clarteon/<repo>`, re-run the latest deploy,
then delete the old token in Vercel. Rotate immediately if a token may have been exposed.

## Enforcement

GitHub Free does not allow required status checks on private repositories. CI therefore reports on every
push and pull request, but a direct push to `main` is not blocked by GitHub. The deploy job runs only after
CI passes, so a failing commit is not deployed, but it still lands on `main`.

Until the organization upgrades to GitHub Team or makes a repository public, treat checks as mandatory by
convention:

1. Open a pull request for every change.
2. Wait for the CI check to pass before merging.
3. Keep `main` deployable at all times.

Even without enforcement, the check history in the Actions tab makes a failing change visible before or
immediately after merge.

## Security

- No secrets are stored in this repository. The deploy workflow needs a `VERCEL_TOKEN` secret, which
  lives in each calling repository and is passed explicitly, never through `secrets: inherit`.
- Workflows declare `permissions: contents: read`, except the release job, which needs `contents: write`
  to create a release, and the deploy job, which needs `pull-requests: write` to post the preview URL.
- Callers reference the reviewed `v1` tag. Moving the tag is an intentional change made from `main`
  after a consumer run passes.
- This repository is public so every repository in the organization can call the workflows and use the
  templates without extra access settings. It contains no application code, credentials or visitor data.

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
