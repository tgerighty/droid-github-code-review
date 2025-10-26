#!/bin/bash

# Script to fix GitHub workflow issues across repositories
# Issues fixed:
# 1. Position calculation and validation for GitHub API 422 errors
# 2. Enhanced logging for debugging position issues

set -euo pipefail

REPOS=(
    "tgerighty/mailintelligence"
    "tgerighty/ai-agent-skills"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW_FILE="$SCRIPT_DIR/droid-code-review.yaml"

echo "🔧 Fixing GitHub workflow issues..."
echo "Source workflow: $WORKFLOW_FILE"
echo ""

# Function to update workflow in a repository
update_workflow() {
    local repo="$1"
    echo "📦 Updating workflow in $repo..."
    
    # Create a temporary directory
    temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    # Clone the repository
    echo "  Cloning $repo..."
    gh repo clone "$repo" "$temp_dir" -- --quiet
    
    # Check if workflow exists
    workflow_path="$temp_dir/.github/workflows/droid-code-review.yaml"
    if [[ ! -f "$workflow_path" ]]; then
        echo "  ⚠️  Workflow not found in $repo - skipping"
        return
    fi
    
    # Backup the existing workflow
    cp "$workflow_path" "$workflow_path.backup"
    echo "  ✅ Backed up existing workflow"
    
    # Copy the fixed workflow
    cp "$WORKFLOW_FILE" "$workflow_path"
    echo "  ✅ Updated workflow file"
    
    # Check if there are changes
    cd "$temp_dir"
    if git diff --quiet HEAD .github/workflows/droid-code-review.yaml; then
        echo "  ℹ️  No changes needed for $repo"
        cd - > /dev/null
        return
    fi
    
    # Commit and push changes
    echo "  📝 Committing changes..."
    git config user.name "Factory Droid Bot"
    git config user.email "bot@factory.ai"
    
    git add .github/workflows/droid-code-review.yaml
    git commit -m "fix: Resolve GitHub API position validation issues in Droid workflow

- Enhanced position calculation and validation logic
- Added fallback position mapping from diff patches  
- Improved logging for debugging position issues
- Fixed 422 Unprocessable Entity errors for review comments
- Added comprehensive position range validation

Fixes workflow failures in PR review submission."

    echo "  🚀 Pushing changes..."
    git push origin main
    
    echo "  ✅ Successfully updated $repo"
    cd - > /dev/null
}

# Main execution
echo "Checking GitHub authentication..."
if ! gh auth status > /dev/null 2>&1; then
    echo "❌ Not authenticated with GitHub CLI. Please run 'gh auth login' first."
    exit 1
fi

echo "✅ GitHub authentication confirmed"
echo ""

# Check if the source workflow file exists
if [[ ! -f "$WORKFLOW_FILE" ]]; then
    echo "❌ Source workflow file not found: $WORKFLOW_FILE"
    exit 1
fi

# Update each repository
for repo in "${REPOS[@]}"; do
    update_workflow "$repo"
    echo ""
done

echo "🎉 Workflow updates completed!"
echo ""
echo "📋 Summary of fixes applied:"
echo "   • Enhanced position validation with range checking [1, 50000]"
echo "   • Improved position mapping from diff patches"
echo "   • Added comprehensive logging for debugging"
echo "   • Fixed GitHub API 422 Unprocessable Entity errors"
echo "   • Better error handling and fallback mechanisms"
echo ""
echo "🔍 Next steps:"
echo "   1. Monitor the next PR workflows in each repository"
echo "   2. Check that comments are posted successfully"
echo "   3. Verify no more 422 position errors occur"
