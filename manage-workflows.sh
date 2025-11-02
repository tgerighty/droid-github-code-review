#!/bin/bash

# Droid Code Review Workflow Management Script
# This script provides utilities to manage installed workflows

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# SECURITY: Function to validate repository format
validate_repo() {
    local repo="$1"
    # Validate repository format (owner/repo)
    if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
        return 1
    fi
    
    # SECURITY: Additional validation for command injection
    if [[ "$repo" =~ [\;\&\|`\$\(\)\{\}\[\]] ]]; then
        return 1
    fi
    
    return 0
}

# Check prerequisites
check_prerequisites() {
    if ! command -v gh &> /dev/null; then
        print_status $RED "❌ GitHub CLI (gh) is not installed."
        exit 1
    fi
    
    if ! gh auth status &> /dev/null; then
        print_status $RED "❌ Not authenticated with GitHub CLI."
        exit 1
    fi
}

# List repositories with the workflow installed
list_installed_repos() {
    print_status $BLUE "🔍 Scanning repositories for droid-code-review workflow..."
    
    local repos=($(gh repo list --limit 1000 --public --source --json nameWithOwner | jq -r '.[].nameWithOwner'))
    local installed=()
    local not_installed=()
    
    for repo in "${repos[@]}"; do
        if gh api "repos/$repo/contents/.github/workflows/droid-code-review.yaml" 2>/dev/null | jq -e '.name' > /dev/null; then
            installed+=("$repo")
        else
            not_installed+=("$repo")
        fi
        
        # Progress indicator
        local count=$((${#installed[@]} + ${#not_installed[@]}))
        if (( count % 50 == 0 )); then
            print_status $BLUE "📂 Scanned $count repositories..."
        fi
    done
    
    echo
    print_status $GREEN "✅ Workflow installed in ${#installed[@]} repositories:"
    for repo in "${installed[@]}"; do
        echo "  ✓ $repo"
    done
    
    if [[ ${#not_installed[@]} -gt 0 ]]; then
        echo
        print_status $YELLOW "⚠️  Workflow NOT installed in ${#not_installed[@]} repositories:"
        for repo in "${not_installed[@]}"; do
            echo "  ✗ $repo"
        done
    fi
}

# Check workflow status in specific repositories
check_workflow_status() {
    local repos=("$@")
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        print_status $YELLOW "⚠️  No repositories specified"
        return
    fi
    
    print_status $BLUE "🔍 Checking workflow status in ${#repos[@]} repositories..."
    
    for repo in "${repos[@]}"; do
        echo
        print_status $BLUE "📁 Repository: $repo"
        
        # Check if workflow file exists
        if gh api "repos/$repo/contents/.github/workflows/droid-code-review.yaml" 2>/dev/null | jq -e '.name' > /dev/null; then
            print_status $GREEN "  ✓ Workflow file exists"
            
            # Get workflow file info
            local workflow_info
            workflow_info=$(gh api "repos/$repo/contents/.github/workflows/droid-code-review.yaml" 2>/dev/null)
            
            local sha=$(echo "$workflow_info" | jq -r '.sha')
            local size=$(echo "$workflow_info" | jq -r '.size')
            local last_modified=$(echo "$workflow_info" | jq -r '.name' | xargs -I {} gh api "repos/$repo/commits?path=.github/workflows/droid-code-review.yaml" 2>/dev/null | jq -r '.[0].commit.committer.date // "Unknown"')
            
            echo "    📝 SHA: $sha"
            echo "    📊 Size: $size bytes"
            echo "    📅 Last modified: $last_modified"
            
            # Check if FACTORY_API_KEY secret exists (this will only work for repos you have admin access to)
            if gh secret list --repo "$repo" 2>/dev/null | grep -q "FACTORY_API_KEY"; then
                print_status $GREEN "  ✓ FACTORY_API_KEY secret configured"
            else
                print_status $YELLOW "  ⚠️  FACTORY_API_KEY secret may not be configured"
            fi
            
            # Check recent workflow runs
            local recent_runs
            recent_runs=$(gh run list --repo "$repo" --workflow="Droid Code Review" --limit 3 --json status,conclusion,created_at 2>/dev/null || echo "[]")
            
            if [[ "$recent_runs" != "[]" ]]; then
                print_status $GREEN "  ✓ Recent workflow runs found:"
                echo "$recent_runs" | jq -r '.[] | "    • \(.status // "unknown")/\(.conclusion // "unknown") - \(.created_at)"' 2>/dev/null || true
            else
                print_status $YELLOW "  ⚠️  No recent workflow runs found"
            fi
        else
            print_status $RED "  ✗ Workflow file not found"
        fi
    done
}

# Update workflow in repositories that have it installed
update_installed_workflows() {
    local force=${1:-false}
    
    if [[ ! -f "droid-code-review-v2.yaml" ]]; then
        print_status $RED "❌ droid-code-review-v2.yaml not found in current directory"
        exit 1
    fi
    
    print_status $BLUE "🔄 Updating installed workflows..."
    
    # Get repositories that have the workflow installed
    local repos=($(gh repo list --limit 1000 --public --source --json nameWithOwner | jq -r '.[].nameWithOwner'))
    local installed=()
    
    for repo in "${repos[@]}"; do
        if gh api "repos/$repo/contents/.github/workflows/droid-code-review.yaml" 2>/dev/null | jq -e '.name' > /dev/null; then
            installed+=("$repo")
        fi
    done
    
    if [[ ${#installed[@]} -eq 0 ]]; then
        print_status $YELLOW "⚠️  No repositories have the workflow installed"
        return
    fi
    
    print_status $BLUE "🚀 Updating workflow in ${#installed[@]} repositories..."
    
    # Use the installation script to update
    ./install-workflow.sh --force --repos "$(IFS=','; echo "${installed[*]}")"
}

# Remove repository variable
remove_repo_variable() {
    local repo=$1
    
    if gh variable delete DROID_INSTALLER_SHA256 --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed DROID_INSTALLER_SHA256 variable"
        return 0
    else
        print_status $YELLOW "  ⚠️  Variable DROID_INSTALLER_SHA256 not found or already removed"
        return 1
    fi
}

# Remove repository secrets
remove_repo_secrets() {
    local repo=$1
    local secrets_removed=0
    
    # Remove FACTORY_API_KEY secret
    if gh secret delete FACTORY_API_KEY --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed FACTORY_API_KEY secret"
        ((secrets_removed++))
    else
        print_status $YELLOW "  ⚠️  Secret FACTORY_API_KEY not found or already removed"
    fi
    
    # Remove MODEL_API_KEY secret
    if gh secret delete MODEL_API_KEY --repo "$repo" 2>&1 > /dev/null; then
        print_status $GREEN "  ✓ Removed MODEL_API_KEY secret"
        ((secrets_removed++))
    else
        print_status $YELLOW "  ⚠️  Secret MODEL_API_KEY not found or already removed"
    fi
    
    if [[ $secrets_removed -gt 0 ]]; then
        print_status $GREEN "  ✓ Removed $secrets_removed secret(s)"
    fi
    
    return 0
}

# Remove workflow from repositories
remove_workflow() {
    local repos=("$@")
    
    if [[ ${#repos[@]} -eq 0 ]]; then
        print_status $YELLOW "⚠️  No repositories specified"
        return
    fi
    
    print_status $RED "🗑️  Removing workflow from ${#repos[@]} repositories..."
    
    for repo in "${repos[@]}"; do
        # SECURITY: Validate repository format before processing
        if ! validate_repo "$repo"; then
            print_status $RED "❌ SECURITY ERROR: Invalid repository format: $repo"
            continue
        fi
        
        print_status $BLUE "📁 Processing $repo..."
        
        # Create temp directory
        local temp_dir=$(mktemp -d)
        trap "rm -rf $temp_dir" RETURN
        
        # SECURITY: Validate repository before cloning
        if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch; then
            cd "$temp_dir"
            
            local workflow_path=".github/workflows/droid-code-review.yaml"
            local backup_path=".github/workflows/backup/droid-code-review.yaml"
            
            # Create backup
            if [[ -f "$workflow_path" ]]; then
                mkdir -p "$(dirname "$backup_path")"
                cp "$workflow_path" "$backup_path"
                print_status $YELLOW "  📦 Backed up to $backup_path"
                
                git config user.name "Droid Workflow Manager"
                git config user.email "workflow-manager@factory.ai"
                
                git add "$backup_path"
                git rm "$workflow_path"
                git commit -m "Remove Droid code review workflow (backup created)"
                
                local default_branch="main"
                if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
                    if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
                        default_branch="master"
                    else
                        print_status $RED "  ❌ Could not determine default branch (main/master) for $repo"
                        cd - > /dev/null
                        continue
                    fi
                fi

                if git push origin "HEAD:${default_branch}"; then
                    print_status $GREEN "  ✅ Removed workflow and pushed to ${default_branch}"
                    
                    # Clean up secrets and variables after successful push
                    cd - > /dev/null
                    print_status $BLUE "  🧹 Cleaning up secrets and variables..."
                    remove_repo_variable "$repo"
                    remove_repo_secrets "$repo"
                else
                    print_status $RED "  ❌ Failed to push removal to ${default_branch}"
                    cd - > /dev/null
                fi
            else
                print_status $YELLOW "  ⚠️  Workflow not found in $repo"
                cd - > /dev/null
                
                # Still try to clean up secrets and variables
                print_status $BLUE "  🧹 Cleaning up secrets and variables..."
                remove_repo_variable "$repo"
                remove_repo_secrets "$repo"
            fi
        else
            print_status $RED "  ❌ Failed to clone $repo"
        fi
        
        sleep 1
    done
}

# Show usage
usage() {
    cat << EOF
Droid Code Review Workflow Management Script

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    list                        List all repositories and their workflow status
    check <repo1,repo2,...>     Check workflow status in specific repositories
    update [--force]            Update workflow in repositories where it's installed
    remove <repo1,repo2,...>    Remove workflow from specific repositories
    help                        Show this help message

OPTIONS:
    -f, --force                 Force update (overwrite existing backups)

EXAMPLES:
    $0 list                     # List all repositories and workflow status
    $0 check owner/repo1        # Check specific repository
    $0 update                   # Update all installed workflows
    $0 update --force           # Force update (overwrite backups)
    $0 remove owner/repo1       # Remove workflow from specific repo

REQUIREMENTS:
    - GitHub CLI (gh) installed and authenticated
    - Write access to target repositories

EOF
}

# Main script
main() {
    check_prerequisites
    
    case "${1:-help}" in
        list)
            list_installed_repos
            ;;
        check)
            shift
            IFS=',' read -ra repos <<< "$1"
            check_workflow_status "${repos[@]}"
            ;;
        update)
            shift
            local force=false
            if [[ "$1" == "--force" ]]; then
                force=true
            fi
            update_installed_workflows "$force"
            ;;
        remove)
            shift
            IFS=',' read -ra repos <<< "$1"
            remove_workflow "${repos[@]}"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            print_status $RED "❌ Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
