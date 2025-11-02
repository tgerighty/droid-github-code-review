# Archived Workflow Files - Version 1

This directory contains the original version 1 workflow files that have been superseded by version 2.

## Archived Files

### droid-code-review-v1.yaml
The main v1 workflow file with optimizations and GLM-4.6 integration.
- **Lines:** 646
- **Features:** Full-featured with API key validation, custom model config, parallel API calls
- **Limitation:** Excluded draft PRs

### droid-code-review-v1-fixed.yaml
A variant attempting to fix some issues from the original.
- **Lines:** 685
- **Features:** Similar to main v1 with additional fixes
- **Limitation:** Excluded draft PRs

### droid-code-review-v1-new.yaml
Another variant with attempted improvements.
- **Lines:** 685
- **Features:** Similar to -fixed variant
- **Limitation:** Excluded draft PRs

### droid-code-review-v1-optimized.yaml
A simplified, more streamlined version.
- **Lines:** 146
- **Features:** Basic workflow without advanced optimizations
- **Limitation:** Excluded draft PRs, fewer features

## Why These Were Archived

All v1 workflows were replaced by **v2** which includes:
- ✅ Support for draft PRs (no longer excluded)
- ✅ Consolidated into a single, well-maintained workflow
- ✅ Enhanced error handling and validation
- ✅ Improved position mapping for inline comments
- ✅ Better documentation and versioning

## Migration Notes

If you need to reference the old behavior:
1. All v1 files excluded draft PRs using: `if: github.event_name == 'workflow_dispatch' || github.event.pull_request.draft == false`
2. The main differences between variants were mostly experimental fixes
3. V2 consolidates the best features from all variants

**Date Archived:** 2025-10-30
