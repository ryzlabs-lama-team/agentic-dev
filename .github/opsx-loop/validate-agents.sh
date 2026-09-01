#!/usr/bin/env bash
# Deterministic static validation for the Copilot opsx-loop distribution.
set -euo pipefail

root="${1:-.}"
cd "$root"
agents=(loop explorer proposer implementer implementer-hard verifier syncer)
for agent in "${agents[@]}"; do
  file=".github/agents/opsx-$agent.agent.md"
  [ -f "$file" ] || { echo "FAIL: missing opsx-$agent" >&2; exit 1; }
  ruby -e 'require "yaml"; s=File.read(ARGV[0]); h=YAML.safe_load(s.split("---",3)[1], aliases: true); abort "missing model" unless h["model"].to_s != ""; abort "worker visibility" if ARGV[1] == "worker" && h["user-invocable"] != false' "$file" "$([ "$agent" = loop ] && echo coordinator || echo worker)"
done
[ "$(printf '%s\n' .github/agents/opsx-*.agent.md 2>/dev/null | wc -l | tr -d ' ')" = 7 ] || { echo 'FAIL: expected exactly 7 Copilot profiles' >&2; exit 1; }
ruby -e 'require "yaml"; h=YAML.safe_load(File.read(ARGV[0]).split("---",3)[1], aliases: true); abort "coordinator visibility" unless h["user-invocable"] == true; expected=%w[opsx-explorer opsx-proposer opsx-implementer opsx-implementer-hard opsx-verifier opsx-syncer]; abort "delegation" unless h["agents"] == expected' .github/agents/opsx-loop.agent.md
for pair in 'loop Luna' 'explorer Terra' 'proposer Sol' 'implementer Terra' 'implementer-hard Sol' 'verifier Sol' 'syncer Luna'; do set -- $pair; grep -q "GPT-5.6 $2 (copilot)" ".github/agents/opsx-$1.agent.md" || { echo "FAIL: $1 model allocation" >&2; exit 1; }; done
# OpenSpec-generated skills and prompts may be present beside this distribution;
# the installer enumerates owned paths and must never include them.
if grep -R -n -E '\.(claude|opencode)/' .github/agents .github/opsx-loop; then echo 'FAIL: stale runtime-tree reference' >&2; exit 1; fi
echo 'Copilot agent validation passed'
