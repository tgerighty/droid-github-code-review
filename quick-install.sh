#!/bin/bash

# Quick install - Just run it and it installs to all repos via GitHub API
# No cloning required, uses GitHub API directly

set -euo pipefail

WORKFLOW_FILE="droid-code-review.yaml"
WORKFLOW_PATH=".github/workflows/droid-code-review.yaml"
DROID_INSTALLER_SHA256=""  # Will be fetched dynamically

# API Keys (loaded from .env)
FACTORY_API_KEY=""
MODEL_API_KEY=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print() {
    echo -e "${1}${2}${NC}"
}

# SECURITY: Load API keys securely from .env file
load_env() {
    if [[ -f .env ]]; then
        print $GREEN "✅ Loading API keys from .env file..."
        
        # SECURITY: Load variables securely with validation (PREVENT COMMAND INJECTION)
        # Using process substitution and read loop instead of dangerous export $(grep | xargs) pattern
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" || -z "$value" ]] && continue
            
            # SECURITY: Validate key name format (only uppercase letters, numbers, and underscores)
            # Prevents environment variable injection attacks
            if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
                # SECURITY: Check for placeholder values that indicate unconfigured keys
                if [[ "$value" == "YOUR_"*"_HERE" ]]; then
                    print $RED "❌ SECURITY ERROR: $key contains placeholder value. Please configure your actual API key."
                    return 1
                fi
                
                # SECURITY: Check for command injection patterns in values
                if [[ "$value" =~ [\;\&\|`\$\(\)\{\}\[\]] ]]; then
                    print $RED "❌ SECURITY ERROR: $key contains potentially dangerous characters"
                    return 1
                fi
                
                # Validate API key format (basic length and character checks)
                case "$key" in
                    *_API_KEY)
                        if [[ ${#value} -lt 32 ]]; then
                            print $RED "❌ SECURITY ERROR: $key appears too short to be a valid API key"
                            return 1
                        fi
                        if [[ ! "$value" =~ ^[a-zA-Z0-9_+-]+$ ]]; then
                            print $RED "❌ SECURITY ERROR: $key contains invalid characters for an API key"
                            return 1
                        fi
                        ;;
                esac
                
                # SECURITY: Export the validated key safely using printf to prevent injection
                printf -v "${key}" '%s' "$value"
                export "$key"
            else
                print $YELLOW "⚠️  WARNING: Invalid environment variable name: $key"
            fi
        done < <(grep -v '^#' .env | grep -v '^$')
        
        # Verify keys are loaded
        if [[ -n "${FACTORY_API_KEY:-}" && -n "${MODEL_API_KEY:-}" ]]; then
            print $GREEN "✅ API keys loaded successfully"
            return 0
        else
            print $YELLOW "⚠️  API keys not found in .env file"
            return 1
        fi
    else
        print $YELLOW "⚠️  .env file not found. API secrets will not be created."
        print $BLUE "   To create secrets automatically, copy .env.example to .env and add your keys."
        return 1
    fi
}

# Fetch current Droid CLI installer SHA256 with integrity verification
fetch_droid_sha256() {
    print $BLUE "🔍 Fetching current Droid CLI installer SHA256..."
    
    local temp_installer=$(mktemp)
    
    # SECURITY: Download with integrity verification
    if ! curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer"; then
        print $RED "❌ Failed to download Droid CLI installer"
        rm -f "$temp_installer"
        return 1
    fi
    
    # SECURITY: Verify download integrity - check if it's a valid script
    if [[ ! -s "$temp_installer" ]] || [[ $(head -c 10 "$temp_installer") != "#!/bin/bash" && $(head -c 10 "$temp_installer") != "#!/bin/sh" ]]; then
        print $RED "❌ SECURITY ERROR: Downloaded file appears invalid or corrupted"
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

# SECURITY: Function to validate repository format
validate_repo() {
    local repo="$1"
    # Validate repository format (owner/repo)
    [[ "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]
}

# SECURITY: Function to securely set repository secrets
set_secret_secure() {
    local repo="$1"
    local secret_name="$2"
    local secret_value="$3"
    
    # Validate inputs
    if [[ -z "$repo" || -z "$secret_name" || -z "$secret_value" ]]; then
        print $RED "❌ SECURITY ERROR: Missing required parameters for secret setting"
        return 1
    fi
    
    # Validate repository format
    if ! validate_repo "$repo"; then
        print $RED "❌ SECURITY ERROR: Invalid repository format: $repo"
        return 1
    fi
    
    # Validate secret name format
    if [[ ! "$secret_name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        print $RED "❌ SECURITY ERROR: Invalid secret name format: $secret_name"
        return 1
    fi
    
    # Use stdin to avoid command line exposure
    echo "$secret_value" | gh secret set "$secret_name" --repo "$repo" 2>&1 > /dev/null
}

# Create repository secrets for API keys
create_repo_secrets() {
    local repo=$1
    local success=true
    
    # Only create secrets if API keys are available
    if [[ -n "${FACTORY_API_KEY:-}" ]]; then
        if set_secret_secure "$repo" "FACTORY_API_KEY" "$FACTORY_API_KEY"; then
            : # Success
        else
            success=false
        fi
    fi
    
    if [[ -n "${MODEL_API_KEY:-}" ]]; then
        if set_secret_secure "$repo" "MODEL_API_KEY" "$MODEL_API_KEY"; then
            : # Success
        else
            success=false
        fi
    fi
    
    if [[ "$success" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Install to single repo via API
install_to_repo() {
    local repo=$1
    local content=$(base64 < "$WORKFLOW_FILE")
    
    # Skip empty/invalid repo names
    if [[ -z "$repo" || "$repo" == *"Getting"* ]]; then
        return 1  # Invalid repo name
    fi
    
    # SECURITY: Validate repository format before processing
    if ! validate_repo "$repo"; then
        print $RED "❌ SECURITY ERROR: Invalid repository format: $repo"
        return 1
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
        # Also set the repository variable and secrets
        set_repo_variable "$repo"
        create_repo_secrets "$repo"
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
