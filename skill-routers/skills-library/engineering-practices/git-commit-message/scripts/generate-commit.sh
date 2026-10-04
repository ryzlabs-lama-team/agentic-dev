#!/bin/bash
set -e

# Conventional Commits v1.0.0 message generator
# Analyzes staged changes and generates a commit message

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo -e "${RED}Error: Not inside a git repository${NC}" >&2
  exit 1
fi

# Check for staged changes
if git diff --cached --quiet; then
  echo -e "${RED}Error: No staged changes found. Stage changes with 'git add' first.${NC}" >&2
  exit 1
fi

# Get staged files
STAGED_FILES=$(git diff --cached --name-only)
STAGED_DIFF=$(git diff --cached --stat)

echo -e "${CYAN}=== Staged Changes ===${NC}"
echo "$STAGED_DIFF"
echo ""

# Analyze file patterns to suggest type
SUGGEST_TYPE=""
SCOPE=""

# Check for common patterns
if echo "$STAGED_FILES" | grep -qE '\.(test|spec)\.(ts|tsx|js|jsx|py|rb|go)$'; then
  SUGGEST_TYPE="test"
elif echo "$STAGED_FILES" | grep -qE '\.(md|txt|rst)$|docs?\/'; then
  SUGGEST_TYPE="docs"
elif echo "$STAGED_FILES" | grep -qE '(\.github|\.gitlab|\.circleci|Jenkinsfile|\.travis)'; then
  SUGGEST_TYPE="ci"
elif echo "$STAGED_FILES" | grep -qE '(package\.json|Cargo\.toml|go\.mod|requirements\.txt|Makefile|Dockerfile|docker-compose)'; then
  SUGGEST_TYPE="build"
elif echo "$STAGED_FILES" | grep -qE '\.(css|scss|less|html)$'; then
  SUGGEST_TYPE="style"
fi

# Try to detect scope from directory structure
FIRST_FILE=$(echo "$STAGED_FILES" | head -1)
if [ -n "$FIRST_FILE" ]; then
  # Use top-level directory as scope if project has src/ structure
  TOP_DIR=$(echo "$FIRST_FILE" | cut -d'/' -f1)
  if [ "$TOP_DIR" != "$FIRST_FILE" ]; then
    SCOPE="$TOP_DIR"
  fi
fi

# Detect breaking changes
BREAKING=false
if git diff --cached | grep -qE '^\-.*BREAKING|BREAKING CHANGE'; then
  BREAKING=true
fi

echo -e "${CYAN}=== Suggested Type: ${GREEN}${SUGGEST_TYPE:-feat}${NC}"
[ -n "$SCOPE" ] && echo -e "${CYAN}=== Suggested Scope: ${GREEN}${SCOPE}${NC}"
[ "$BREAKING" = true ] && echo -e "${YELLOW}=== Breaking change detected${NC}"
echo ""

# Output JSON for programmatic use
cat <<EOF
{
  "type": "${SUGGEST_TYPE:-feat}",
  "scope": "${SCOPE}",
  "breaking": ${BREAKING},
  "files": $(echo "$STAGED_FILES" | jq -R -s 'split("\n") | map(select(. != ""))')
}
EOF
