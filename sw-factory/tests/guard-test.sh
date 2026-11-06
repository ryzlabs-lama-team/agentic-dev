#!/usr/bin/env bash
# Tests for .claude/sw-factory/hooks/guard.sh against a throwaway project.
#   bash tests/guard-test.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$SRC/.claude/sw-factory/hooks/guard.sh"
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
expect allow "po writes its PRD (custom path)"       <<< "$(write po "$PROJ/docs/requirements/auth/prd.md")"
expect block "po writes default prds path"            <<< "$(write po "$PROJ/docs/prds/auth/prd.md")"
expect block "po writes code"                         <<< "$(write po "$PROJ/src/app.ts")"
expect allow "po writes clarification log"            <<< "$(write po "$PROJ/.sw-factory/runs/x/clarifications.md")"
expect allow "architect writes HLD"                   <<< "$(write sw-architect "$PROJ/docs/tech-designs/core/hld.md")"
expect allow "architect writes ADR"                   <<< "$(write sw-architect "$PROJ/docs/adrs/0001-db.md")"
expect block "architect writes PRD"                   <<< "$(write sw-architect "$PROJ/docs/requirements/auth/prd.md")"
expect block "architect writes code"                  <<< "$(write sw-architect "$PROJ/src/app.ts")"
expect allow "planner writes plan"                    <<< "$(write sw-planner "$PROJ/docs/plans/auth.md")"
expect block "planner writes HLD"                     <<< "$(write sw-planner "$PROJ/docs/tech-designs/core/hld.md")"
expect allow "qa writes findings"                     <<< "$(write sw-qa "$PROJ/.sw-factory/runs/x/qa-P1-0.md")"
expect block "qa writes code"                         <<< "$(write sw-qa "$PROJ/src/app.ts")"
expect allow "manager writes ledger"                  <<< "$(write sw-manager "$PROJ/.sw-factory/runs/x/ledger.md")"
expect allow "manager writes opsx ledger"             <<< "$(write sw-manager "$PROJ/.opsx-run/x/ledger.md")"
expect block "manager writes code"                    <<< "$(write sw-manager "$PROJ/src/app.ts")"
expect allow "builder writes code"                    <<< "$(write sw-builder "$PROJ/src/app.ts")"
expect allow "builder writes ops docs"                <<< "$(write sw-builder "$PROJ/docs/operations/run.md")"
expect allow "builder ticks plan"                     <<< "$(write sw-builder "$PROJ/docs/plans/auth.md")"
expect block "builder writes PRD"                     <<< "$(write sw-builder "$PROJ/docs/requirements/auth/prd.md")"
expect block "builder writes ADR"                     <<< "$(write sw-builder "$PROJ/docs/adrs/0001-db.md")"
expect block "builder writes openspec spec"           <<< "$(write sw-builder "$PROJ/openspec/specs/auth/spec.md")"
expect block "builder lowers coverage gate"           <<< "$(write sw-builder "$PROJ/.sw-factory/config.yaml")"
expect block "builder edits its own guard"            <<< "$(write sw-builder "$PROJ/.claude/sw-factory/hooks/guard.sh")"
expect block "builder escapes via .."                 <<< "$(write sw-builder "$PROJ/src/../docs/adrs/0001-db.md")"
expect block "builder via symlinked project dir"      "$LINK" <<< "$(write sw-builder "$PROJ/docs/adrs/0001-db.md")"
expect block "builder via symlinked file path"        <<< "$(write sw-builder "$LINK/docs/adrs/0001-db.md")"
expect allow "builder relative path"                  <<< "$(write sw-builder "src/app.ts")"
expect allow "builder notebook"                       <<< '{"tool_name":"NotebookEdit","agent_type":"sw-builder","tool_input":{"notebook_path":"'"$PROJ"'/nb/a.ipynb"}}'
expect block "opsx-implementer writes PRD"            <<< "$(write opsx-implementer "$PROJ/docs/requirements/auth/prd.md")"
expect allow "opsx-implementer writes code"           <<< "$(write opsx-implementer "$PROJ/src/app.ts")"
expect allow "opsx-proposer writes openspec change"   <<< "$(write opsx-proposer "$PROJ/openspec/changes/x/proposal.md")"
expect allow "outside the project is not governed"    <<< "$(write po "/tmp/elsewhere.md")"
expect allow "plain main session is not governed"     <<< "$(write "" "$PROJ/docs/adrs/0001-db.md")"
expect allow "non-factory agent is not governed"      <<< "$(write Explore "$PROJ/docs/adrs/0001-db.md")"
expect allow "other tools are not governed"           <<< '{"tool_name":"Bash","agent_type":"sw-builder","tool_input":{"command":"ls"}}'

# --- consultation -------------------------------------------------------------
expect allow "builder consults po"                    <<< "$(spawn sw-builder po)"
expect allow "builder consults architect"             <<< "$(spawn sw-builder sw-architect)"
expect block "builder spawns another builder"         <<< "$(spawn sw-builder sw-builder)"
expect block "builder spawns general-purpose"         <<< "$(spawn sw-builder '')"
expect allow "planner consults architect"             <<< "$(spawn sw-planner sw-architect)"
expect allow "architect consults po"                  <<< "$(spawn sw-architect po)"
expect block "architect spawns architect"             <<< "$(spawn sw-architect sw-architect)"
expect block "po spawns anything"                     <<< "$(spawn po sw-architect)"
expect block "qa spawns anything"                     <<< "$(spawn sw-qa po)"
expect allow "manager spawns (own allowlist)"         <<< "$(spawn sw-manager sw-builder)"
expect allow "plain main spawns anything"             <<< "$(spawn '' sw-builder)"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
