# Custom Model Configuration - GLM-4.6

## Overview

The Droid Code Review workflow has been extended to use a custom model (GLM-4.6) via Z.ai's API endpoint instead of the default Factory.ai models.

## Changes Made

### 1. Added MODEL_API_KEY Secret Validation

**File**: `droid-code-review.yaml`

**Location**: "Validate configuration and check prerequisites" step

**Change**: Added validation to ensure `MODEL_API_KEY` secret is configured before running the workflow.

```yaml
if [ -z "$MODEL_API_KEY" ]; then
  echo "❌ MODEL_API_KEY secret is not configured."
  echo "Add MODEL_API_KEY in repository settings → Secrets and variables → Actions."
  exit 1
fi
```

### 2. Created Custom Model Configuration Step

**File**: `droid-code-review.yaml`

**Location**: New step after "Install Droid CLI"

**Purpose**: Creates `~/.factory/config.json` with custom model configuration

**Details**:
- Creates `$HOME/.factory` directory (which is `/home/runner/.factory` on GitHub Actions ubuntu-latest runner)
- Generates `config.json` with GLM-4.6 model configuration
- Uses Z.ai's API endpoint: `https://api.z.ai/api/coding/paas/v4`
- Securely injects `MODEL_API_KEY` from GitHub secrets using jq
- Verifies configuration without exposing the API key

**Configuration Template**:
```json
{
  "custom_models": [
    {
      "model_display_name": "GLM-4.6 [Z.AI]",
      "model": "GLM-4.6",
      "base_url": "https://api.z.ai/api/coding/paas/v4",
      "api_key": "<injected from MODEL_API_KEY secret>",
      "provider": "generic-chat-completion-api",
      "max_tokens": 131072
    }
  ]
}
```

### 3. Updated Droid Exec Command

**File**: `droid-code-review.yaml`

**Location**: "Perform automated code review" step

**Change**: Added `-m "GLM-4.6"` parameter to use the custom model

```bash
# Before:
droid exec -f prompt.txt --skip-permissions-unsafe

# After:
droid exec -f prompt.txt -m "GLM-4.6" --skip-permissions-unsafe
```

**Note**: Uses the `model` field value ("GLM-4.6"), NOT the `model_display_name` field.

### 4. Updated README.md

**File**: `README.md`

**Change**: Added documentation for the new `MODEL_API_KEY` secret requirement

## Setup Instructions

### For New Installations

After running the installation script, configure both secrets in each repository:

1. **FACTORY_API_KEY** (existing requirement)
   - Go to repository settings → Secrets and variables → Actions
   - Add secret: `FACTORY_API_KEY` = Your Factory API key

2. **MODEL_API_KEY** (new requirement)
   - In the same section
   - Add secret: `MODEL_API_KEY` = Your Z.ai API key

### For Existing Installations

1. Update the workflow file:
   ```bash
   ./quick-install.sh  # This will update all repositories
   ```

2. Add the `MODEL_API_KEY` secret to each repository:
   - Go to each repository → Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `MODEL_API_KEY`
   - Value: Your Z.ai API key

## Technical Details

### GitHub Actions Environment

- **Runner**: `ubuntu-latest`
- **User**: `runner`
- **Home Directory**: `/home/runner`
- **Config Path**: `/home/runner/.factory/config.json`

### Environment Variables Used

- `$HOME` - Points to `/home/runner`
- `${{ secrets.FACTORY_API_KEY }}` - Factory.ai API key (existing)
- `${{ secrets.MODEL_API_KEY }}` - Z.ai API key for GLM-4.6 (new)

### Security Considerations

- API keys are stored as GitHub secrets (encrypted)
- Keys are never logged or displayed
- Config verification shows only whether API key is set, not the actual value
- Config file is created fresh on each workflow run

## Workflow Execution Flow

1. **Check API Keys (FIRST)** ✨ NEW - Fail Fast
   - Check `FACTORY_API_KEY` exists
   - Check `MODEL_API_KEY` exists
   - If missing: Post PR comment with setup instructions and exit gracefully
   - **Saves GitHub Actions minutes by not running unnecessary steps**

