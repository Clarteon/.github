#!/usr/bin/env bash
# Connect a repository to Vercel deploys through GitHub Actions.
#
# Run from the root of the app repository:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Clarteon/.github/v1.1.0/scripts/setup-vercel-deploy.sh)
#
# It links the Vercel project, stores the project and team IDs as repository variables,
# and asks for a Vercel token to store as the VERCEL_TOKEN repository secret. The token
# is read by gh directly and is never echoed or written to disk.
#
# GitHub Free does not share organization secrets with private repositories, so each
# private repository needs its own VERCEL_TOKEN.

set -euo pipefail

VERCEL_CLI_VERSION="64.0.2"

for tool in gh node npx; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install it and try again." >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "Run gh auth login first." >&2; exit 1; }

repo="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
echo "Setting up Vercel deploys for $repo"

if [ ! -f .vercel/project.json ]; then
  echo "Linking this folder to a Vercel project (choose the existing project)..."
  npx --yes "vercel@${VERCEL_CLI_VERSION}" link
fi

org_id="$(node -p "require('./.vercel/project.json').orgId")"
project_id="$(node -p "require('./.vercel/project.json').projectId")"

gh variable set VERCEL_ORG_ID --repo "$repo" --body "$org_id"
gh variable set VERCEL_PROJECT_ID --repo "$repo" --body "$project_id"
echo "Stored VERCEL_ORG_ID and VERCEL_PROJECT_ID as repository variables."

cat <<'EOF'

Create a Vercel token now:
  Vercel -> Account Settings -> Tokens -> Create
  Scope: the team that owns the project. Expiration: 90 days or less.
Paste it at the prompt below. It is sent straight to GitHub and not shown.
EOF
gh secret set VERCEL_TOKEN --repo "$repo"

cat <<EOF

Done. Next:
  1. Add the deploy job to .github/workflows/ci.yml (see the Clarteon/.github README).
  2. In Vercel, Settings -> Git: disconnect any Git repository so pushes do not deploy twice.
  3. Push a branch and open a pull request: the preview URL appears as a comment.
EOF
