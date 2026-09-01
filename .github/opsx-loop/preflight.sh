#!/usr/bin/env bash
# Preflight for the Copilot distribution. Run from a target repository root.
set -uo pipefail
root="${1:-.}"
cd "$root"
fail=0
ok() { printf '  ok    %s\n' "$1"; }; bad() { printf '  FAIL  %s\n' "$1"; fail=1; }; warn() { printf '  warn  %s\n' "$1"; }
has_regular_file() { local file; while IFS= read -r file; do [ -f "$file" ] && return 0; done < <(compgen -G "$1"); return 1; }
echo 'opsx-loop preflight (GitHub Copilot)'
command -v openspec >/dev/null 2>&1 && ok 'openspec CLI present' || bad 'openspec CLI not on PATH — install it, then run: openspec init'
[ -d openspec ] && ok 'openspec/ directory present' || bad 'no openspec/ directory — run: openspec init'
if ! bash .github/opsx-loop/validate-agents.sh; then fail=1; fi
if mkdir -p .opsx-run 2>/dev/null && (: > .opsx-run/.preflight-write-probe) 2>/dev/null; then rm -f .opsx-run/.preflight-write-probe; ok '.opsx-run/ writable'; else bad '.opsx-run/ is missing or not writable'; fi
has_regular_file '.github/skills/openspec-*/SKILL.md' || warn 'no .github/skills/openspec-* — workers may use prompt/CLI fallback'
has_regular_file '.github/prompts/opsx-*.prompt.md' || warn 'no .github/prompts/opsx-*.prompt.md — workers may use skill/CLI fallback'
[ ! -d .git ] || grep -qs '^\.opsx-run' .gitignore 2>/dev/null || warn '.opsx-run/ is not in .gitignore'
warn 'VS Code agent discovery and subscription model availability cannot be checked automatically; in current VS Code, select opsx-loop and confirm at least one configured model for every profile before release.'
echo; [ "$fail" -eq 0 ] && echo 'preflight passed (manual VS Code validation required)' || echo 'preflight FAILED'; exit "$fail"
