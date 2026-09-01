#!/usr/bin/env bash
# Install the opsx-loop orchestrator + subagents into a target repo.
#   ./install.sh [--force] [--target claude|opencode|both] /path/to/repo
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: $0 [--force] [--target claude|opencode|both] /path/to/target-repo" >&2
}

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
TARGET=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f)
      FORCE=1
      shift
      ;;
    --target)
      if [ -n "$TARGET" ]; then
        usage
        exit 1
      fi
      if [ -z "${2:-}" ]; then
        usage
        exit 1
      fi
      case "$2" in
        claude|opencode|both) TARGET="$2" ;;
        *) usage; exit 1 ;;
      esac
      shift 2
      ;;
    -*)
      usage
      exit 1
      ;;
    *)
      if [ -n "$DEST" ]; then
        usage
        exit 1
      fi
      DEST="$1"
      shift
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="claude"
fi

if [ -z "$DEST" ]; then
  usage
  exit 1
fi
if [ ! -d "$DEST" ]; then
  echo "error: $DEST is not a directory" >&2
  exit 1
fi

# Installed set: enumerated per distribution, as paths relative to $SRC.
#
# Claude: five hardcoded agent files plus every file under the skills tree —
# that directory holds nothing but toolkit files, so a `find` is safe.
CLAUDE_AGENT_LIST="$(for a in explorer proposer implementer verifier syncer; do
  printf '.claude/agents/opsx-%s.md\n' "$a"
done)"

CLAUDE_SKILL_LIST="$(find "$SRC/.claude/skills/opsx-loop" -type f | while IFS= read -r f; do
  printf '%s\n' "${f#$SRC/}"
done)"

CLAUDE_LIST="$(printf '%s\n%s\n' "$CLAUDE_AGENT_LIST" "$CLAUDE_SKILL_LIST" | LC_ALL=C sort)"

# OpenCode: an explicitly enumerated list. Never `find` over `.opencode/` as a
# whole — that directory also holds `openspec init --tools opencode` output
# (`.opencode/commands/opsx-<stage>.md`, `.opencode/skills/openspec-*/`) which
# belongs to OpenSpec, not to this toolkit, and must never be classified,
# written, or recorded.
OPENCODE_AGENT_LIST="$(for a in loop explorer proposer implementer implementer-hard verifier syncer; do
  printf '.opencode/agents/opsx-%s.md\n' "$a"
done)"

OPENCODE_COMMAND_LIST=".opencode/commands/opsx-loop.md"

OPENCODE_SKILL_LIST="$(find "$SRC/.opencode/opsx-loop" -type f | while IFS= read -r f; do
  printf '%s\n' "${f#$SRC/}"
done)"

OPENCODE_LIST="$(printf '%s\n%s\n%s\n' "$OPENCODE_AGENT_LIST" "$OPENCODE_COMMAND_LIST" "$OPENCODE_SKILL_LIST" | LC_ALL=C sort)"

case "$TARGET" in
  claude)
    INSTALLED_LIST="$CLAUDE_LIST"
    ;;
  opencode)
    INSTALLED_LIST="$OPENCODE_LIST"
    ;;
  both)
    INSTALLED_LIST="$(printf '%s\n%s\n' "$CLAUDE_LIST" "$OPENCODE_LIST" | LC_ALL=C sort)"
    ;;
esac

CLAUDE_MANIFEST="$DEST/.claude/.opsx-install-manifest"
OPENCODE_MANIFEST="$DEST/.opencode/.opsx-install-manifest"

# Which distribution a path belongs to, so classification and manifest
# writing each consult only that distribution's own manifest.
manifest_for() {
  case "$1" in
    .claude/*)   echo "$CLAUDE_MANIFEST" ;;
    .opencode/*) echo "$OPENCODE_MANIFEST" ;;
  esac
}

# Plan pass: classify every destination file without touching the destination.
# Fed via a here-string (not a pipe) so PLAN_REL/PLAN_CLASS survive the loop.
PLAN_REL=()
PLAN_CLASS=()

while IFS= read -r rel; do
  [ -z "$rel" ] && continue
  manifest="$(manifest_for "$rel")"
  if [ ! -e "$DEST/$rel" ]; then
    class="new"
  elif cmp -s "$SRC/$rel" "$DEST/$rel"; then
    class="identical"
  else
    class="customized"
    if [ "$HAVE_SHA" -eq 1 ] && [ -f "$manifest" ]; then
      recorded_line="$(grep " $rel\$" "$manifest" 2>/dev/null || true)"
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
# user did not pass --force. With --target both this spans the whole union,
# so a conflict in either distribution blocks writing both.
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

# Commit pass: write every non-identical file, report each, accumulate each
# distribution's own manifest entries, then set permissions, update
# .gitignore, and write the manifest of each installed distribution.
CLAUDE_MANIFEST_CONTENT=""
OPENCODE_MANIFEST_CONTENT=""
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}"
  class="${PLAN_CLASS[$i]}"
  if [ "$class" != "identical" ]; then
    mkdir -p "$(dirname "$DEST/$rel")"
    cp "$SRC/$rel" "$DEST/$rel"
  fi
  echo "  $class  $rel"
  if [ "$HAVE_SHA" -eq 1 ]; then
    entry="$(sha256_of "$SRC/$rel")  $rel
"
    case "$rel" in
      .claude/*)   CLAUDE_MANIFEST_CONTENT="${CLAUDE_MANIFEST_CONTENT}${entry}" ;;
      .opencode/*) OPENCODE_MANIFEST_CONTENT="${OPENCODE_MANIFEST_CONTENT}${entry}" ;;
    esac
  fi
done

case "$TARGET" in
  claude)   chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh" ;;
  opencode) chmod +x "$DEST/.opencode/opsx-loop/preflight.sh" ;;
  both)
    chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh"
    chmod +x "$DEST/.opencode/opsx-loop/preflight.sh"
    ;;
esac

if [ -d "$DEST/.git" ] && ! grep -qs '^\.opsx-run' "$DEST/.gitignore" 2>/dev/null; then
  printf '\n# opsx-loop run state\n.opsx-run/\n' >> "$DEST/.gitignore"
  echo "  .gitignore += .opsx-run/"
fi

if [ "$HAVE_SHA" -eq 1 ]; then
  case "$TARGET" in
    claude)   printf '%s' "$CLAUDE_MANIFEST_CONTENT" > "$CLAUDE_MANIFEST" ;;
    opencode) printf '%s' "$OPENCODE_MANIFEST_CONTENT" > "$OPENCODE_MANIFEST" ;;
    both)
      printf '%s' "$CLAUDE_MANIFEST_CONTENT" > "$CLAUDE_MANIFEST"
      printf '%s' "$OPENCODE_MANIFEST_CONTENT" > "$OPENCODE_MANIFEST"
      ;;
  esac
fi

echo
echo "Installed into $DEST"
case "$TARGET" in
  claude)
    echo "Next: cd $DEST && bash .claude/skills/opsx-loop/preflight.sh"
    ;;
  opencode)
    echo "Next: cd $DEST && bash .opencode/opsx-loop/preflight.sh"
    ;;
  both)
    echo "Next: cd $DEST && bash .claude/skills/opsx-loop/preflight.sh   (Claude Code)"
    echo "  or: cd $DEST && bash .opencode/opsx-loop/preflight.sh        (OpenCode)"
    ;;
esac
