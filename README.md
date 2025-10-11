# Droid Code Review Workflow

Automated code review workflow that uses AI to analyze pull requests and provide actionable feedback.

## Files

- `droid-code-review.yaml` - GitHub Actions workflow file
- `quick-install.sh` - ⭐ **Simple installation script**
- `install-workflow.sh` - Advanced installation with options
- `manage-workflows.sh` - Manage existing installations

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
  - Manual: Can be triggered manually for any PR (see [Manual Trigger Guide](MANUAL_TRIGGER.md))
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

See [MANUAL_TRIGGER.md](MANUAL_TRIGGER.md) for detailed instructions.

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

## Managing Installations

### Check Where It's Installed

```bash
./manage-workflows.sh list
```

### Check Specific Repositories

```bash
./manage-workflows.sh check owner/repo1,owner/repo2
```

### Update All Installed Workflows

```bash
./manage-workflows.sh update
```

### Remove from Repositories

```bash
./manage-workflows.sh remove owner/repo1,owner/repo2
```

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
