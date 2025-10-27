# Troubleshooting Guide: Droid Code Review Workflow

## Common Errors

### Error: `Process completed with exit code 1` at "Install Droid CLI"

**Symptoms:**
- The workflow fails immediately at the "Install Droid CLI" step
- Error message: `set -euo pipefail` followed by `Process completed with exit code 1`
- No detailed error output

**Root Causes:**

1. **Cached droid binary is corrupted or outdated**
   - The cache contains an old/broken version of droid
   - The workflow tries to use it but fails

2. **DROID_INSTALLER_SHA256 mismatch**
   - The SHA256 in repository variables doesn't match the actual installer
   - Installation verification fails silently

3. **PATH issues**
   - The droid binary isn't where expected
   - Permissions issue with cached binary

**Solutions:**

#### Option 1: Clear the Actions Cache (Recommended)

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Click **Caches** in the left sidebar
4. Find and delete all caches starting with `droid-cli-`
5. Re-run the failed workflow

#### Option 2: Update DROID_INSTALLER_SHA256

The installer SHA256 may have changed. Update it:

```bash
# Get the current SHA256 of the Droid installer
curl -fsSL https://app.factory.ai/cli | sha256sum

# Update the repository variable via GitHub CLI
gh variable set DROID_INSTALLER_SHA256 --body "NEW_SHA256_HERE" --repo YOUR_OWNER/YOUR_REPO
```

Or via GitHub UI:
1. Go to **Settings** → **Secrets and variables** → **Actions** → **Variables**
2. Edit `DROID_INSTALLER_SHA256`
3. Update to the new SHA256

#### Option 3: Manually Trigger Cache Rebuild

Push an empty commit to force a fresh workflow run:

```bash
git commit --allow-empty -m "chore: rebuild droid cache"
git push
```

### Error: Missing API Keys

**Symptoms:**
- Workflow posts a comment about missing API keys
- Exits successfully but doesn't perform review

**Solution:**
Add the required secrets:

1. Go to **Settings** → **Secrets and variables** → **Actions**
2. Add `FACTORY_API_KEY` with your Factory.ai API key
3. Add `MODEL_API_KEY` with your Z.ai API key
4. Re-run the workflow

### Error: Invalid JSON in comments.json

**Symptoms:**
- Workflow completes but shows "Invalid JSON" error
- Debug artifacts contain malformed JSON

**Solution:**
This is usually an AI generation issue. The workflow automatically handles this by creating an empty `comments.json`. No action needed - the workflow will retry on the next PR update.

### Error: Droid command not found in subsequent steps

**Symptoms:**
- Install step succeeds
- Later steps fail with "droid: command not found"

**Solution:**
This is a PATH issue. The fix is already in the updated workflow - it adds `$HOME/.local/bin` to `$GITHUB_PATH`.

## Debugging Steps

### 1. Check Workflow Logs

```bash
# List recent workflow runs
gh run list --repo OWNER/REPO --workflow="droid-code-review.yaml" --limit 5

# View specific run logs
gh run view RUN_ID --repo OWNER/REPO --log

# View only failed steps
gh run view RUN_ID --repo OWNER/REPO --log-failed
```

### 2. Check Repository Configuration

```bash
# Check secrets (won't show values, just names)
gh secret list --repo OWNER/REPO

# Check variables
gh variable list --repo OWNER/REPO
```

### 3. Download Debug Artifacts

When the workflow fails, it uploads debug artifacts:

```bash
# List artifacts
gh run view RUN_ID --repo OWNER/REPO

# Download artifacts
gh run download RUN_ID --repo OWNER/REPO
```

Debug artifacts include:
- `diff.txt` - The PR diff being reviewed
- `files.json` - File patches with line numbers
- `existing_comments.json` - Comments already on the PR
- `prompt.txt` - The prompt sent to the AI
- `comments.json` - The AI's review output

## Manual Test

To test the workflow locally:

### Test Droid Installation

```bash
# Download and verify the installer
curl -fsSL https://app.factory.ai/cli -o droid-cli-installer.sh
sha256sum droid-cli-installer.sh

# Compare with your DROID_INSTALLER_SHA256 variable
# If they don't match, update the variable

# Install droid
sh droid-cli-installer.sh

# Verify
~/.local/bin/droid --version
```

### Test Custom Model Configuration

```bash
# Create config directory
mkdir -p ~/.factory

# Create config.json
cat > ~/.factory/config.json << 'EOF'
{
  "custom_models": [
    {
      "model_display_name": "GLM-4.6 [Z.AI]",
      "model": "GLM-4.6",
      "base_url": "https://api.z.ai/api/coding/paas/v4",
      "api_key": "YOUR_MODEL_API_KEY_HERE",
      "provider": "generic-chat-completion-api",
      "max_tokens": 131072
    }
  ]
}
EOF

# Test the model
echo "Test prompt" > test.txt
droid exec -f test.txt -m "glm-4.6" --skip-permissions-unsafe
```

## Getting Help

If none of the above solutions work:

1. **Check the updated workflow file**: Make sure you're using the latest version with improved error handling
2. **Review recent changes**: Check if any recent commits to your repo might have broken the workflow
3. **Check GitHub Status**: Visit https://www.githubstatus.com/ to see if there are any ongoing incidents
4. **Contact support**: Reach out with:
   - Repository name
   - Workflow run ID
   - Full error logs
   - Steps already tried
