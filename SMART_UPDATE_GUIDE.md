# Smart Update Guide

## Overview

The `smart-update.sh` script provides intelligent update management for the Droid Code Review workflow across all your repositories. It automatically detects what needs updating and performs only the necessary changes.

## Why Use Smart Update?

### The Problem

When managing a workflow across many repositories, you often face these scenarios:

1. **SHA256 Changes**: The Droid CLI installer gets updated, requiring a new SHA256 hash
2. **Workflow Changes**: You modify the workflow file and need to push it to all repos
3. **Mixed Changes**: Some repos need full updates, others just SHA256 updates

Traditional update methods force you to:
- Update everything (slow and wasteful)
- Manually track what changed (error-prone)
- Risk overwriting unchanged files

### The Solution

`smart-update.sh` intelligently:
- ✅ Fetches the latest Droid CLI SHA256 automatically
- ✅ Compares your local workflow with each repository's workflow
- ✅ Updates only what changed (SHA256, workflow, or both)
- ✅ Skips repositories that are already up-to-date
- ✅ Provides clear reporting on what was updated

## Quick Start

```bash
# Basic smart update (recommended for most cases)
./smart-update.sh

# Force full workflow update for all repositories
./smart-update.sh --force-full

# Only update SHA256 variable, skip workflow comparison
./smart-update.sh --sha256-only

# Show help
./smart-update.sh --help
```

## How It Works

### Smart Mode (Default)

When you run `./smart-update.sh` without options:

```
┌─────────────────────────────────────────────────────────┐
│ 1. Fetch Latest Droid CLI SHA256                       │
│    Downloads and calculates current SHA256 hash         │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Get All Repositories                                │
│    Lists all accessible GitHub repositories              │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Process Each Repository                             │
│    For each repo:                                        │
│    a. Get current SHA256 variable                       │
│    b. Compare local vs remote workflow                  │
│    c. Determine update strategy                         │
└─────────────────────────────────────────────────────────┘
                         ↓
           ┌─────────────┴─────────────┐
           │                           │
      No Changes                   Has Changes
           │                           │
           v                           v
    ⏭️ Skip Repo              ┌──────────────┐
                             │  Workflows    │
                             │  Identical?   │
                             └──────┬───────┘
                                    │
                    ┌───────────────┼───────────────┐
                    │                               │
                  Yes                              No
                    │                               │
                    v                               v
            ⚡ Update SHA256               ✅ Full Update
            (Variable Only)               (Workflow + SHA256)
```

### Decision Logic

For each repository, the script:

1. **Checks SHA256**: Gets the current `DROID_INSTALLER_SHA256` variable
2. **Compares Workflows**: Downloads and compares remote workflow with local file
3. **Decides Strategy**:
   - **Workflows identical + SHA256 different** → SHA256-only update ⚡
   - **Workflows different** → Full update (workflow + SHA256) ✅
   - **Both identical** → Skip (no changes needed) ⏭️

## Update Modes

### 1. Smart Mode (Default)

```bash
./smart-update.sh
```

**Best for:**
- Regular maintenance
- When you're not sure what changed
- Automatic optimization

**What it does:**
- Compares workflows before updating
- Only updates what changed
- Fastest and most efficient

### 2. Force Full Mode

```bash
./smart-update.sh --force-full
```

**Best for:**
- After modifying the workflow file
- When you want to ensure consistency
- Forcing a complete refresh

**What it does:**
- Skips workflow comparison
- Updates both workflow and SHA256 for all repos
- Ensures all repos have identical workflows

### 3. SHA256-Only Mode

```bash
./smart-update.sh --sha256-only
```

**Best for:**
- When only the Droid CLI was updated
- Maximum speed
- You know the workflow hasn't changed

**What it does:**
- Skips workflow comparison and update
- Only updates the SHA256 variable
- Fastest possible update

## Understanding the Output

### Example Output

```
🚀 Smart Update - Droid Code Review Workflow
=============================================

✅ Prerequisites checked

🔍 Fetching current Droid CLI installer SHA256...
✅ Current SHA256: d5c0d4615da546b3d6c604b919a4eac952482b3593b506977c30e5ba354c334a

📋 Mode: Smart update (minimal changes)

📊 Processing 15 repositories...

REPOSITORY                                         STATUS
-------------------------------------------------- --------------------
[  1/ 15] tgerighty/repo1                          ⚡ SHA256 updated
[  2/ 15] tgerighty/repo2                          ✅ Full update
[  3/ 15] tgerighty/repo3                          ⏭️  No changes needed
[  4/ 15] tgerighty/repo4                          ⚡ SHA256 updated
[  5/ 15] tgerighty/repo5                          ❌ Failed

========================================
📊 UPDATE SUMMARY

⚡ SHA256 only updates: 10
✅ Full workflow updates: 3
⏭️  No changes needed: 1
❌ Failed: 1
📈 Total processed: 15

🎊 Great! 93% success rate!

🔍 What happened:
   • 10 repositories: SHA256 variable updated (workflow unchanged)
   • 3 repositories: Full update (workflow + SHA256)
   • 1 repositories: Already up to date
   • 1 repositories: Failed to update
```

