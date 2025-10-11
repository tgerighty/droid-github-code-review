# Manual Workflow Trigger Instructions

The Droid Code Review workflow can now be triggered manually for any pull request, regardless of size or draft status.

## When to Use Manual Trigger

Use manual trigger when:
- ✅ You want to review a large PR (previously skipped if >100 files)
- ✅ You want to re-run the review on an existing PR
- ✅ The workflow didn't run automatically (e.g., due to draft status)
- ✅ You made changes and want a fresh review without pushing new commits

## How to Trigger Manually

### Option 1: GitHub Web UI (Easiest)

1. **Navigate to the Actions tab** in your repository
   - Go to `https://github.com/YOUR_ORG/YOUR_REPO/actions`

2. **Select the "Droid Code Review" workflow** from the left sidebar

3. **Click "Run workflow"** button (top right, above the workflow runs list)

4. **Fill in the PR number**
   - Enter the PR number you want to review (e.g., `12`)
   - Make sure the branch is set to the default branch (usually `main`)

5. **Click "Run workflow"** to start the review

### Option 2: GitHub CLI

```bash
# Trigger review for PR #12
gh workflow run "Droid Code Review" \
  --repo YOUR_ORG/YOUR_REPO \
  --field pr_number=12

# Check the status
gh run list --workflow="Droid Code Review" --limit 5
```

### Option 3: GitHub API

```bash
# Using curl
curl -X POST \
  -H "Authorization: token YOUR_GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/YOUR_ORG/YOUR_REPO/actions/workflows/droid-code-review.yaml/dispatches \
  -d '{"ref":"main","inputs":{"pr_number":"12"}}'
```

## What Happens During Manual Trigger

When you manually trigger the workflow:

1. **Fetches PR details** - The workflow retrieves all PR information from the GitHub API
2. **Checks out the PR branch** - Fetches the latest code from the PR's head branch
3. **Runs the same review process** - Identical to automatic triggers:
   - Validates API keys
   - Generates diff
   - Analyzes code with GLM-4.6 model
   - Posts inline comments
4. **Bypasses all restrictions** - No file count limits, works on draft PRs

## Differences from Automatic Trigger

| Feature | Automatic | Manual |
|---------|-----------|--------|
| Trigger event | PR opened/sync/reopened | Manual dispatch |
| Draft PRs | Skipped | ✅ Runs |
| File count limit | None (limit removed) | ✅ No limit |
| Re-run on same code | Requires new commit | ✅ Can re-run anytime |

## Troubleshooting

### "Workflow not found"
- Make sure the workflow file is in `.github/workflows/droid-code-review.yaml`
- Check that the workflow is on the default branch (`main`)

### "Invalid PR number"
- Verify the PR exists in the repository
- Use just the number (e.g., `12`, not `#12`)

### Workflow fails with API key errors
- Ensure `FACTORY_API_KEY` and `MODEL_API_KEY` are set in repository secrets
- Go to **Settings** → **Secrets and variables** → **Actions**

### No comments posted
- Check the workflow logs for errors
- Verify the PR has actual code changes to review
- Large PRs may take longer to process (15-minute timeout)

## Examples

### Review a migration PR with 134 files
```bash
gh workflow run "Droid Code Review" --field pr_number=12
```

### Re-review after addressing comments
```bash
# No need to push new commits - just re-run manually
gh workflow run "Droid Code Review" --field pr_number=12
```

### Review a draft PR before publishing
```bash
gh workflow run "Droid Code Review" --field pr_number=15
```

## Monitoring the Run

### GitHub Web UI
1. Go to **Actions** tab
2. Click on the workflow run at the top of the list
3. Watch the progress in real-time

### GitHub CLI
```bash
# List recent runs
gh run list --workflow="Droid Code Review" --limit 5

# Watch a specific run
gh run watch RUN_ID

# View logs
gh run view RUN_ID --log
```

## Cost Considerations

- Manual triggers consume GitHub Actions minutes
- Large PRs may take longer to process
- GLM-4.6 API calls count against your API quota
- Use judiciously for very large PRs (100+ files)

## Best Practices

1. **Wait for automatic trigger first** - Let the workflow run automatically when possible
2. **Use for exceptions** - Manual trigger is best for large PRs or re-reviews
3. **Monitor API usage** - Keep an eye on Factory.ai and Z.ai API quotas
4. **Check logs on failure** - Download debug artifacts if the review fails
