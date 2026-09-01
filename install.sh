#!/usr/bin/env bash
# Install the opsx-loop distributions into a target repository.
#   ./install.sh [--force] [--target claude|opencode|copilot|all] /path/to/repo
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: $0 [--force] [--target claude|opencode|copilot|all] /path/to/target-repo" >&2; }
FORCE=0 DEST='' TARGET=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --target)
      [ -z "$TARGET" ] && [ -n "${2:-}" ] || { usage; exit 1; }
      case "$2" in claude|opencode|copilot|all) TARGET="$2" ;; *) usage; exit 1 ;; esac
      shift 2 ;;
    -*) usage; exit 1 ;;
    *) [ -z "$DEST" ] || { usage; exit 1; }; DEST="$1"; shift ;;
  esac
done
TARGET="${TARGET:-claude}"
[ -n "$DEST" ] || { usage; exit 1; }
[ -d "$DEST" ] || { echo "error: $DEST is not a directory" >&2; exit 1; }

# Hashes distinguish a prior toolkit install from a user customization. Without
# a SHA-256 utility, retain the conservative direct-comparison behavior and do
# not write manifests that could not be consulted on a later install.
HAVE_SHA=0
SHA256_CMD=()
if command -v sha256sum >/dev/null 2>&1; then
  HAVE_SHA=1
  SHA256_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  HAVE_SHA=1
  SHA256_CMD=(shasum -a 256)
fi
sha256_of() { "${SHA256_CMD[@]}" "$1" | awk '{print $1}'; }
CLAUDE_LIST="$( { for a in explorer proposer implementer verifier syncer; do printf '.claude/agents/opsx-%s.md\n' "$a"; done; find "$SRC/.claude/skills/opsx-loop" -type f | while IFS= read -r f; do printf '%s\n' "${f#$SRC/}"; done; } | LC_ALL=C sort)"
OPENCODE_LIST="$( { for a in loop explorer proposer implementer implementer-hard verifier syncer; do printf '.opencode/agents/opsx-%s.md\n' "$a"; done; printf '%s\n' '.opencode/commands/opsx-loop.md'; find "$SRC/.opencode/opsx-loop" -type f | while IFS= read -r f; do printf '%s\n' "${f#$SRC/}"; done; } | LC_ALL=C sort)"
COPILOT_LIST="$( { for a in loop explorer proposer implementer implementer-hard verifier syncer; do printf '.github/agents/opsx-%s.agent.md\n' "$a"; done; find "$SRC/.github/opsx-loop" -type f | while IFS= read -r f; do printf '%s\n' "${f#$SRC/}"; done; } | LC_ALL=C sort)"
case "$TARGET" in
  claude) INSTALLED_LIST="$CLAUDE_LIST";; opencode) INSTALLED_LIST="$OPENCODE_LIST";; copilot) INSTALLED_LIST="$COPILOT_LIST";;
  all) INSTALLED_LIST="$(printf '%s\n%s\n%s\n' "$CLAUDE_LIST" "$OPENCODE_LIST" "$COPILOT_LIST" | LC_ALL=C sort)";;
