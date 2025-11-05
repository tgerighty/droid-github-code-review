#!/bin/bash

# =============================================================================
# Smart Update Script for Droid Code Review
# =============================================================================
#
# Description: Intelligently updates repositories with minimal changes
#              - SHA256-only updates: Only updates the DROID_INSTALLER_SHA256 variable
#              - Full updates: Updates both workflow file and SHA256 variable
# Author: Factory AI
# Date: 2025-01-05
# Version: 1.0
#
# Usage: ./smart-update.sh [--force-full] [--sha256-only]
#        --force-full: Force full workflow update even if only SHA256 changed
#        --sha256-only: Only update SHA256, skip workflow comparison
#
# Dependencies: GitHub CLI (gh), jq, curl, git
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Global Variables
# -----------------------------------------------------------------------------
WORKFLOW_FILE="droid-code-review-v2.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"
DROID_INSTALLER_SHA256=""
FORCE_FULL=false
SHA256_ONLY=false

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
SHA256_UPDATED=0
WORKFLOW_UPDATED=0
NO_CHANGE=0
FAILED=0

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

print() {
    echo -e "${1}${2}${NC}"
}

error_exit() {
    print $RED "❌ ERROR: $1"
    exit 1
}

# -----------------------------------------------------------------------------
# Function: parse_args
# Description: Parse command line arguments
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-full)
                FORCE_FULL=true
                shift
                ;;
            --sha256-only)
                SHA256_ONLY=true
                shift
                ;;
            --help|-h)
                cat << EOF
Usage: $0 [OPTIONS]

Smart update script for Droid Code Review workflow across all repositories.

Options:
  --force-full    Force full workflow update even if only SHA256 changed
  --sha256-only   Only update SHA256 variable, skip workflow comparison
  --help, -h      Show this help message

Examples:
  $0                  # Smart update (SHA256 only if workflow unchanged)
  $0 --force-full     # Force full workflow update
  $0 --sha256-only    # Only update SHA256 variable

EOF
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Function: check_prerequisites
# Description: Check if all required tools are available
# -----------------------------------------------------------------------------
check_prerequisites() {
    if ! command -v gh &> /dev/null; then
        error_exit "Install GitHub CLI: brew install gh"
    fi
    
    if ! gh auth status &> /dev/null; then
        error_exit "Login to GitHub: gh auth login"
    fi
    
    if ! command -v jq &> /dev/null; then
        error_exit "Install jq: brew install jq"
    fi
    
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        error_exit "$WORKFLOW_FILE not found"
    fi
    
    print $GREEN "✅ Prerequisites checked"
}

# -----------------------------------------------------------------------------
# Function: fetch_droid_sha256
# Description: Fetch current SHA256 hash of Droid CLI installer
# -----------------------------------------------------------------------------
fetch_droid_sha256() {
    print $BLUE "🔍 Fetching current Droid CLI installer SHA256..."
    
    local temp_installer=$(mktemp)
    
    if ! curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer" 2>/dev/null; then
        rm -f "$temp_installer"
        error_exit "Failed to download Droid CLI installer"
    fi
    
    # Verify download integrity
    if [[ ! -s "$temp_installer" ]]; then
        rm -f "$temp_installer"
        error_exit "Downloaded file is empty"
    fi
    
    # Check if file starts with shebang
    local first_two_bytes=$(head -c 2 "$temp_installer")
    if [[ "$first_two_bytes" != "#!" ]]; then
        rm -f "$temp_installer"
        error_exit "Downloaded file does not appear to be a valid script"
    fi
    
    # Use shasum on macOS, sha256sum on Linux
    local sha_cmd=""
    if command -v sha256sum &> /dev/null; then
        sha_cmd="sha256sum"
    elif command -v shasum &> /dev/null; then
        sha_cmd="shasum -a 256"
    else
        rm -f "$temp_installer"
        error_exit "Neither sha256sum nor shasum command found"
    fi
    
    DROID_INSTALLER_SHA256=$($sha_cmd "$temp_installer" | awk '{print $1}')
    rm -f "$temp_installer"
    
    if [[ -z "$DROID_INSTALLER_SHA256" ]]; then
        error_exit "Failed to calculate SHA256"
    fi
    
    if [[ ! "$DROID_INSTALLER_SHA256" =~ ^[a-f0-9]{64}$ ]]; then
        error_exit "Invalid SHA256 format: $DROID_INSTALLER_SHA256"
    fi
    
    print $GREEN "✅ Current SHA256: $DROID_INSTALLER_SHA256"
}

