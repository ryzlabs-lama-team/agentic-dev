#!/usr/bin/env bash
# Preflight for the sw-factory (OpenCode distribution). Run from the target repo root.
# Exits non-zero only if the factory itself cannot run; missing optional tracks are reported on the
# TRACKS line, which swf-manager reads to decide what it may select.
set -uo pipefail

fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "sw-factory preflight (OpenCode)"

AGENTS="swf-manager swf-po swf-architect swf-planner swf-builder swf-builder-hard swf-qa"
missing=""
for a in $AGENTS; do
  [ -f ".opencode/agents/$a.md" ] || missing="$missing $a"
done
[ -z "$missing" ] && ok "all 7 sw-factory agents installed" || bad "missing agents:$missing"

for f in .opencode/swf-tools/protocols/clarification.md .sw-factory/tools/references/track-selection.md \
         .sw-factory/tools/hooks/guard.sh .sw-factory/tools/swf-cli.py; do
  [ -f "$f" ] || bad "$f missing — reinstall the sw-factory"
done

CFG=.sw-factory/config.yaml
if [ -f "$CFG" ]; then ok "$CFG present"; else bad "$CFG missing — copy .sw-factory/tools/templates/config.yaml there"; fi

# The plugin is both the ownership guard and what lets builders consult swf-po / swf-architect
# (it raises subagent_depth), so the factory cannot run as designed without it.
if [ -f .opencode/plugins/swf-guard.ts ]; then
  ok "guard plugin installed (.opencode/plugins/swf-guard.ts)"
else
  bad "guard plugin .opencode/plugins/swf-guard.ts missing — reinstall the sw-factory"
fi
if ! command -v python3 >/dev/null 2>&1; then
  bad "python3 not on PATH — the agents' bookkeeping CLI (swf-cli.py) needs it"
elif v="$(python3 .sw-factory/tools/swf-cli.py --version 2>&1)"; then
  ok "bookkeeping CLI runs ($v)"
else
  bad ".sw-factory/tools/swf-cli.py does not run: $v"
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

# --- runtime ----------------------------------------------------------------
# The OpenCode installation must resolve every agent, and every model id they pin must be one it
# can reach: both would otherwise fail at spawn time, mid-run, after a human gate. Listings go to
# temp files rather than straight into a pipe: the CLI can exit before a pipe's reader has drained
# a large listing.
OPENCODE_AGENTS=''
if command -v opencode >/dev/null 2>&1; then
  agent_listing="$(mktemp)" models_listing="$(mktemp)"
  trap 'rm -f "$agent_listing" "$models_listing"' EXIT
  opencode agent list >"$agent_listing" 2>/dev/null
  OPENCODE_AGENTS="$agent_listing"
  unresolved=""
  for a in $AGENTS; do grep -q "^$a " "$agent_listing" || unresolved="$unresolved $a"; done
  [ -z "$unresolved" ] && ok "OpenCode resolves all 7 sw-factory agents" || bad "OpenCode does not resolve:$unresolved"

  opencode models >"$models_listing" 2>/dev/null
  model_fail=0
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    grep -qxF "$m" "$models_listing" || { bad "model '$m' is not in the OpenCode installation's model list"; model_fail=1; }
  done <<< "$(grep -h '^model:' .opencode/agents/swf-*.md 2>/dev/null | sed 's/^model:[[:space:]]*//' | LC_ALL=C sort -u)"
  [ "$model_fail" -eq 0 ] && ok "all configured model ids are available"
else
  warn "opencode binary not on PATH — skipping runtime agent/model checks"
fi

# --- tracks -----------------------------------------------------------------
enabled() { [ ! -f "$CFG" ] || ! grep -q '^[[:space:]]*enabled:' "$CFG" || grep -E '^[[:space:]]*enabled:' "$CFG" | grep -qw -- "$1"; }
tracks=""
add() { tracks="$tracks $1=$2"; }

for t in direct subagents; do enabled "$t" && add "$t" yes || add "$t" "no(disabled)"; done

opsx_reason=""
command -v openspec >/dev/null 2>&1 || opsx_reason="openspec CLI not on PATH"
[ -n "$opsx_reason" ] || [ -d openspec ] || opsx_reason="openspec/ missing; run: openspec init --tools opencode"
if [ -z "$opsx_reason" ]; then
  for a in loop explorer proposer implementer implementer-hard verifier syncer; do
    [ -f ".opencode/agents/opsx-$a.md" ] || { opsx_reason="opsx-$a agent missing; run openspec-agents/opsx-loop/install.sh --target opencode"; break; }
  done
fi
if [ -z "$opsx_reason" ] && [ -n "$OPENCODE_AGENTS" ]; then
  for a in explorer proposer implementer implementer-hard verifier syncer; do
    grep -q "^opsx-$a " "$OPENCODE_AGENTS" || { opsx_reason="OpenCode does not resolve opsx-$a"; break; }
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
