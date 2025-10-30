# Shell Scripts Security Assessment Report

## Executive Summary

This report provides a comprehensive security analysis of 11 shell scripts in the Droid GitHub Code Review repository. The analysis identified multiple critical and high-severity vulnerabilities across the scripts, including command injection risks, insufficient input validation, and unsafe use of external commands.

**Overall Risk Rating: HIGH**

- Critical vulnerabilities: 3
- High vulnerabilities: 12
- Medium vulnerabilities: 8
- Low vulnerabilities: 5

## Detailed Security Findings

### 1. auto-setup-all.sh

**Overall Security Rating: HIGH**

#### Critical Vulnerabilities

1. **Command Injection - CRITICAL**
   - **Location:** Line 86-87, 98-99, 109-110
   - **Issue:** Repository names are directly interpolated into git commands without validation
   ```bash
   if timeout 60 git clone --depth 1 "https://github.com/$repo.git" "$temp_dir" 2>/dev/null; then
   if gh api repos/"$repo"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256" 2>/dev/null; then
   ```
   - **Risk:** Malicious repository names could execute arbitrary commands
   - **Fix:** Validate repository name format and use parameter passing instead of string interpolation

2. **Hardcoded Default SHA256 - HIGH**
   - **Location:** Lines 244-245 in setup-new-repo.sh (similar pattern in auto-setup-all.sh)
   - **Issue:** Static SHA256 hash used as fallback
   ```bash
   SHA256_VALUE="${DROID_INSTALLER_SHA256:-e31357edcacd7434670621617a0d327ada7491f2d4ca40e3cac3829c388fad9a}"
   ```
   - **Risk:** Compromised installer could be accepted if hash verification fails
   - **Fix:** Fail securely instead of using hardcoded fallback

#### High Vulnerabilities

3. **Unsafe Environment Variable Sourcing - HIGH**
   - **Location:** Line 32-33
   - **Issue:** Source command executes .env file without validation
   ```bash
   source .env
   if [ -z "${FACTORY_API_KEY:-}" ] || [ -z "${MODEL_API_KEY:-}" ]; then
   ```
   - **Risk:** Malicious .env file could execute arbitrary commands
   - **Fix:** Parse .env file safely with key-value validation

4. **Insufficient API Key Validation - HIGH**
   - **Location:** Lines 34-36
   - **Issue:** Only checks for non-empty strings, not valid key format
   - **Risk:** Invalid or malicious keys could be processed
   - **Fix:** Implement format validation for API keys

### 2. bulk-install.sh

**Overall Security Rating: HIGH**

#### Critical Vulnerabilities

1. **Command Injection via Repository Names - CRITICAL**
   - **Location:** Lines 165, 170
   - **Issue:** Unvalidated repository names in git commands
   ```bash
   if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
   ```
   - **Risk:** Repository name injection could lead to command execution
   - **Fix:** Validate repository names against expected format (owner/repo)

#### High Vulnerabilities

2. **Unsafe File Operations - HIGH**
   - **Location:** Lines 173-174
   - **Issue:** File paths used without validation
   ```bash
   cp "$OLDPWD/$WORKFLOW_FILE" "$WORKFLOW_PATH"
   git add "$WORKFLOW_PATH"
   ```
   - **Risk:** Path traversal if WORKFLOW_PATH is manipulated
   - **Fix:** Validate and sanitize file paths

3. **Environment Variable Pollution Risk - HIGH**
   - **Location:** Line 67
   - **Issue:** Export all variables from .env without filtering
   ```bash
   export $(grep -v '^#' .env | grep -v '^$' | xargs)
   ```
   - **Risk:** Could overwrite critical environment variables
   - **Fix:** Only export specific required variables

### 3. bulk-uninstall.sh

**Overall Security Rating: MEDIUM**

#### High Vulnerabilities

1. **Command Injection via Repository Names - HIGH**
   - **Location:** Lines 93, 118
   - **Issue:** Unvalidated repository names in commands
   ```bash
   if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
   if git push origin "HEAD:${default_branch}"; then
   ```
   - **Risk:** Repository name injection
   - **Fix:** Validate repository name format

#### Medium Vulnerabilities

2. **Unsafe Branch Name Handling - MEDIUM**
   - **Location:** Lines 124-128
   - **Issue:** Branch names used without proper validation
   ```bash
   local default_branch="main"
   if ! git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
       if git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
           default_branch="master"
       fi
   fi
   ```
   - **Risk:** Could be manipulated for command injection
   - **Fix:** Use a whitelist of allowed branch names

### 4. install-workflow.sh

**Overall Security Rating: HIGH**

#### Critical Vulnerabilities

1. **Command Injection via Repository Names - CRITICAL**
   - **Location:** Lines 159, 195, 207
   - **Issue:** Multiple instances of unvalidated repository names
   ```bash
   if ! gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch; then
   if ! git push origin "HEAD:${default_branch}"; then
   if gh variable set DROID_INSTALLER_SHA256 --repo "$repo" --body "$DROID_INSTALLER_SHA256" 2>&1 > /dev/null; then
   ```
   - **Risk:** Severe command injection possibility
   - **Fix:** Implement strict repository name validation

