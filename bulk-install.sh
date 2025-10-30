#!/bin/bash

# =============================================================================
# Bulk Installation Script for Droid Code Review
# =============================================================================
#
# Description: Bulk installation script for Droid Code Review workflow across
#              all accessible GitHub repositories with API keys configuration.
# Author: Factory AI
# Date: 2024-01-01
# Version: 2.0
#
# Usage: ./bulk-install.sh
# Dependencies: GitHub CLI (gh), jq, curl, git
#
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Global Variables
# -----------------------------------------------------------------------------
WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"
DROID_INSTALLER_SHA256=""  # Will be fetched dynamically
SCRIPT_DIR=$(dirname "$0")
TEMP_DIRS=()  # Track all temporary directories for cleanup
SUCCESS_COUNT=0
FAILED_COUNT=0

# API Keys (loaded from .env)
FACTORY_API_KEY=""
MODEL_API_KEY=""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Function: print_status
# Description: Print colored status messages
# Parameters:
#   $1 - Color code
#   $2 - Message to display
# Returns: 0
# -----------------------------------------------------------------------------
print_status() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
}

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
    print_status $YELLOW "⚠️  $message" >&2
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
    print_status $BLUE "ℹ️  $message"
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
# Function: load_env
# Description: Load API keys securely from .env file with validation
# Parameters: None
# Returns: 0 if successful, 1 if failed
# -----------------------------------------------------------------------------
load_env() {
    if [[ -f .env ]]; then
        print_status $GREEN "✅ Loading API keys from .env file..."
        
        local env_file=".env"
        local line_num=0
        
        # Load variables securely with validation
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
        
        # Verify keys are loaded
        if [[ -n "${FACTORY_API_KEY:-}" && -n "${MODEL_API_KEY:-}" ]]; then
            print_status $GREEN "✅ API keys loaded successfully"
            return 0
        else
            warn "API keys not found in .env file"
            return 1
        fi
    else
        warn ".env file not found. API secrets will not be created."
        print_status $BLUE "   To create secrets automatically, copy .env.example to .env and add your keys."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: fetch_droid_sha256
# Description: Fetch current SHA256 hash of Droid CLI installer
# Parameters: None
# Returns: 0 if successful, 1 if failed (sets global DROID_INSTALLER_SHA256)
# -----------------------------------------------------------------------------
fetch_droid_sha256() {
    print_status $BLUE "🔍 Fetching current Droid CLI installer SHA256..."
    
    local temp_installer
    temp_installer=$(mktemp) || error_exit "Failed to create temporary file for SHA256 calculation"
    
    # Download with error handling
    if ! curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer" 2>/dev/null; then
        rm -f "$temp_installer"
        error_exit "Failed to download Droid CLI installer"
    fi
    
    # Calculate SHA256 with fallback commands
    if command -v sha256sum &> /dev/null; then
        DROID_INSTALLER_SHA256=$(sha256sum "$temp_installer" | awk '{print $1}')
    elif command -v shasum &> /dev/null; then
        DROID_INSTALLER_SHA256=$(shasum -a 256 "$temp_installer" | awk '{print $1}')
    else
        rm -f "$temp_installer"
        error_exit "Neither sha256sum nor shasum commands are available"
    fi
    
    rm -f "$temp_installer"
    
    # Validate SHA256 format
    if [[ -z "$DROID_INSTALLER_SHA256" ]]; then
        error_exit "Failed to calculate SHA256"
    fi
    
    if [[ ! "$DROID_INSTALLER_SHA256" =~ ^[a-f0-9]{64}$ ]]; then
        error_exit "Invalid SHA256 format received: $DROID_INSTALLER_SHA256"
    fi
    
    print_status $GREEN "✅ Current SHA256: $DROID_INSTALLER_SHA256"
    return 0
}

# -----------------------------------------------------------------------------
# Function: check_prerequisites
# Description: Check if all required tools and files are available
# Parameters: None
# Returns: 0 if successful
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
    
    # Check workflow file exists
    validate_file_exists "$WORKFLOW_FILE"
    
    print_status $GREEN "✅ Prerequisites checked"
    return 0
}

