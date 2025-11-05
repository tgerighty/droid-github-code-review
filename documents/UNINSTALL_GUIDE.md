# Droid Code Review Workflow - Uninstallation Guide

This guide provides detailed information about removing the Droid Code Review workflow from your repositories.

## Table of Contents

- [Quick Uninstall](#quick-uninstall)
- [Advanced Uninstall](#advanced-uninstall)
- [What Gets Removed](#what-gets-removed)
- [Uninstall Options](#uninstall-options)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Quick Uninstall

The fastest way to remove the workflow from all your repositories:

```bash
./bulk-uninstall.sh
```

This script will:
1. Ask for confirmation before proceeding
2. Remove the workflow file from each repository
3. Delete all associated secrets and variables
4. Show you a summary of the results

## Advanced Uninstall

For more control over the uninstallation process, use the advanced script:

```bash
./uninstall-workflow.sh [OPTIONS]
```

### Available Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message and exit |
| `-b, --backup` | Keep a backup copy of the workflow file in each repository |
| `-i, --interactive` | Select repositories interactively |
| `-r, --repos REPOS` | Comma-separated list of specific repositories to uninstall from |
| `--dry-run` | Preview what would be removed without making changes |

## What Gets Removed

When you uninstall the workflow, the following items are removed from each repository:

### 1. Workflow File
- **Path**: `.github/workflows/droid-code-review.yaml`
- **Action**: Deleted (or backed up if using `--backup`)

### 2. Repository Variable
- **Name**: `DROID_INSTALLER_SHA256`
- **Purpose**: SHA256 checksum of the Droid CLI installer
- **Action**: Permanently deleted

### 3. Repository Secrets
- **Name**: `FACTORY_API_KEY`
- **Purpose**: Factory.ai API authentication
- **Action**: Permanently deleted

- **Name**: `MODEL_API_KEY`
- **Purpose**: Z.ai API authentication for GLM-4.6 model
- **Action**: Permanently deleted

## Uninstall Options

### Option 1: Remove from All Repositories

```bash
./bulk-uninstall.sh
```

**Use when**: You want to completely remove the workflow from all your repositories.

**What happens**:
- Scans all your repositories
- Removes workflow files
- Cleans up secrets and variables
- Shows progress and summary

### Option 2: Remove from Specific Repositories

```bash
./uninstall-workflow.sh --repos "owner/repo1,owner/repo2,owner/repo3"
```

**Use when**: You only want to remove the workflow from certain repositories.

**What happens**:
- Only processes the specified repositories
- Same cleanup as bulk uninstall
- Faster if you have many repositories

### Option 3: Interactive Selection

```bash
./uninstall-workflow.sh --interactive
```

**Use when**: You want to manually select which repositories to uninstall from.

**What happens**:
- Shows a numbered list of all your repositories
- You select which ones to uninstall from (e.g., "1,3,5-8")
- Processes only your selected repositories

### Option 4: Uninstall with Backup

```bash
./uninstall-workflow.sh --backup
```

**Use when**: You want to keep a copy of the workflow file for reference or future use.

**What happens**:
- Workflow file is copied to `.github/workflows/backup/droid-code-review.yaml`
- Original workflow file is removed
- Secrets and variables are still deleted
- Backup is committed to the repository

### Option 5: Dry Run (Preview Only)

```bash
./uninstall-workflow.sh --dry-run
```

**Use when**: You want to see what would be removed without actually making changes.

**What happens**:
- Shows list of repositories that would be processed
- Shows what would be removed from each repository
- No actual changes are made
- Safe to run anytime

## Examples

### Example 1: Complete Removal from All Repos

```bash
# Quick and simple - removes everything
./bulk-uninstall.sh
```

**Output**:
```
🗑️  Droid Code Review - Bulk Uninstallation
==========================================
✅ Prerequisites checked

⚠️  WARNING: This will remove the Droid Code Review workflow from ALL repositories
⚠️  It will also remove associated secrets and variables

Are you sure you want to continue? (yes/no): yes

📂 Getting your repositories...
📊 Found 10 repositories

🗑️  owner/repo1...
    ✅ Removed workflow
    ✓ Removed variable
    ✓ Removed secrets

🗑️  owner/repo2...
    ⚠️  Workflow not found
    ✓ Removed variable
    ✓ Removed secrets

...

🎉 Uninstallation complete!
✅ Success: 10

✅ Cleaned up:
   • Workflow files removed
   • DROID_INSTALLER_SHA256 variables deleted
   • FACTORY_API_KEY secrets deleted
   • MODEL_API_KEY secrets deleted
```

### Example 2: Remove from Specific Repositories

```bash
./uninstall-workflow.sh --repos "myorg/frontend,myorg/backend"
```

**Output**:
```
=== Droid Workflow Uninstallation Started ===

⚠️  WARNING: This will remove the Droid Code Review workflow and associated secrets/variables
⚠️  No backup will be kept (use --backup to keep a copy)

Are you sure you want to continue? (yes/no): yes

🗑️  Uninstalling from 2 specified repositories...

🔄 Processing myorg/frontend...
  ✅ Removed workflow from myorg/frontend
  🧹 Cleaning up secrets and variables...
  ✓ Removed DROID_INSTALLER_SHA256 variable
  ✓ Removed FACTORY_API_KEY secret
  ✓ Removed MODEL_API_KEY secret
✅ Completed myorg/frontend

🔄 Processing myorg/backend...
  ✅ Removed workflow from myorg/backend
  🧹 Cleaning up secrets and variables...
  ✓ Removed DROID_INSTALLER_SHA256 variable
  ✓ Removed FACTORY_API_KEY secret
  ✓ Removed MODEL_API_KEY secret
✅ Completed myorg/backend

🎉 Uninstallation completed!
✅ Successful: 2
```

### Example 3: Interactive Selection

```bash
./uninstall-workflow.sh --interactive
```

**Output**:
```
📂 Fetched 5 repositories...

📋 Available repositories:
  1. owner/repo1
  2. owner/repo2
  3. owner/repo3
  4. owner/repo4
  5. owner/repo5

Enter repository numbers to uninstall from (e.g., 1,3,5-8) or 'all' for all: 1,3,5

⚠️  WARNING: This will remove the Droid Code Review workflow and associated secrets/variables

Are you sure you want to continue? (yes/no): yes

🗑️  Uninstalling from 3 selected repositories...
[Processing repositories...]
```

### Example 4: Dry Run

```bash
./uninstall-workflow.sh --dry-run
```

**Output**:
```
🔍 DRY RUN MODE - No changes will be made
📂 Fetched 10 repositories...

Would uninstall workflow from 10 repositories:
owner/repo1
owner/repo2
owner/repo3
...

Would remove from each repository:
  • .github/workflows/droid-code-review.yaml
  • DROID_INSTALLER_SHA256 variable
  • FACTORY_API_KEY secret
  • MODEL_API_KEY secret
```

### Example 5: Uninstall with Backup

```bash
./uninstall-workflow.sh --backup --repos "owner/repo1"
```

**Output**:
```
🔄 Processing owner/repo1...
  📦 Created backup at .github/workflows/backup/droid-code-review.yaml
  ✅ Removed workflow from owner/repo1
  🧹 Cleaning up secrets and variables...
  ✓ Removed DROID_INSTALLER_SHA256 variable
  ✓ Removed FACTORY_API_KEY secret
  ✓ Removed MODEL_API_KEY secret
✅ Completed owner/repo1
```

## Using manage-workflows.sh

You can also use the management script to remove workflows:

```bash
# Remove from specific repositories
./manage-workflows.sh remove owner/repo1,owner/repo2
```

This provides the same functionality but integrates with other workflow management commands.

## Troubleshooting

### "Failed to clone repository"

**Cause**: Insufficient permissions or network issue.

**Solution**:
```bash
# Verify you have access to the repository
gh repo view owner/repo

# Check your authentication
gh auth status
```

### "Secret not found or already removed"

**Cause**: The secret may have been manually deleted already or never existed.

**Impact**: This is a warning, not an error. The script continues normally.

**Action**: No action needed - this is expected if secrets were already removed.

### "Variable not found or already removed"

**Cause**: The variable may have been manually deleted already or never existed.

**Impact**: This is a warning, not an error. The script continues normally.

**Action**: No action needed - this is expected if the variable was already removed.

### "Workflow not found"

**Cause**: The workflow file doesn't exist in the repository.

**Impact**: The script will still attempt to clean up secrets and variables.

**Action**: No action needed - the script will continue to clean up other resources.

### "Failed to push changes"

**Cause**: Insufficient permissions or branch protection rules.

**Solution**:
```bash
# Check if you have write access
gh api repos/owner/repo --jq '.permissions'

# Check branch protection rules
gh api repos/owner/repo/branches/main/protection
```

### Rate Limiting

If you have many repositories, you might hit GitHub API rate limits.

**Solution**: The scripts include automatic delays between operations. If you still hit limits:
```bash
# Check your rate limit status
gh api rate_limit

# Wait and try again later, or process fewer repositories at a time
./uninstall-workflow.sh --repos "repo1,repo2" # Process in batches
```

## Safety Features

All uninstallation scripts include safety features:

1. **Confirmation Prompt**: Always asks for explicit "yes" confirmation
2. **Warnings**: Clearly shows what will be removed
3. **Dry Run Mode**: Preview changes without making them
4. **Error Handling**: Continues processing other repositories if one fails
5. **Detailed Logging**: All operations are logged to `workflow-uninstallation.log`
6. **Backup Option**: Can keep workflow file copies for reference
7. **Rate Limiting Protection**: Automatic delays between operations

## Best Practices

1. **Start with Dry Run**: Always run with `--dry-run` first to preview changes
2. **Keep Backups**: Use `--backup` flag if you might need the workflow configuration later
3. **Specific First**: Test with specific repositories before bulk operations
4. **Check Logs**: Review `workflow-uninstallation.log` for detailed information
5. **Verify Access**: Ensure you have admin access to all target repositories

## After Uninstallation

Once the workflow is removed:

1. ✅ The workflow file is deleted from repositories
2. ✅ No more automated code reviews will run
3. ✅ Secrets and variables are permanently deleted
4. ✅ No trace of the workflow remains (unless backup was kept)

### To Reinstall Later

If you want to reinstall the workflow:

```bash
# Use the installation scripts
./quick-install.sh

# Or for specific repositories
./install-workflow.sh --repos "owner/repo1,owner/repo2"
```

## Need Help?

- Check the main [README.md](README.md) for general information
- Review [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for installation issues
- Check the log files for detailed error messages
- Ensure GitHub CLI is properly authenticated: `gh auth status`
