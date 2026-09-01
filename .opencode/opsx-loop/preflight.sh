#!/usr/bin/env bash
# Preflight for the opsx-loop orchestrator (OpenCode distribution). Run from the target repo root.
# Exits non-zero if the loop cannot run.
set -uo pipefail

fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "opsx-loop preflight (OpenCode)"

if command -v openspec >/dev/null 2>&1; then
  ok "openspec CLI: $(openspec --version 2>/dev/null || echo present)"
else
  bad "openspec CLI not on PATH — install it, then run: openspec init"
fi

if [ -d openspec ]; then
  ok "openspec/ directory present"
  [ -d openspec/specs ]   && ok "openspec/specs/"   || warn "openspec/specs/ missing (fine on a fresh project)"
  [ -d openspec/changes ] && ok "openspec/changes/" || warn "openspec/changes/ missing (fine on a fresh project)"
else
  bad "no openspec/ directory — run: openspec init"
fi

stage_commands="$(find .opencode/commands -maxdepth 1 -name 'opsx-*.md' ! -name 'opsx-loop.md' 2>/dev/null)"
if [ -n "$stage_commands" ]; then
  ok "opsx-<stage> commands: $(printf '%s\n' "$stage_commands" | wc -l | tr -d ' ') found"
else
  bad ".opencode/commands/ has no OpenSpec opsx-<stage>.md files — run: openspec init --tools opencode"
fi

if compgen -G ".opencode/skills/openspec-*" >/dev/null 2>&1; then
  ok "openspec-* skills present (preferred instruction source for subagents)"
else
  warn "no .opencode/skills/openspec-* — subagents will fall back to reading command files"
fi

missing=""
for a in loop explorer proposer implementer implementer-hard verifier syncer; do
  [ -f ".opencode/agents/opsx-$a.md" ] || missing="$missing opsx-$a"
done
[ -z "$missing" ] && ok "all 7 opsx-* agents installed" || bad "missing agents:$missing"

if mkdir -p .opsx-run 2>/dev/null && ( : > .opsx-run/.preflight-write-probe ) 2>/dev/null; then
  rm -f .opsx-run/.preflight-write-probe
  ok ".opsx-run/ writable"
else
  bad ".opsx-run/ is missing or not writable — check that it is a directory with write permission"
fi

if [ -d .git ] && ! grep -qs '^\.opsx-run' .gitignore; then
  warn ".opsx-run/ is not in .gitignore — add it to keep run state out of commits"
fi

# Runtime assertions: the OpenCode installation must actually resolve all seven
# agents, and every model id configured in those agent files must be one the
# installation can reach. Both are cheap to check now, before a subagent spawn
# fails mid-run, after the human gate.
#
# Both listings are captured to a temp file rather than piped straight into
# grep: the opencode CLI can exit before a direct pipe's reader has drained a
# large listing, truncating it non-deterministically.
if command -v opencode >/dev/null 2>&1; then
  agent_listing="$(mktemp)"
  models_listing="$(mktemp)"
  trap 'rm -f "$agent_listing" "$models_listing"' EXIT

  opencode agent list >"$agent_listing" 2>/dev/null
  agent_count="$(grep -Ec '^opsx-(loop|explorer|proposer|implementer|implementer-hard|verifier|syncer) ' "$agent_listing")"
  if [ "$agent_count" -eq 7 ]; then
    ok "OpenCode resolves all 7 opsx-* agents"
  else
    bad "OpenCode resolves only $agent_count/7 opsx-* agents"
  fi

  opencode models >"$models_listing" 2>/dev/null
  model_ids="$(grep -h '^model:' .opencode/agents/opsx-*.md 2>/dev/null | sed 's/^model:[[:space:]]*//' | LC_ALL=C sort -u)"
  model_fail=0
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if ! grep -qxF "$m" "$models_listing"; then
      bad "model '$m' is not in the OpenCode installation's model list"
      model_fail=1
    fi
  done <<< "$model_ids"
  [ "$model_fail" -eq 0 ] && ok "all configured model ids are available"
else
  warn "opencode binary not on PATH — skipping runtime agent/model checks"
fi

echo
[ "$fail" -eq 0 ] && echo "preflight passed" || echo "preflight FAILED — fix the items above before running the loop"
exit "$fail"