#### High Vulnerabilities

2. **Unsafe Environment Handling - HIGH**
   - **Location:** Lines 75-79
   - **Issue:** Same environment variable pollution issue as other scripts
   - **Risk:** Environment variable manipulation
   - **Fix:** Selective variable export with validation

3. **Insecure Temporary Directory Usage - HIGH**
   - **Location:** Line 158
   - **Issue:** Temporary directory without proper permissions
   ```bash
   local temp_dir=$(mktemp -d)
   ```
   - **Risk:** Other users could access temporary files
   - **Fix:** Set restrictive permissions on temp directory (chmod 700)

### 5. local-droid-review-codex.sh

**Overall Security Rating: CRITICAL**

#### Critical Vulnerabilities

1. **Command Injection via Git Operations - CRITICAL**
   - **Location:** Multiple lines (51, 54, 65, 71, etc.)
   - **Issue:** Git commands with interpolated variables without validation
   ```bash
   LATEST_COMMIT=$(git rev-parse HEAD)
   PREVIOUS_COMMIT=$(git rev-parse HEAD~1 2>/dev/null)
   CHANGED_FILES=$(git diff --name-only "${PREVIOUS_COMMIT}..${LATEST_COMMIT}")
   ```
   - **Risk:** Git command injection through manipulated environment or repository state
   - **Fix:** Validate all git references and use argument arrays

2. **Unsafe File Processing - CRITICAL**
   - **Location:** Lines 135-150
   - **Issue:** Processing files without validation or limits
   - **Risk:** Could process malicious files leading to code execution
   - **Fix:** Implement file type validation and size limits

3. **Model Name Injection - HIGH**
   - **Location:** Lines 13-14, 310
   - **Issue:** Hardcoded but vulnerable to modification
   ```bash
   MODEL_NAME="gpt-5"
   if codex exec --model "${CODEX_MODEL}" --json --output-last-message comments.json "$(cat prompt.txt)"; then
   ```
   - **Risk:** Model name could be manipulated
   - **Fix:** Validate model names against whitelist

### 6. local-droid-review-secure.sh

**Overall Security Rating: MEDIUM** (Notably more secure than others)

#### Medium Vulnerabilities

1. **Remaining Command Injection Risks - MEDIUM**
   - **Location:** Lines 257-258
   - **Issue:** Despite improvements, some risk remains
   ```bash
   if ! gh secret set FACTORY_API_KEY --repo "$repo" --body "$FACTORY_API_KEY" 2>&1 > /dev/null; then
   ```
   - **Risk:** Limited command injection potential
   - **Fix:** Complete validation of all parameters

#### Positive Security Features

This script demonstrates several good security practices:
- Input sanitization functions
- Commit hash validation
- Path traversal protection
- Safe command execution patterns
- Resource limits

### 7. local-droid-review.sh

**Overall Security Rating: HIGH**

#### High Vulnerabilities

1. **Command Injection via Git Operations - HIGH**
   - **Location:** Multiple lines throughout
   - **Issue:** Similar to codex version but without security fixes
   ```bash
   LATEST_COMMIT=$(git rev-parse HEAD)
   CHANGED_FILES=$(git diff --name-only "${PREVIOUS_COMMIT}..${LATEST_COMMIT}")
   ```
   - **Risk:** Git command injection
   - **Fix:** Implement same security measures as secure version

2. **Unsafe File Processing - HIGH**
   - **Location:** Lines 100-120
   - **Issue:** File processing without validation
   - **Risk:** Similar to codex version
   - **Fix:** Add file validation and processing limits

### 8. manage-workflows.sh

**Overall Security Rating: HIGH**

#### High Vulnerabilities

1. **Repository Name Injection - HIGH**
   - **Location:** Lines 178, 205, 247
   - **Issue:** Unvalidated repository names
   ```bash
   if gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch; then
   if git push origin "HEAD:${default_branch}"; then
   ```
   - **Risk:** Command injection through repository names
   - **Fix:** Validate repository names

2. **Unsafe API Calls - HIGH**
   - **Location:** Line 86
   - **Issue:** API calls without validation
   ```bash
   if gh api "repos/$repo/contents/.github/workflows/droid-code-review.yaml" 2>/dev/null | jq -e '.name' > /dev/null; then
   ```
   - **Risk:** API injection
   - **Fix:** Validate repository names and API responses

### 9. quick-install.sh

**Overall Security Rating: HIGH**

#### Critical Vulnerabilities

1. **API Command Injection - CRITICAL**
   - **Location:** Lines 170-178
   - **Issue:** Direct API calls with interpolated variables
   ```bash
   api_response=$(gh api --method PUT "repos/$repo/contents/$WORKFLOW_PATH" \
       --field message="Update Droid automated code review workflow" \
       --field content="$content" \
       --field sha="$sha" 2>&1)
   ```
   - **Risk:** API parameter injection
   - **Fix:** Validate all API parameters and use proper encoding

