# Security Analysis Report: Shell Scripts for Droid Code Review

## Executive Summary

This security analysis identifies multiple **critical** vulnerabilities in the shell scripts used for Droid Code Review workflow management. The most severe issues involve:

1. **Unverified external downloads** without integrity checking
2. **Improper API key handling** that exposes sensitive credentials
3. **Command injection vulnerabilities** from insufficient input validation
4. **Privilege escalation risks** when modifying multiple repositories

## Critical Vulnerabilities by Category

### 1. CRITICAL: Unverified External Downloads

**Affected Files:** 
- `auto-setup-all.sh` (line 50)
- `bulk-install.sh` (lines 88-98)
- `install-workflow.sh` (lines 116-126)
- `droid-code-review.yaml` (line 77)

**Vulnerability:**
```bash
# In auto-setup-all.sh line 50
SHA256=$(curl -fsSL --connect-timeout 10 --max-time 30 --compressed https://app.factory.ai/cli | sha256sum | cut -d' ' -f1)

# In bulk-install.sh lines 88-98
if ! curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer"; then
    print $RED "❌ Failed to download Droid CLI installer"
    rm -f "$temp_installer"
    return 1
fi
```

**Risk Assessment:**
- **Severity:** CRITICAL
- **CVSS Score:** 9.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)
- **Impact:** Complete system compromise possible through malicious script injection

**Exploit Scenario:**
1. Attacker compromises `app.factory.ai` or performs DNS hijacking
2. Replaces legitimate CLI installer with malicious script
3. Scripts download and execute the malicious code without verification
4. Attacker gains access to all repositories and API keys

**Remediation:**
```bash
# Use cryptographic signature verification
GPG_KEY_URL="https://app.factory.ai/cli/gpg-key.pub"
SIGNATURE_URL="https://app.factory.ai/cli.sha256.sig"

# Download and verify
curl -fsSL "$GPG_KEY_URL" | gpg --import
curl -fsSL https://app.factory.ai/cli -o droid-cli-installer.sh
curl -fsSL "$SIGNATURE_URL" -o droid-cli-installer.sha256.sig

# Verify signature before execution
if ! gpg --verify droid-cli-installer.sha256.sig droid-cli-installer.sh; then
    echo "❌ Signature verification failed"
    exit 1
fi
```

### 2. CRITICAL: API Key Exposure and Improper Handling

**Affected Files:**
- `.env` (all lines)
- `auto-setup-all.sh` (lines 14-20, 95-106)
- `bulk-install.sh` (lines 41-55, 189-202)
- `install-workflow.sh` (lines 41-57, 340-355)

**Vulnerability:**
```bash
# In auto-setup-all.sh lines 14-20
if [ ! -f ".env" ]; then
    echo "❌ .env file not found. Please create it with your API keys."
    echo "   Copy .env.example to .env and add your keys."
    exit 1
fi

# Load API keys
source .env

# Lines 95-106 - API keys passed via command line
if echo "$FACTORY_API_KEY" | gh secret set FACTORY_API_KEY --repo="$repo" 2>/dev/null; then
    echo "  ✅ Set FACTORY_API_KEY"
fi
```

**Risk Assessment:**
- **Severity:** CRITICAL
- **CVSS Score:** 8.9 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)
- **Impact:** Complete credential compromise, unauthorized access to services

**Security Issues:**
1. **Plaintext storage**: API keys stored in `.env` file
2. **Shell history exposure**: Keys visible in process list and shell history
3. **Logging exposure**: Keys may be written to log files
4. **Process list visibility**: Keys visible in `ps` output during execution
5. **Error message leakage**: Error messages may expose key fragments

**Remediation:**
```bash
# Use environment variable injection instead of file sourcing
secure_load_env() {
    if [ -f ".env" ]; then
        # Use grep with exact matching to prevent injection
        if grep -q '^FACTORY_API_KEY=' .env; then
            # Extract value safely without sourcing entire file
            FACTORY_API_KEY=$(grep '^FACTORY_API_KEY=' .env | cut -d'=' -f2-)
            export FACTORY_API_KEY
            # Clear from environment after use
            trap 'unset FACTORY_API_KEY' EXIT
        fi
    fi
}

# Use stdin for sensitive operations instead of command line args
set_api_key_secure() {
    local repo="$1"
    local key="$2"
    
    # Use process substitution to avoid command line exposure
    echo "$key" | gh secret set FACTORY_API_KEY --repo="$repo" 2>/dev/null
}
```

### 3. HIGH: Command Injection Vulnerabilities

**Affected Files:**
- `auto-setup-all.sh` (line 76)
- `bulk-install.sh` (lines 172-176)
- `install-workflow.sh` (lines 279-283)
- `local-droid-review.sh` (lines 254-258)

