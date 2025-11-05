# Environment Variable Setup for API Keys

## Summary of Changes

All three installation scripts (`quick-install.sh`, `bulk-install.sh`, and `install-workflow.sh`) have been updated to automatically create repository secrets from a `.env` file.

## Benefits

✅ **Automated Secret Creation**: No need to manually add secrets to each repository  
✅ **Secure**: API keys stored in gitignored `.env` file  
✅ **Convenient**: One-time setup for all repositories  
✅ **Flexible**: Can still add secrets manually if preferred  

## Setup Instructions

### Step 1: Create `.env` File

```bash
# Copy the example file
cp .env.example .env
```

### Step 2: Add Your API Keys

Edit the `.env` file and add your actual API keys:

```bash
# Droid Code Review API Keys
FACTORY_API_KEY=your_factory_api_key_here
MODEL_API_KEY=your_zai_api_key_here
```

**Where to get the keys:**
- `FACTORY_API_KEY`: Get from https://app.factory.ai/settings
- `MODEL_API_KEY`: Get from https://api.z.ai/

### Step 3: Run Installation Script

```bash
# Any of these will work
./quick-install.sh         # Fast API-based installation
./bulk-install.sh          # Simple bulk installation
./install-workflow.sh      # Advanced installation with options
```

## What Happens Automatically

When you run any installation script with a `.env` file configured:

1. **Loads API Keys**: Reads `FACTORY_API_KEY` and `MODEL_API_KEY` from `.env`
2. **Installs Workflow**: Adds `.github/workflows/droid-code-review.yaml` to each repository
3. **Creates Secrets**: Automatically creates both secrets in each repository using `gh secret set`
4. **Sets Variable**: Sets `DROID_INSTALLER_SHA256` repository variable
5. **Confirms**: Shows success message when secrets are created

## Script Behavior

### With `.env` File Present

```
✅ Loading API keys from .env file...
✅ API keys loaded successfully
... (installation proceeds) ...
✅ DROID_INSTALLER_SHA256 variable has been set automatically on all repositories
✅ FACTORY_API_KEY and MODEL_API_KEY secrets have been created in all repositories
```

### Without `.env` File

```
⚠️  .env file not found. API secrets will not be created.
   To create secrets automatically, copy .env.example to .env and add your keys.
... (installation proceeds) ...
✅ DROID_INSTALLER_SHA256 variable has been set automatically on all repositories

🔔 REMINDER: API secrets were not created automatically.
   To create secrets automatically next time:
   1. Copy .env.example to .env
   2. Add your API keys to the .env file
   3. Run this script again
   
   Or add them manually to each repository:
   Repository Settings → Secrets and variables → Actions → New repository secret
   Required secrets:
   - FACTORY_API_KEY: Your Factory.ai API key
   - MODEL_API_KEY: Your Z.ai API key (for GLM-4.6 model)
```

## Security Considerations

### ✅ Safe Practices

- `.env` is added to `.gitignore` - will never be committed to Git
- Secrets are transmitted securely via GitHub CLI
- Each repository gets its own copy of the secrets
- API keys are only read during script execution

### ⚠️ Important Notes

- **Never commit `.env` to Git**
- Keep your `.env` file in the root of this project only
- Don't share your `.env` file with others
- If you need to rotate keys, update `.env` and re-run the scripts

## Troubleshooting

### API Keys Not Loading

If you see "⚠️ API keys not found in .env file":

1. Check that `.env` file exists in the current directory
2. Verify the keys are named exactly: `FACTORY_API_KEY` and `MODEL_API_KEY`
3. Make sure there are no spaces around the `=` sign
4. Check that the file has actual values, not placeholders

### Secrets Not Created

If secrets aren't being created:

1. Verify you're authenticated with GitHub CLI: `gh auth status`
2. Check you have write access to the repositories
3. Review the logs in `workflow-installation.log` for errors
4. Try creating a secret manually to verify permissions:
   ```bash
   gh secret set TEST_SECRET --repo your-org/your-repo --body "test"
   ```

### Update Existing Secrets

To update secrets in repositories that already have them:

1. Update the values in your `.env` file
2. Run any installation script again
3. The `gh secret set` command will overwrite existing secrets

## Manual Secret Creation (Alternative)

If you prefer not to use `.env` or need to add secrets manually:

```bash
# For a single repository
gh secret set FACTORY_API_KEY --repo owner/repo --body "your_key_here"
gh secret set MODEL_API_KEY --repo owner/repo --body "your_key_here"

# For multiple repositories (loop)
for repo in owner/repo1 owner/repo2 owner/repo3; do
  gh secret set FACTORY_API_KEY --repo $repo --body "your_key_here"
  gh secret set MODEL_API_KEY --repo $repo --body "your_key_here"
done
```

## Files Added/Modified

### New Files
- `.env.example` - Template file with placeholder values
- `.gitignore` - Updated to include `.env`
- `ENV_SETUP.md` - This documentation file

### Modified Files
- `quick-install.sh` - Added `.env` loading and secret creation
- `bulk-install.sh` - Added `.env` loading and secret creation
- `install-workflow.sh` - Added `.env` loading and secret creation
- `README.md` - Updated with `.env` setup instructions

## Example Workflow

```bash
# 1. Initial setup (one time)
cp .env.example .env
nano .env  # Add your API keys

# 2. Install to all repositories
./quick-install.sh

# 3. Verify secrets were created
gh secret list --repo your-org/your-repo

# 4. Done! All repositories now have:
#    - droid-code-review.yaml workflow
#    - FACTORY_API_KEY secret
#    - MODEL_API_KEY secret  
#    - DROID_INSTALLER_SHA256 variable
```

## Questions?

If you encounter any issues or have questions:

1. Check the troubleshooting section above
2. Review the logs in `workflow-installation.log`
3. Verify your `.env` file format matches `.env.example`
4. Ensure GitHub CLI is properly authenticated
