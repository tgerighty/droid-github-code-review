#!/bin/bash

# Setup Droid Code Review for a new repository
# Usage: ./setup-new-repo.sh <owner/repo>

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <owner/repo>"
    echo "Example: $0 myusername/mynewrepo"
    exit 1
fi

# SECURITY: Validate repository input
REPO="$1"

# Validate repository format (owner/repo)
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
    echo "❌ SECURITY ERROR: Invalid repository format. Expected format: owner/repo"
    echo "   Example: myusername/mynewrepo"
    exit 1
fi

# SECURITY: Check for command injection patterns
if [[ "$REPO" =~ [\;\&\|`\$\(\)\{\}\[\]] ]]; then
    echo "❌ SECURITY ERROR: Repository name contains dangerous characters"
    exit 1
fi

echo "🚀 Setting up Droid Code Review for $REPO..."

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with your API keys."
    exit 1
fi

# SECURITY: Load API keys securely with validation
load_env_secure() {
    if [[ -f .env ]]; then
        # SECURITY: Load variables securely with validation (PREVENT COMMAND INJECTION)
        # Using process substitution and read loop instead of dangerous export $(grep | xargs) pattern
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" || -z "$value" ]] && continue
            
            # SECURITY: Validate key name format (only uppercase letters, numbers, and underscores)
            # Prevents environment variable injection attacks
            if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
                # SECURITY: Check for placeholder values that indicate unconfigured keys
                if [[ "$value" == "YOUR_"*"_HERE" ]]; then
                    echo "❌ SECURITY ERROR: $key contains placeholder value. Please configure your actual API key."
                    return 1
                fi
                
                # SECURITY: Check for command injection patterns in values
                if [[ "$value" =~ [\;\&\|`\$\(\)\{\}\[\]] ]]; then
                    echo "❌ SECURITY ERROR: $key contains potentially dangerous characters"
                    return 1
                fi
                
                # Validate API key format (basic length and character checks)
                case "$key" in
                    *_API_KEY)
                        if [[ ${#value} -lt 32 ]]; then
                            echo "❌ SECURITY ERROR: $key appears too short to be a valid API key"
                            return 1
                        fi
                        if [[ ! "$value" =~ ^[a-zA-Z0-9_+-]+$ ]]; then
                            echo "❌ SECURITY ERROR: $key contains invalid characters for an API key"
                            return 1
                        fi
                        ;;
                esac
                
                # SECURITY: Export validated key safely using printf to prevent injection
                printf -v "${key}" '%s' "$value"
                export "$key"
            else
                echo "⚠️  WARNING: Invalid environment variable name: $key"
            fi
        done < <(grep -v '^#' .env | grep -v '^$')
        return 0
    else
        echo "❌ .env file not found"
        return 1
    fi
}

# Load API keys securely
if ! load_env_secure; then
    echo "❌ Failed to load environment variables securely"
    exit 1
fi

# Validate API keys
if [ -z "${FACTORY_API_KEY:-}" ] || [ -z "${MODEL_API_KEY:-}" ]; then
    echo "❌ Missing API keys in .env file"
    exit 1
fi

echo "✅ API keys loaded"

# SECURITY: Clone the repository temporarily with timeout and validation
TEMP_DIR=$(mktemp -d)
# SECURITY: Validate REPO format is safe before using in git clone command
if ! timeout 60 git clone "https://github.com/$REPO.git" "$TEMP_DIR"; then
    echo "❌ Failed to clone repository within 60 seconds"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# SECURITY: Verify we cloned the correct repository
cd "$TEMP_DIR"
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$REMOTE_URL" != *"github.com/$REPO"* ]]; then
    echo "❌ SECURITY ERROR: Repository URL mismatch"
    cd / && rm -rf "$TEMP_DIR"
    exit 1
fi

# Create workflows directory
mkdir -p .github/workflows

# Copy workflow file
cp "$(dirname "$0")/droid-code-review-v2.yaml" .github/workflows/droid-code-review.yaml

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

# SECURITY: Set repository variable safely
SHA256_VALUE="${DROID_INSTALLER_SHA256:-e31357edcacd7434670621617a0d327ada7491f2d4ca40e3cac3829c388fad9a}"
if [ -z "$DROID_INSTALLER_SHA256" ]; then
    echo "⚠️  Using default SHA256. Set DROID_INSTALLER_SHA256 environment variable to override."
fi
gh api repos/"$REPO"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256_VALUE" 2>/dev/null || true

# SECURITY: Set secrets using stdin to avoid command line exposure
echo "$FACTORY_API_KEY" | gh secret set FACTORY_API_KEY --repo="$REPO"
echo "$MODEL_API_KEY" | gh secret set MODEL_API_KEY --repo="$REPO"

echo "✅ Secrets and variables configured"
echo "🎉 Droid Code Review is now set up for $REPO!"
echo "   The workflow will run automatically on pull requests."

# Cleanup
cd ..
rm -rf "$TEMP_DIR"