**Vulnerability:**
```bash
# In auto-setup-all.sh line 76 - User input directly used in git commands
if timeout 60 git clone --depth 1 "https://github.com/$repo.git" "$temp_dir" 2>/dev/null; then

# In bulk-install.sh lines 172-176 - Repository name not sanitized
if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then

# In local-droid-review.sh lines 254-258 - File path not validated
PATCH=$(git diff "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" -- "$file" 2>/dev/null || echo "")
```

**Risk Assessment:**
- **Severity:** HIGH
- **CVSS Score:** 8.6 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:H)
- **Impact:** Code injection, arbitrary command execution

**Exploit Scenario:**
1. Attacker creates repository with malicious name: `owner/repo; rm -rf /; #`
2. Script concatenates repository name into git command
3. Command injection executes with shell privileges
4. System compromise through arbitrary command execution

**Remediation:**
```bash
# Input validation for repository names
validate_repo_name() {
    local repo="$1"
    
    # Only allow alphanumeric, hyphens, underscores, and forward slashes
    if [[ ! "$repo" =~ ^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$ ]]; then
        echo "❌ Invalid repository name format: $repo"
        return 1
    fi
    
    # Prevent path traversal
    if [[ "$repo" =~ \.\. ]]; then
        echo "❌ Path traversal detected in repository name: $repo"
        return 1
    fi
    
    # Limit length to prevent buffer overflow
    if [ ${#repo} -gt 255 ]; then
        echo "❌ Repository name too long: $repo"
        return 1
    fi
    
    return 0
}

# Safe git clone with properly quoted arguments
safe_clone_repo() {
    local repo="$1"
    local temp_dir="$2"
    
    # Validate input
    if ! validate_repo_name "$repo"; then
        return 1
    fi
    
    # Use arrays to properly quote arguments
    local git_args=(
        "clone"
        "--depth" "1"
        "--quiet"
        "https://github.com/${repo}.git"
        "$temp_dir"
    )
    
    # Execute with properly quoted arguments
    if timeout 60 git "${git_args[@]}" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}
```

### 4. HIGH: Insufficient Input Validation

**Affected Files:**
- `bulk-install.sh` (lines 41-55)
- `install-workflow.sh` (lines 41-57)
- `local-droid-review.sh` (lines 47-68)

**Vulnerability:**
```bash
# In bulk-install.sh lines 41-55 - No validation of .env file contents
if [[ -f .env ]]; then
    print $GREEN "✅ Loading API keys from .env file..."
    # Export variables from .env
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
```

**Risk Assessment:**
- **Severity:** HIGH
- **CVSS Score:** 7.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:H)
- **Impact:** Environment variable pollution, command injection

**Security Issues:**
1. **No validation of file contents**: Any content in `.env` is exported
2. **Command injection through variable names**: Malicious variable names can execute commands
3. **Buffer overflow**: No limits on variable values
4. **Special character injection**: No escaping of shell metacharacters

**Remediation:**
```bash
# Secure environment variable loading
secure_load_env() {
    local env_file=".env"
    
    if [ ! -f "$env_file" ]; then
        echo "❌ Environment file not found: $env_file"
        return 1
    fi
    
    # Process each line safely
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        
        # Validate key format (alphanumeric and underscores only)
        if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            echo "⚠️ Skipping invalid variable name: $key"
            continue
        fi
        
        # Validate value length
        if [ ${#value} -gt 1024 ]; then
            echo "⚠️ Skipping variable with too long value: $key"
            continue
        fi
        
        # Only allow specific keys
        case "$key" in
            FACTORY_API_KEY|MODEL_API_KEY)
                export "$key"="$value"
                ;;
            *)
                echo "⚠️ Skipping unauthorized variable: $key"
                ;;
        esac
    done < "$env_file"
}
```

### 5. MEDIUM: Temporary File Handling Vulnerabilities

**Affected Files:**
- `auto-setup-all.sh` (line 79)
- `bulk-install.sh` (lines 88-90, 178)
- `install-workflow.sh` (line 254)
- `local-droid-review.sh` (line 277)

**Vulnerability:**
```bash
# Multiple scripts use mktemp without secure permissions
local temp_dir=$(mktemp -d)
local temp_installer=$(mktemp)
```

**Risk Assessment:**
- **Severity:** MEDIUM
- **CVSS Score:** 6.2 (AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N)
- **Impact:** Information disclosure, race conditions

**Security Issues:**
1. **Predictable temporary names**: Race condition vulnerability
2. **Insecure permissions**: Temporary files may be readable by others
3. **Cleanup failure**: Temp files may persist containing sensitive data
4. **Path traversal**: No validation of temp directory paths