esac
manifest_for() { case "$1" in .claude/*) echo "$DEST/.claude/.opsx-install-manifest";; .opencode/*) echo "$DEST/.opencode/.opsx-install-manifest";; .github/*) echo "$DEST/.github/.opsx-install-manifest";; esac; }
manifest_hash_for() {
  local manifest="$1" wanted="$2" hash path
  [ -f "$manifest" ] || return 1
  while IFS= read -r line; do
    hash="${line%%  *}"
    path="${line#*  }"
    if [ "$path" = "$wanted" ] && [ "$hash  $path" = "$line" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done < "$manifest"
  return 1
}
PLAN_REL=() PLAN_CLASS=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue; manifest="$(manifest_for "$rel")"
  if [ ! -e "$DEST/$rel" ]; then class=new
  elif cmp -s "$SRC/$rel" "$DEST/$rel"; then class=identical
  elif [ "$HAVE_SHA" -eq 1 ] && recorded_hash="$(manifest_hash_for "$manifest" "$rel" || true)" && [ -n "$recorded_hash" ] && [ "$recorded_hash" = "$(sha256_of "$DEST/$rel")" ]; then class=stale
  else class=customized; fi
  PLAN_REL+=("$rel"); PLAN_CLASS+=("$class")
done <<< "$INSTALLED_LIST"
conflicts=(); for i in "${!PLAN_REL[@]}"; do [ "${PLAN_CLASS[$i]}" = customized ] && conflicts+=("${PLAN_REL[$i]}"); done
if [ "${#conflicts[@]}" -gt 0 ] && [ "$FORCE" -ne 1 ]; then echo 'error: refusing to overwrite customized files:' >&2; printf '  %s\n' "${conflicts[@]}" >&2; echo 'hint: pass --force (or -f) to overwrite these files' >&2; exit 1; fi
CLAUDE_MANIFEST='' OPENCODE_MANIFEST='' COPILOT_MANIFEST=''
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}" class="${PLAN_CLASS[$i]}"; [ "$class" = identical ] || { mkdir -p "$(dirname "$DEST/$rel")"; cp "$SRC/$rel" "$DEST/$rel"; }; echo "  $class  $rel"
  if [ "$HAVE_SHA" -eq 1 ]; then
    entry="$(sha256_of "$SRC/$rel")  $rel"$'\n'
    case "$rel" in .claude/*) CLAUDE_MANIFEST+="$entry";; .opencode/*) OPENCODE_MANIFEST+="$entry";; .github/*) COPILOT_MANIFEST+="$entry";; esac
  fi
done
case "$TARGET" in claude) selected=(claude);; opencode) selected=(opencode);; copilot) selected=(copilot);; all) selected=(claude opencode copilot);; esac
for distribution in "${selected[@]}"; do
  case "$distribution" in
    claude) chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh"; [ "$HAVE_SHA" -eq 0 ] || printf '%s' "$CLAUDE_MANIFEST" > "$DEST/.claude/.opsx-install-manifest";;
    opencode) chmod +x "$DEST/.opencode/opsx-loop/preflight.sh"; [ "$HAVE_SHA" -eq 0 ] || printf '%s' "$OPENCODE_MANIFEST" > "$DEST/.opencode/.opsx-install-manifest";;
    copilot) chmod +x "$DEST/.github/opsx-loop/preflight.sh" "$DEST/.github/opsx-loop/validate-agents.sh"; [ "$HAVE_SHA" -eq 0 ] || printf '%s' "$COPILOT_MANIFEST" > "$DEST/.github/.opsx-install-manifest";;
  esac
done
if [ "$HAVE_SHA" -eq 0 ]; then
  echo 'warning: no SHA-256 utility found; manifests were not written and differing files are treated as customized' >&2
fi
if [ -d "$DEST/.git" ] && ! grep -qs '^\.opsx-run' "$DEST/.gitignore" 2>/dev/null; then printf '\n# opsx-loop run state\n.opsx-run/\n' >> "$DEST/.gitignore"; echo '  .gitignore += .opsx-run/'; fi
echo; echo "Installed into $DEST"
case "$TARGET" in claude) echo "Next: cd $DEST && bash .claude/skills/opsx-loop/preflight.sh";; opencode) echo "Next: cd $DEST && bash .opencode/opsx-loop/preflight.sh";; copilot) echo "Next: cd $DEST && bash .github/opsx-loop/preflight.sh";; all) echo "Next: cd $DEST && bash .claude/skills/opsx-loop/preflight.sh   (Claude Code)"; echo "  or: cd $DEST && bash .opencode/opsx-loop/preflight.sh        (OpenCode)"; echo "  or: cd $DEST && bash .github/opsx-loop/preflight.sh          (GitHub Copilot)";; esac
