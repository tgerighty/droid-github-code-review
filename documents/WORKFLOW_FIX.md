# Workflow Fix: Enhanced Error Handling and Validation

## Problem
The workflow failed with error: `Object reference not set to an instance of an object.` when trying to create PR review comments.

**Failed Run**: https://github.com/tgerighty/doodletoslide/actions/runs/18431689066/job/52519825825

## Root Cause
The GitHub Script action that posts review comments was missing proper error handling and validation, leading to:
1. Null reference errors when accessing PR data
2. No validation of comment structure before posting
3. Insufficient logging to debug issues
4. Missing commit_id in the review payload (can cause positioning issues)

## Changes Made

### 1. **Enhanced PR Number Validation**
```javascript
// Safely get PR number with validation
const prNumber = context.payload.pull_request?.number || ${{ steps.pr-number.outputs.number }};
if (!prNumber) {
  core.error('Unable to determine PR number from context');
  throw new Error('PR number is undefined');
}
core.info(`Processing PR #${prNumber}`);
```

### 2. **Added Debug Logging**
- Log raw comments.json content (first 500 chars)
- Log number of comments parsed
- Log existing reviews/comments count
- Log each comment being posted with path and position
- Log API responses and errors with full details

### 3. **Comprehensive Comment Validation**
Instead of simple `.filter()`, added detailed validation loop:
```javascript
for (let i = 0; i < comments.length; i++) {
  const entry = comments[i];
  
  // Validate comment structure
  if (!entry || typeof entry !== 'object') {
    core.warning(`Skipping comment ${i}: not an object`);
    continue;
  }

  // Validate required fields
  if (!path) {
    core.warning(`Skipping comment ${i}: missing path`);
    continue;
  }
  if (typeof position !== 'number') {
    core.warning(`Skipping comment ${i}: invalid position (${typeof position})`);
    continue;
  }
  if (!body) {
    core.warning(`Skipping comment ${i}: empty body`);
    continue;
  }
  
  // Check for duplicates
  const key = `${path}::${position}::${body}`;
  if (existingKeys.has(key)) {
    core.info(`Skipping comment ${i}: duplicate (${path}:${position})`);
    continue;
  }

  filtered.push({ path, position, body });
}
```

### 4. **Error Handling for API Calls**
Wrapped all GitHub API calls in try-catch blocks:
```javascript
let existingReviews = [];
try {
  existingReviews = await github.paginate(github.rest.pulls.listReviews, {...});
  core.info(`Found ${existingReviews.length} existing reviews`);
} catch (error) {
  core.warning(`Failed to fetch existing reviews: ${error.message}`);
}
```

### 5. **Added commit_id to Review Payload**
This ensures comments are anchored to the correct commit:
```javascript
const payload = {
  owner: context.repo.owner,
  repo: context.repo.repo,
  pull_number: prNumber,
  commit_id: '${{ github.event.pull_request.head.sha || steps.pr-details.outputs.head_sha }}',
  event: 'COMMENT',
  body: `${summary}\n\n${NO_ISSUES_MARKER}`,
  comments: filtered
};
```

### 6. **Enhanced Error Reporting**
Added detailed error logging in retry logic:
```javascript
catch (error) {
  core.error(`createReview attempt ${attempt} failed: ${error.message}`);
  if (error.response) {
    core.error(`Status: ${error.response.status}`);
    core.error(`Response: ${JSON.stringify(error.response.data)}`);
  }
  if (attempt === 3) {
    core.error('Failed to post review after 3 attempts');
    throw error;
  }
  core.warning(`Retrying in ${attempt * 2} seconds...`);
  await sleep(attempt * 2000);
}
```

### 7. **Success Confirmation Logging**
Added confirmation when review is successfully posted:
```javascript
const result = await github.rest.pulls.createReview(payload);
core.info(`✅ Successfully submitted review with ${filtered.length} inline comments`);
core.info(`Review ID: ${result.data.id}, URL: ${result.data.html_url}`);
```

## Benefits

1. **Better Debugging**: Detailed logs help identify exactly what went wrong
2. **Graceful Degradation**: Invalid comments are skipped instead of breaking the workflow
3. **Clearer Error Messages**: Specific error messages for each failure scenario
4. **Proper Validation**: All data is validated before attempting to post
5. **Commit Anchoring**: Comments are properly anchored to the commit SHA

## Testing

To test these changes:
1. Trigger the workflow on a PR with code changes
2. Check the Actions logs for detailed diagnostic information
3. Verify comments are posted correctly to the PR
4. Test edge cases: empty comments, invalid positions, duplicate comments

## Next Steps

If issues persist, check:
1. The logs for detailed error messages
2. The `droid-review-debug-*` artifact uploaded on failure
3. Whether comments.json has valid structure and positions
4. GitHub API rate limits or permissions issues
