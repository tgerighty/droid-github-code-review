#!/bin/bash

# Setup Droid Code Review for a new repository
# Usage: ./setup-new-repo.sh <owner/repo>

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <owner/repo>"
    echo "Example: $0 myusername/mynewrepo"
    exit 1
fi

REPO="$1"
echo "🚀 Setting up Droid Code Review for $REPO..."

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with your API keys."
    exit 1
fi

# Load API keys
source .env

# Validate API keys
if [ -z "${FACTORY_API_KEY:-}" ] || [ -z "${MODEL_API_KEY:-}" ]; then
    echo "❌ Missing API keys in .env file"
    exit 1
fi

echo "✅ API keys loaded"

# Clone the repository temporarily with timeout
TEMP_DIR=$(mktemp -d)
if ! timeout 60 git clone "https://github.com/$REPO.git" "$TEMP_DIR"; then
    echo "❌ Failed to clone repository within 60 seconds"
    rm -rf "$TEMP_DIR"
    exit 1
fi
cd "$TEMP_DIR"

# Create workflows directory
mkdir -p .github/workflows

# Copy workflow file
cp "$(dirname "$0")/droid-code-review.yaml" .github/workflows/

# Commit and push
git add .github/workflows/droid-code-review.yaml
git commit -m "Add Droid Code Review workflow

- Automated AI-powered code analysis
- Uses GLM-4.6 model via Factory.ai
- Runs on pull requests for code review

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"

if ! timeout 60 git push; then
    echo "❌ Failed to push within 60 seconds"
    cd / && rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ Workflow added to $REPO"

# Set up secrets and variables
echo "🔧 Configuring secrets and variables..."

# Set repository variable
SHA256_VALUE="${DROID_INSTALLER_SHA256:-e31357edcacd7434670621617a0d327ada7491f2d4ca40e3cac3829c388fad9a}"
if [ -z "$DROID_INSTALLER_SHA256" ]; then
    echo "⚠️  Using default SHA256. Set DROID_INSTALLER_SHA256 environment variable to override."
fi
gh api repos/"$REPO"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256_VALUE"

# Set secrets
echo "$FACTORY_API_KEY" | gh secret set FACTORY_API_KEY --repo="$REPO"
echo "$MODEL_API_KEY" | gh secret set MODEL_API_KEY --repo="$REPO"

echo "✅ Secrets and variables configured"
echo "🎉 Droid Code Review is now set up for $REPO!"
echo "   The workflow will run automatically on pull requests."

# Cleanup
cd ..
rm -rf "$TEMP_DIR"
