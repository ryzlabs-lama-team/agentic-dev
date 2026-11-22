#!/usr/bin/env bash
# Install the sw-factory into a target repository, for Claude Code, OpenCode, or both.
#   ./install.sh [--force] [--target claude|opencode|all] /path/to/repo
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "usage: $0 [--force] [--target claude|opencode|all] /path/to/target-repo" >&2; }
FORCE=0 DEST='' TARGET=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force|-f) FORCE=1; shift ;;
    --target)
      [ -z "$TARGET" ] && [ -n "${2:-}" ] || { usage; exit 1; }
      case "$2" in claude|opencode|all) TARGET="$2" ;; *) usage; exit 1 ;; esac
      shift 2 ;;
    -*) usage; exit 1 ;;
    *) [ -z "$DEST" ] || { usage; exit 1; }; DEST="$1"; shift ;;
  esac
done
TARGET="${TARGET:-claude}"
case "$TARGET" in claude) SELECTED=(claude) ;; opencode) SELECTED=(opencode) ;; all) SELECTED=(claude opencode) ;; esac
has() { case " ${SELECTED[*]} " in *" $1 "*) return 0 ;; esac; return 1; }
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

# One manifest per distribution, each listing only its own files.
manifest_for() { case "$1" in .opencode/*) echo "$DEST/.opencode/.sw-factory-install-manifest" ;; *) echo "$DEST/.claude/.sw-factory-install-manifest" ;; esac; }
manifest_hash_for() {
  local wanted="$1" line hash path MANIFEST
  MANIFEST="$(manifest_for "$1")"
  [ -f "$MANIFEST" ] || return 1
  while IFS= read -r line; do
    hash="${line%%  *}" path="${line#*  }"
    [ "$path" = "$wanted" ] && [ "$hash  $path" = "$line" ] && { printf '%s\n' "$hash"; return 0; }
  done < "$MANIFEST"
  return 1
}

# The OpenCode tree ships only what differs by runtime: agents, the guard plugin, and the
# .opencode/swf-tools/ files whose text names runtime paths or tools. Every other support file
# (swf-cli.py, guard.sh, usage.py, templates, …) is runtime-neutral and installed from .claude/swf-tools/.
claude_list() {
  for a in swf-manager swf-po swf-architect swf-planner swf-builder swf-qa; do printf '.claude/agents/swf/%s.md\n' "$a"; done
  find "$SRC/.claude/swf-tools" -type f ! -name '.DS_Store' | while IFS= read -r f; do printf '%s\n' "${f#"$SRC"/}"; done
}
opencode_list() {
  for a in swf-manager swf-po swf-architect swf-planner swf-builder swf-builder-hard swf-qa; do printf '.opencode/agents/%s.md\n' "$a"; done
  printf '%s\n' .opencode/plugins/swf-guard.ts
  { find "$SRC/.claude/swf-tools" -type f ! -name '.DS_Store' | while IFS= read -r f; do printf '.opencode/swf-tools/%s\n' "${f#"$SRC"/.claude/swf-tools/}"; done
    find "$SRC/.opencode/swf-tools" -type f ! -name '.DS_Store' | while IFS= read -r f; do printf '%s\n' "${f#"$SRC"/}"; done; } | LC_ALL=C sort -u
}
# src_of <rel>: the source file for an installed path (an OpenCode support file falls back to the shared copy).
src_of() {
  case "$1" in
    .opencode/swf-tools/*) [ -e "$SRC/$1" ] && printf '%s' "$SRC/$1" || printf '%s' "$SRC/.claude/swf-tools/${1#.opencode/swf-tools/}" ;;
    *) printf '%s' "$SRC/$1" ;;
  esac
}
LIST="$( { if has claude; then claude_list; fi; if has opencode; then opencode_list; fi; } | LC_ALL=C sort)"

PLAN_REL=() PLAN_CLASS=()
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  if [ ! -e "$DEST/$rel" ]; then class=new
  elif cmp -s "$(src_of "$rel")" "$DEST/$rel"; then class=identical
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
    .opencode/*) continue ;;
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

CLAUDE_MANIFEST='' OPENCODE_MANIFEST=''
for i in "${!PLAN_REL[@]}"; do
  rel="${PLAN_REL[$i]}" class="${PLAN_CLASS[$i]}" from="$(src_of "${PLAN_REL[$i]}")"
  [ "$class" = identical ] || { mkdir -p "$(dirname "$DEST/$rel")"; cp "$from" "$DEST/$rel"; }
  echo "  $class  $rel"
  [ "$HAVE_SHA" -eq 0 ] && continue
  case "$rel" in
    .opencode/*) OPENCODE_MANIFEST+="$(sha256_of "$from")  $rel"$'\n' ;;
    *) CLAUDE_MANIFEST+="$(sha256_of "$from")  $rel"$'\n' ;;
  esac
done
if has claude; then
  chmod +x "$DEST/.claude/swf-tools/preflight.sh" "$DEST/.claude/swf-tools/hooks/guard.sh" \
    "$DEST/.claude/swf-tools/usage.py" "$DEST/.claude/swf-tools/swf-cli.py"
  [ "$HAVE_SHA" -eq 0 ] || printf '%s' "$CLAUDE_MANIFEST" > "$(manifest_for .claude/x)"
fi
if has opencode; then
  chmod +x "$DEST/.opencode/swf-tools/preflight.sh" "$DEST/.opencode/swf-tools/hooks/guard.sh" \
    "$DEST/.opencode/swf-tools/usage.py" "$DEST/.opencode/swf-tools/swf-cli.py"
  [ "$HAVE_SHA" -eq 0 ] || printf '%s' "$OPENCODE_MANIFEST" > "$(manifest_for .opencode/x)"
fi
[ "$HAVE_SHA" -eq 1 ] || echo 'warning: no SHA-256 utility found; manifest not written and differing files are treated as customized' >&2

# The config is the user's from the first install on: create it once, never overwrite it.
if [ -e "$DEST/.sw-factory/config.yaml" ]; then
  echo "  kept  .sw-factory/config.yaml"
else
  mkdir -p "$DEST/.sw-factory"; cp "$SRC/.claude/swf-tools/templates/config.yaml" "$DEST/.sw-factory/config.yaml"
  echo "  new  .sw-factory/config.yaml"
fi

# Claude Code settings: hooks and the swf-cli permission. OpenCode needs neither: its guard is the
# plugin installed above, and its default permissions already allow the CLI.
if has claude; then

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
  if grep -qs '\.claude/sw-factory/\(hooks/guard\.sh\|usage\.py\|sf\.py\)\|\.claude/swf-tools/sf\.py' "$s"; then
    sed -e 's#\.claude/sw-factory/hooks/guard\.sh#.claude/swf-tools/hooks/guard.sh#g' \
        -e 's#\.claude/sw-factory/usage\.py#.claude/swf-tools/usage.py#g' \
        -e 's#\.claude/sw-factory/sf\.py#.claude/swf-tools/swf-cli.py#g' \
        -e 's#\.claude/swf-tools/sf\.py#.claude/swf-tools/swf-cli.py#g' "$s" > "$s.sw-factory.tmp" \
      && mv "$s.sw-factory.tmp" "$s" && echo "  updated  ${s#"$DEST"/} (hooks moved to .claude/swf-tools/)"
  fi
done

# Agents run the bookkeeping CLI constantly; allow it so they never stop at a permission prompt.
SF_ALLOW='Bash(python3 .claude/swf-tools/swf-cli.py:*)'
merge_allow() { # merge_allow <rule> <in> <out>: append <rule> to permissions.allow
  if command -v jq >/dev/null 2>&1; then
    jq --arg r "$1" '.permissions.allow = ((.permissions.allow // []) + [$r])' "$2" > "$3"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys
s = json.load(open(sys.argv[1]))
s.setdefault("permissions", {}).setdefault("allow", []).append(sys.argv[3])
json.dump(s, open(sys.argv[2], "w"), indent=2); open(sys.argv[2], "a").write("\n")' "$2" "$3" "$1"
  else return 1; fi
}
if [ ! -e "$SETTINGS" ]; then
  printf '{\n  "permissions": {\n    "allow": [\n      "%s"\n    ]\n  }\n}\n' "$SF_ALLOW" > "$SETTINGS"
  echo "  new  .claude/settings.json (swf-cli.py permission)"
elif grep -qF "$SF_ALLOW" "$SETTINGS"; then
  echo "  kept  .claude/settings.json (swf-cli.py permission already allowed)"
elif merge_allow "$SF_ALLOW" "$SETTINGS" "$SETTINGS.sw-factory.tmp" 2>/dev/null; then
  mv "$SETTINGS.sw-factory.tmp" "$SETTINGS"; echo "  merged  .claude/settings.json += permission $SF_ALLOW"
else
  rm -f "$SETTINGS.sw-factory.tmp"
  echo "warning: could not add \"$SF_ALLOW\" to permissions.allow in .claude/settings.json; add it yourself." >&2
fi

wire_hook PreToolUse 'swf-tools/hooks/guard.sh' \
  "$(hook_entry 'bash "${CLAUDE_PROJECT_DIR}/.claude/swf-tools/hooks/guard.sh"' 'Write|Edit|NotebookEdit|Agent|Task')" guard
wire_hook SessionEnd 'swf-tools/usage.py' \
  "$(hook_entry 'python3 "${CLAUDE_PROJECT_DIR}/.claude/swf-tools/usage.py" snapshot --hook >/dev/null 2>&1 || true')" 'usage snapshot'

fi

if [ -d "$DEST/.git" ] && ! grep -qs '^\.sw-factory/runs' "$DEST/.gitignore"; then
  printf '\n# sw-factory run state\n.sw-factory/runs/\n' >> "$DEST/.gitignore"; echo '  .gitignore += .sw-factory/runs/'
fi

echo
echo "Installed into $DEST"
if has claude; then echo "Next: cd $DEST && bash .claude/swf-tools/preflight.sh && claude --agent swf-manager   (Claude Code)"; fi
if has opencode; then echo "Next: cd $DEST && bash .opencode/swf-tools/preflight.sh && opencode --agent swf-manager   (OpenCode)"; fi
