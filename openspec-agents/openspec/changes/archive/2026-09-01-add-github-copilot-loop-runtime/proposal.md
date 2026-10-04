## Why

The toolkit currently runs its coordinated OpenSpec loop only through Claude Code and OpenCode. A GitHub Copilot distribution is needed so teams can run the same governed loop in VS Code while reusing compatible agent definitions in Copilot CLI and cloud environments where those runtimes support the required delegation features.

## What Changes

- Add a GitHub Copilot custom-agent distribution under `.github/agents/`, with a user-invocable `opsx-loop` coordinator and purpose-specific worker subagents.
- Preserve the established serial stage sequence, file-backed handoffs, run ledger, mandatory human approval gate, independent verification, and two-round retry budget.
- Retain explicit per-agent model configuration and the existing Luna/Terra/Sol allocation intent, while documenting and validating that concrete Copilot model availability depends on client and subscription.
- Make VS Code the required full-loop runtime; package the agent profiles without a restrictive target for best-effort discovery in Copilot CLI and cloud agent, without claiming behavioral parity there.
- **BREAKING** Set the installer targets to exactly `claude`, `opencode`, `copilot`, and `all`; `both` is no longer an accepted target. Extend provenance, preflight, tests, and README guidance accordingly.
- Exclude OpenSpec-owned `.github/skills/` and `.github/prompts/` assets from the toolkit's installed set so installation never classifies, overwrites, or records them.
- Do not replace, remove, restructure, or abstract the existing `.claude/` and `.opencode/` distributions; do not add repository-wide Copilot instructions or a duplicated launcher unless a supported launcher can select the coordinator and forward input.

## Capabilities

### New Capabilities

- `github-copilot-loop-runtime`: Defines the Copilot agent set, coordinator/worker boundaries, models, durable loop protocol, human gate, retries, supported-runtime posture, and preflight expectations.

### Modified Capabilities

- `toolkit-install`: Replaces the installer target set with exactly `claude`, `opencode`, `copilot`, and `all`, and adds the Copilot distribution manifest.

## Impact

This change affects new toolkit-owned `.github/agents/` and Copilot preflight assets, `install.sh`, installer and distribution validation tests, and `README.md`. The installer CLI drops `both` in favor of the exact target set `claude`, `opencode`, `copilot`, and `all`. It introduces no application API and does not change the existing Claude Code or OpenCode runtime contracts. Target repositories must already contain their OpenSpec-generated GitHub skills and prompts; those remain outside installer ownership.
