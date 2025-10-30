#!/bin/bash

# Model to use with codex CLI
MODEL_NAME="gpt-5"
CODEX_MODEL="gpt-5"

echo -e "${BLUE}🤖 Local Codex Code Review${NC}"
echo -e "${BLUE}============================${NC}"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# SECURITY: Function to sanitize file paths - removes dangerous characters
sanitize_path() {
    local path="$1"
    # Remove null bytes, control characters, and dangerous shell metacharacters
    # Only allow alphanumeric, dot, hyphen, underscore, forward slash
    # SECURITY: Use fixed string to prevent command injection
    if [[ -z "$path" ]]; then
        return 1
    fi
    echo "$path" | tr -d '\000' | sed 's/[^a-zA-Z0-9._\/-]//g'
}

# Function to check if file should be ignored based on .gitignore
should_ignore_file() {
    local file="$1"
    
    # SECURITY: Validate file path before processing
    if [[ -z "$file" ]]; then
        return 1
    fi
    
    # SECURITY: Check for path traversal attempts
    if [[ "$file" =~ \.\./|\.\.\\ ]]; then
        return 1
    fi
    
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
            regex_pattern=$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/g; s/^\//^/' 2>/dev/null || echo "")
            if [[ -n "$regex_pattern" ]]; then
                [[ "$pattern" == /* ]] || regex_pattern="/$regex_pattern"
                # Check if file matches the pattern
                [[ "$file" =~ $regex_pattern ]] && return 0
            fi
        done < ".gitignore"
    fi
    
    return 1
}

# SECURITY: Get the latest commit hash with validation
LATEST_COMMIT=$(git rev-parse HEAD 2>/dev/null)
if [[ $? -ne 0 || -z "$LATEST_COMMIT" ]]; then
    echo -e "${RED}❌ Security Error: Failed to get latest commit hash${NC}"
    exit 1
fi

# SECURITY: Validate commit hash format
if [[ ! "$LATEST_COMMIT" =~ ^[a-fA-F0-9]{40}$ ]] && [[ ! "$LATEST_COMMIT" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
    echo -e "${RED}❌ Security Error: Invalid commit hash format${NC}"
    exit 1
fi

echo -e "${BLUE}Latest commit: ${LATEST_COMMIT}${NC}"

# Get the previous commit hash (one before latest) with validation
PREVIOUS_COMMIT=$(git rev-parse HEAD~1 2>/dev/null)
if [ $? -eq 0 ] && [[ -n "$PREVIOUS_COMMIT" ]]; then
    # SECURITY: Validate previous commit hash format
    if [[ "$PREVIOUS_COMMIT" =~ ^[a-fA-F0-9]{40}$ ]] || [[ "$PREVIOUS_COMMIT" =~ ^[a-fA-F0-9]{7,40}$ ]]; then
        echo -e "${BLUE}Previous commit: ${PREVIOUS_COMMIT}${NC}"
    else
        echo -e "${RED}❌ Security Error: Invalid previous commit hash format${NC}"
        PREVIOUS_COMMIT=""
    fi
else
    echo -e "${YELLOW}Warning: No previous commit found, reviewing all tracked files${NC}"
    PREVIOUS_COMMIT=""
fi

# SECURITY: Get changed files for context with validated commits
if [ -n "$PREVIOUS_COMMIT" ]; then
    # SECURITY: Use fixed array arguments to prevent command injection
    CHANGED_FILES=$(git diff --name-only "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" 2>/dev/null || echo "")
    # Filter out ignored files and .gitignore
    FILTERED_FILES=""
    while IFS= read -r file; do
        # SECURITY: Sanitize file path to prevent injection
        if [ -n "$file" ] && ! should_ignore_file "$file" && [[ "$file" != ".gitignore" ]]; then
            # SECURITY: Additional check for path traversal
            if [[ ! "$file" =~ \.\./|\.\.\\ ]]; then
                FILTERED_FILES="${FILTERED_FILES}${file}
"
            fi
        fi
    done <<< "$CHANGED_FILES"
    CHANGED_FILES="$FILTERED_FILES"
    echo -e "${BLUE}Files changed:${NC}"
    echo "$CHANGED_FILES" | nl
    
    # Create files.json with patch information for each changed file
    echo -e "${BLUE}📁 Processing file patches...${NC}"
    
    # SECURITY: Get detailed file information from git with fixed arguments
    git diff --numstat "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" > numstat.txt 2>/dev/null || touch numstat.txt
else
    # If no previous commit, show all tracked files
    CHANGED_FILES=$(git ls-tree -r HEAD --name-only 2>/dev/null || echo "")
    # Filter out ignored files and .gitignore
    FILTERED_FILES=""
    while IFS= read -r file; do
        # SECURITY: Sanitize file path to prevent injection
        if [ -n "$file" ] && ! should_ignore_file "$file" && [[ "$file" != ".gitignore" ]]; then
            # SECURITY: Additional check for path traversal
            if [[ ! "$file" =~ \.\./|\.\.\\ ]]; then
                FILTERED_FILES="${FILTERED_FILES}${file}
"
            fi
        fi
    done <<< "$CHANGED_FILES"
    CHANGED_FILES="$FILTERED_FILES"
    echo -e "${BLUE}All files in repository:${NC}"
    echo "$CHANGED_FILES" | nl
    
    # Create files.json with patch information for each file
    echo -e "${BLUE}📁 Processing all files...${NC}"
    
    # SECURITY: Get detailed file information from git with proper validation
    git ls-tree -r HEAD --name-only 2>/dev/null | while read -r file; do
        # SECURITY: Validate file path before processing
        if [ -n "$file" ] && [ -f "$file" ] && [[ ! "$file" =~ \.\./|\.\.\\ ]]; then
            # SECURITY: Limit file size to prevent resource exhaustion
            if [ $(stat -f%z "$file" 2>/dev/null || echo 0) -lt 1048576 ]; then  # 1MB limit
                lines=$(wc -l < "$file" 2>/dev/null || echo "0")
                echo "$lines	0	$file"
            else
                echo "0	0	$file"  # File too large
            fi
        fi
    done > numstat.txt
fi

TOTAL_FILES=$(echo "$CHANGED_FILES" | grep -c .)
echo -e "${BLUE}Total files to review: ${TOTAL_FILES}${NC}"

# Calculate review limits based on file count
if [ "$TOTAL_FILES" -gt 50 ]; then
    COMMENT_LIMIT=5
    MAX_CONTEXT_FILES=20
    echo -e "${YELLOW}Large PR detected: Limiting to ${COMMENT_LIMIT} comments and ${MAX_CONTEXT_FILES} context files${NC}"
else
    COMMENT_LIMIT=10
    MAX_CONTEXT_FILES=50
fi

# Create files.json with patch data using jq for proper JSON escaping
echo -e "${BLUE}📝 Building files.json with patches...${NC}"

# Initialize files.json
echo '[' > files.json
FIRST_FILE=true

# Process each changed file
while IFS= read -r file; do
    if [ -n "$file" ]; then
        # Skip if file doesn't exist (e.g., deleted file)
        if [ ! -f "$file" ]; then
            echo -e "${YELLOW}Skipping deleted file: $file${NC}"
            continue
        fi
        
        # Get file extension for language detection
        FILE_EXTENSION="${file##*.}"
        case "$FILE_EXTENSION" in
            js) LANGUAGE="javascript" ;;
            ts) LANGUAGE="typescript" ;;
            py) LANGUAGE="python" ;;
            java) LANGUAGE="java" ;;
            cpp|c|cc|cxx) LANGUAGE="cpp" ;;
            cs) LANGUAGE="csharp" ;;
            go) LANGUAGE="go" ;;
            rs) LANGUAGE="rust" ;;
            php) LANGUAGE="php" ;;
            rb) LANGUAGE="ruby" ;;
            swift) LANGUAGE="swift" ;;
            kt) LANGUAGE="kotlin" ;;
            scala) LANGUAGE="scala" ;;
            sh) LANGUAGE="bash" ;;
            yaml|yml) LANGUAGE="yaml" ;;
            json) LANGUAGE="json" ;;
            xml) LANGUAGE="xml" ;;
            html) LANGUAGE="html" ;;
            css) LANGUAGE="css" ;;
            scss|sass) LANGUAGE="scss" ;;
            md) LANGUAGE="markdown" ;;
            sql) LANGUAGE="sql" ;;
            dockerfile) LANGUAGE="dockerfile" ;;
            *) LANGUAGE="text" ;;
        esac
        
        # Get the patch content
        if [ -n "$PREVIOUS_COMMIT" ]; then
            PATCH_CONTENT=$(git diff "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" -- "$file" || echo "")
        else
            PATCH_CONTENT=$(git show HEAD:"$file" | head -200 || echo "")
        fi
        
        # Escape JSON properly using jq
        JSON_ENTRY=$(jq -n \
            --arg path "$file" \
            --arg language "$LANGUAGE" \
            --arg patch "$PATCH_CONTENT" \
            '{
                path: $path,
                language: $language,
                patch: $patch
            }')
        
        # Add comma if not first file
        if [ "$FIRST_FILE" = true ]; then
            FIRST_FILE=false
        else
            echo ',' >> files.json
        fi
        
        # Add the JSON entry
        echo "$JSON_ENTRY" >> files.json
    fi
done <<< "$CHANGED_FILES"

echo ']' >> files.json

# Count total entries in files.json
FILE_COUNT=$(jq length files.json)
echo -e "${GREEN}✅ Created files.json with ${FILE_COUNT} files${NC}"

# Create prompt.txt for Codex
echo -e "${BLUE}📝 Creating prompt for Codex analysis...${NC}"

cat > prompt.txt << 'EOF'
You are an expert code reviewer. Analyze the provided code changes and identify potential issues, improvements, or bugs.

Review guidelines:
- Focus on security vulnerabilities, performance issues, and logic errors
- Highlight code quality issues and best practices violations  
- Suggest improvements for readability and maintainability
- Flag potential bugs or edge cases
- Consider architectural and design patterns
- Be constructive and provide specific, actionable feedback

Output format:
Return a JSON array of comment objects with this structure:
[
  {
    "path": "path/to/file.ext",
    "line": 123,
    "body": "Specific issue description and suggested fix"
  }
]

Limits:
- Maximum 10 comments for standard PRs
- Maximum 5 comments for large PRs (>50 files)
- Focus on the most critical issues
- Prioritize security and correctness over style

Files to review:
EOF

# Add file context to prompt
echo "\`\`\`json" >> prompt.txt
cat files.json >> prompt.txt
echo "\`\`\`" >> prompt.txt

echo -e "${GREEN}✅ Created prompt.txt with ${FILE_COUNT} files for review${NC}"

# Create diff.txt for report context
echo -e "${BLUE}📝 Creating diff.txt for context...${NC}"
if [ -n "$PREVIOUS_COMMIT" ]; then
    git diff "${PREVIOUS_COMMIT}..${LATEST_COMMIT}" > diff.txt
else
    git show --stat HEAD > diff.txt
fi
DIFF_SIZE=$(wc -l < diff.txt)
echo -e "${GREEN}✅ Created diff.txt (${DIFF_SIZE} lines)${NC}"

# Validate JSON before running Codex
echo -e "${BLUE}🔍 Validating JSON format...${NC}"
if ! jq empty files.json 2>/dev/null; then
    echo -e "${RED}❌ ERROR: Invalid JSON in files.json${NC}"
    echo -e "${YELLOW}Please check the JSON format and try again.${NC}"
    echo -e "${YELLOW}Common issues:${NC}"
    echo -e "${YELLOW}  - Unescaped special characters in file paths${NC}"
    echo -e "${YELLOW}  - Incomplete JSON structure${NC}"
    echo -e "${YELLOW}  - Missing quotes around strings${NC}"
    exit 1
fi

# Check if codex CLI is available
if ! command -v codex &> /dev/null; then
    echo -e "${RED}❌ Error: codex CLI not found in PATH${NC}"
    echo -e "${YELLOW}Please install codex CLI${NC}"
    exit 1
fi

# Run Codex with the gpt-5-High model
echo -e "${BLUE}🚀 Running code review analysis with ${MODEL_NAME}...${NC}"

if codex exec --model "${CODEX_MODEL}" --json --output-last-message comments.json "$(cat prompt.txt)"; then
    echo -e "${GREEN}✅ Review analysis completed successfully${NC}"
else
    echo -e "${RED}❌ ERROR: codex exec failed${NC}"
    echo -e "${YELLOW}This could be due to missing configuration or runtime issues.${NC}"
    exit 1
fi

# Check if comments.json was created (codex might output to a different file)
OUTPUT_FILE="comments.json"
if [ ! -f "$OUTPUT_FILE" ]; then
    # Try common output filenames
    for alt_file in "codex_output.json" "review.json" "output.json"; do
        if [ -f "$alt_file" ]; then
            OUTPUT_FILE="$alt_file"
            break
        fi
    done
    
    if [ ! -f "$OUTPUT_FILE" ]; then
        echo -e "${RED}❌ ERROR: codex exec did not create an output file${NC}"
        echo -e "${YELLOW}This usually indicates the review run failed.${NC}"
        echo -e "${YELLOW}Expected files: comments.json, codex_output.json, review.json, or output.json${NC}"
        exit 1
    fi
fi

# If using a different output file, copy it to comments.json
if [ "$OUTPUT_FILE" != "comments.json" ]; then
    cp "$OUTPUT_FILE" comments.json
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
        echo -e "${GREEN}📊 Found ${COMMENT_COUNT} potential issue${S} that should be addressed.${NC}"
    fi
else
    echo -e "${RED}❌ ERROR: Invalid JSON in comments.json${NC}"
    echo -e "${YELLOW}Please check the JSON format:${NC}"
    echo -e "${YELLOW}  - Test your JSON by running: python3 -m json.tool comments.json${NC}"
    echo -e "${YELLOW}  - The JSON must be a single line without line breaks within string values${NC}"
    exit 1
fi

# Create report directory if it doesn't exist
mkdir -p codexreview

# Create report
echo -e "${BLUE}📝 Creating consolidated report...${NC}"
REPORT_FILE="codexreview/codex-review-report.md"

cat > "$REPORT_FILE" << EOF
# Code Review Report

## Summary

This is a local code review generated using Codex CLI with the ${MODEL_NAME} model.

- **Files reviewed:** ${TOTAL_FILES}
- **Issues found:** ${COMMENT_COUNT}
- **Review Strategy:** $(if [ "$TOTAL_FILES" -gt 50 ]; then echo "Large PR (5 comment limit)"; else echo "Standard PR (10 comment limit)"; fi)

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

- **Review Type:** Local Codex Code Review
- **Model:** ${MODEL_NAME}
- **Analysis Date:** $(date '+%Y-%m-%d %H:%M:%S')
- **Git Repository:** $(git remote get-url origin 2>/dev/null || echo "Local repository")
- **Review Strategy:** $(if [ "$TOTAL_FILES" -gt 50 ]; then echo "Large PR (5 comment limit)"; else echo "Standard PR (10 comment limit)"; fi)
- **Total Files:** ${TOTAL_FILES}
- **Issues Found:** ${COMMENT_COUNT}

EOF

echo -e "${GREEN}✅ Report saved to: ${REPORT_FILE}${NC}"

# Cleanup temporary files
echo -e "${BLUE}🧹 Cleaning up temporary files...${NC}"
rm -f files.json prompt.txt diff.txt numstat.txt

echo -e "${GREEN}🎉 Review completed successfully!${NC}"
echo -e "${BLUE}📄 View the detailed report: ${REPORT_FILE}${NC}"