#### High Vulnerabilities

2. **Repository Name Validation Missing - HIGH**
   - **Location:** Lines 163-165
   - **Issue:** Basic checks insufficient
   ```bash
   if [[ -z "$repo" || "$repo" == *"Getting"* ]]; then
       return 1  # Invalid repo name
   fi
   ```
   - **Risk:** Incomplete validation allows injection
   - **Fix:** Implement full repository name format validation

### 10. setup-new-repo.sh

**Overall Security Rating: HIGH**

#### High Vulnerabilities

1. **Command Injection - HIGH**
   - **Location:** Lines 59, 70, 76-77
   - **Issue:** Unvalidated repository name
   ```bash
   if ! timeout 60 git clone "https://github.com/$REPO.git" "$TEMP_DIR"; then
   gh api repos/"$REPO"/actions/variables -X POST -f name=DROID_INSTALLER_SHA256 -f value="$SHA256_VALUE"
   echo "$FACTORY_API_KEY" | gh secret set FACTORY_API_KEY --repo="$REPO"
   ```
   - **Risk:** Repository name injection
   - **Fix:** Validate repository name format

2. **Hardcoded SHA256 Fallback - HIGH**
   - **Location:** Line 75
   - **Issue:** Same issue as auto-setup-all.sh
   - **Risk:** Security bypass through fallback
   - **Fix:** Remove hardcoded fallback, fail securely

### 11. uninstall-workflow.sh

**Overall Security Rating: MEDIUM**

#### High Vulnerabilities

1. **Repository Name Injection - HIGH**
   - **Location:** Lines 183, 207, 237
   - **Issue:** Similar to other scripts
   ```bash
   if ! gh repo clone "$repo" "$temp_dir" -- --quiet --depth=1 --filter=blob:none --single-branch 2>/dev/null; then
   if ! git push origin "HEAD:${default_branch}"; then
   ```
   - **Risk:** Command injection
   - **Fix:** Validate repository names

## Common Vulnerability Patterns

### 1. Command Injection (Critical/High)
- **Affected Scripts:** All scripts except local-droid-review-secure.sh
- **Root Cause:** Unvalidated user input (repository names) in shell commands
- **Impact:** Arbitrary command execution
- **Remediation:** Implement strict input validation and use parameter arrays

### 2. Environment Variable Pollution (High)
- **Affected Scripts:** auto-setup-all.sh, bulk-install.sh, install-workflow.sh, quick-install.sh
- **Root Cause:** Blindly exporting all variables from .env files
- **Impact:** System configuration manipulation
- **Remediation:** Selective variable export with validation

### 3. Hardcoded Security Values (High)
- **Affected Scripts:** auto-setup-all.sh, setup-new-repo.sh
- **Root Cause:** Fallback security values
- **Impact:** Security bypass vulnerabilities
- **Remediation:** Fail securely without fallbacks

## Recommended Security Improvements

### Immediate Actions (Critical/High)

1. **Input Validation Framework**
   ```bash
   validate_repo_name() {
       local repo="$1"
       if [[ ! "$repo" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]]; then
           echo "Invalid repository format: $repo" >&2
           return 1
       fi
       return 0
   }
   ```

2. **Safe Command Execution**
   ```bash
   safe_git_clone() {
       local repo="$1"
       local temp_dir="$2"
       validate_repo_name "$repo" || return 1
       git clone --depth 1 "https://github.com/$repo.git" "$temp_dir"
   }
   ```

3. **Secure Environment Handling**
   ```bash
   load_env_secure() {
       if [[ -f .env ]]; then
           while IFS='=' read -r key value; do
               case "$key" in
                   FACTORY_API_KEY|MODEL_API_KEY)
                       export "$key=$value"
                       ;;
               esac
           done < .env
       fi
   }
   ```

### Long-term Improvements

1. **Security Hardening Template**
   - Adopt security patterns from local-droid-review-secure.sh
   - Implement comprehensive input validation
   - Add error handling and logging

2. **Dependency Management**
   - Pin versions of external tools (gh, jq, curl)
   - Verify tool integrity before execution

3. **Audit Logging**
   - Log all security-relevant operations
   - Implement tamper-evident logging

## Conclusion

The shell scripts in this repository contain serious security vulnerabilities that require immediate attention. The most critical issues are command injection vulnerabilities through repository names and unsafe environment variable handling.

**local-droid-review-secure.sh** serves as a good example of proper security practices and should be used as a template for hardening the other scripts.

Priority should be given to:
1. Implementing input validation for all user-controlled data
2. Replacing unsafe string interpolation with parameter arrays
3. Removing hardcoded security fallbacks
4. Implementing proper error handling and secure defaults

The overall security posture can be significantly improved by addressing these vulnerabilities systematically.
