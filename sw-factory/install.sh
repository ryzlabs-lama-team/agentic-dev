#!/usr/bin/env bash
# Install the sw-factory (Claude Code) into a target repository.
#   ./install.sh [--force] /path/to/repo
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: $0 [--force] /path/to/target-repo" >&2; }
FORCE=0 DEST=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    -*) usage; exit 1 ;;
    *) [ -z "$DEST" ] || { usage; exit 1; }; DEST="$1"; shift ;;
  esac
done
[ -n "$DEST" ] || { usage; exit 1; }
[ -d "$DEST" ] || { echo "error: $DEST is not a directory" >&2; exit 1; }
DEST="$(cd "$DEST" && pwd)"
[ "$DEST" != "$SRC" ] || { echo "error: target is the sw-factory source itself" >&2; exit 1; }

# Hashes distinguish a prior install from a user customization (same scheme as opsx-loop). Without
# a SHA-256 utility, every differing file is treated as customized and no manifest is written.
HAVE_SHA=0 SHA256_CMD=()
if command -v sha256sum >/dev/null 2>&1; then HAVE_SHA=1; SHA256_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then HAVE_SHA=1; SHA256_CMD=(shasum -a 256); fi
sha256_of() { "${SHA256_CMD[@]}" "$1" | awk '{print $1}'; }

MANIFEST="$DEST/.claude/.sw-factory-install-manifest"
manifest_hash_for() {
  local wanted="$1" line hash path
  [ -f "$MANIFEST" ] || return 1
  while IFS= read -r line; do
    hash="${line%%  *}" path="${line#*  }"
    [ "$path" = "$wanted" ] && [ "$hash  $path" = "$line" ] && { printf '%s\n' "$hash"; return 0; }
  done < "$MANIFEST"
  return 1
}

LIST="$( {
  for a in sw-manager po sw-architect sw-planner sw-builder sw-qa; do printf '.claude/agents/%s.md\n' "$a"; done
  find "$SRC/.claude/sw-factory" -type f ! -name '.DS_Store' | while IFS= read -r f; do printf '%s\n' "${f#"$SRC"/}"; done
} | LC_ALL=C sort)"

PLAN_REL=() PLAN_CLASS=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ ! -e "$DEST/$rel" ]; then class=new
  elif cmp -s "$SRC/$rel" "$DEST/$rel"; then class=identical
  elif [ "$HAVE_SHA" -eq 1 ] && recorded="$(manifest_hash_for "$rel" || true)" && [ -n "$recorded" ] \
       && [ "$recorded" = "$(sha256_of "$DEST/$rel")" ]; then class=stale
  else class=customized; fi
  PLAN_REL+=("$rel"); PLAN_CLASS+=("$class")
done <<< "$LIST"

conflicts=()
for i in "${!PLAN_REL[@]}"; do [ "${PLAN_CLASS[$i]}" = customized ] && conflicts+=("${PLAN_REL[$i]}"); done
if [ "${#conflicts[@]}" -gt 0 ] && [ "$FORCE" -ne 1 ]; then
  echo 'error: refusing to overwrite customized files:' >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  echo 'hint: pass --force (or -f) to overwrite these files' >&2
  exit 1
fi

MANIFEST_BODY=''
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}" class="${PLAN_CLASS[$i]}"
  [ "$class" = identical ] || { mkdir -p "$(dirname "$DEST/$rel")"; cp "$SRC/$rel" "$DEST/$rel"; }
  echo "  $class  $rel"
  [ "$HAVE_SHA" -eq 0 ] || MANIFEST_BODY+="$(sha256_of "$SRC/$rel")  $rel"$'\n'
done
chmod +x "$DEST/.claude/sw-factory/preflight.sh" "$DEST/.claude/sw-factory/hooks/guard.sh"
if [ "$HAVE_SHA" -eq 1 ]; then printf '%s' "$MANIFEST_BODY" > "$MANIFEST"
else echo 'warning: no SHA-256 utility found; manifest not written and differing files are treated as customized' >&2; fi

# The config is the user's from the first install on: create it once, never overwrite it.
if [ -e "$DEST/.sw-factory/config.yaml" ]; then
  echo "  kept  .sw-factory/config.yaml"
else
  mkdir -p "$DEST/.sw-factory"; cp "$SRC/.claude/sw-factory/templates/config.yaml" "$DEST/.sw-factory/config.yaml"
  echo "  new  .sw-factory/config.yaml"
fi

# Wire the ownership guard as a project PreToolUse hook. Agent-frontmatter hooks did not fire in
# Claude Code 2.1.318, so the guard runs from settings and dispatches on the hook's agent_type.
SETTINGS="$DEST/.claude/settings.json"
MATCHER='Write|Edit|NotebookEdit|Agent|Task'
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.claude/sw-factory/hooks/guard.sh"'
ENTRY="{\"matcher\":\"$MATCHER\",\"hooks\":[{\"type\":\"command\",\"command\":\"${HOOK_CMD//\"/\\\"}\"}]}"
merge_hook() { # merge_hook <in> <out>: append ENTRY to hooks.PreToolUse
  if command -v jq >/dev/null 2>&1; then
    jq --argjson e "$ENTRY" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [$e])' "$1" > "$2"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys
s = json.load(open(sys.argv[1])); e = json.loads(sys.argv[3])
s.setdefault("hooks", {}).setdefault("PreToolUse", []).append(e)
json.dump(s, open(sys.argv[2], "w"), indent=2); open(sys.argv[2], "a").write("\n")' "$1" "$2" "$ENTRY"
  else return 1; fi
}
if [ ! -e "$SETTINGS" ]; then
  printf '{\n  "hooks": {\n    "PreToolUse": [\n      %s\n    ]\n  }\n}\n' "$ENTRY" > "$SETTINGS"
  echo "  new  .claude/settings.json (PreToolUse guard)"
elif grep -q 'sw-factory/hooks/guard.sh' "$SETTINGS"; then
  echo "  kept  .claude/settings.json (guard already wired)"
elif merge_hook "$SETTINGS" "$SETTINGS.sw-factory.tmp" 2>/dev/null; then
  mv "$SETTINGS.sw-factory.tmp" "$SETTINGS"; echo "  merged  .claude/settings.json += PreToolUse guard"
else
  rm -f "$SETTINGS.sw-factory.tmp"
  echo "warning: could not merge the guard into .claude/settings.json (no jq/python3, or invalid JSON)." >&2
  echo "         Add this entry to hooks.PreToolUse yourself:" >&2
  echo "         $ENTRY" >&2
fi

if [ -d "$DEST/.git" ] && ! grep -qs '^\.sw-factory/runs' "$DEST/.gitignore"; then
  printf '\n# sw-factory run state\n.sw-factory/runs/\n' >> "$DEST/.gitignore"; echo '  .gitignore += .sw-factory/runs/'
fi

echo
echo "Installed into $DEST"
echo "Next: cd $DEST && bash .claude/sw-factory/preflight.sh && claude --agent sw-manager"
