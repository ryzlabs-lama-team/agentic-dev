#!/usr/bin/env bash
# Install the opsx-loop orchestrator + subagents into a target repo.
#   ./install.sh [--force] /path/to/repo
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect a sha256 tool once at startup (macOS ships shasum, Linux ships sha256sum).
HAVE_SHA=1
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  HAVE_SHA=0
fi

sha256_of() {
  if [ -z "${_SHA256_CMD:-}" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      _SHA256_CMD="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
      _SHA256_CMD="shasum -a 256"
    else
      _SHA256_CMD="false"
    fi
  fi
  $_SHA256_CMD "$1" | awk '{print $1}'
}

FORCE=0
DEST=""
for arg in "$@"; do
  case "$arg" in
    --force|-f)
      FORCE=1
      ;;
    -*)
      echo "usage: $0 [--force] /path/to/target-repo" >&2
      exit 1
      ;;
    *)
      if [ -n "$DEST" ]; then
        echo "usage: $0 [--force] /path/to/target-repo" >&2
        exit 1
      fi
      DEST="$arg"
      ;;
  esac
done

if [ -z "$DEST" ]; then
  echo "usage: $0 [--force] /path/to/target-repo" >&2
  exit 1
fi
if [ ! -d "$DEST" ]; then
  echo "error: $DEST is not a directory" >&2
  exit 1
fi

mkdir -p "$DEST/.claude/agents" "$DEST/.claude/skills"

# Installed set: five hardcoded agent files plus every file under the skills
# tree, as paths relative to $SRC, sorted for deterministic manifest order.
AGENT_LIST="$(for a in explorer proposer implementer verifier syncer; do
  printf '.claude/agents/opsx-%s.md\n' "$a"
done)"

SKILL_LIST="$(find "$SRC/.claude/skills/opsx-loop" -type f | while IFS= read -r f; do
  printf '%s\n' "${f#$SRC/}"
done)"

INSTALLED_LIST="$(printf '%s\n%s\n' "$AGENT_LIST" "$SKILL_LIST" | LC_ALL=C sort)"

MANIFEST="$DEST/.claude/.opsx-install-manifest"

# Plan pass: classify every destination file without touching the destination.
# Fed via a here-string (not a pipe) so PLAN_REL/PLAN_CLASS survive the loop.
PLAN_REL=()
PLAN_CLASS=()

while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  if [ ! -e "$DEST/$rel" ]; then
    class="new"
  elif cmp -s "$SRC/$rel" "$DEST/$rel"; then
    class="identical"
  else
    class="customized"
    if [ "$HAVE_SHA" -eq 1 ] && [ -f "$MANIFEST" ]; then
      recorded_line="$(grep " $rel\$" "$MANIFEST" 2>/dev/null || true)"
      recorded_hash="${recorded_line%%[[:space:]]*}"
      if [ -n "$recorded_hash" ] && [ "$recorded_hash" = "$(sha256_of "$DEST/$rel")" ]; then
        class="stale"
      fi
    fi
  fi
  PLAN_REL+=("$rel")
  PLAN_CLASS+=("$class")
done <<< "$INSTALLED_LIST"

# Decision: refuse before writing anything if any file is customized and the
# user did not pass --force.
CONFLICTS=()
for i in "${!PLAN_REL[@]}"; do
  if [ "${PLAN_CLASS[$i]}" = "customized" ]; then
    CONFLICTS+=("${PLAN_REL[$i]}")
  fi
done

if [ "${#CONFLICTS[@]}" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  echo "error: refusing to overwrite customized files:" >&2
  for c in "${CONFLICTS[@]}"; do
    echo "  $c" >&2
  done
  echo "hint: pass --force (or -f) to overwrite these files" >&2
  exit 1
fi

# Commit pass: write every non-identical file, report each, accumulate
# manifest entries, then set permissions, update .gitignore, and write the
# manifest.
MANIFEST_CONTENT=""
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}"
  class="${PLAN_CLASS[$i]}"
  if [ "$class" != "identical" ]; then
    mkdir -p "$(dirname "$DEST/$rel")"
    cp "$SRC/$rel" "$DEST/$rel"
  fi
  echo "  $class  $rel"
  if [ "$HAVE_SHA" -eq 1 ]; then
    MANIFEST_CONTENT="${MANIFEST_CONTENT}$(sha256_of "$SRC/$rel")  $rel
"
  fi
done

chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh"

if [ -d "$DEST/.git" ] && ! grep -qs '^\.opsx-run' "$DEST/.gitignore" 2>/dev/null; then
  printf '\n# opsx-loop run state\n.opsx-run/\n' >> "$DEST/.gitignore"
  echo "  .gitignore += .opsx-run/"
fi

if [ "$HAVE_SHA" -eq 1 ]; then
  printf '%s' "$MANIFEST_CONTENT" > "$MANIFEST"
fi

echo
echo "Installed into $DEST"
echo "Next: cd $DEST && bash .claude/skills/opsx-loop/preflight.sh"
