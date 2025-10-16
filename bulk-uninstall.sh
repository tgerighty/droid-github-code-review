#!/bin/bash

# Simple bulk uninstallation script for Droid Code Review workflow
# Removes the workflow and cleans up secrets/variables from all your repos

set -euo pipefail

# Configuration
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
    
    print $GREEN "✅ Prerequisites checked"
}

# Get all repos
get_repos() {
    print $BLUE "📂 Getting your repositories..."
    gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner'
}

# Remove repository variable
remove_variable() {
    local repo=$1
    
    if gh variable delete DROID_INSTALLER_SHA256 --repo "$repo" 2>&1 > /dev/null; then
        print $GREEN "    ✓ Removed variable"
    fi
}

# Remove repository secrets
remove_secrets() {
    local repo=$1
    
    gh secret delete FACTORY_API_KEY --repo "$repo" 2>&1 > /dev/null || true
    gh secret delete MODEL_API_KEY --repo "$repo" 2>&1 > /dev/null || true
    print $GREEN "    ✓ Removed secrets"
}

# Uninstall from single repo
uninstall_from_repo() {
    local repo=$1
    local temp_dir=$(mktemp -d)
    
    print $BLUE "🗑️  $repo..."
    
    if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
        cd "$temp_dir"
        
        # Check if workflow exists
        if [[ ! -f "$WORKFLOW_PATH" ]]; then
            print $YELLOW "    ⚠️  Workflow not found"
            cd - > /dev/null
            rm -rf "$temp_dir"
            
            # Still clean up secrets and variables
            remove_variable "$repo"
            remove_secrets "$repo"
            return 0
        fi
        
        # Git setup
        git config user.name "Droid Uninstaller"
        git config user.email "uninstaller@factory.ai"
        
        # Remove workflow file
        git rm "$WORKFLOW_PATH"
        
        if git diff --staged --quiet; then
            print $YELLOW "    ⚠️  No changes needed"
        else
            git commit -m "Remove Droid automated code review workflow"
            
            # Determine default branch
            local default_branch="main"
            if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
                if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
                    default_branch="master"
                fi
            fi
            
            if git push origin "HEAD:${default_branch}"; then
                print $GREEN "    ✅ Removed workflow"
                
                # Remove variable and secrets after successful push
                remove_variable "$repo"
                remove_secrets "$repo"
            else
                print $RED "    ❌ Failed to push"
            fi
        fi
        
        cd - > /dev/null
    else
        print $RED "    ❌ Failed to clone"
    fi
    
    rm -rf "$temp_dir"
}

# Main uninstallation
main() {
    print $BLUE "🗑️  Droid Code Review - Bulk Uninstallation"
    print $BLUE "=========================================="
    echo
    
    check
    echo
    
    print $YELLOW "⚠️  WARNING: This will remove the Droid Code Review workflow from ALL repositories"
    print $YELLOW "⚠️  It will also remove associated secrets and variables"
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print $YELLOW "❌ Uninstallation cancelled"
        exit 0
    fi
    
    echo
    
    local repos=()
    while IFS= read -r repo; do
        repos+=("$repo")
    done < <(get_repos)
    
    print $BLUE "📊 Found ${#repos[@]} repositories"
    echo
    
    local success=0
    local failed=0
    
    for repo in "${repos[@]}"; do
        if uninstall_from_repo "$repo"; then
            ((success++))
        else
            ((failed++))
        fi
        sleep 1 # Avoid rate limiting
    done
    
    echo
    print $GREEN "🎉 Uninstallation complete!"
    print $GREEN "✅ Success: $success"
    if [[ $failed -gt 0 ]]; then
        print $RED "❌ Failed: $failed"
    fi
    echo
    print $GREEN "✅ Cleaned up:"
    print $GREEN "   • Workflow files removed"
    print $GREEN "   • DROID_INSTALLER_SHA256 variables deleted"
    print $GREEN "   • FACTORY_API_KEY secrets deleted"
    print $GREEN "   • MODEL_API_KEY secrets deleted"
}

main "$@"
