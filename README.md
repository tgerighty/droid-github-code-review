# Droid Code Review Workflow

Automated code review workflow that uses AI to analyze pull requests and provide actionable feedback.

## Repository Structure

```
droid-github-code-review/
├── README.md                      # This file
├── droid-code-review-v2.yaml     # Main workflow file
│
├── Installation Scripts
│   ├── quick-install.sh          # ⭐ Recommended: Simple installation
│   ├── install-workflow.sh       # Advanced installation with options
│   └── bulk-install.sh           # Alternative bulk installation
│
├── Update Scripts
│   └── smart-update.sh           # ⭐ Recommended: Intelligent updates
│
├── Management Scripts
│   ├── manage-workflows.sh       # Manage existing installations
│   ├── uninstall-workflow.sh     # Advanced uninstallation
│   └── bulk-uninstall.sh         # Simple bulk uninstallation
│
├── documents/                     # All documentation
│   ├── SMART_UPDATE_GUIDE.md     # Smart update detailed guide
│   ├── TROUBLESHOOTING.md        # Troubleshooting guide
│   ├── MANUAL_TRIGGER.md         # Manual trigger guide
│   ├── ENV_SETUP.md              # Environment setup guide
│   ├── CUSTOM_MODEL_SETUP.md     # Custom model configuration
│   ├── UNINSTALL_GUIDE.md        # Uninstallation guide
│   └── ... (other documentation)
│
└── archive/                       # Legacy files and testing
    ├── scripts/                   # Prototype/legacy scripts
    ├── testing/                   # Test files and data
    └── workflows-v1/              # Old workflow versions
```

## Quick Links

### Main Scripts (in root)
- `quick-install.sh` - ⭐ **Simple installation** (recommended)
- `smart-update.sh` - ⭐ **Intelligent updates** (recommended)
- `bulk-uninstall.sh` - ⭐ **Simple uninstallation**

### Documentation (in `documents/`)
- [Smart Update Guide](documents/SMART_UPDATE_GUIDE.md) - Detailed update guide
- [Troubleshooting](documents/TROUBLESHOOTING.md) - Common issues and solutions
- [Manual Trigger Guide](documents/MANUAL_TRIGGER.md) - How to manually trigger reviews
- [Environment Setup](documents/ENV_SETUP.md) - API keys and configuration
- [Uninstall Guide](documents/UNINSTALL_GUIDE.md) - Complete uninstallation guide

## Quick Start

### 1. Setup API Keys (One-Time Setup)

```bash
# Copy the example environment file
cp .env.example .env

# Edit .env and add your API keys
# - FACTORY_API_KEY: Get from https://app.factory.ai/settings
# - MODEL_API_KEY: Get from https://api.z.ai/
nano .env  # or use your favorite editor
```

**Important**: The `.env` file is gitignored and will never be committed to your repository.

### 2. Install to All Repositories (Recommended)

```bash
# Make sure you have GitHub CLI installed and authenticated
brew install gh
gh auth login

# Just run the quick install script
./quick-install.sh
```

That's it! The script will:
- Load API keys from your `.env` file
- Get all your repositories
- Install the workflow to each one
- **Automatically create the required secrets in each repository**
- Set the DROID_INSTALLER_SHA256 variable
- Show you the results

### 2. Install to Specific Repositories

```bash
# Using the advanced script
./install-workflow.sh --repos "owner/repo1,owner/repo2"

# Or interactive selection
./install-workflow.sh --interactive
```

### 3. Force Overwrite Existing Workflows

```bash
./install-workflow.sh --force
```

## What This Workflow Does

- **Triggers**: 
  - Automatic: Runs on pull request events (opened, synchronized, reopened, ready_for_review)
  - Manual: Can be triggered manually for any PR (see [Manual Trigger Guide](documents/MANUAL_TRIGGER.md))
- **Skips**: Draft pull requests (only in automatic mode)
- **Fail-Fast**: Checks API keys first - exits in ~10 seconds with helpful PR comment if missing (saves Actions minutes!)
- **Analyzes**: Code changes using GLM-4.6 model via Z.ai
- **Reports**: Inline comments with actionable feedback
- **Timeout**: 15 minutes with concurrency control

### Manual Trigger

You can manually trigger a code review for any PR:
- Works on PRs of any size (no file limit)
- Can re-run reviews without pushing new commits
- Works on draft PRs

See [MANUAL_TRIGGER.md](documents/MANUAL_TRIGGER.md) for detailed instructions.

## How It Works

The installation scripts automatically configure everything for you:

### ✅ Automatically Created

When you run any installation script with a `.env` file configured:

1. **Workflow File**: Installs `.github/workflows/droid-code-review.yaml` in each repository
2. **Repository Secrets** (automatically created):
   - `FACTORY_API_KEY`: Your Factory.ai API key (from `.env`)
   - `MODEL_API_KEY`: Your Z.ai API key (from `.env`)
3. **Repository Variable** (automatically set):
   - `DROID_INSTALLER_SHA256`: SHA256 checksum of the Droid CLI installer

### 🔐 Security

- Your API keys are stored in `.env` which is **gitignored** and never committed
- Secrets are securely transmitted to GitHub using the GitHub CLI
- Each repository gets its own copy of the secrets
- The workflow uses the GLM-4.6 model via Z.ai's API endpoint

### 📝 Manual Setup (If Needed)

If you didn't create a `.env` file or want to add secrets manually:

1. Go to repository **Settings** → **Secrets and variables** → **Actions**
2. Click **New repository secret**
3. Add both secrets:
   - Name: `FACTORY_API_KEY`, Value: Your Factory API key
   - Name: `MODEL_API_KEY`, Value: Your Z.ai API key

