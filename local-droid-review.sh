#!/bin/bash

# Local Droid Code Review Script
# Runs the same code review logic as the GitHub workflow but locally
# Uses your existing Factory GLM-4.6 model configuration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Model to use (matches the GitHub workflow)
MODEL_NAME="GLM-4.6"

echo -e "${BLUE}🤖 Local Droid Code Review${NC}"
echo -e "${BLUE}============================${NC}"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# Function to check if file should be ignored based on .gitignore
should_ignore_file() {
    local file="$1"
    
    # Read .gitignore if it exists and filter out comments/empty lines
    if [ -f ".gitignore" ]; then
        while IFS= read -r pattern; do
            # Skip comments and empty lines
            [[ "$pattern" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$pattern" ]] && continue
            
            # Remove leading/trailing whitespace
            pattern=$(echo "$pattern" | xargs)
            
            # Convert pattern to regex
            # Escape special regex characters, replace * with .*, handle leading /
            regex_pattern=$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/g; s/^\//^/')
            [[ "$pattern" == /* ]] || regex_pattern="/$regex_pattern"
            
            # Check if file matches the pattern
            [[ "$file" =~ $regex_pattern ]] && return 0
        done < ".gitignore"
    fi
    
    return 1
}

# Get the current git status and changes
echo -e "${BLUE}📊 Analyzing git changes...${NC}"

# Get the current branch
CURRENT_BRANCH=$(git branch --show-current)
echo -e "${BLUE}Current branch: ${CURRENT_BRANCH}${NC}"

# Get the latest commit hash
LATEST_COMMIT=$(git rev-parse HEAD)
echo -e "${BLUE}Latest commit: ${LATEST_COMMIT}${NC}"

# Get the previous commit (HEAD~1) or show all files if this is the first commit
PREVIOUS_COMMIT=""
if git rev-parse HEAD~1 > /dev/null 2>&1; then
    PREVIOUS_COMMIT=$(git rev-parse HEAD~1)
    echo -e "${BLUE}Previous commit: ${PREVIOUS_COMMIT}${NC}"
    # Generate diff between current and previous commit
    echo -e "${BLUE}📝 Generating code diff...${NC}"
    git diff "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" > diff.txt
else
    echo -e "${BLUE}No previous commit found, reviewing all files${NC}"
    # Show all files in the repository
    echo -e "${BLUE}📝 Generating full file listing...${NC}"
    git ls-tree -r HEAD --name-only > diff.txt
fi

# Check if there are any changes
if [ ! -s diff.txt ]; then
    echo -e "${YELLOW}⚠️ No code changes detected${NC}"
    rm -f diff.txt
    exit 0
fi

# Get changed files for context
if [ -n "$PREVIOUS_COMMIT" ]; then
    CHANGED_FILES=$(git diff --name-only "${PREVIOUS_COMMIT}..${LATEST_COMMIT}")
    # Filter out ignored files
    FILTERED_FILES=""
    while IFS= read -r file; do
        if [ -n "$file" ] && ! should_ignore_file "$file"; then
            FILTERED_FILES="${FILTERED_FILES}${file}
"
        fi
    done <<< "$CHANGED_FILES"
    CHANGED_FILES="$FILTERED_FILES"
    echo -e "${BLUE}Files changed:${NC}"
    echo "$CHANGED_FILES" | nl
    
    # Create files.json with patch information for each changed file
    echo -e "${BLUE}📁 Processing file patches...${NC}"
    
    # Get detailed file information from git
    git diff --numstat "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" > numstat.txt
else
    # If no previous commit, show all tracked files
    CHANGED_FILES=$(git ls-tree -r HEAD --name-only)
    # Filter out ignored files
    FILTERED_FILES=""
    while IFS= read -r file; do
        if [ -n "$file" ] && ! should_ignore_file "$file"; then
            FILTERED_FILES="${FILTERED_FILES}${file}
"
        fi
    done <<< "$CHANGED_FILES"
    CHANGED_FILES="$FILTERED_FILES"
    echo -e "${BLUE}All files in repository:${NC}"
    echo "$CHANGED_FILES" | nl
    
    # Create files.json with patch information for each file
    echo -e "${BLUE}📁 Processing all files...${NC}"
    
    # Get detailed file information from git (show all files)
    git ls-tree -r HEAD --name-only | awk '{print "1\t0\t" $0}' > numstat.txt
fi

# Create files.json with patch data using jq for proper JSON escaping
TEMP_FILES_DIR=$(mktemp -d)
FILE_OBJECTS_FILE="$TEMP_FILES_DIR/file_objects.json"

while IFS= read -r file; do
    if [ -n "$file" ] && ! should_ignore_file "$file"; then
        # Get the patch for this file
        if [ -n "$PREVIOUS_COMMIT" ]; then
            PATCH=$(git diff "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" -- "$file" 2>/dev/null || echo "")
        else
            # If no previous commit, show the full file content if it exists
            if [ -f "$file" ]; then
                PATCH=$(cat "$file" 2>/dev/null || echo "")
            else
                PATCH=""
            fi
        fi
        
        if [ -n "$PATCH" ]; then
            # Get file stats from numstat
            STATS=$(grep -F "$file" numstat.txt || echo "0	0	$file")
            ADDITIONS=$(echo "$STATS" | awk '{print $1}')
            DELETIONS=$(echo "$STATS" | awk '{print $2}')
            
            # Use jq to create properly escaped JSON object
            jq -n --arg filename "$file" --arg patch "$PATCH" --argjson additions "$ADDITIONS" --argjson deletions "$DELETIONS" '{
                filename: $filename,
                patch: $patch,
                status: "modified",
                additions: $additions,
                deletions: $deletions,
                changes: ($additions + $deletions)
            }' >> "$FILE_OBJECTS_FILE"
        fi
    fi
done <<< "$CHANGED_FILES"

# Combine all file objects into a valid JSON array
if [ -f "$FILE_OBJECTS_FILE" ] && [ -s "$FILE_OBJECTS_FILE" ]; then
    jq -s '.' "$FILE_OBJECTS_FILE" > files.json
else
    echo "[]" > files.json
fi

# Clean up temporary directory
rm -rf "$TEMP_FILES_DIR"

# Clean up temporary files
rm -f numstat.txt

# Determine PR size and adjust review strategy (similar to GitHub workflow)
TOTAL_FILES=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
if [ "$TOTAL_FILES" -gt 50 ]; then
    MAX_COMMENTS=5
    PRIORITY_NOTE="⚠️ LARGE REVIEW: Focus ONLY on the most critical bugs and security issues."
    echo -e "${YELLOW}⚠️ Large review detected ($TOTAL_FILES files). Review will focus on critical issues only.${NC}"
else
    MAX_COMMENTS=10
    PRIORITY_NOTE=""
    echo -e "${GREEN}✅ Standard review size ($TOTAL_FILES files). Full review will be performed.${NC}"
fi

# Create the prompt (based on GitHub workflow but adapted for local use)
echo -e "${BLUE}📋 Creating review prompt...${NC}"

cat > prompt.txt << EOF
You are an automated code review system. Review the provided code changes and identify clear issues that need to be fixed.

${PRIORITY_NOTE}

Input files (already in current directory):
- diff.txt: the code changes to review
- files.json: file patches with line numbers for positioning comments

Task: Create a file called comments.json with this exact format:
[{ "path": "path/to/file.js", "line": 42, "body": "Your comment here" }]

Focus on these types of issues:
- Dead/unreachable code (if (false), while (false), code after return/throw/break)
- Broken control flow (missing break in switch, fallthrough bugs)
- Async/await mistakes (missing await, .then without return, unhandled promise rejections)
- Array/object mutations in React components or reducers
- UseEffect dependency array problems (missing deps, incorrect deps)
- Incorrect operator usage (== vs ===, && vs ||, = in conditions)
- Off-by-one errors in loops or array indexing
- Integer overflow/underflow in calculations
- Regex catastrophic backtracking vulnerabilities
- Missing base cases in recursive functions
- Incorrect type coercion that changes behavior
- Environment variable access without defaults or validation
- Null/undefined dereferences
- Resource leaks (unclosed files or connections)
- SQL/XSS injection vulnerabilities
- Concurrency/race conditions
- Missing error handling for critical operations

Comment format:
- Clearly describe the issue: "This code block is unreachable due to the if (false) condition"
- Provide a concrete fix: "Remove this entire if block as it will never execute"
- When possible, suggest the exact code change:
\`\`\`suggestion
// Remove the unreachable code
\`\`\`
- Be specific about why it's a problem: "This will cause a TypeError if input is null"
- No emojis, just clear technical language

Skip commenting on:
- Code style, formatting, or naming conventions
- Minor performance optimizations
- Architectural decisions or design patterns
- Features or functionality (unless broken)
- Test coverage (unless tests are clearly broken)

Line calculation:
- Use the "line" field from files.json patches
- This refers to the actual line number in the file, not the diff position
- Comments must align with exact changed lines only

Output:
- Empty array [] if no issues found
- Otherwise array of comment objects with path, line, body
- Each comment should be actionable and clear about what needs to be fixed
- Maximum ${MAX_COMMENTS} comments total; prioritize the most critical issues

CRITICAL: Ensure the comments.json file contains valid JSON that can be parsed by JSON.parse().
- All strings in JSON must be properly escaped
- Use \n for newlines in body strings
- Use \" for quotes in strings
- Use \\\\ for backslashes
- Use \t for tabs
- No unescaped newlines, quotes, backslashes, or control characters in the JSON text
- Test your JSON by running: python3 -m json.tool comments.json
- The JSON must be a single line without line breaks within string values
EOF

# Check if Droid CLI is available
if ! command -v droid &> /dev/null; then
    echo -e "${RED}❌ Error: Droid CLI not found in PATH${NC}"
    echo -e "${YELLOW}Please install Droid CLI: curl -fsSL https://app.factory.ai/cli | sh${NC}"
    exit 1
fi

# Run Droid with the local model
echo -e "${BLUE}🚀 Running code review analysis with ${MODEL_NAME}...${NC}"

if droid exec -f prompt.txt --model custom:"${MODEL_NAME}" --skip-permissions-unsafe; then
    echo -e "${GREEN}✅ Review analysis completed successfully${NC}"
else
    echo -e "${RED}❌ ERROR: droid exec failed${NC}"
    echo -e "${YELLOW}This could be due to missing configuration or runtime issues.${NC}"
    exit 1
fi

# Check if comments.json was created
if [ ! -f comments.json ]; then
    echo -e "${RED}❌ ERROR: droid exec did not create comments.json${NC}"
    echo -e "${YELLOW}This usually indicates the review run failed.${NC}"
    exit 1
fi

echo -e "${BLUE}=== Review Results ===${NC}"
cat comments.json
echo ""

# Validate JSON
echo -e "${BLUE}🔍 Validating JSON format...${NC}"
if python3 -m json.tool comments.json > /dev/null 2>&1; then
    echo -e "${GREEN}✅ JSON validation passed${NC}"
    
    # Count comments
    COMMENT_COUNT=$(python3 -c "import json; data=json.load(open('comments.json')); print(len(data) if isinstance(data, list) else 0)")
    
    if [ "$COMMENT_COUNT" -eq 0 ]; then
        echo -e "${GREEN}🎉 No issues found in the current changes!${NC}"
    else
        # Set plural suffix
        if [ "$COMMENT_COUNT" -eq 1 ]; then
            S=""
        else
            S="s"
        fi
        echo -e "${BLUE}📊 Found ${COMMENT_COUNT} potential issue${S} that should be addressed.${NC}"
    fi
else
    echo -e "${RED}❌ ERROR: Invalid JSON in comments.json${NC}"
    echo -e "${YELLOW}Content that failed validation:${NC}"
    cat comments.json
    echo ""
    echo -e "${YELLOW}Creating a fallback empty comments.json...${NC}"
    echo "[]" > comments.json
fi

# Create consolidated markdown report
echo -e "${BLUE}📝 Creating consolidated report...${NC}"

# Create droidreview directory if it doesn't exist
mkdir -p droidreview

# Get timestamp for filename
TIMESTAMP=$(date '+%Y-%m-%dT%H-%M-%S')
REPORT_FILE="droidreview/Droid Review ${TIMESTAMP}.md"

# Get git information
GIT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse HEAD --short 2>/dev/null || echo "unknown")
GIT_AUTHOR=$(git log -1 --pretty=format:'%an' 2>/dev/null || echo "unknown")

# Count comments
COMMENT_COUNT=0
if [ -f comments.json ]; then
    COMMENT_COUNT=$(python3 -c "import json; data=json.load(open('comments.json')); print(len(data) if isinstance(data, list) else 0)" 2>/dev/null || echo "0")
fi

cat > "$REPORT_FILE" << EOF
# Droid Code Review Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')  
**Branch:** $GIT_BRANCH  
**Commit:** $GIT_COMMIT  
**Author:** $GIT_AUTHOR  
**Files Changed:** $(echo "$CHANGED_FILES" 2>/dev/null | wc -l | tr -d ' ' || echo "0")  
**Issues Found:** $COMMENT_COUNT  

---

## Review Summary

EOF

if [ "$COMMENT_COUNT" -eq 0 ]; then
    cat >> "$REPORT_FILE" << EOF
🎉 **No issues found** in the current changes! The code review completed successfully with no actionable items.

EOF
else
    # Set plural suffix for the report
    if [ "$COMMENT_COUNT" -ne 1 ]; then
        REPORT_SUFFIX="s"
    else
        REPORT_SUFFIX=""
    fi
    
    cat >> "$REPORT_FILE" << EOF
🔍 **$COMMENT_COUNT potential issue$REPORT_SUFFIX** found that should be addressed:

EOF
fi

# Add code changes section
cat >> "$REPORT_FILE" << EOF
---

## Code Changes

The following files were modified in this review:

\`\`\`diff
EOF

cat diff.txt >> "$REPORT_FILE"

cat >> "$REPORT_FILE" << EOF
\`\`\`

---

EOF

# Add review findings if any
if [ "$COMMENT_COUNT" -gt 0 ] && [ -f comments.json ]; then
    cat >> "$REPORT_FILE" << EOF
## Review Findings

EOF

    # Process comments and format them nicely
    python3 << 'PYTHON_SCRIPT' >> "$REPORT_FILE"
import json
import sys

try:
    with open('comments.json', 'r') as f:
        comments = json.load(f)
    
    if isinstance(comments, list):
        for i, comment in enumerate(comments, 1):
            if isinstance(comment, dict) and 'path' in comment and 'line' in comment and 'body' in comment:
                print(f"### Issue {i}")
                print(f"**File:** `{comment['path']}`")
                print(f"**Line:** {comment['line']}")
                print(f"**Issue:** {comment['body']}")
                print()
                print("---")
                print()
except Exception as e:
    print(f"Error processing comments: {e}")
PYTHON_SCRIPT
fi

# Add metadata section
cat >> "$REPORT_FILE" << EOF
---

## Metadata

- **Review Type:** Local Droid Code Review
- **Model:** GLM-4.6 [Z.AI]
- **Analysis Date:** $(date '+%Y-%m-%d %H:%M:%S')
- **Git Repository:** $(git remote get-url origin 2>/dev/null || echo "Local repository")
- **Review Strategy:** $(if [ "$TOTAL_FILES" -gt 50 ]; then echo "Large PR (5 comment limit)"; else echo "Standard PR (10 comment limit)"; fi)

---

*Generated by Local Droid Code Review Script*
EOF

# Clean up temporary files
echo -e "${BLUE}🧹 Cleaning up temporary files...${NC}"
rm -f prompt.txt diff.txt files.json

echo -e "${GREEN}✅ Local Droid review completed!${NC}"
echo -e "${BLUE}Report saved to:${NC}"
echo -e "${GREEN}  - $REPORT_FILE${NC}"
echo ""
echo -e "${BLUE}Report contents:${NC}"
echo "  - Review summary and metadata"
echo "  - Complete code changes (diff)"
echo "  - Detailed findings with file/line references"
echo ""
echo -e "${YELLOW}💡 Tip: You can open the report in your preferred markdown viewer${NC}"