# Get all repos
get_repos() {
    print $BLUE "📂 Getting your repositories..."
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

# SECURITY: Function to validate repository format
validate_repo() {
    local repo="$1"
    # Validate repository format (owner/repo)
    [[ "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
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
    validate_repo "$repo" || error_exit "Invalid repository format: $repo"
    
    # Validate secret name format
    if [[ ! "$secret_name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        error_exit "Invalid secret name format: $secret_name"
    fi
    
    # Use stdin to avoid command line exposure
    if echo "$secret_value" | gh secret set "$secret_name" --repo "$repo" 2>/dev/null; then
        info "Set $secret_name secret for $repo"
        return 0
    else
        warn "Failed to set $secret_name secret for $repo"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: create_repository_secrets
# Description: Create repository secrets for API keys
# Parameters:
#   $1 - Repository name (owner/repo)
# Returns: 0 if all secrets created successfully, 1 if any failed
# -----------------------------------------------------------------------------
create_repository_secrets() {
    local repo="$1"
    local secrets_created=true
    
    # Only create secrets if API keys are available
    if [[ -n "${FACTORY_API_KEY:-}" ]]; then
        if set_secret_secure "$repo" "FACTORY_API_KEY" "$FACTORY_API_KEY"; then
            info "FACTORY_API_KEY secret created for $repo"
        else
            secrets_created=false
        fi
    fi
    
    if [[ -n "${MODEL_API_KEY:-}" ]]; then
        if set_secret_secure "$repo" "MODEL_API_KEY" "$MODEL_API_KEY"; then
            info "MODEL_API_KEY secret created for $repo"
        else
            secrets_created=false
        fi
    fi
    
    if [[ "$secrets_created" == "true" ]]; then
        return 0
    else
        warn "Some secrets failed to create for $repo"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Function: install_to_repository
# Description: Install workflow to a single repository
# Parameters:
#   $1 - Repository name (owner/repo)
# Returns: 0 if successful, 1 if failed
# -----------------------------------------------------------------------------
install_to_repository() {
    local repo="$1"
    local temp_dir
    
    # SECURITY: Validate repository format before processing
    validate_repo "$repo" || {
        warn "Invalid repository format: $repo"
        return 1
    }
    
    print_status $BLUE "🔄 $repo..."
    
    # Create temporary directory with proper cleanup
    temp_dir=$(create_temp_dir) || return 1
    
    # Clone repository with error handling
    if gh repo clone "$repo" "$temp_dir" --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
        cd "$temp_dir" || {
            warn "Failed to change to repository directory"
            cleanup_temp "$temp_dir"
            return 1
        }
        
        # Create workflow directory
        mkdir -p .github/workflows
        
        # Copy workflow file from original directory
        validate_file_exists "$OLDPWD/$WORKFLOW_FILE"
        cp "$OLDPWD/$WORKFLOW_FILE" "$WORKFLOW_PATH"
        
        # Configure git
        git config user.name "Droid Installer"
        git config user.email "installer@factory.ai"
        
        # Add and commit changes
        git add "$WORKFLOW_PATH"
        if git diff --staged --quiet; then
            print_status $YELLOW "  ⚠️  No changes needed"
        else
            git commit -m "Add Droid automated code review workflow"
            
            # Push changes
            if git push 2>/dev/null; then
                print_status $GREEN "  ✅ Installed workflow to $repo"
                
                # Set the repository variable and secrets after successful push
                set_repository_variable "$repo"
                create_repository_secrets "$repo"
                
                # Update success counter
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                warn "Failed to push changes to $repo"
                FAILED_COUNT=$((FAILED_COUNT + 1))
            fi
        fi
        
        # Return to original directory and cleanup
        cd - >/dev/null || true
        cleanup_temp "$temp_dir"
    else
        warn "Failed to clone $repo"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        cleanup_temp "$temp_dir"
        return 1
    fi
    
    return 0
}

# Main installation
main() {
    print $BLUE "🚀 Droid Code Review - Bulk Installation"
    print $BLUE "========================================"
    
    check
    
    # Load API keys from .env
    local has_api_keys=false
    if load_env; then
        has_api_keys=true
    fi
    echo
    
    # Fetch current Droid SHA256
    if ! fetch_droid_sha256; then
        print $RED "❌ Cannot proceed without valid Droid installer SHA256"
        exit 1
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
    echo
    print $GREEN "✅ DROID_INSTALLER_SHA256 variable has been set automatically on all repositories"
    
    if [[ "$has_api_keys" == "true" ]]; then
        print $GREEN "✅ FACTORY_API_KEY and MODEL_API_KEY secrets have been created in all repositories"
    else
        echo
        print $BLUE "🔔 REMINDER: API secrets were not created automatically."
        print $BLUE "   To create secrets automatically next time:"
        print $BLUE "   1. Copy .env.example to .env"
        print $BLUE "   2. Add your API keys to the .env file"
        print $BLUE "   3. Run this script again"
        echo
        print $BLUE "   Or add them manually to each repository:"
        print $BLUE "   Repository Settings → Secrets and variables → Actions → New repository secret"
        print $BLUE "   Required secrets:"
        print $BLUE "   - FACTORY_API_KEY: Your Factory.ai API key"
        print $BLUE "   - MODEL_API_KEY: Your Z.ai API key (for GLM-4.6 model)"
    fi
}

main "$@"
