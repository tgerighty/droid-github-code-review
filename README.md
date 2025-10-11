# Droid Code Review Workflow

Automated code review workflow that uses AI to analyze pull requests and provide actionable feedback.

## Files

- `droid-code-review.yaml` - GitHub Actions workflow file
- `quick-install.sh` - ⭐ **Simple installation script**
- `install-workflow.sh` - Advanced installation with options
- `manage-workflows.sh` - Manage existing installations

## Quick Start

### 1. Install to All Repositories (Recommended)

```bash
# Make sure you have GitHub CLI installed and authenticated
brew install gh
gh auth login

# Just run the quick install script
./quick-install.sh
```

That's it! The script will:
- Get all your repositories
- Install the workflow to each one
- Skip repos that already have it
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

- **Triggers**: Runs on pull request events (opened, synchronized, reopened, ready_for_review)
- **Skips**: Draft pull requests and PRs with 100+ changed files
- **Fail-Fast**: Checks API keys first - exits in ~10 seconds with helpful PR comment if missing (saves Actions minutes!)
- **Analyzes**: Code changes using GLM-4.6 model via Z.ai
- **Reports**: Inline comments with actionable feedback
- **Timeout**: 15 minutes with concurrency control

## Required Setup

After installation, you need to add two secrets to each repository:

### 1. Factory API Key
1. Go to repository settings
2. Click "Secrets and variables" > "Actions"
3. Click "New repository secret"
4. Name: `FACTORY_API_KEY`
5. Value: Your Factory API key

### 2. Custom Model API Key
1. In the same "Secrets and variables" > "Actions" section
2. Click "New repository secret"
3. Name: `MODEL_API_KEY`
4. Value: Your Z.ai API key (for GLM-4.6 model)

**Note**: The workflow uses the GLM-4.6 model via Z.ai's API endpoint for code reviews.

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
