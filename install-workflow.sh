#!/bin/bash

# Droid Code Review Workflow Installation Script
# This script installs the droid-code-review.yaml workflow across all repositories

set -euo pipefail

# Configuration
WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_DIR=".github/workflows"
BACKUP_DIR=".github/workflows/backup"
LOG_FILE="workflow-installation.log"

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
    
    if [[ ! -f "$WORKFLOW_FILE" ]]; then
        print_status $RED "❌ Workflow file '$WORKFLOW_FILE' not found in current directory."
        exit 1
    fi
    
    print_status $GREEN "✅ Prerequisites check passed"
    log "Prerequisites check passed"
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

# Install workflow in a single repository
install_workflow_in_repo() {
    local repo=$1
    local force=${2:-false}
    
    log "Processing repository: $repo"
    
    # Create temp directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" RETURN
    
    print_status $BLUE "🔄 Cloning $repo..."
    
    # Clone the repository
    if ! gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch; then
        print_status $RED "❌ Failed to clone $repo"
        log "Failed to clone $repo"
        return 1
    fi
    
    cd "$temp_dir"
    
    # Create .github/workflows directory if it doesn't exist
    mkdir -p "$WORKFLOW_DIR"
    
    # Check if workflow already exists
    local workflow_path="$WORKFLOW_DIR/$WORKFLOW_FILE"
    local backup_path="$BACKUP_DIR/$WORKFLOW_FILE"
    
    if [[ -f "$workflow_path" ]]; then
        if [[ "$force" == "true" ]]; then
            # Create backup directory and backup existing file
            mkdir -p "$BACKUP_DIR"
            cp "$workflow_path" "$backup_path"
            print_status $YELLOW "⚠️  Backed up existing workflow to $backup_path"
            log "Backed up existing workflow in $repo"
        else
            print_status $YELLOW "⚠️  Workflow already exists in $repo (use --force to overwrite)"
            log "Workflow already exists in $repo (skipped)"
            cd - > /dev/null
            return 0
        fi
    fi
    
    # Copy the new workflow file
    cp "$OLDPWD/$WORKFLOW_FILE" "$workflow_path"
    
    # Check if there are changes to commit
    if git diff --quiet; then
        print_status $YELLOW "⚠️  No changes needed in $repo"
        log "No changes needed in $repo"
        cd - > /dev/null
        return 0
    fi
    
    # Configure git
    git config user.name "Droid Workflow Installer"
    git config user.email "workflow-installer@factory.ai"
    
    # Add and commit changes
    git add "$workflow_path"
    if [[ -f "$backup_path" ]]; then
        git add "$backup_path"
    fi
    
    local commit_message="Install Droid automated code review workflow"
    if [[ -f "$backup_path" ]]; then
        commit_message="Update Droid automated code review workflow (backup created)"
    fi
    
    git commit -m "$commit_message"
    
    # Push changes directly to default branch
    local default_branch="main"
    if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
        if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
            default_branch="master"
        else
            print_status $RED "❌ Could not determine default branch for $repo (tried main/master)"
            log "Default branch detection failed for $repo"
            cd - > /dev/null
            return 1
        fi
    fi

    if ! git push origin "HEAD:${default_branch}"; then
        print_status $RED "❌ Failed to push changes to ${default_branch}"
        log "Push to ${default_branch} failed for $repo"
        cd - > /dev/null
        return 1
    fi
    log "Pushed workflow update directly to ${default_branch} for $repo"
    
    cd - > /dev/null
    print_status $GREEN "✅ Completed $repo"
    log "Completed processing $repo"
}

# Main installation function
install_to_all_repos() {
    local force=${1:-false}
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
    
    print_status $BLUE "🚀 Starting workflow installation across $total repositories..."
    log "Starting workflow installation across $total repositories"
    
    if [[ "$force" == "true" ]]; then
        print_status $YELLOW "⚠️  Force mode enabled - existing workflows will be overwritten"
    fi
    
    for i in "${!repos[@]}"; do
        local repo="${repos[$i]}"
        local progress=$((i + 1))
        
        print_status $BLUE "[$progress/$total] Processing $repo..."
        
        if install_workflow_in_repo "$repo" "$force"; then
            ((success++))
        else
            ((failed++))
        fi
        
        # Small delay to avoid rate limiting
        sleep 1
    done
    
    # Summary
    print_status $GREEN "🎉 Installation completed!"
    echo -e "${GREEN}✅ Successful: $success${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}❌ Failed: $failed${NC}"
    fi
    echo -e "${BLUE}📊 Total: $total${NC}"
    
    log "Installation completed - Success: $success, Failed: $failed, Total: $total"
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
    read -p "Enter repository numbers to install (e.g., 1,3,5-8) or 'all' for all: " selection
    
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
Droid Code Review Workflow Installation Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -f, --force         Overwrite existing workflows
    -i, --interactive   Select repositories interactively
    -r, --repos REPOS   Comma-separated list of repositories
    --dry-run           Show what would be done without making changes

EXAMPLES:
    $0                              # Install to all repositories
    $0 --force                      # Install to all repos, overwriting existing
    $0 --interactive                # Select repositories interactively
    $0 --repos "owner/repo1,owner/repo2"  # Install to specific repos
    $0 --dry-run                    # Preview installation

REQUIREMENTS:
    - GitHub CLI (gh) installed and authenticated
    - Write access to target repositories
    - droid-code-review.yaml in current directory

EOF
}

# Main script
main() {
    local force=false
    local interactive=false
    local specific_repos=""
    local dry_run=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -f|--force)
                force=true
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
    log "=== Droid Workflow Installation Started ==="
    log "Force mode: $force"
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
        print_status $BLUE "Would install workflow to ${#repos[@]} repositories:"
        printf '%s\n' "${repos[@]}"
        exit 0
    fi
    
    if [[ "$interactive" == "true" ]]; then
        local repos=()
        while IFS= read -r repo; do
            [[ -n "$repo" ]] && repos+=("$repo")
        done < <(select_repositories)
        print_status $BLUE "🚀 Installing to ${#repos[@]} selected repositories..."
        
        for repo in "${repos[@]}"; do
            install_workflow_in_repo "$repo" "$force"
            sleep 1
        done
    elif [[ -n "$specific_repos" ]]; then
        IFS=',' read -ra repos_list <<< "$specific_repos"
        print_status $BLUE "🚀 Installing to ${#repos_list[@]} specified repositories..."
        
        for repo in "${repos_list[@]}"; do
            repo=$(echo "$repo" | xargs) # Trim whitespace
            install_workflow_in_repo "$repo" "$force"
            sleep 1
        done
    else
        install_to_all_repos "$force"
    fi
    
    print_status $GREEN "🎊 Installation process completed!"
    log "=== Droid Workflow Installation Completed ==="
}

# Run main function with all arguments
main "$@"
