#!/bin/bash

# =============================================================================
# Auto Setup All Repositories Script
# =============================================================================
#
# Description: Automatically adds Droid Code Review workflow to ALL repositories
#              This script sets up the code review workflow across all accessible
#              GitHub repositories, including API keys and configuration.
# Author: Factory AI
# Date: 2024-01-01
# Version: 2.0
#
# Usage: ./auto-setup-all.sh
# Dependencies: GitHub CLI (gh), jq, curl, git
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Global Variables
# -----------------------------------------------------------------------------
SCRIPT_DIR=$(dirname "$0")
TEMP_DIRS=()  # Track all temporary directories for cleanup
SUCCESS_COUNT=0
FAILED_COUNT=0

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Function: error_exit
# Description: Standard error handling function with consistent exit codes
# Parameters:
#   $1 - Error message to display
#   $2 - Exit code (optional, defaults to 1)
# Returns: Exits the script with the specified code
# -----------------------------------------------------------------------------
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    echo "ERROR: $message" >&2
    cleanup_on_exit
    exit "$exit_code"
}

# -----------------------------------------------------------------------------
# Function: warn
# Description: Standard warning function for non-fatal issues
# Parameters:
#   $1 - Warning message to display
# Returns: 0
# -----------------------------------------------------------------------------
warn() {
    local message="$1"
    echo "WARNING: $message" >&2
    return 0
}

