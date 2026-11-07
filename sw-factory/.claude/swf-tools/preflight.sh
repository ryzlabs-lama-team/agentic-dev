#!/usr/bin/env bash
# Preflight for the sw-factory. Run from the target repo root.
# Exits non-zero only if the factory itself cannot run; missing optional tracks are reported on the
# TRACKS line, which swf-manager reads to decide what it may select.
set -uo pipefail

fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "sw-factory preflight"

missing=""
for a in swf-manager swf-po swf-architect swf-planner swf-builder swf-qa; do
  [ -f ".claude/agents/swf/$a.md" ] || missing="$missing $a"
done
[ -z "$missing" ] && ok "all 6 sw-factory agents installed" || bad "missing agents:$missing"

for f in protocols/clarification.md references/track-selection.md hooks/guard.sh; do
  [ -f ".claude/swf-tools/$f" ] || bad ".claude/swf-tools/$f missing — reinstall the sw-factory"
done

CFG=.sw-factory/config.yaml
if [ -f "$CFG" ]; then ok "$CFG present"; else bad "$CFG missing — copy .claude/swf-tools/templates/config.yaml there"; fi

if grep -qs 'swf-tools/hooks/guard.sh' .claude/settings.json .claude/settings.local.json; then
  ok "ownership guard wired as a PreToolUse hook"
else
  warn "ownership guard not wired in .claude/settings.json — rerun install.sh; until then only swf-qa's drift check applies"
fi
if ! command -v python3 >/dev/null 2>&1; then
  bad "python3 not on PATH — the agents' bookkeeping CLI (sf.py) needs it"
elif v="$(python3 .claude/swf-tools/sf.py --version 2>&1)"; then
  ok "bookkeeping CLI runs ($v)"
else
  bad ".claude/swf-tools/sf.py does not run: $v"
fi
if grep -qsF 'Bash(python3 .claude/swf-tools/sf.py:*)' .claude/settings.json .claude/settings.local.json; then
  ok "sf.py allowed in permissions"
else
  warn "sf.py not in permissions.allow — agents will stop at permission prompts; rerun install.sh"
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

echo
echo "TRACKS:$tracks"
[ "$fail" -eq 0 ] && echo "preflight passed" || echo "preflight FAILED — fix the items above before running the factory"
exit "$fail"