## Updating Existing Installations

### Smart Update (Recommended)

The `smart-update.sh` script intelligently determines what needs updating:

```bash
# Smart update - only updates what's changed
./smart-update.sh
```

**How it works:**
- Fetches the latest Droid CLI SHA256
- Compares your local workflow with each repository's workflow
- **If workflows are identical**: Only updates the SHA256 variable (fast! ⚡)
- **If workflows differ**: Updates both workflow and SHA256 (full update)
- **If nothing changed**: Skips the repository

**Options:**
```bash
# Force full workflow update for all repositories
./smart-update.sh --force-full

# Only update SHA256 variable, skip workflow comparison
./smart-update.sh --sha256-only

# Show help
./smart-update.sh --help
```

**Example output:**
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
[  1/ 15] owner/repo1                              ⚡ SHA256 updated
[  2/ 15] owner/repo2                              ✅ Full update
[  3/ 15] owner/repo3                              ⏭️  No changes needed

========================================
📊 UPDATE SUMMARY

⚡ SHA256 only updates: 10
✅ Full workflow updates: 3
⏭️  No changes needed: 2
📈 Total processed: 15

🎉 Perfect! All repositories processed successfully!

🔍 What happened:
   • 10 repositories: SHA256 variable updated (workflow unchanged)
   • 3 repositories: Full update (workflow + SHA256)
   • 2 repositories: Already up to date
```

### When to Use Each Update Method

**Use `smart-update.sh`** (recommended):
- When you only need to update the Droid CLI SHA256
- When you're not sure what changed
- For regular maintenance updates
- Fastest and safest option

**Use `smart-update.sh --force-full`**:
- After modifying the workflow file
- When you want to ensure all repos have the latest workflow

**Use `smart-update.sh --sha256-only`**:
- When you ONLY want to update the SHA256 variable
- Skip workflow comparison for maximum speed

## Managing Installations

### Check Where It's Installed

```bash
./manage-workflows.sh list
```

### Check Specific Repositories

```bash
./manage-workflows.sh check owner/repo1,owner/repo2
```

### Update All Installed Workflows (Old Method)

```bash
./manage-workflows.sh update
```

**Note**: Consider using `./smart-update.sh` instead for more efficient updates.

### Remove from Repositories

```bash
./manage-workflows.sh remove owner/repo1,owner/repo2
```

## Uninstalling the Workflow

If you want to remove the workflow from your repositories, we provide dedicated uninstallation scripts that will:
- Remove the workflow file from repositories
- Delete the `DROID_INSTALLER_SHA256` variable
- Delete the `FACTORY_API_KEY` secret
- Delete the `MODEL_API_KEY` secret

### Quick Uninstall (All Repositories)

```bash
./bulk-uninstall.sh
```

This will remove the workflow and clean up all secrets/variables from **all** your repositories. It will ask for confirmation before proceeding.

### Advanced Uninstall Options

```bash
# Uninstall from all repositories (with confirmation)
./uninstall-workflow.sh

# Uninstall but keep a backup in each repo
./uninstall-workflow.sh --backup

# Interactively select repositories to uninstall from
./uninstall-workflow.sh --interactive

# Uninstall from specific repositories
./uninstall-workflow.sh --repos "owner/repo1,owner/repo2"

# Preview what would be removed (dry run)
./uninstall-workflow.sh --dry-run
```

### What Gets Removed

During uninstallation, the following items are removed from each repository:

1. **Workflow File**: `.github/workflows/droid-code-review.yaml`
2. **Repository Variable**: `DROID_INSTALLER_SHA256`
3. **Repository Secrets**:
   - `FACTORY_API_KEY`
   - `MODEL_API_KEY`

### Uninstall with Backup

Use the `--backup` flag to keep a backup copy of the workflow file in `.github/workflows/backup/droid-code-review.yaml`:

```bash
./uninstall-workflow.sh --backup
```

This is useful if you want to preserve the workflow configuration for future reference or reinstallation.

## Script Options

### quick-install.sh (Simple)
- No options needed
- Just run it and it works
- Uses GitHub API directly
- Skips existing installations

### install-workflow.sh (Advanced)
```bash
./install-workflow.sh [OPTIONS]

OPTIONS:
  -h, --help          Show help
  -f, --force         Overwrite existing workflows
  -i, --interactive   Select repositories interactively
  -r, --repos REPOS   Specific repositories (comma-separated)
  --dry-run           Preview without making changes
```

## Prerequisites

- GitHub CLI (`gh`) installed
- Authenticated with `gh auth login`
- Write access to target repositories
- `droid-code-review.yaml` in current directory

## Notes

- All scripts create backups before overwriting
- Pull requests are created for all changes
- Rate limiting is handled automatically
- Logs are written to `workflow-installation.log`

## Troubleshooting

**"Not authenticated with GitHub CLI"**
```bash
gh auth login
```

**"GitHub CLI not found"**
```bash
brew install gh
```

**"Failed to install"**
- Check your permissions on the repository
- Make sure the repository isn't empty
- Try running with `--dry-run` first to see what would happen

## Workflow Details

The workflow installs with these settings:
- **Runner**: `ubuntu-latest`
- **Timeout**: 15 minutes
- **Permissions**: Minimal (pull-requests: write, contents: read, issues: write)
- **Concurrency**: One run per PR, cancels in-progress runs
- **Artifacts**: Debug logs uploaded on failure (7-day retention)
- **Model**: Uses GLM-4.6 via custom Factory.ai configuration
