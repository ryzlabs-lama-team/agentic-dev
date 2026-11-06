#!/usr/bin/env bash
# Preflight for the sw-factory. Run from the target repo root.
# Exits non-zero only if the factory itself cannot run; missing optional tracks are reported on the
# TRACKS line, which sw-manager reads to decide what it may select.
set -uo pipefail

fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "sw-factory preflight"

missing=""
for a in sw-manager po sw-architect sw-planner sw-builder sw-qa; do
  [ -f ".claude/agents/$a.md" ] || missing="$missing $a"
done
[ -z "$missing" ] && ok "all 6 sw-factory agents installed" || bad "missing agents:$missing"

for f in protocols/clarification.md references/track-selection.md hooks/guard.sh; do
  [ -f ".claude/sw-factory/$f" ] || bad ".claude/sw-factory/$f missing — reinstall the sw-factory"
done

CFG=.sw-factory/config.yaml
if [ -f "$CFG" ]; then ok "$CFG present"; else bad "$CFG missing — copy .claude/sw-factory/templates/config.yaml there"; fi

if grep -qs 'sw-factory/hooks/guard.sh' .claude/settings.json .claude/settings.local.json; then
  ok "ownership guard wired as a PreToolUse hook"
else
  warn "ownership guard not wired in .claude/settings.json — rerun install.sh; until then only sw-qa's drift check applies"
fi
if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  ok "hook JSON parser available (jq or python3)"
else
  warn "neither jq nor python3 on PATH — the ownership guard allows everything; sw-qa drift check still applies"
fi

cfg_path() {
  local v=''
  [ -f "$CFG" ] && v="$(awk -v k="$1" '
    /^[^[:space:]#]/ { in_paths = ($1 == "paths:") }
    in_paths { sub(/#.*/, ""); if ($1 == k ":") { print $2; exit } }' "$CFG" | tr -d "\"'")"
  v="${v:-$2}"; printf '%s' "${v%/}"
}
for kv in prds:docs/prds tech_designs:docs/tech-designs adrs:docs/adrs plans:docs/plans; do
  d="$(cfg_path "${kv%%:*}" "${kv#*:}")"
  [ -d "$d" ] && ok "$d/" || warn "$d/ not present yet (created on first use)"
done

RUNS="$(cfg_path runs .sw-factory/runs)"
if mkdir -p "$RUNS" 2>/dev/null && ( : > "$RUNS/.preflight-write-probe" ) 2>/dev/null; then
  rm -f "$RUNS/.preflight-write-probe"; ok "$RUNS/ writable"
else
  bad "$RUNS/ is not writable"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "git repository (branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null))"
  git check-ignore -q "$RUNS/x" 2>/dev/null || warn "$RUNS/ is not gitignored — add it to keep run state out of commits"
else
  warn "not a git repository — QA cannot diff against a base ref; coverage scope 'changed' is unavailable"
fi

# --- tracks -----------------------------------------------------------------
enabled() { [ ! -f "$CFG" ] || ! grep -q '^[[:space:]]*enabled:' "$CFG" || grep -E '^[[:space:]]*enabled:' "$CFG" | grep -qw -- "$1"; }
tracks=""
add() { tracks="$tracks $1=$2"; }

for t in direct subagents; do enabled "$t" && add "$t" yes || add "$t" "no(disabled)"; done

opsx_reason=""
command -v openspec >/dev/null 2>&1 || opsx_reason="openspec CLI not on PATH"
[ -n "$opsx_reason" ] || [ -d openspec ] || opsx_reason="openspec/ missing; run: openspec init"
if [ -z "$opsx_reason" ]; then
  [ -f .claude/skills/opsx-loop/SKILL.md ] || opsx_reason="opsx-loop toolkit not installed; run openspec-agents/opsx-loop/install.sh"
fi
if [ -z "$opsx_reason" ]; then
  for a in explorer proposer implementer verifier syncer; do
    [ -f ".claude/agents/opsx-$a.md" ] || { opsx_reason="opsx-$a agent missing; reinstall opsx-loop"; break; }
  done
fi
for t in opsx-loop openspec; do
  if ! enabled "$t"; then add "$t" "no(disabled)"
  elif [ -n "$opsx_reason" ]; then add "$t" "no"; else add "$t" yes; fi
done
[ -z "$opsx_reason" ] && ok "OpenSpec + opsx-loop available" || warn "opsx-loop/openspec tracks unavailable: $opsx_reason"

sk_reason=""
[ -d .specify ] || sk_reason="no .specify/ directory; run: specify init --here --integration claude"
if [ -z "$sk_reason" ]; then
  for s in constitution specify clarify plan tasks analyze implement; do
    [ -f ".claude/skills/speckit-$s/SKILL.md" ] || { sk_reason="speckit-$s skill missing; run: specify integration install claude"; break; }
  done
fi
if ! enabled spec-kit; then add spec-kit "no(disabled)"
elif [ -n "$sk_reason" ]; then add spec-kit no; else add spec-kit yes; fi
[ -z "$sk_reason" ] && ok "spec-kit available" || warn "spec-kit track unavailable: $sk_reason"

echo
echo "TRACKS:$tracks"
[ "$fail" -eq 0 ] && echo "preflight passed" || echo "preflight FAILED — fix the items above before running the factory"
exit "$fail"