### Status Indicators

| Symbol | Status | Meaning |
|--------|--------|---------|
| ⚡ | SHA256 updated | Only the SHA256 variable was updated (workflow unchanged) |
| ✅ | Full update | Both workflow and SHA256 were updated |
| ⏭️ | No changes needed | Repository is already up-to-date |
| ❌ | Failed | Update failed (check permissions or network) |

## Use Cases

### Use Case 1: Droid CLI Updated

**Scenario**: Factory.ai released a new version of the Droid CLI installer.

**Solution**:
```bash
./smart-update.sh
```

**What happens**:
- Fetches the new SHA256 hash
- Compares workflows (they're identical)
- Updates only the SHA256 variable across all repos
- Fast: ~2-3 seconds per repository

**Output**:
```
⚡ SHA256 only updates: 15
✅ Full workflow updates: 0
```

### Use Case 2: Modified Workflow File

**Scenario**: You improved the workflow (added caching, fixed a bug, etc.)

**Solution**:
```bash
./smart-update.sh
```

**What happens**:
- Detects workflow file differences
- Updates both workflow and SHA256 for all repos
- Ensures consistency across all repositories

**Output**:
```
⚡ SHA256 only updates: 0
✅ Full workflow updates: 15
```

### Use Case 3: Mixed State

**Scenario**: Some repos have old workflows, others are current, all need new SHA256.

**Solution**:
```bash
./smart-update.sh
```

**What happens**:
- Old workflow repos: Full update (workflow + SHA256)
- Current workflow repos: SHA256-only update
- Up-to-date repos: Skipped

**Output**:
```
⚡ SHA256 only updates: 10
✅ Full workflow updates: 3
⏭️  No changes needed: 2
```

### Use Case 4: Force Consistency

**Scenario**: You want to ensure all repos have the exact same workflow.

**Solution**:
```bash
./smart-update.sh --force-full
```

**What happens**:
- Skips comparison
- Updates everything
- Guarantees consistency

**Output**:
```
✅ Full workflow updates: 15
```

### Use Case 5: Quick SHA256 Update

**Scenario**: You know only the SHA256 changed and want maximum speed.

**Solution**:
```bash
./smart-update.sh --sha256-only
```

**What happens**:
- Skips workflow comparison
- Only updates SHA256 variable
- Fastest possible update

**Output**:
```
⚡ SHA256 only updates: 15
```

## Performance Comparison

### Traditional Update (Full Update Always)

```
Time per repo: ~10-15 seconds
Total time (15 repos): ~2.5-4 minutes
Network: High (uploads workflow every time)
API calls: Maximum
```

### Smart Update (SHA256-Only When Possible)

```
Time per repo: ~2-3 seconds (SHA256 only)
Time per repo: ~10-15 seconds (full update)
Total time (15 repos): ~30-60 seconds (if mostly SHA256-only)
Network: Minimal (only when needed)
API calls: Optimized
```

**Speed improvement**: **3-5x faster** when workflows are unchanged!

## Workflow Comparison Details

### What Gets Compared

The script compares the **content** of the workflow files, ignoring:
- Whitespace differences
- Comments (in some cases)

### Comparison Method

1. Downloads remote workflow file via GitHub API
2. Base64 decodes the content
3. Strips whitespace from both local and remote
4. Compares the normalized content
5. Returns match/no-match result

### Why This Works

- **Accurate**: Detects actual content changes
- **Reliable**: Handles encoding and formatting differences
- **Fast**: Uses GitHub API (no git clone needed)

## Security Considerations

### What Gets Updated

**SHA256-only mode**:
- Updates `DROID_INSTALLER_SHA256` repository variable only
- No file changes to repositories

**Full update mode**:
- Updates `.github/workflows/droid-code-review.yaml` file
- Updates `DROID_INSTALLER_SHA256` repository variable

### Permissions Required

- **Read**: Repository content (to compare workflows)
- **Write**: Repository content (to update workflow file)
- **Write**: Repository variables (to update SHA256)

### API Rate Limits

The script includes rate limiting protection:
- 0.2 second delay between repositories
- Prevents GitHub API rate limit issues
- Processes ~300 repos/hour safely

## Troubleshooting

### Issue: "Failed to download Droid CLI installer"

**Cause**: Network issue or Factory.ai endpoint unavailable

**Solution**:
```bash
# Check connectivity
curl -I https://app.factory.ai/cli

# Retry the update
./smart-update.sh
```

### Issue: "Invalid SHA256 format"

**Cause**: Downloaded file was corrupted or not a valid script

**Solution**:
```bash
# Manually verify the download
curl -fsSL https://app.factory.ai/cli | shasum -a 256

# If it works, retry the script
./smart-update.sh
```

### Issue: "Failed to update workflow"

**Cause**: Insufficient permissions or repository doesn't exist

**Solution**:
```bash
# Check permissions
gh repo view owner/repo

# Verify you have write access
# If not, the repo will be skipped
```

### Issue: Updates are slow

**Cause**: Many full updates or network issues

**Solution**:
```bash
# If you know only SHA256 changed, use fast mode
./smart-update.sh --sha256-only

# Check network speed
# Wait and retry if needed
```

## Best Practices

### 1. Regular Maintenance

Run smart update weekly to keep SHA256 current:
```bash
# Add to your workflow
./smart-update.sh
```

### 2. After Workflow Changes

Always use force-full after modifying the workflow:
```bash
# Edit droid-code-review-v2.yaml
nano droid-code-review-v2.yaml

# Force full update
./smart-update.sh --force-full
```

### 3. Verify Before Large Updates

Check what will be updated:
```bash
# Review your local workflow
cat droid-code-review-v2.yaml

# Run smart update (it will show what's happening)
./smart-update.sh
```

### 4. Monitor Output

Pay attention to the summary:
- High failure rate? Check permissions
- All full updates when expecting SHA256-only? Workflow might have changed
- All skipped? You're up-to-date!

### 5. Keep Local Workflow Updated

Always keep your local `droid-code-review-v2.yaml` as the source of truth:
```bash
# Update local file
nano droid-code-review-v2.yaml

# Push to all repos
./smart-update.sh --force-full
```

## FAQ

### Q: How often should I run smart-update?

**A**: Run it weekly or after:
- Droid CLI updates
- Workflow file modifications
- Adding new repositories

### Q: What if I'm not sure what changed?

**A**: Just run `./smart-update.sh`. It will figure it out!

### Q: Can I update specific repositories only?

**A**: Currently, no. The script updates all accessible repositories. Use `manage-workflows.sh` for selective updates.

### Q: What happens if the update fails?

**A**: The repository is marked as failed in the output. Other repositories continue processing. Check permissions and retry.

### Q: Is it safe to run multiple times?

**A**: Yes! The script is idempotent. Running it multiple times won't cause issues. Already up-to-date repos will be skipped.

### Q: Does it work with private repositories?

**A**: Yes! As long as you have proper GitHub CLI authentication and repository access.

### Q: Can I use it in CI/CD pipelines?

**A**: Yes! The script is designed for automation. It exits with appropriate codes:
- 0: Success
- 1: Error

## Advanced Usage

### Combining with Other Scripts

```bash
# Install to new repos, then update all
./quick-install.sh
./smart-update.sh

# Uninstall from select repos, then update the rest
./uninstall-workflow.sh --repos "owner/old-repo"
./smart-update.sh
```

### Scripting

```bash
#!/bin/bash
# Auto-update script

# Fetch latest workflow from main repo
git pull origin main

# Smart update all repos
./smart-update.sh --force-full

# Commit the log
echo "Updated $(date)" >> update-log.txt
git add update-log.txt
git commit -m "Auto-update: $(date)"
```

### Monitoring

```bash
# Run with logging
./smart-update.sh 2>&1 | tee update-log.txt

# Check results
grep "SHA256 updated" update-log.txt | wc -l
grep "Full update" update-log.txt | wc -l
```

## Summary

The `smart-update.sh` script is your **intelligent update tool** for managing the Droid Code Review workflow across all repositories:

- ⚡ **Fast**: 3-5x faster than full updates when only SHA256 changed
- 🧠 **Smart**: Automatically detects what needs updating
- 🔒 **Safe**: Only updates what's necessary
- 📊 **Clear**: Detailed reporting on all changes
- 🚀 **Efficient**: Minimal API calls and network usage

Use it regularly to keep your repositories up-to-date with minimal effort!

## Related Documentation

- [README.md](README.md) - Main documentation
- [DYNAMIC_SHA256_UPDATE.md](DYNAMIC_SHA256_UPDATE.md) - SHA256 automatic fetching
- [VARIABLE_SETUP_CHANGES.md](VARIABLE_SETUP_CHANGES.md) - Variable configuration details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide
