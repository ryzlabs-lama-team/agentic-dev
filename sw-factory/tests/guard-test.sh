#!/usr/bin/env bash
# Tests for .sw-factory/tools/hooks/guard.sh (shared by the Claude Code hook and the OpenCode
# plugin) against a throwaway project.
#   bash tests/guard-test.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$SRC/.sw-factory/tools/hooks/guard.sh"
BASE="$(mktemp -d)"; trap 'rm -rf "$BASE"' EXIT
PROJ="$BASE/proj"; LINK="$BASE/link"
mkdir -p "$PROJ/.sw-factory" "$PROJ/docs" && ln -s "$PROJ" "$LINK"
# A customized config: requirements live in docs/requirements, not docs/prds.
cat > "$PROJ/.sw-factory/config.yaml" <<'YAML'
paths:
  prds: "docs/requirements/"   # quoted, trailing slash
  tech_designs: docs/tech-designs
  adrs: docs/adrs
gates:
  prds: not-a-path             # same key outside `paths:` must be ignored
YAML

pass=0 fail=0
expect() { # expect <allow|block> <description> [project dir] <<< hook-json
  local want="$1" desc="$2" dir="${3:-$PROJ}" got
  CLAUDE_PROJECT_DIR="$dir" bash "$GUARD" >/dev/null 2>&1
  case $? in 0) got=allow ;; 2) got=block ;; *) got="error($?)" ;; esac
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %s: want %s, got %s\n' "$desc" "$want" "$got"; fi
}
# write <agent_type|""> <file_path>
write() { printf '{"tool_name":"Write",%s"tool_input":{"file_path":"%s","content":"x"}}' "${1:+\"agent_type\":\"$1\",}" "$2"; }
# spawn <agent_type|""> <subagent_type|"">
spawn() { printf '{"tool_name":"Agent",%s"tool_input":{"description":"d","prompt":"p"%s}}' "${1:+\"agent_type\":\"$1\",}" "${2:+,\"subagent_type\":\"$2\"}"; }

# --- document ownership -------------------------------------------------------
expect allow "swf-po writes its PRD (custom path)"       <<< "$(write swf-po "$PROJ/docs/requirements/auth/prd.md")"
expect block "swf-po writes default prds path"            <<< "$(write swf-po "$PROJ/docs/prds/auth/prd.md")"
expect block "swf-po writes code"                         <<< "$(write swf-po "$PROJ/src/app.ts")"
expect allow "swf-po writes clarification log"            <<< "$(write swf-po "$PROJ/.sw-factory/runs/x/clarifications.md")"
expect allow "architect writes HLD"                   <<< "$(write swf-architect "$PROJ/docs/tech-designs/core/hld.md")"
expect allow "architect writes ADR"                   <<< "$(write swf-architect "$PROJ/docs/adrs/0001-db.md")"
expect block "architect writes PRD"                   <<< "$(write swf-architect "$PROJ/docs/requirements/auth/prd.md")"
expect block "architect writes code"                  <<< "$(write swf-architect "$PROJ/src/app.ts")"
expect allow "planner writes plan"                    <<< "$(write swf-planner "$PROJ/docs/plans/auth.md")"
expect block "planner writes HLD"                     <<< "$(write swf-planner "$PROJ/docs/tech-designs/core/hld.md")"
expect allow "qa writes findings"                     <<< "$(write swf-qa "$PROJ/.sw-factory/runs/x/qa-P1-0.md")"
expect block "qa writes code"                         <<< "$(write swf-qa "$PROJ/src/app.ts")"
expect allow "manager writes ledger"                  <<< "$(write swf-manager "$PROJ/.sw-factory/runs/x/ledger.md")"
expect allow "manager writes opsx ledger"             <<< "$(write swf-manager "$PROJ/.opsx-run/x/ledger.md")"
expect block "manager writes code"                    <<< "$(write swf-manager "$PROJ/src/app.ts")"
expect allow "builder writes code"                    <<< "$(write swf-builder "$PROJ/src/app.ts")"
expect allow "builder writes ops docs"                <<< "$(write swf-builder "$PROJ/docs/operations/run.md")"
expect allow "builder ticks plan"                     <<< "$(write swf-builder "$PROJ/docs/plans/auth.md")"
expect block "builder writes PRD"                     <<< "$(write swf-builder "$PROJ/docs/requirements/auth/prd.md")"
expect block "builder writes ADR"                     <<< "$(write swf-builder "$PROJ/docs/adrs/0001-db.md")"
expect block "builder writes openspec spec"           <<< "$(write swf-builder "$PROJ/openspec/specs/auth/spec.md")"
expect block "builder lowers coverage gate"           <<< "$(write swf-builder "$PROJ/.sw-factory/config.yaml")"
expect block "builder edits its own guard"            <<< "$(write swf-builder "$PROJ/.claude/swf-tools/hooks/guard.sh")"
expect block "builder escapes via .."                 <<< "$(write swf-builder "$PROJ/src/../docs/adrs/0001-db.md")"
expect block "builder via symlinked project dir"      "$LINK" <<< "$(write swf-builder "$PROJ/docs/adrs/0001-db.md")"
expect block "builder via symlinked file path"        <<< "$(write swf-builder "$LINK/docs/adrs/0001-db.md")"
expect allow "builder relative path"                  <<< "$(write swf-builder "src/app.ts")"
expect allow "builder notebook"                       <<< '{"tool_name":"NotebookEdit","agent_type":"swf-builder","tool_input":{"notebook_path":"'"$PROJ"'/nb/a.ipynb"}}'
expect block "opsx-implementer writes PRD"            <<< "$(write opsx-implementer "$PROJ/docs/requirements/auth/prd.md")"
expect allow "opsx-implementer writes code"           <<< "$(write opsx-implementer "$PROJ/src/app.ts")"
expect allow "opsx-proposer writes openspec change"   <<< "$(write opsx-proposer "$PROJ/openspec/changes/x/proposal.md")"
expect allow "outside the project is not governed"    <<< "$(write swf-po "/tmp/elsewhere.md")"
expect allow "plain main session is not governed"     <<< "$(write "" "$PROJ/docs/adrs/0001-db.md")"
expect allow "non-factory agent is not governed"      <<< "$(write Explore "$PROJ/docs/adrs/0001-db.md")"
expect allow "other tools are not governed"           <<< '{"tool_name":"Bash","agent_type":"swf-builder","tool_input":{"command":"ls"}}'
expect block "builder edits the shared tools"          <<< "$(write swf-builder "$PROJ/.sw-factory/tools/swf-cli.py")"
expect block "opsx-implementer edits a template"      <<< "$(write opsx-implementer "$PROJ/.sw-factory/tools/templates/prd.md")"
expect block "builder edits the OpenCode tree"          <<< "$(write swf-builder "$PROJ/.opencode/plugins/swf-guard.ts")"
expect block "opsx-implementer edits the OpenCode tree" <<< "$(write opsx-implementer "$PROJ/.opencode/agents/swf-qa.md")"
expect allow "builder-hard writes code"               <<< "$(write swf-builder-hard "$PROJ/src/app.ts")"
expect block "builder-hard writes ADR"                <<< "$(write swf-builder-hard "$PROJ/docs/adrs/0001-db.md")"
expect allow "OpenCode Edit (plugin input)"           <<< '{"tool_name":"Edit","agent_type":"swf-builder","tool_input":{"file_path":"'"$PROJ"'/src/a.ts"}}'

