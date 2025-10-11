#!/bin/bash

# Simple bulk installation script for Droid Code Review workflow
# Just run it and it will install to all your repos

set -euo pipefail

# Configuration
WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print() {
    echo -e "${1}${2}${NC}"
}

# Check prerequisites
check() {
    if ! command -v gh &> /dev/null; then
        print $RED "❌ Install GitHub CLI first: brew install gh"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print $RED "❌ Login to GitHub first: gh auth login"
        exit 1
    fi
    
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        print $RED "❌ droid-code-review.yaml not found in current directory"
        exit 1
    fi
    
    print $GREEN "✅ Prerequisites checked"
}

# Get all repos
get_repos() {
    print $BLUE "📂 Getting your repositories..."
    gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner'
}

# Install to single repo
install_to_repo() {
    local repo=$1
    local temp_dir=$(mktemp -d)
    
    print $BLUE "🔄 $repo..."
    
    if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
        cd "$temp_dir"
        
        # Create workflow directory
        mkdir -p .github/workflows
        
        # Copy workflow file
        cp "$OLDPWD/$WORKFLOW_FILE" "$WORKFLOW_PATH"
        
        # Git setup
        git config user.name "Droid Installer"
        git config user.email "installer@factory.ai"
        
        # Commit and push
        git add "$WORKFLOW_PATH"
        if git diff --staged --quiet; then
            print $YELLOW "  ⚠️  No changes needed"
        else
            git commit -m "Add Droid automated code review workflow"
            git push
            
            print $GREEN "  ✅ Installed"
        fi
        
        cd - > /dev/null
    else
        print $RED "  ❌ Failed to clone"
    fi
    
    rm -rf "$temp_dir"
}

# Main installation
main() {
    print $BLUE "🚀 Droid Code Review - Bulk Installation"
    print $BLUE "========================================"
    
    check
    
    local repos=()
    while IFS= read -r repo; do
        repos+=("$repo")
    done < <(get_repos)
    
    print $BLUE "📊 Found ${#repos[@]} repositories"
    echo
    
    local success=0
    local failed=0
    
    for repo in "${repos[@]}"; do
        if install_to_repo "$repo"; then
            ((success++))
        else
            ((failed++))
        fi
        sleep 1 # Avoid rate limiting
    done
    
    echo
    print $GREEN "🎉 Installation complete!"
    print $GREEN "✅ Success: $success"
    if [[ $failed -gt 0 ]]; then
        print $RED "❌ Failed: $failed"
    fi
}

main "$@"
