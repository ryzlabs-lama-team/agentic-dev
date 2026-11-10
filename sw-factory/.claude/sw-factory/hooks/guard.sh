#!/usr/bin/env bash
# PreToolUse guard for the sw-factory, wired once in .claude/settings.json for
# Write|Edit|NotebookEdit|Agent|Task. It reads the calling agent from the hook input's
# `agent_type` and enforces:
#   - document ownership: each factory agent writes only the documents it owns
#   - consultation: builders may spawn only swf-po / swf-architect, the architect only swf-po
# Calls from the plain main session or from non-factory agents are not governed.
# Exit 2 blocks the call and shows stderr to the agent; exit 0 allows it. Without jq or python3
# the input cannot be parsed, so the call is allowed and swf-qa's drift check is the backstop.
set -uo pipefail
set -f   # path patterns below must not glob against the filesystem

INPUT="$(cat)"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
CFG="$PROJECT/.sw-factory/config.yaml"

if command -v jq >/dev/null 2>&1; then PARSER=jq
elif command -v python3 >/dev/null 2>&1; then PARSER=python3
else exit 0; fi

# field <path>...: the first non-empty string among top-level or tool_input.<key> fields.
field() {
  if [ "$PARSER" = jq ]; then
    local f v
    for f in "$@"; do
      v="$(jq -r "$f // empty | strings" <<<"$INPUT" 2>/dev/null)"
      [ -n "$v" ] && { printf '%s' "$v"; return 0; }
    done
  else
    python3 -I -c 'import json, sys
d = json.loads(sys.stdin.read())
for path in sys.argv[1:]:
    v = d
    for key in path.lstrip(".").split("."):
        v = v.get(key) if isinstance(v, dict) else None
    if isinstance(v, str) and v:
        sys.stdout.write(v); break' "$@" <<<"$INPUT" 2>/dev/null
  fi
  return 0
}

ROLE="$(field .agent_type)"
TOOL="$(field .tool_name)"
case "$ROLE" in
  swf-manager|swf-po|swf-architect|swf-planner|swf-builder|swf-qa|opsx-*) ;;
  *) exit 0 ;;
esac

block() { printf 'sw-factory guard: %s\n' "$1" >&2; exit 2; }

# matches <path> <pattern>...: true if the path matches any shell pattern.
matches() {
  local p="$1" pat; shift
  for pat in "$@"; do
    # shellcheck disable=SC2254
    case "$p" in $pat) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------- consultation
case "$TOOL" in
  Agent|Task)
    # An Agent call without subagent_type spawns the general-purpose agent.
    type="$(field .tool_input.subagent_type)"; type="${type:-general-purpose}"
    case "$ROLE" in
      swf-builder|swf-planner) allowed='swf-po swf-architect' ;;
      swf-architect)          allowed='swf-po' ;;
      swf-manager)            exit 0 ;;   # restricted by its own `tools: Agent(...)` allowlist
      *)                     allowed='' ;;
    esac
    for a in $allowed; do [ "$type" = "$a" ] && exit 0; done
    block "$ROLE may consult only: ${allowed:-nobody}. Requested: $type. Put the question in your return payload for the swf-manager instead."
    ;;
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# ---------------------------------------------------------------------------- ownership
# cfg_path <key> <default>: a value from the `paths:` block of the config, without trailing slash.
cfg_path() {
  local v=''
  [ -f "$CFG" ] && v="$(awk -v k="$1" '
    /^[^[:space:]#]/ { in_paths = ($1 == "paths:") }
    in_paths { sub(/#.*/, ""); if ($1 == k ":") { print $2; exit } }' "$CFG" | tr -d "\"'")"
  v="${v:-$2}"; printf '%s' "${v%/}"
}

# normpath <path>: collapse "." and ".." segments without touching the filesystem.
normpath() {
  local IFS=/ part abs='' out=()
  case "$1" in /*) abs=/ ;; esac
  for part in $1; do
    case "$part" in
      ''|.) ;;
      ..) [ "${#out[@]}" -gt 0 ] && unset "out[$(( ${#out[@]} - 1 ))]" ;;
      *) out+=("$part") ;;
    esac
  done
  printf '%s%s' "$abs" "${out[*]-}"
}

# physical <abs path>: resolve symlinks in the longest existing directory prefix, so that
# /var/… and /private/var/… (macOS) or a symlinked checkout compare equal.
physical() {
  local dir="$1" rest='' real
  while [ "$dir" != / ] && [ ! -d "$dir" ]; do rest="/${dir##*/}$rest"; dir="${dir%/*}"; dir="${dir:-/}"; done
  real="$(cd "$dir" 2>/dev/null && pwd -P)" || real="$dir"
  [ "$real" = / ] && real=''
  printf '%s%s' "$real" "$rest"
}

file="$(field .tool_input.file_path .tool_input.notebook_path)"
[ -n "$file" ] || exit 0
case "$file" in /*) ;; *) file="$PWD/$file" ;; esac
file="$(physical "$(normpath "$file")")"
root="$(physical "$(normpath "$PROJECT")")"
case "$file" in "$root"/*) rel="${file#"$root"/}" ;; *) exit 0 ;; esac   # outside the project

PRDS="$(cfg_path prds docs/prds)"
DESIGNS="$(cfg_path tech_designs docs/tech-designs)"
ADRS="$(cfg_path adrs docs/adrs)"
PLANS="$(cfg_path plans docs/plans)"
RUNS="$(cfg_path runs .sw-factory/runs)"
GUARDED='.sw-factory/config.yaml .claude/*'

owner_of() {
  if matches "$1" "$PRDS/*"; then echo swf-po
  elif matches "$1" "$DESIGNS/*" "$ADRS/*"; then echo swf-architect
  elif matches "$1" "$PLANS/*"; then echo swf-planner
  elif matches "$1" 'openspec/*'; then echo 'the OpenSpec stage agents'
  else echo 'the human (via swf-manager)'; fi
}
deny() {
  block "$ROLE may not write $rel; it is owned by $(owner_of "$rel"). Ask the owner (.claude/sw-factory/protocols/clarification.md) or report it in your return payload."
}

case "$ROLE" in
  swf-po)           matches "$rel" "$PRDS/*" "$RUNS/*" || deny ;;
  swf-architect) matches "$rel" "$DESIGNS/*" "$ADRS/*" "$RUNS/*" || deny ;;
  swf-planner)   matches "$rel" "$PLANS/*" "$RUNS/*" || deny ;;
  swf-qa)        matches "$rel" "$RUNS/*" || deny ;;
  swf-manager)   matches "$rel" "$RUNS/*" '.opsx-run/*' || deny ;;
  swf-builder)   matches "$rel" "$PRDS/*" "$DESIGNS/*" "$ADRS/*" 'openspec/*' $GUARDED && deny ;;
  opsx-*)       matches "$rel" "$PRDS/*" "$DESIGNS/*" "$ADRS/*" "$PLANS/*" $GUARDED && deny ;;
esac
exit 0