# --- project dir from the OpenCode plugin ---------------------------------------
swf_expect() { # same as expect, with SWF_PROJECT_DIR (OpenCode) instead of CLAUDE_PROJECT_DIR
  local want="$1" desc="$2" got
  env -u CLAUDE_PROJECT_DIR SWF_PROJECT_DIR="$PROJ" bash "$GUARD" >/dev/null 2>&1
  case $? in 0) got=allow ;; 2) got=block ;; *) got="error($?)" ;; esac
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); printf 'FAIL  %s: want %s, got %s\n' "$desc" "$want" "$got"; fi
}
swf_expect block "SWF_PROJECT_DIR: builder writes PRD"  <<< "$(write swf-builder "$PROJ/docs/requirements/auth/prd.md")"
swf_expect allow "SWF_PROJECT_DIR: swf-po writes PRD"   <<< "$(write swf-po "$PROJ/docs/requirements/auth/prd.md")"

# The block message names the running runtime's protocol.
msg="$(write swf-builder "$PROJ/docs/adrs/0001-db.md" | env -u CLAUDE_PROJECT_DIR SWF_PROJECT_DIR="$PROJ" SWF_RUNTIME=opencode bash "$GUARD" 2>&1 >/dev/null)"
case "$msg" in *".opencode/swf-tools/protocols/clarification.md"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); echo "FAIL  OpenCode message names its protocol: $msg" ;; esac
msg="$(write swf-builder "$PROJ/docs/adrs/0001-db.md" | CLAUDE_PROJECT_DIR="$PROJ" bash "$GUARD" 2>&1 >/dev/null)"
case "$msg" in *".claude/swf-tools/protocols/clarification.md"*) pass=$((pass + 1)) ;; *) fail=$((fail + 1)); echo "FAIL  Claude message names its protocol: $msg" ;; esac

# --- consultation -------------------------------------------------------------
expect allow "builder consults swf-po"                    <<< "$(spawn swf-builder swf-po)"
expect allow "builder consults architect"             <<< "$(spawn swf-builder swf-architect)"
expect block "builder spawns another builder"         <<< "$(spawn swf-builder swf-builder)"
expect block "builder spawns general-purpose"         <<< "$(spawn swf-builder '')"
expect allow "planner consults architect"             <<< "$(spawn swf-planner swf-architect)"
expect allow "architect consults swf-po"                  <<< "$(spawn swf-architect swf-po)"
expect block "architect spawns architect"             <<< "$(spawn swf-architect swf-architect)"
expect block "swf-po spawns anything"                     <<< "$(spawn swf-po swf-architect)"
expect block "qa spawns anything"                     <<< "$(spawn swf-qa swf-po)"
expect allow "builder-hard consults architect"        <<< "$(spawn swf-builder-hard swf-architect)"
expect block "builder-hard spawns qa"                 <<< "$(spawn swf-builder-hard swf-qa)"
expect block "OpenCode task spawn (plugin input)"     <<< '{"tool_name":"Task","agent_type":"swf-po","tool_input":{"subagent_type":"swf-architect"}}'
expect allow "manager spawns (own allowlist)"         <<< "$(spawn swf-manager swf-builder)"
expect allow "plain main spawns anything"             <<< "$(spawn '' swf-builder)"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
