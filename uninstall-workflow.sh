#!/bin/bash

# Droid Code Review Workflow Uninstallation Script
# This script removes the droid-code-review.yaml workflow from repositories
# and cleans up associated secrets and variables

set -euo pipefail

# Configuration
WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"
LOG_FILE="workflow-uninstallation.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" >&2
}

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}" >&2
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v gh &> /dev/null; then
        print_status $RED "❌ GitHub CLI (gh) is not installed. Please install it first."
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_status $RED "❌ Not authenticated with GitHub CLI. Run 'gh auth login' first."
        exit 1
    fi
    
    print_status $GREEN "✅ Prerequisites check passed"
    log "Prerequisites check passed"
}

# Remove repository variable
remove_repo_variable() {
    local repo=$1
    
    log "Attempting to remove DROID_INSTALLER_SHA256 variable from $repo"
    
    if gh variable delete DROID_INSTALLER_SHA256 --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed DROID_INSTALLER_SHA256 variable"
        log "Removed DROID_INSTALLER_SHA256 variable from $repo"
        return 0
    else
        print_status $YELLOW "  ⚠️  Variable DROID_INSTALLER_SHA256 not found or already removed"
        log "Variable DROID_INSTALLER_SHA256 not found in $repo"
        return 1
    fi
}

# Remove repository secrets
remove_repo_secrets() {
    local repo=$1
    local secrets_removed=0
    
    log "Attempting to remove secrets from $repo"
    
    # Remove FACTORY_API_KEY secret
    if gh secret delete FACTORY_API_KEY --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed FACTORY_API_KEY secret"
        log "Removed FACTORY_API_KEY secret from $repo"
        ((secrets_removed++))
    else
        print_status $YELLOW "  ⚠️  Secret FACTORY_API_KEY not found or already removed"
        log "Secret FACTORY_API_KEY not found in $repo"
    fi
    
    # Remove MODEL_API_KEY secret
    if gh secret delete MODEL_API_KEY --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed MODEL_API_KEY secret"
        log "Removed MODEL_API_KEY secret from $repo"
        ((secrets_removed++))
    else
        print_status $YELLOW "  ⚠️  Secret MODEL_API_KEY not found or already removed"
        log "Secret MODEL_API_KEY not found in $repo"
    fi
    
    if [[ $secrets_removed -gt 0 ]]; then
        print_status $GREEN "  ✓ Removed $secrets_removed secret(s)"
    fi
    
    return 0
}

# Remove workflow from a single repository
uninstall_workflow_from_repo() {
    local repo=$1
    local keep_backup=${2:-false}
    
    log "Processing repository: $repo"
    print_status $BLUE "🔄 Processing $repo..."
    
    # Create temp directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" RETURN
    
    # Clone the repository
    if ! gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
        print_status $RED "❌ Failed to clone $repo"
        log "Failed to clone $repo"
        return 1
    fi
    
    cd "$temp_dir"
    
    # Check if workflow exists
    if [[ ! -f "$WORKFLOW_PATH" ]]; then
        print_status $YELLOW "  ⚠️  Workflow not found in $repo"
        log "Workflow not found in $repo"
        cd - > /dev/null
        
        # Still try to clean up secrets and variables
        print_status $BLUE "  🧹 Cleaning up secrets and variables..."
        remove_repo_variable "$repo"
        remove_repo_secrets "$repo"
        
        return 0
    fi
    
    # Configure git
    git config user.name "Droid Workflow Uninstaller"
    git config user.email "workflow-uninstaller@factory.ai"
    
    local backup_path=".github/workflows/backup/$WORKFLOW_FILE"
    local commit_message="Remove Droid automated code review workflow"
    
    if [[ "$keep_backup" == "true" ]]; then
        # Create backup before removing
        mkdir -p "$(dirname "$backup_path")"
        cp "$WORKFLOW_PATH" "$backup_path"
        git add "$backup_path"
        commit_message="Remove Droid automated code review workflow (backup created)"
        print_status $YELLOW "  📦 Created backup at $backup_path"
        log "Created backup in $repo"
    fi
    
    # Remove the workflow file
    git rm "$WORKFLOW_PATH"
    
    # Commit the changes
    if git diff --staged --quiet; then
        print_status $YELLOW "  ⚠️  No changes to commit"
        log "No changes to commit in $repo"
        cd - > /dev/null
        return 0
    fi
    
    git commit -m "$commit_message"
    
    # Determine default branch
    local default_branch="main"
    if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
        if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
            default_branch="master"
        else
            print_status $RED "  ❌ Could not determine default branch (main/master) for $repo"
            log "Default branch detection failed for $repo"
            cd - > /dev/null
            return 1
        fi
    fi
    
    # Push changes
    if ! git push origin "HEAD:${default_branch}"; then
        print_status $RED "  ❌ Failed to push changes to ${default_branch}"
        log "Push to ${default_branch} failed for $repo"
        cd - > /dev/null
        return 1
    fi
    
    print_status $GREEN "  ✅ Removed workflow from $repo"
    log "Removed workflow from $repo"
    
    cd - > /dev/null
    
    # Remove repository variable and secrets
    print_status $BLUE "  🧹 Cleaning up secrets and variables..."
    remove_repo_variable "$repo"
    remove_repo_secrets "$repo"
    
    print_status $GREEN "✅ Completed $repo"
    log "Completed processing $repo"
    return 0
}