# -----------------------------------------------------------------------------
# Function: get_repos
# Description: Get all accessible repositories
# -----------------------------------------------------------------------------
get_repos() {
    print $BLUE "📂 Getting repositories..." >&2
    gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner'
}

# -----------------------------------------------------------------------------
# Function: validate_repo
# Description: Validate repository format
# -----------------------------------------------------------------------------
validate_repo() {
    local repo="$1"
    [[ "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
}

# -----------------------------------------------------------------------------
# Function: get_current_sha256
# Description: Get the current SHA256 variable from a repository
# -----------------------------------------------------------------------------
get_current_sha256() {
    local repo="$1"
    gh variable get DROID_INSTALLER_SHA256 --repo "$repo" 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# Function: set_repo_sha256
# Description: Set the DROID_INSTALLER_SHA256 variable for a repository
# -----------------------------------------------------------------------------
set_repo_sha256() {
    local repo="$1"
    
    gh variable set DROID_INSTALLER_SHA256 \
        --repo "$repo" \
        --body "$DROID_INSTALLER_SHA256" 2>&1 > /dev/null
}

# -----------------------------------------------------------------------------
# Function: get_remote_workflow_sha
# Description: Get the SHA of the current workflow file in the repository
# -----------------------------------------------------------------------------
get_remote_workflow_sha() {
    local repo="$1"
    
    local response=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        echo "$response" | jq -r '.sha // ""'
    else
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# Function: workflows_are_identical
# Description: Compare local workflow file with remote repository workflow
# -----------------------------------------------------------------------------
workflows_are_identical() {
    local repo="$1"
    
    # Get remote workflow content
    local remote_content=$(gh api "repos/$repo/contents/$WORKFLOW_PATH" 2>/dev/null | jq -r '.content // ""')
    if [[ -z "$remote_content" ]]; then
        return 1  # Remote workflow doesn't exist
    fi
    
    # Decode remote content (it's base64 encoded)
    local remote_decoded=$(echo "$remote_content" | base64 -d 2>/dev/null)
    if [[ -z "$remote_decoded" ]]; then
        return 1  # Failed to decode
    fi
    
    # Get local content
    local local_content=$(cat "$WORKFLOW_FILE")
    
    # Compare (ignoring whitespace differences)
    if [[ "$(echo "$remote_decoded" | tr -d '[:space:]')" == "$(echo "$local_content" | tr -d '[:space:]')" ]]; then
        return 0  # Identical
    else
        return 1  # Different
    fi
}

# -----------------------------------------------------------------------------
# Function: update_workflow_file
# Description: Update the workflow file in a repository via GitHub API
# -----------------------------------------------------------------------------
update_workflow_file() {
    local repo="$1"
    local content=$(base64 < "$WORKFLOW_FILE")
    
    # Get current file SHA if it exists
    local sha=$(get_remote_workflow_sha "$repo")
    
    # Create or update the file via GitHub API
    if [[ -n "$sha" ]]; then
        # Update existing file
        gh api --method PUT "repos/$repo/contents/$WORKFLOW_PATH" \
            --field message="Update Droid automated code review workflow" \
            --field content="$content" \
            --field sha="$sha" 2>&1 > /dev/null
    else
        # Create new file
        gh api --method PUT "repos/$repo/contents/$WORKFLOW_PATH" \
            --field message="Add Droid automated code review workflow" \
            --field content="$content" 2>&1 > /dev/null
    fi
}

# -----------------------------------------------------------------------------
# Function: smart_update_repo
# Description: Intelligently update a repository (SHA256 only or full update)
# -----------------------------------------------------------------------------
smart_update_repo() {
    local repo="$1"
    
    # Validate repository format
    if ! validate_repo "$repo"; then
        print $RED "  ❌ Invalid format"
        ((FAILED++))
        return 1
    fi
    
    # Get current SHA256 from repository
    local current_sha256=$(get_current_sha256 "$repo")
    
    # Check if SHA256 needs updating
    local sha256_needs_update=false
    if [[ "$current_sha256" != "$DROID_INSTALLER_SHA256" ]]; then
        sha256_needs_update=true
    fi
    
    # Determine update strategy
    local update_type="none"
    
    if [[ "$SHA256_ONLY" == "true" ]]; then
        # SHA256-only mode
        if [[ "$sha256_needs_update" == "true" ]]; then
            update_type="sha256"
        fi
    elif [[ "$FORCE_FULL" == "true" ]]; then
        # Force full update
        update_type="full"
    else
        # Smart mode: check if workflows are identical
        if workflows_are_identical "$repo"; then
            # Workflows identical, only update SHA256 if needed
            if [[ "$sha256_needs_update" == "true" ]]; then
                update_type="sha256"
            fi
        else
            # Workflows different, do full update
            update_type="full"
        fi
    fi
    
    # Perform update based on strategy
    case "$update_type" in
        sha256)
            if set_repo_sha256 "$repo"; then
                print $CYAN "  ⚡ SHA256 updated"
                ((SHA256_UPDATED++))
                return 0
            else
                print $RED "  ❌ SHA256 update failed"
                ((FAILED++))
                return 1
            fi
            ;;
        full)
            if update_workflow_file "$repo" && set_repo_sha256 "$repo"; then
                print $GREEN "  ✅ Full update"
                ((WORKFLOW_UPDATED++))
                return 0
            else
                print $RED "  ❌ Full update failed"
                ((FAILED++))
                return 1
            fi
            ;;
        none)
            print $YELLOW "  ⏭️  No changes needed"
            ((NO_CHANGE++))
            return 0
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Function: main
# Description: Main execution function
# -----------------------------------------------------------------------------
main() {
    print $BLUE "🚀 Smart Update - Droid Code Review Workflow"
    print $BLUE "============================================="
    echo
    
    # Parse command line arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    echo
    
    # Fetch current Droid SHA256
    if ! fetch_droid_sha256; then
        error_exit "Cannot proceed without valid Droid installer SHA256"
    fi
    echo
    
    # Display update mode
    if [[ "$SHA256_ONLY" == "true" ]]; then
        print $YELLOW "📋 Mode: SHA256 variable update only"
    elif [[ "$FORCE_FULL" == "true" ]]; then
        print $YELLOW "📋 Mode: Force full workflow update"
    else
        print $CYAN "📋 Mode: Smart update (minimal changes)"
    fi
    echo
    
    # Get all repositories
    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done < <(get_repos)
    
    print $BLUE "📊 Processing ${#repos[@]} repositories..."
    echo
    
    # Print header
    printf "%-50s %-20s\n" "REPOSITORY" "STATUS"
    printf "%-50s %-20s\n" "$(printf '%.0s-' {1..50})" "$(printf '%.0s-' {1..20})"
    
    local current=0
    for repo in "${repos[@]}"; do
        ((current++))
        printf "[%3d/%3d] %-50s" "$current" "${#repos[@]}" "${repo:0:50}"
        
        smart_update_repo "$repo"
        
        # Brief pause to avoid rate limiting
        sleep 0.2
    done
    
    echo
    echo "========================================"
    print $BLUE "📊 UPDATE SUMMARY"
    echo
    print $CYAN "⚡ SHA256 only updates: $SHA256_UPDATED"
    print $GREEN "✅ Full workflow updates: $WORKFLOW_UPDATED"
    print $YELLOW "⏭️  No changes needed: $NO_CHANGE"
    if [[ $FAILED -gt 0 ]]; then
        print $RED "❌ Failed: $FAILED"
    fi
    print $BLUE "📈 Total processed: ${#repos[@]}"
    echo
    
    # Calculate success rate
    local total_updates=$((SHA256_UPDATED + WORKFLOW_UPDATED + NO_CHANGE))
    local success_rate=$(( (total_updates * 100) / ${#repos[@]} ))
    
    if [[ $success_rate -eq 100 ]]; then
        print $GREEN "🎉 Perfect! All repositories processed successfully!"
    elif [[ $success_rate -ge 80 ]]; then
        print $GREEN "🎊 Great! $success_rate% success rate!"
    elif [[ $success_rate -ge 50 ]]; then
        print $YELLOW "👍 Good! $success_rate% success rate."
    else
        print $YELLOW "⚠️  $success_rate% success rate. Some repositories may need manual attention."
    fi
    echo
    
    # Summary of what was done
    print $BLUE "🔍 What happened:"
    if [[ $SHA256_UPDATED -gt 0 ]]; then
        print $CYAN "   • $SHA256_UPDATED repositories: SHA256 variable updated (workflow unchanged)"
    fi
    if [[ $WORKFLOW_UPDATED -gt 0 ]]; then
        print $GREEN "   • $WORKFLOW_UPDATED repositories: Full update (workflow + SHA256)"
    fi
    if [[ $NO_CHANGE -gt 0 ]]; then
        print $YELLOW "   • $NO_CHANGE repositories: Already up to date"
    fi
    if [[ $FAILED -gt 0 ]]; then
        print $RED "   • $FAILED repositories: Failed to update"
    fi
}

# Run main function with all arguments
main "$@"