2. **Checkout Repository**
   - Only runs if API keys are present
   - Shallow clone for speed

3. **Validate Prerequisites**
   - Check `DROID_INSTALLER_SHA256` exists

4. **Install Droid CLI**
   - Install if not cached
   - Add to PATH

5. **Configure Custom Model** ✨ NEW
   - Create `~/.factory` directory
   - Generate `config.json` from template
   - Inject `MODEL_API_KEY` using jq
   - Verify configuration

6. **Perform Code Review**
   - Run `droid exec -m "GLM-4.6"` ✨ UPDATED
   - Generate review comments
   - Post to PR

## Fail-Fast Behavior ⚡

The workflow now checks API keys **before any other steps** to save GitHub Actions minutes:

### What Happens When Keys Are Missing

1. **Workflow starts** - Only the API key check runs (5-10 seconds)
2. **Check fails** - Detects missing API keys
3. **Posts PR comment** - Automatically adds a helpful comment to the PR:

```markdown
## ⚠️ Droid Code Review: Configuration Required

The automated code review cannot run because the following API keys are not configured:

- `FACTORY_API_KEY`
- `MODEL_API_KEY`

### Setup Instructions

1. Go to repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret** for each missing key:
   - **FACTORY_API_KEY**: Your Factory.ai API key
   - **MODEL_API_KEY**: Your Z.ai API key (for GLM-4.6 model)
3. Re-run this workflow or push a new commit to trigger the review
```

4. **Exits gracefully** - Workflow completes successfully (not failed)
5. **No wasted minutes** - Doesn't run checkout, install, or any other steps

### Benefits

- ✅ **Saves Actions minutes** - Exits in ~5-10 seconds instead of running full workflow
- ✅ **Better UX** - Clear instructions posted directly on the PR
- ✅ **No false failures** - Workflow succeeds (just skips review)
- ✅ **Easy recovery** - Just add the keys and re-run

## Testing the Configuration

To verify the custom model configuration is working:

1. Check the workflow logs for:
   ```
   ✅ Custom model configuration created at /home/runner/.factory/config.json
   ```

2. Look for the verification output showing:
   ```json
   {
     "model_display_name": "GLM-4.6 [Z.AI]",
     "model": "GLM-4.6",
     "base_url": "https://api.z.ai/api/coding/paas/v4",
     "provider": "generic-chat-completion-api",
     "max_tokens": 131072,
     "api_key_set": true
   }
   ```

3. Check the code review step shows:
   ```
   Running code review analysis with GLM-4.6 model...
   ```

## Troubleshooting

### Error: "MODEL_API_KEY secret is not configured"

**Solution**: Add the `MODEL_API_KEY` secret to your repository settings.

### Error: "droid exec failed"

**Possible Causes**:
- Missing or invalid `MODEL_API_KEY`
- Missing or invalid `FACTORY_API_KEY`
- Z.ai API endpoint is unreachable
- Model name mismatch (ensure using "GLM-4.6" not "GLM-4.6 Coding Plan")

**Solution**: Check workflow logs for specific error messages. Verify both API keys are valid.

### Model Not Using Custom Configuration

**Check**:
1. Verify `config.json` was created in the logs
2. Ensure `-m "GLM-4.6"` parameter is present in droid exec command
3. Confirm model name matches exactly (case-sensitive)

## Model Information

**Model Name**: GLM-4.6
**Display Name**: GLM-4.6 [Z.AI]
**Provider**: Generic Chat Completion API
**API Endpoint**: https://api.z.ai/api/coding/paas/v4
**Protocol**: Generic Chat Completion API
**Max Tokens**: 131072

## Future Enhancements

Potential improvements for consideration:

1. **Multiple Custom Models**: Support array of models for different review types
2. **Model Selection by PR Size**: Use different models based on PR complexity
3. **Fallback Model**: Automatic fallback to Factory.ai models if custom model fails
4. **Cost Tracking**: Log API usage for cost monitoring
5. **Model Performance Metrics**: Track review quality across different models