# Get all repositories for the authenticated user
get_repositories() {
    log "Fetching repositories..."
    
    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done < <(gh repo list --limit 1000 --json nameWithOwner --source --no-archived | jq -r '.[].nameWithOwner' 2>/dev/null || true)

    print_status $BLUE "📂 Fetched ${#repos[@]} repositories..."
    
    log "Found ${#repos[@]} repositories"
    printf '%s\n' "${repos[@]}"
}

# Uninstall from all repositories
uninstall_from_all_repos() {
    local keep_backup=${1:-false}
    
    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done < <(get_repositories)
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        print_status $YELLOW "⚠️  No repositories found to process"
        log "No repositories returned by get_repositories"
        return
    fi
    
    local total=${#repos[@]}
    local success=0
    local failed=0
    
    print_status $BLUE "🗑️  Starting workflow uninstallation across $total repositories..."
    log "Starting workflow uninstallation across $total repositories"
    
    if [[ "$keep_backup" == "true" ]]; then
        print_status $YELLOW "📦 Backup mode enabled - workflow files will be backed up"
    fi
    
    for i in "${!repos[@]}"; do
        local repo="${repos[$i]}"
        local progress=$((i + 1))
        
        print_status $BLUE "[$progress/$total] Processing $repo..."
        
        if uninstall_workflow_from_repo "$repo" "$keep_backup"; then
            ((success++))
        else
            ((failed++))
        fi
        
        # Small delay to avoid rate limiting
        sleep 1
    done
    
    # Summary
    echo
    print_status $GREEN "🎉 Uninstallation completed!"
    echo -e "${GREEN}✅ Successful: $success${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}❌ Failed: $failed${NC}"
    fi
    echo -e "${BLUE}📊 Total: $total${NC}"
    
    log "Uninstallation completed - Success: $success, Failed: $failed, Total: $total"
}

# Interactive repository selection
select_repositories() {
    local repos=()
    while IFS= read -r repo; do
        [[ -n "$repo" ]] && repos+=("$repo")
    done < <(get_repositories)
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        print_status $YELLOW "⚠️  No repositories available for selection"
        return
    fi
    
    print_status $BLUE "📋 Available repositories:"
    for i in "${!repos[@]}"; do
        echo "  $((i + 1)). ${repos[$i]}"
    done
    
    echo
    read -p "Enter repository numbers to uninstall from (e.g., 1,3,5-8) or 'all' for all: " selection
    
    if [[ "$selection" == "all" ]]; then
        printf '%s\n' "${repos[@]}"
        return
    fi
    
    local selected_repos=()
    IFS=',' read -ra selections <<< "$selection"
    
    for sel in "${selections[@]}"; do
        if [[ "$sel" =~ ^[0-9]+$ ]]; then
            local idx=$((sel - 1))
            if [[ $idx -ge 0 && $idx -lt ${#repos[@]} ]]; then
                selected_repos+=("${repos[$idx]}")
            fi
        elif [[ "$sel" =~ ^[0-9]+-[0-9]+$ ]]; then
            local start=$(echo "$sel" | cut -d'-' -f1)
            local end=$(echo "$sel" | cut -d'-' -f2)
            start=$((start - 1))
            end=$((end - 1))
            
            for ((i=start; i<=end && i<${#repos[@]}; i++)); do
                if [[ $i -ge 0 ]]; then
                    selected_repos+=("${repos[$i]}")
                fi
            done
        fi
    done
    
    printf '%s\n' "${selected_repos[@]}"
}

# Show usage
usage() {
    cat << EOF
Droid Code Review Workflow Uninstallation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -b, --backup        Keep a backup copy of the workflow file
    -i, --interactive   Select repositories interactively
    -r, --repos REPOS   Comma-separated list of repositories (e.g., owner/repo1,owner/repo2)
    --dry-run           Show what would be done without making changes

EXAMPLES:
    $0                              # Uninstall from all repositories
    $0 --backup                     # Uninstall but keep backup in repos
    $0 --interactive                # Select repositories interactively
    $0 --repos "owner/repo1,owner/repo2"  # Uninstall from specific repos
    $0 --dry-run                    # Preview uninstallation

WHAT GETS REMOVED:
    - .github/workflows/droid-code-review.yaml file
    - DROID_INSTALLER_SHA256 repository variable
    - FACTORY_API_KEY repository secret
    - MODEL_API_KEY repository secret

REQUIREMENTS:
    - GitHub CLI (gh) installed and authenticated
    - Admin access to target repositories

EOF
}

# Main script
main() {
    local keep_backup=false
    local interactive=false
    local specific_repos=""
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -b|--backup)
                keep_backup=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -r|--repos)
                specific_repos="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            *)
                print_status $RED "❌ Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Initialize log
    log "=== Droid Workflow Uninstallation Started ==="
    log "Backup mode: $keep_backup"
    log "Interactive mode: $interactive"
    log "Specific repos: $specific_repos"
    log "Dry run: $dry_run"
    
    check_prerequisites
    
    if [[ "$dry_run" == "true" ]]; then
        print_status $BLUE "🔍 DRY RUN MODE - No changes will be made"
        local repos=()
        while IFS= read -r repo; do
            [[ -n "$repo" ]] && repos+=("$repo")
        done < <(get_repositories)
        print_status $BLUE "Would uninstall workflow from ${#repos[@]} repositories:"
        printf '%s\n' "${repos[@]}"
        echo
        print_status $BLUE "Would remove from each repository:"
        print_status $BLUE "  • .github/workflows/droid-code-review.yaml"
        print_status $BLUE "  • DROID_INSTALLER_SHA256 variable"
        print_status $BLUE "  • FACTORY_API_KEY secret"
        print_status $BLUE "  • MODEL_API_KEY secret"
        exit 0
    fi
    
    echo
    print_status $YELLOW "⚠️  WARNING: This will remove the Droid Code Review workflow and associated secrets/variables"
    if [[ "$keep_backup" == "false" ]]; then
        print_status $YELLOW "⚠️  No backup will be kept (use --backup to keep a copy)"
    fi
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_status $YELLOW "❌ Uninstallation cancelled"
        exit 0
    fi
    
    echo
    
    if [[ "$interactive" == "true" ]]; then
        local repos=()
        while IFS= read -r repo; do
            [[ -n "$repo" ]] && repos+=("$repo")
        done < <(select_repositories)
        
        if [[ ${#repos[@]} -eq 0 ]]; then
            print_status $YELLOW "⚠️  No repositories selected"
            exit 0
        fi
        
        print_status $BLUE "🗑️  Uninstalling from ${#repos[@]} selected repositories..."
        
        local success=0
        local failed=0
        
        for repo in "${repos[@]}"; do
            if uninstall_workflow_from_repo "$repo" "$keep_backup"; then
                ((success++))
            else
                ((failed++))
            fi
            sleep 1
        done
        
        echo
        print_status $GREEN "🎉 Uninstallation completed!"
        echo -e "${GREEN}✅ Successful: $success${NC}"
        if [[ $failed -gt 0 ]]; then
            echo -e "${RED}❌ Failed: $failed${NC}"
        fi
        
    elif [[ -n "$specific_repos" ]]; then
        IFS=',' read -ra repos_list <<< "$specific_repos"
        print_status $BLUE "🗑️  Uninstalling from ${#repos_list[@]} specified repositories..."
        
        local success=0
        local failed=0
        
        for repo in "${repos_list[@]}"; do
            repo=$(echo "$repo" | xargs) # Trim whitespace
            if uninstall_workflow_from_repo "$repo" "$keep_backup"; then
                ((success++))
            else
                ((failed++))
            fi
            sleep 1
        done
        
        echo
        print_status $GREEN "🎉 Uninstallation completed!"
        echo -e "${GREEN}✅ Successful: $success${NC}"
        if [[ $failed -gt 0 ]]; then
            echo -e "${RED}❌ Failed: $failed${NC}"
        fi
    else
        uninstall_from_all_repos "$keep_backup"
    fi
    
    echo
    print_status $GREEN "✅ All done!"
    log "=== Droid Workflow Uninstallation Completed ==="
}

# Run main function with all arguments
main "$@"
