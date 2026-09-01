#!/usr/bin/env bash
# Preflight for the opsx-loop orchestrator. Run from the target repo root.
# Exits non-zero if the loop cannot run.
set -uo pipefail

fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
warn() { printf '  warn  %s\n' "$1"; }

echo "opsx-loop preflight"

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

if [ -d .claude/commands/opsx ]; then
  ok "opsx slash commands: $(find .claude/commands/opsx -name '*.md' | wc -l | tr -d ' ') found"
else
  bad ".claude/commands/opsx/ missing — subagents resolve stage instructions from here"
fi

if compgen -G ".claude/skills/openspec-*" >/dev/null 2>&1; then
  ok "openspec-* skills present (preferred instruction source for subagents)"
else
  warn "no .claude/skills/openspec-* — subagents will fall back to reading command files"
fi

missing=""
for a in explorer proposer implementer verifier syncer; do
  [ -f ".claude/agents/opsx-$a.md" ] || missing="$missing opsx-$a"
done
[ -z "$missing" ] && ok "all 5 opsx-* subagents installed" || bad "missing subagents:$missing"

mkdir -p .opsx-run && ok ".opsx-run/ writable"

if [ -d .git ] && ! grep -qs '^\.opsx-run' .gitignore; then
  warn ".opsx-run/ is not in .gitignore — add it to keep run state out of commits"
fi

echo
[ "$fail" -eq 0 ] && echo "preflight passed" || echo "preflight FAILED — fix the items above before running the loop"
exit "$fail"
