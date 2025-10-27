# GitHub CLI Alias for Quick Setup

## Add this alias to your GitHub CLI configuration:

```bash
gh alias set droid-setup '!cd /path/to/droid-github-code-review && ./setup-new-repo.sh $1'
```

## Usage:

```bash
# Setup Droid Code Review for a new repository
gh droid-setup username/new-repo

# Or for any existing repository
gh droid-setup username/existing-repo
```

## Alternative: One-liner setup

First, set the required environment variables:
```bash
export FACTORY_API_KEY="your-factory-api-key"
export MODEL_API_KEY="your-model-api-key"
export DROID_INSTALLER_SHA256="e31357edcacd7434670621617a0d327ada7491f2d4ca40e3cac3829c388fad9a"  # optional
```

Then add this alias for immediate setup:

```bash
gh alias set droid-now '!gh api repos/$1/actions/secrets -X POST -f name=FACTORY_API_KEY -f value=$FACTORY_API_KEY && gh api repos/$1/actions/secrets -X POST -f name=MODEL_API_KEY -f value=$MODEL_API_KEY && gh api repos/$1/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value=${DROID_INSTALLER_SHA256:-e31357edcacd7434670621617a0d327ada7491f2d4ca40e3cac3829c388fad9a} && curl -fsSL https://raw.githubusercontent.com/tgerighty/droid-github-code-review/main/droid-code-review.yaml | gh api repos/$1/contents/.github/workflows/droid-code-review.yaml --input - -X PUT -f message="Add Droid Code Review workflow"'
```

## Usage:

```bash
gh droid-now username/repo-name
```
