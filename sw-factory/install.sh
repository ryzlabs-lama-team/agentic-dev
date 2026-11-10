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
  for a in swf-manager swf-po swf-architect swf-planner swf-builder swf-qa; do printf '.claude/agents/swf/%s.md\n' "$a"; done
  find "$SRC/.claude/swf-tools" -type f ! -name '.DS_Store' | while IFS= read -r f; do printf '%s\n' "${f#"$SRC"/}"; done
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

# Earlier installs used .claude/agents/ (agents) and .claude/sw-factory/ (support tools). Remove
# those copies when they are unmodified (identical to the source, or matching the old manifest); a
# customized one is kept and reported, since two agents with the same name would conflict.
for rel in "${PLAN_REL[@]}"; do
  case "$rel" in
    .claude/agents/swf/*) old=".claude/agents/${rel#.claude/agents/swf/}" ;;
    .claude/swf-tools/*)  old=".claude/sw-factory/${rel#.claude/swf-tools/}" ;;
    *) continue ;;
  esac
  [ -e "$DEST/$old" ] || continue
  if cmp -s "$SRC/$rel" "$DEST/$old" \
     || { [ "$HAVE_SHA" -eq 1 ] && recorded="$(manifest_hash_for "$old" || true)" && [ -n "$recorded" ] \
          && [ "$recorded" = "$(sha256_of "$DEST/$old")" ]; }; then
    rm "$DEST/$old"; echo "  removed  $old (moved to $rel)"
  else
    echo "warning: $old is customized and was left in place; move your changes into" >&2
    echo "         $rel and delete it" >&2
  fi
done
[ ! -d "$DEST/.claude/sw-factory" ] || find "$DEST/.claude/sw-factory" -depth -type d -empty -delete

MANIFEST_BODY=''
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}" class="${PLAN_CLASS[$i]}"
  [ "$class" = identical ] || { mkdir -p "$(dirname "$DEST/$rel")"; cp "$SRC/$rel" "$DEST/$rel"; }
  echo "  $class  $rel"
  [ "$HAVE_SHA" -eq 0 ] || MANIFEST_BODY+="$(sha256_of "$SRC/$rel")  $rel"$'\n'
done
chmod +x "$DEST/.claude/swf-tools/preflight.sh" "$DEST/.claude/swf-tools/hooks/guard.sh" "$DEST/.claude/swf-tools/usage.py"
if [ "$HAVE_SHA" -eq 1 ]; then printf '%s' "$MANIFEST_BODY" > "$MANIFEST"
else echo 'warning: no SHA-256 utility found; manifest not written and differing files are treated as customized' >&2; fi

# The config is the user's from the first install on: create it once, never overwrite it.
if [ -e "$DEST/.sw-factory/config.yaml" ]; then
  echo "  kept  .sw-factory/config.yaml"
else
  mkdir -p "$DEST/.sw-factory"; cp "$SRC/.claude/swf-tools/templates/config.yaml" "$DEST/.sw-factory/config.yaml"
  echo "  new  .sw-factory/config.yaml"
fi

# Project hooks. Agent-frontmatter hooks did not fire in Claude Code 2.1.318, so both run from
# settings: the ownership guard (PreToolUse, dispatching on the hook's agent_type) and the usage
# snapshot (SessionEnd, which runs after the session's last turn and never reaches any context).
SETTINGS="$DEST/.claude/settings.json"
hook_entry() { # hook_entry <command> [matcher]: one hooks.<event> entry as JSON
  printf '{%s"hooks":[{"type":"command","command":"%s"}]}' "${2:+\"matcher\":\"$2\",}" "${1//\"/\\\"}"
}
merge_hook() { # merge_hook <event> <entry> <in> <out>: append <entry> to hooks.<event>
  if command -v jq >/dev/null 2>&1; then
    jq --arg ev "$1" --argjson e "$2" '.hooks[$ev] = ((.hooks[$ev] // []) + [$e])' "$3" > "$4"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys
s = json.load(open(sys.argv[1])); e = json.loads(sys.argv[3])
s.setdefault("hooks", {}).setdefault(sys.argv[4], []).append(e)
json.dump(s, open(sys.argv[2], "w"), indent=2); open(sys.argv[2], "a").write("\n")' "$3" "$4" "$2" "$1"
  else return 1; fi
}
wire_hook() { # wire_hook <event> <marker> <entry> <label>: add <entry> unless <marker> is already wired
  local tmp="$SETTINGS.sw-factory.tmp"
  if [ ! -e "$SETTINGS" ]; then
    printf '{\n  "hooks": {\n    "%s": [\n      %s\n    ]\n  }\n}\n' "$1" "$3" > "$SETTINGS"
    echo "  new  .claude/settings.json ($1 $4)"
  elif grep -q "$2" "$SETTINGS"; then
    echo "  kept  .claude/settings.json ($4 already wired)"
  elif merge_hook "$1" "$3" "$SETTINGS" "$tmp" 2>/dev/null; then
    mv "$tmp" "$SETTINGS"; echo "  merged  .claude/settings.json += $1 $4"
  else
    rm -f "$tmp"
    echo "warning: could not merge the $4 into .claude/settings.json (no jq/python3, or invalid JSON)." >&2
    echo "         Add this entry to hooks.$1 yourself:" >&2
    echo "         $3" >&2
  fi
}
# Hooks wired by earlier installs point at .claude/sw-factory/; repoint them at .claude/swf-tools/.
for s in "$SETTINGS" "$DEST/.claude/settings.local.json"; do
  if grep -qs '\.claude/sw-factory/\(hooks/guard\.sh\|usage\.py\)' "$s"; then
    sed -e 's#\.claude/sw-factory/hooks/guard\.sh#.claude/swf-tools/hooks/guard.sh#g' \
        -e 's#\.claude/sw-factory/usage\.py#.claude/swf-tools/usage.py#g' "$s" > "$s.sw-factory.tmp" \
      && mv "$s.sw-factory.tmp" "$s" && echo "  updated  ${s#"$DEST"/} (hooks moved to .claude/swf-tools/)"
  fi
done
wire_hook PreToolUse 'swf-tools/hooks/guard.sh' \
  "$(hook_entry 'bash "${CLAUDE_PROJECT_DIR}/.claude/swf-tools/hooks/guard.sh"' 'Write|Edit|NotebookEdit|Agent|Task')" guard
wire_hook SessionEnd 'swf-tools/usage.py' \
  "$(hook_entry 'python3 "${CLAUDE_PROJECT_DIR}/.claude/swf-tools/usage.py" snapshot --hook >/dev/null 2>&1 || true')" 'usage snapshot'

if [ -d "$DEST/.git" ] && ! grep -qs '^\.sw-factory/runs' "$DEST/.gitignore"; then
  printf '\n# sw-factory run state\n.sw-factory/runs/\n' >> "$DEST/.gitignore"; echo '  .gitignore += .sw-factory/runs/'
fi

echo
echo "Installed into $DEST"
echo "Next: cd $DEST && bash .claude/swf-tools/preflight.sh && claude --agent swf-manager"