# -----------------------------------------------------------------------------
# Function: info
# Description: Standard info function for status messages
# Parameters:
#   $1 - Info message to display
# Returns: 0
# -----------------------------------------------------------------------------
info() {
    local message="$1"
    echo "INFO: $message"
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_not_empty
# Description: Validates that a value is not empty
# Parameters:
#   $1 - Value to validate
#   $2 - Field name for error message
# Returns: 0 if valid, 1 if invalid
# -----------------------------------------------------------------------------
validate_not_empty() {
    local value="$1"
    local field_name="$2"
    
    [[ -n "$value" ]] || error_exit "Empty value not allowed for $field_name"
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_file_exists
# Description: Validates that a file exists
# Parameters:
#   $1 - File path to validate
# Returns: 0 if valid, 1 if invalid
# -----------------------------------------------------------------------------
validate_file_exists() {
    local file_path="$1"
    
    [[ -f "$file_path" ]] || error_exit "File not found: $file_path"
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_command_exists
# Description: Validates that a command exists in PATH
# Parameters:
#   $1 - Command name to validate
# Returns: 0 if valid, 1 if invalid
# -----------------------------------------------------------------------------
validate_command_exists() {
    local command="$1"
    
    command -v "$command" >/dev/null 2>&1 || error_exit "Required command not found: $command"
    return 0
}

# -----------------------------------------------------------------------------
# Function: create_temp_dir
# Description: Creates a secure temporary directory
# Parameters: None
# Returns: Path to the created temporary directory
# -----------------------------------------------------------------------------
create_temp_dir() {
    local temp_dir
    temp_dir=$(mktemp -d) || error_exit "Failed to create temp directory"
    chmod 700 "$temp_dir"  # Restrict permissions
    TEMP_DIRS+=("$temp_dir")  # Track for cleanup
    echo "$temp_dir"
}

# -----------------------------------------------------------------------------
# Function: cleanup_temp
# Description: Cleanup function for temporary directories
# Parameters: 
#   $1 - Path to temporary directory (optional)
# Returns: 0
# -----------------------------------------------------------------------------
cleanup_temp() {
    local temp_dir="$1"
    [[ -n "$temp_dir" && -d "$temp_dir" ]] && rm -rf "$temp_dir"
    return 0
}

# -----------------------------------------------------------------------------
# Function: cleanup_on_exit
# Description: Cleanup all tracked temporary directories
# Parameters: None
# Returns: 0
# -----------------------------------------------------------------------------
cleanup_on_exit() {
    for temp_dir in "${TEMP_DIRS[@]}"; do
        cleanup_temp "$temp_dir"
    done
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_repo
# Description: Validates repository format (owner/repo)
# Parameters:
#   $1 - Repository string to validate
# Returns: 0 if valid, 1 if invalid
# -----------------------------------------------------------------------------
validate_repo() {
    local repo="$1"
    # Validate repository format (owner/repo)
    [[ "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
}

# -----------------------------------------------------------------------------
# Core Functions
# -----------------------------------------------------------------------------

echo "🚀 Auto-Setup Droid Code Review for All Repositories"
echo "=================================================="

# -----------------------------------------------------------------------------
# Function: check_env_file
# Description: Checks if .env file exists and is readable
# Parameters: None
# Returns: 0 if file exists, 1 otherwise
# -----------------------------------------------------------------------------
check_env_file() {
    if [ ! -f ".env" ]; then
        error_exit ".env file not found. Please create it with your API keys.\n   Copy .env.example to .env and add your keys."
    fi
    
    if [ ! -r ".env" ]; then
        error_exit ".env file exists but is not readable. Check file permissions."
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_api_key_format
# Description: Validates API key format and length
# Parameters:
#   $1 - Key name
#   $2 - Key value
# Returns: 0 if valid, 1 if invalid
# -----------------------------------------------------------------------------
validate_api_key_format() {
    local key_name="$1"
    local key_value="$2"
    
    # Check for placeholder values that indicate unconfigured keys
    if [[ "$key_value" == "YOUR_"*"_HERE" ]]; then
        error_exit "SECURITY ERROR: $key_name contains placeholder value. Please configure your actual API key."
    fi
    
    # Validate API key format (basic length and character checks)
    if [[ ${#key_value} -lt 32 ]]; then
        error_exit "SECURITY ERROR: $key_name appears too short to be a valid API key (minimum 32 characters)"
    fi
    
    if [[ ! "$key_value" =~ ^[a-zA-Z0-9_+-]+$ ]]; then
        error_exit "SECURITY ERROR: $key_name contains invalid characters for an API key"
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: load_env_secure
# Description: Load API keys securely with validation
# Parameters: None
# Returns: 0 if successful, 1 if failed
# -----------------------------------------------------------------------------
load_env_secure() {
    validate_file_exists ".env"
    
    local env_file=".env"
    local line_num=0
    
    while IFS='=' read -r key value; do
        ((line_num++))
        
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" || -z "$value" ]] && continue
        
        # Validate key name format (only uppercase letters, numbers, and underscores)
        if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            # Special validation for API keys
            case "$key" in
                *_API_KEY)
                    validate_api_key_format "$key" "$value"
                    info "Validated API key: $key"
                    ;;
                *)
                    info "Loading environment variable: $key"
                    ;;
            esac
            
            # Export the validated key
            export "$key=$value"
        else
            warn "Invalid environment variable name at line $line_num: $key"
        fi
    done < <(grep -v '^#' "$env_file" | grep -v '^$')
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: validate_required_api_keys
# Description: Validates that required API keys are present
# Parameters: None
# Returns: 0 if all keys present, 1 if missing
# -----------------------------------------------------------------------------
validate_required_api_keys() {
    local missing_keys=()
    
    if [ -z "${FACTORY_API_KEY:-}" ]; then
        missing_keys+=("FACTORY_API_KEY")
    fi
    
    if [ -z "${MODEL_API_KEY:-}" ]; then
        missing_keys+=("MODEL_API_KEY")
    fi
    
    if [ ${#missing_keys[@]} -gt 0 ]; then
        error_exit "Missing required API keys in .env file: ${missing_keys[*]}"
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: check_prerequisites
# Description: Check if all required tools are installed and configured
# Parameters: None
# Returns: 0 if all prerequisites are met, exits with error code otherwise
# -----------------------------------------------------------------------------
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check GitHub CLI
    validate_command_exists "gh"
    
    # Check GitHub CLI authentication
    if ! gh auth status &> /dev/null; then
        error_exit "GitHub CLI is not authenticated. Please run 'gh auth login' first."
    fi
    
    # Check jq
    validate_command_exists "jq"
    
    # Check curl
    validate_command_exists "curl"
    
    # Check git
    validate_command_exists "git"
    
    info "All prerequisites check passed"
    return 0
}

# -----------------------------------------------------------------------------
# Function: fetch_current_sha256
# Description: Fetch the current SHA256 hash of the Droid CLI installer
# Parameters: None
# Returns: 0 if successful, 1 if failed (sets global SHA256 variable)
# -----------------------------------------------------------------------------
fetch_current_sha256() {
    info "Fetching current Droid CLI installer SHA256..."
    
    local temp_installer
    temp_installer=$(mktemp) || error_exit "Failed to create temporary file for SHA256 calculation"
    
    # Download with timeout and error handling
    if ! curl -fsSL --connect-timeout 10 --max-time 30 --compressed \
         "https://app.factory.ai/cli" -o "$temp_installer" 2>/dev/null; then
        rm -f "$temp_installer"
        error_exit "Failed to download Droid CLI installer"
    fi
    
    # Calculate SHA256
    if command -v sha256sum &> /dev/null; then
        SHA256=$(sha256sum "$temp_installer" | cut -d' ' -f1)
    elif command -v shasum &> /dev/null; then
        SHA256=$(shasum -a 256 "$temp_installer" | cut -d' ' -f1)
    else
        rm -f "$temp_installer"
        error_exit "Neither sha256sum nor shasum commands are available"
    fi
    
    rm -f "$temp_installer"
    
    # Validate SHA256 format
    if [[ ! "$SHA256" =~ ^[a-f0-9]{64}$ ]]; then
        error_exit "Invalid SHA256 format received: $SHA256"
    fi
    
    info "Current SHA256: $SHA256"
    return 0
}

# -----------------------------------------------------------------------------
# Function: initialize_script
# Description: Initialize script environment and perform initial checks
# Parameters: None
# Returns: 0 if successful
# -----------------------------------------------------------------------------
initialize_script() {
    # Set up cleanup trap
    trap cleanup_on_exit EXIT INT TERM
    
    # Check environment file
    check_env_file
    
    # Load and validate environment variables
    if ! load_env_secure; then
        error_exit "Failed to load environment variables securely"
    fi
    
    # Validate required API keys
    validate_required_api_keys
    
    info "API keys loaded and validated successfully"
    
    # Check prerequisites
    check_prerequisites
    
    # Fetch current SHA256
    fetch_current_sha256
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: set_secret_secure
# Description: Securely set repository secrets with validation
# Parameters:
#   $1 - Repository name (owner/repo)
#   $2 - Secret name
#   $3 - Secret value
# Returns: 0 if successful, 1 if failed
# -----------------------------------------------------------------------------
set_secret_secure() {
    local repo="$1"
    local secret_name="$2"
    local secret_value="$3"
    
    # Validate inputs
    validate_not_empty "$repo" "repository"
    validate_not_empty "$secret_name" "secret name"
    validate_not_empty "$secret_value" "secret value"
    
    # Validate repository format
    if ! validate_repo "$repo"; then
        error_exit "SECURITY ERROR: Invalid repository format: $repo"
    fi
    
    # Validate secret name format
    if [[ ! "$secret_name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        error_exit "SECURITY ERROR: Invalid secret name format: $secret_name"
    fi
    
    # Use stdin to avoid command line exposure
    if echo "$secret_value" | gh secret set "$secret_name" --repo "$repo" 2>/dev/null; then
        info "Secret $secret_name set successfully for $repo"
        return 0
    else
        warn "Failed to set secret $secret_name for $repo"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: setup_repository
# Description: Setup Droid Code Review workflow for a single repository
# Parameters:
#   $1 - Repository name (owner/repo)
# Returns: 0 if successful, 1 if failed
# -----------------------------------------------------------------------------
setup_repository() {
    local repo="$1"
    info "Setting up $repo..."
    
    # Validate repository format before processing
    validate_repo "$repo" || return 1
    
    # Create temporary directory with proper cleanup
    local temp_dir
    temp_dir=$(create_temp_dir) || return 1
    
    # Clone repository with timeout and error handling
    if ! timeout 60 git clone --depth 1 "https://github.com/$repo.git" "$temp_dir" 2>/dev/null; then
        warn "Failed to clone $repo"
        return 1
    fi
    
    # Change to repository directory
    cd "$temp_dir" || {
        warn "Failed to change to repository directory"
        return 1
    }
    
    # Create workflows directory if it doesn't exist
    mkdir -p .github/workflows
    
    # Copy workflow file from original script directory
    local workflow_source="${SCRIPT_DIR:-$(dirname "$0")}/droid-code-review.yaml"
    validate_file_exists "$workflow_source"
    cp "$workflow_source" .github/workflows/
    
    # Determine if this is a new install or update
    local commit_message
    local action_description
    
    if [ -f ".github/workflows/droid-code-review.yaml" ]; then
        if ! diff -q ".github/workflows/droid-code-review.yaml" "$(dirname "$0")/droid-code-review.yaml" >/dev/null 2>&1; then
            commit_message="Update Droid Code Review workflow

- Automated AI-powered code analysis  
- Uses GLM-4.6 model via Factory.ai
- Runs on pull requests for code review

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"
            action_description="Updated workflow"
        else
            info "Workflow already exists and is up to date for $repo"
            cd / && rm -rf "$temp_dir" 2>/dev/null || true
            return 0
        fi
    else
        commit_message="Add Droid Code Review workflow

- Automated AI-powered code analysis
- Uses GLM-4.6 model via Factory.ai  
- Runs on pull requests for code review

Co-authored-by: factory-droid[bot] <138933559+factory-droid[bot]@users.noreply.github.com>"
        action_description="Added workflow"
    fi
    
    # Configure git
    git config user.name "Droid Auto Setup"
    git config user.email "auto-setup@factory.ai"
    
    # Add and commit changes
    git add .github/workflows/droid-code-review.yaml
    git commit -m "$commit_message" 2>/dev/null
    
    # Push changes
    if git push 2>/dev/null; then
        info "$action_description for $repo"
    else
        warn "Failed to push $action_description to $repo"
        cd / && rm -rf "$temp_dir" 2>/dev/null || true
        return 1
    fi
    
    # Set repository variable
    if gh api repos/"$repo"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256" 2>/dev/null; then
        info "Set DROID_INSTALLER_SHA256 variable for $repo"
    else
        warn "Failed to set DROID_INSTALLER_SHA256 variable for $repo"
    fi
    
    # Set secrets using secure method
    local secrets_configured=true
    
    if set_secret_secure "$repo" "FACTORY_API_KEY" "$FACTORY_API_KEY"; then
        info "Set FACTORY_API_KEY for $repo"
    else
        secrets_configured=false
    fi
    
    if set_secret_secure "$repo" "MODEL_API_KEY" "$MODEL_API_KEY"; then
        info "Set MODEL_API_KEY for $repo"
    else
        secrets_configured=false
    fi
    
    if [ "$secrets_configured" = true ]; then
        info "Configured all secrets and variables for $repo"
    else
        warn "Some secrets or variables failed to configure for $repo"
    fi
    
    # Return to original directory and cleanup
    cd / || true
    cleanup_temp "$temp_dir"
    
    # Update counters
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    return 0
}

# -----------------------------------------------------------------------------
# Function: get_user_repositories
# Description: Get all repositories for the authenticated user
# Parameters: None
# Returns: Repository list (one per line)
# -----------------------------------------------------------------------------
get_user_repositories() {
    info "Fetching your repositories..."
    
    local repos
    repos=$(gh repo list --limit 1000 --json nameWithOwner | jq -r '.[].nameWithOwner')
    
    if [[ -z "$repos" ]]; then
        error_exit "No repositories found or failed to fetch repository list"
    fi
    
    echo "$repos"
}

# -----------------------------------------------------------------------------
# Function: process_repositories
# Description: Process all repositories and set up Droid Code Review
# Parameters: 
#   $1 - List of repositories (one per line)
# Returns: 0 if successful
# -----------------------------------------------------------------------------
process_repositories() {
    local repos="$1"
    local total
    total=$(echo "$repos" | wc -l | tr -d ' ')
    
    info "Processing $total repositories..."
    
    local repo_num=0
    
    while IFS= read -r repo; do
        [[ -z "$repo" ]] && continue
        
        ((repo_num++))
        info "[$repo_num/$total] Processing $repo"
        
        if setup_repository "$repo"; then
            # Success count is updated in setup_repository function
            true
        else
            FAILED_COUNT=$((FAILED_COUNT + 1))
        fi
        
        # Add delay to avoid rate limiting
        sleep 1
        
        echo ""
    done <<< "$repos"
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: display_summary
# Description: Display final summary of operations
# Parameters: 
#   $1 - Total number of repositories processed
# Returns: 0
# -----------------------------------------------------------------------------
display_summary() {
    local total="$1"
    
    echo ""
    echo "🎉 All repositories have been processed!"
    echo ""
    echo "Summary:"
    echo "- Successful: $SUCCESS_COUNT/$total repositories"
    echo "- Failed: $FAILED_COUNT/$total repositories"
    echo "- Workflow added/updated in accessible repositories"
    echo "- API keys configured as repository secrets"  
    echo "- SHA256 variable set for security validation"
    echo ""
    echo "The workflow will now run automatically on pull requests."
    
    # Calculate success rate
    if [[ $total -gt 0 ]]; then
        local success_rate=$(( (SUCCESS_COUNT * 100) / total ))
        if [[ $success_rate -eq 100 ]]; then
            echo "🎊 Perfect! All repositories were configured successfully!"
        elif [[ $success_rate -ge 80 ]]; then
            echo "👍 Great! $success_rate% of repositories were configured successfully."
        else
            echo "⚠️  $success_rate% success rate. Some repositories may need manual attention."
        fi
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# Function: main
# Description: Main execution function
# Parameters: None
# Returns: 0 if successful
# -----------------------------------------------------------------------------
main() {
    echo "🚀 Auto-Setup Droid Code Review for All Repositories"
    echo "=================================================="
    echo ""
    
    # Initialize script environment
    initialize_script
    echo ""
    
    # Get repositories
    local repos
    repos=$(get_user_repositories)
    
    # Process repositories
    process_repositories "$repos"
    
    # Display summary
    local total
    total=$(echo "$repos" | wc -l | tr -d ' ')
    display_summary "$total"
    
    return 0
}

# Execute main function
main "$@"
