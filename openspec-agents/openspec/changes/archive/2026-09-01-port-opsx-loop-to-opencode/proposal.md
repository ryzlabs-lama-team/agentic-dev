## Why

The opsx-loop toolkit (orchestrator + five subagents + installer) only runs under Claude Code.
OpenCode reads none of `.claude/agents/`, so a user on OpenCode gets nothing from this repo today,
even though OpenCode natively supports primary/subagent modes, per-agent permissions, subagent
delegation, and Claude-compatible skills — everything the loop's design depends on. Porting now,
while the toolkit is one commit old and structurally simple, is far cheaper than porting after the
two runtimes' prompt trees have diverged.

## What Changes

- Add a second, co-equal OpenCode distribution of the toolkit under `.opencode/` at the repo root,
  so it both ships to users and doubles as this repo's own OpenCode config (mirroring how
  `.claude/` works today).
- Ship seven OpenCode agent files: `opsx-loop` (`mode: primary`, carrying the orchestrator prompt
  that is today `.claude/skills/opsx-loop/SKILL.md`) plus `opsx-explorer`, `opsx-proposer`,
  `opsx-implementer`, `opsx-implementer-hard`, `opsx-verifier`, `opsx-syncer` (`mode: subagent`).
- Ship one `/opsx-loop` command that routes to the primary agent, and an OpenCode preflight script
  at `.opencode/opsx-loop/preflight.sh`.
- Express the Claude `tools:` allowlists as OpenCode `permission:` maps. Because OpenCode defaults
  to allow-all, the port writes **explicit denies**; the two read-only agents additionally get a
  path-scoped `edit` map so "the brief/findings file is the only file you may write" becomes
  enforced rather than merely instructed.
- Replace the per-call model escalation (Claude's Agent-tool `model:` override) with a second
  subagent, `opsx-implementer-hard` (hidden, opus), because OpenCode's Task tool accepts no model
  parameter. Stage semantics, the ≤2 retry budget, and the escalation policy are unchanged.
- Extend `install.sh` with `--target claude|opencode|both`, defaulting to `claude`, so every
  current invocation behaves exactly as it does today. Each target writes its own provenance
  manifest and has its own explicitly enumerated installed set.
- **The OpenCode installed set is enumerated, not discovered.** `.opencode/commands/opsx-*.md` and
  `.opencode/skills/openspec-*/` are produced by `openspec init --tools opencode` in the target
  repo; the installer must never classify, write, or report them.
- Update `README.md` with the OpenCode layout, the two-runtime instruction-resolution table, the
  model-allocation table with concrete OpenCode model ids, and one comparison table explaining that
  escalation differs by runtime.

### Non-goals (carried verbatim from the explore brief)

- **Do not port the six `openspec-*` skills or the `/opsx:*` stage commands.**
  `openspec init --tools opencode` already emits `.opencode/commands/opsx-<stage>.md` and
  `.opencode/skills/openspec-*/SKILL.md`. Those are OpenSpec's files; shipping copies forks them.
- Do not remove, deprecate, or restructure the Claude Code tree. This change is purely additive.
- Do not ship an `opencode.json`. Merging into a user's existing config is a worse clobber problem
  than copying files, and markdown agents win over JSON for the same key anyway.
- Do not add a `verify` OpenSpec command or skill. The verify gate stays self-contained.
- Do not build any cross-runtime abstraction (shared prompt templating, a generator, a CI diff
  check). Two hand-maintained trees is the right cost at this size.
- Do not change stage logic, model allocation policy, or the ≤2 retry budget.

## Capabilities

### New Capabilities
- `opencode-loop-runtime`: the OpenCode distribution of the opsx loop — which agent files exist and
  where, their modes, their permission posture (including the parent-deny propagation constraint),
  the escalation pair that replaces per-call model override, the `/opsx-loop` command, the
  instruction-resolution chain under OpenCode, the human gate, and the preflight checks.

### Modified Capabilities
- `toolkit-install`: the **installed set** becomes target-dependent rather than fixed to the five
  `.claude/agents/opsx-*.md` files plus the `.claude/skills/opsx-loop/` tree; the manifest path
  becomes per-target (`.claude/.opsx-install-manifest` and `.opencode/.opsx-install-manifest`); the
  argument shape gains `--target claude|opencode|both` defaulting to `claude`; and the
  preserve-foreign-files requirement gains an OpenCode obligation that OpenSpec-generated files
  under `.opencode/commands/` and `.opencode/skills/` are never classified, written, or reported.
  Every existing scenario must still hold verbatim under the default target.

## Impact

- **New**: `.opencode/agents/opsx-{loop,explorer,proposer,implementer,implementer-hard,verifier,syncer}.md`,
  `.opencode/commands/opsx-loop.md`, `.opencode/opsx-loop/preflight.sh`.
- **Modified**: `install.sh` (target flag, per-target installed set and manifest, per-target chmod
  and next-step hint), `README.md` (layout, tables, install/use instructions),
  `openspec/specs/toolkit-install/spec.md` (via the delta).
- **Committed as dogfood config, excluded from the installed set**: `.opencode/commands/opsx-*.md`
  and `.opencode/skills/openspec-*/` generated by `openspec init --tools opencode` in this repo.
- **Unchanged**: everything under `.claude/`. No existing `install.sh` invocation changes behavior.
- **External dependency**: OpenCode's agent/command/permission schema and its model ids. Concrete
  `provider/model` ids are deliberately kept out of the spec and resolved at implementation time.
