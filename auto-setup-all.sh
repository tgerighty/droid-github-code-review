#!/bin/bash

# Automatically add Droid Code Review to ALL your repositories
# Use this for new repositories or to update existing ones

set -euo pipefail

echo "🚀 Auto-Setup Droid Code Review for All Repositories"
echo "=================================================="

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with your API keys."
    echo "   Copy .env.example to .env and add your keys."
    exit 1
fi

# Load API keys
source .env

# Validate API keys
if [ -z "${FACTORY_API_KEY:-}" ] || [ -z "${MODEL_API_KEY:-}" ]; then
    echo "❌ Missing API keys in .env file"
    exit 1
fi

# Check for required tools
check() {
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) is not installed. Please install it first."
        echo "   Visit: https://cli.github.com/"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        echo "❌ GitHub CLI is not authenticated. Please run 'gh auth login' first."
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Please install it first."
        echo "   macOS: brew install jq"
        echo "   Ubuntu/Debian: sudo apt-get install jq"
        echo "   CentOS/RHEL: sudo yum install jq"
        exit 1
    fi
}

check

echo "✅ API keys loaded"

# Get current SHA256
SHA256=$(curl -fsSL --connect-timeout 10 --max-time 30 --compressed https://app.factory.ai/cli | sha256sum | cut -d' ' -f1)
echo "✅ Current SHA256: $SHA256"

# Function to setup a single repository
setup_repo() {
    local repo="$1"
    echo "🔧 Setting up $repo..."
    
    # Clone temporarily with timeout and shallow clone
    local temp_dir=$(mktemp -d)
    if timeout 60 git clone --depth 1 "https://github.com/$repo.git" "$temp_dir" 2>/dev/null; then
        cd "$temp_dir"
        
        # Create workflows directory
        mkdir -p .github/workflows
        
        # Copy workflow file
        cp "$(dirname "$0")/droid-code-review.yaml" .github/workflows/
        
        # Check if workflow already exists
        if [ -f ".github/workflows/droid-code-review.yaml" ]; then
            # Check if it's different
            if ! diff -q ".github/workflows/droid-code-review.yaml" "$(dirname "$0")/droid-code-review.yaml" >/dev/null 2>&1; then
                git add .github/workflows/droid-code-review.yaml
                git commit -m "Update Droid Code Review workflow

- Automated AI-powered code analysis  
- Uses GLM-4.6 model via Factory.ai
- Runs on pull requests for code review

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>" 2>/dev/null
                if git push 2>/dev/null; then
                    echo "  ✅ Updated workflow"
                else
                    echo "  ❌ Failed to push updates"
                    cd / && rm -rf "$temp_dir"
                    return 1
                fi
            else
                echo "  ⚠️  Workflow already exists (up to date)"
            fi
        else
            git add .github/workflows/droid-code-review.yaml
            git commit -m "Add Droid Code Review workflow

- Automated AI-powered code analysis
- Uses GLM-4.6 model via Factory.ai  
- Runs on pull requests for code review

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>" 2>/dev/null
            if git push 2>/dev/null; then
                echo "  ✅ Added workflow"
            else
                echo "  ❌ Failed to push workflow"
                cd / && rm -rf "$temp_dir"
                return 1
            fi
        fi
        
        # Set repository variable
        if gh api repos/"$repo"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256" 2>/dev/null; then
            echo "  ✅ Set SHA256 variable"
        else
            echo "  ⚠️  Failed to set SHA256 variable"
        fi
        
        # Set secrets
        if echo "$FACTORY_API_KEY" | gh secret set FACTORY_API_KEY --repo="$repo" 2>/dev/null; then
            echo "  ✅ Set FACTORY_API_KEY"
        else
            echo "  ⚠️  Failed to set FACTORY_API_KEY"
        fi
        
        if echo "$MODEL_API_KEY" | gh secret set MODEL_API_KEY --repo="$repo" 2>/dev/null; then
            echo "  ✅ Set MODEL_API_KEY"
        else
            echo "  ⚠️  Failed to set MODEL_API_KEY"
        fi
        
        echo "  ✅ Configured secrets and variables"
    else
        echo "  ❌ Failed to clone $repo"
        cd / && rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # Cleanup
    cd / && rm -rf "$temp_dir"
    return 0
}

# Get all your repositories
echo "📂 Fetching your repositories..."
repos=$(gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner')

# Initialize counters
success=0
failed=0
total=$(echo "$repos" | wc -l)

# Process each repository
echo "🚀 Processing $total repositories..."
echo ""

for repo in $repos; do
    if setup_repo "$repo"; then
        success=$((success + 1))
    else
        failed=$((failed + 1))
    fi
    echo ""
done

echo "🎉 All repositories have been processed!"
echo ""
echo "Summary:"
echo "- Successful: $success/$total repositories"
echo "- Failed: $failed/$total repositories"
echo "- Workflow added/updated in accessible repositories"
echo "- API keys configured as repository secrets"  
echo "- SHA256 variable set for security validation"
echo ""
echo "The workflow will now run automatically on pull requests."