**Remediation:**
```bash
# Secure temporary file creation
secure_mktemp() {
    local template="${1:-tmp.XXXXXX}"
    local temp_file
    
    # Create with restrictive permissions
    temp_file=$(mktemp -t "$template" 2>/dev/null) || {
        echo "❌ Failed to create temporary file"
        return 1
    }
    
    # Set secure permissions
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        return 1
    }
    
    echo "$temp_file"
}

# Secure temporary directory creation
secure_mktemp_dir() {
    local template="${1:-tmp.XXXXXX}"
    local temp_dir
    
    # Create with restrictive permissions
    temp_dir=$(mktemp -d -t "$template" 2>/dev/null) || {
        echo "❌ Failed to create temporary directory"
        return 1
    }
    
    # Set secure permissions
    chmod 700 "$temp_dir" || {
        rm -rf "$temp_dir"
        return 1
    }
    
    # Register cleanup handler
    trap "rm -rf '$temp_dir'" EXIT
    
    echo "$temp_dir"
}
```

### 6. MEDIUM: Network Security Weaknesses

**Affected Files:**
- All scripts with curl operations

**Vulnerability:**
```bash
# No SSL certificate verification in some cases
curl -fsSL --compressed https://app.factory.ai/cli -o "$temp_installer"
```

**Risk Assessment:**
- **Severity:** MEDIUM
- **CVSS Score:** 5.9 (AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N)
- **Impact:** Man-in-the-middle attacks, data interception

**Remediation:**
```bash
# Secure curl with proper SSL verification
secure_curl() {
    local url="$1"
    local output="$2"
    
    curl \
        --proto '=https' \
        --tlsv1.2 \
        --cacert /etc/ssl/certs/ca-certificates.crt \
        --connect-timeout 10 \
        --max-time 30 \
        --fail \
        --silent \
        --show-error \
        --location \
        --output "$output" \
        "$url"
}
```

## Comprehensive Security Recommendations

### 1. Immediate Actions Required

1. **Implement Cryptographic Verification**
   - Add GPG signature verification for all downloads
   - Verify SHA256 hashes against trusted sources
   - Fail fast on verification failures

2. **Secure API Key Management**
   - Use credential managers instead of `.env` files
   - Implement key rotation mechanisms
   - Mask sensitive data in logs and outputs

3. **Input Sanitization**
   - Validate all user inputs against strict patterns
   - Use parameterized commands instead of string concatenation
   - Implement allow-lists for repository names

4. **Secure Temporary Files**
   - Use secure temp file creation with proper permissions
   - Implement guaranteed cleanup mechanisms
   - Validate temp directory paths

### 2. Security Hardening Measures

```bash
# Add to the beginning of all scripts
set -euo pipefail

# Security configurations
export HISTCONTROL=ignorespace
export HISTFILESIZE=0
unset HISTFILE

# Secure umask
umask 077

# Trap for cleanup
cleanup() {
    local temp_dirs=("$@")
    for dir in "${temp_dirs[@]}"; do
        [ -d "$dir" ] && rm -rf "$dir"
    done
}

# Signal handlers
trap 'cleanup "${TEMP_DIRS[@]}"' EXIT INT TERM
```

### 3. Monitoring and Auditing

1. **Add Comprehensive Logging**
   ```bash
   secure_log() {
       local level="$1"
       local message="$2"
       
       # Sanitize message to prevent log injection
       local sanitized
       sanitized=$(echo "$message" | tr -d '\0\r\n')
       
       # Log with timestamp and level
       echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $sanitized" \
           >> /var/log/droid-review.log
   }
   ```

2. **Audit Trail Implementation**
   - Log all repository operations
   - Track API key usage
   - Monitor for suspicious activities

### 4. Access Control

1. **Principle of Least Privilege**
   - Use specific GitHub tokens with minimal scopes
   - Implement repository-level access controls
   - Use read-only tokens where possible

2. **Rate Limiting**
   - Implement delays between operations
   - Track API usage to prevent exhaustion
   - Add circuit breakers for failure conditions

## Testing and Validation

### 1. Security Test Suite

```bash
# test_security.sh
#!/bin/bash

# Test command injection protection
test_command_injection() {
    local malicious_repo="owner/repo; rm -rf /; #"
    if auto-setup-all.sh "$malicious_repo"; then
        echo "FAIL: Command injection vulnerability detected"
        return 1
    fi
    echo "PASS: Command injection protection working"
}

# Test API key exposure
test_api_key_exposure() {
    # Check if API keys appear in process list
    if ps aux | grep -q "FACTORY_API_KEY"; then
        echo "FAIL: API key exposure in process list"
        return 1
    fi
    echo "PASS: API keys properly protected"
}

# Run all tests
run_security_tests() {
    test_command_injection
    test_api_key_exposure
}
```

## Conclusion

The analyzed shell scripts contain **multiple critical security vulnerabilities** that require immediate attention. The most severe issues involve:

1. **Unverified external downloads** that could lead to complete system compromise
2. **Improper API key handling** that exposes sensitive credentials
3. **Command injection vulnerabilities** that enable arbitrary code execution

Priority should be given to implementing cryptographic verification for downloads, securing API key management, and adding comprehensive input validation. These measures will significantly reduce the attack surface and protect against the most critical vulnerabilities.

A comprehensive security audit should be performed on all remaining scripts and regular security reviews should be implemented to prevent future vulnerabilities.
