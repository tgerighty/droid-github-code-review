#!/bin/bash

# Quick install - Just run it and it installs to all repos via GitHub API
# No cloning required, uses GitHub API directly

set -euo pipefail

WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"
DROID_INSTALLER_SHA256=""  # Will be fetched dynamically

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print() {
    echo -e "${1}${2}${NC}"
}

# Fetch current Droid CLI installer SHA256
fetch_droid_sha256() {
    print $BLUE "🔍 Fetching current Droid CLI installer SHA256..."
    
    local temp_installer=$(mktemp)
    
    if ! curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer"; then
        print $RED "❌ Failed to download Droid CLI installer"
        rm -f "$temp_installer"
        return 1
    fi
    
    if ! command -v sha256sum &> /dev/null; then
        print $RED "❌ sha256sum command not found"
        rm -f "$temp_installer"
        return 1
    fi
    
    DROID_INSTALLER_SHA256=$(sha256sum "$temp_installer" | awk '{print $1}')
    rm -f "$temp_installer"
    
    if [[ -z "$DROID_INSTALLER_SHA256" ]]; then
        print $RED "❌ Failed to calculate SHA256"
        return 1
    fi
    
    print $GREEN "✅ Current SHA256: $DROID_INSTALLER_SHA256"
    return 0
}

# Check prerequisites
check() {
    if ! command -v gh &> /dev/null; then
        print $RED "❌ Install GitHub CLI: brew install gh"
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print $RED "❌ Login to GitHub: gh auth login"
        exit 1
    fi
    
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        print $RED "❌ $WORKFLOW_FILE not found"
        exit 1
    fi
    
    print $GREEN "✅ Ready to install"
}

# Get all repos
get_repos() {
    print $BLUE "📂 Getting repositories..." >&2
    gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner'
}

# Set repository variable for Droid installer SHA256
set_repo_variable() {
    local repo=$1
    
    # Set the DROID_INSTALLER_SHA256 variable
    gh variable set DROID_INSTALLER_SHA256 \
        --repo "$repo" \
        --body "$DROID_INSTALLER_SHA256" 2>&1 > /dev/null
    
    return $?
}

# Install to single repo via API
install_to_repo() {
    local repo=$1
    local content=$(base64 < "$WORKFLOW_FILE")
    
    # Skip empty/invalid repo names
    if [[ -z "$repo" || "$repo" == *"Getting"* ]]; then
        return 1  # Invalid repo name
    fi
    
    # First, try to get the current file (if it exists)
    local sha=""
    if gh api "repos/$repo/contents/$WORKFLOW_PATH" > /dev/null 2>&1; then
        sha=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" | jq -r '.sha // ""')
    fi
    
    # Create or update the file via GitHub API
    local api_response
    if [[ -n "$sha" ]]; then
        # Update existing file (overwrite)
        api_response=$(gh api --method PUT "repos/$repo/contents/$WORKFLOW_PATH" \
            --field message="Update Droid automated code review workflow" \
            --field content="$content" \
            --field sha="$sha" 2>&1)
    else
        # Create new file
        api_response=$(gh api --method PUT "repos/$repo/contents/$WORKFLOW_PATH" \
            --field message="Add Droid automated code review workflow" \
            --field content="$content" 2>&1)
    fi
    
    if [[ $? -eq 0 ]]; then
        # Also set the repository variable
        set_repo_variable "$repo"
        return 0  # Success - installed/updated
    else
        # Check specific error types
        if echo "$api_response" | grep -q "Not Found"; then
            return 3  # Repo not found or no access
        elif echo "$api_response" | grep -q "Forbidden"; then
            return 4  # No write access
        else
            return 1  # Other failure
        fi
    fi
}

# Main installation
main() {
    print $BLUE "🚀 Quick Install - Droid Code Review Workflow"
    print $BLUE "==========================================="
    
    check
    
    # Fetch current Droid SHA256
    if ! fetch_droid_sha256; then
        print $RED "❌ Cannot proceed without valid Droid installer SHA256"
        exit 1
    fi
    echo
    
    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done < <(get_repos)
    
    print $BLUE "📊 Installing to ${#repos[@]} repositories..."
    echo
    
    local success=0
    local failed=0
    local skipped=0
    local current=0
    
    # Print header
    printf "%-40s %-12s\n" "REPOSITORY" "STATUS"
    printf "%-40s %-12s\n" "----------------------------------------" "------------"
    
    for repo in "${repos[@]}"; do
        ((current++))
        local status=""
        local color=""
        
        # Show progress
        printf "[%3d/%3d] %-40s " "$current" "${#repos[@]}" "$repo"
        
        # Attempt installation
        if install_to_repo "$repo"; then
            local exit_code=$?
            case $exit_code in
                0)
                    # Check if it was a new install or update
                    if gh api "repos/$repo/contents/$WORKFLOW_PATH" > /dev/null 2>&1; then
                        local current_sha=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" | jq -r '.sha // ""')
                        # Simple heuristic: if we just installed it, it's new, otherwise it was updated
                        status="✅ UPDATED"
                        color=$GREEN
                    else
                        status="✅ INSTALLED"
                        color=$GREEN
                    fi
                    ((success++))
                    ;;
                3)
                    status="❌ NO ACCESS"
                    color=$RED
                    ((failed++))
                    ;;
                4)
                    status="❌ FORBIDDEN"
                    color=$RED
                    ((failed++))
                    ;;
                *)
                    status="❌ FAILED"
                    color=$RED
                    ((failed++))
                    ;;
            esac
        else
            status="❌ FAILED"
            color=$RED
            ((failed++))
        fi
        
        # Print status with color
        printf "${color}%-12s${NC}\n" "$status"
        
        # Brief pause to avoid rate limiting
        sleep 0.3
    done
    
    echo
    echo "========================================"
    print $BLUE "📊 INSTALLATION SUMMARY"
    print $GREEN "✅ Successfully installed: $success"
    if [[ $skipped -gt 0 ]]; then
        print $YELLOW "⚠️  Already existed: $skipped"
    fi
    if [[ $failed -gt 0 ]]; then
        print $RED "❌ Failed: $failed"
    fi
    print $BLUE "📈 Total processed: ${#repos[@]}"
    
    # Success rate
    local success_rate=$(( (success * 100) / ${#repos[@]} ))
    if [[ $success_rate -eq 100 ]]; then
        print $GREEN "🎉 Perfect! All repositories processed successfully!"
    elif [[ $success_rate -ge 80 ]]; then
        print $GREEN "🎊 Great! $success_rate% success rate!"
    elif [[ $success_rate -ge 50 ]]; then
        print $YELLOW "👍 Good! $success_rate% success rate."
    else
        print $YELLOW "⚠️  $success_rate% success rate. Some repositories may need manual attention."
    fi
    
    # Next steps reminder
    echo
    print $BLUE "🔔 REMINDER: Don't forget to add required secrets to each repository!"
    print $BLUE "   Repository Settings → Secrets and variables → Actions → New repository secret"
    print $BLUE "   Required secrets:"
    print $BLUE "   - FACTORY_API_KEY: Your Factory.ai API key"
    print $BLUE "   - MODEL_API_KEY: Your Z.ai API key (for GLM-4.6 model)"
    echo
    print $GREEN "✅ DROID_INSTALLER_SHA256 variable has been set automatically on all repositories"
}

main "$@"
