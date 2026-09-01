# opsx-loop

A Claude Code orchestrator and five subagents that drive an [OpenSpec](https://github.com/Fission-AI/OpenSpec)
change from a fuzzy idea to a synced spec.

```
explore ──► propose ──► [HUMAN GATE] ──► apply ──► verify ──┬──► sync ──► archive (optional)
                                           ▲                │
                                           └── retry ≤2 ────┘
```

## Install

```sh
./install.sh [--force] /path/to/your-repo
cd /path/to/your-repo
bash .claude/skills/opsx-loop/preflight.sh
```

Requires OpenSpec already initialized in the target repo (`openspec init`, with Claude Code
selected so `.claude/commands/opsx/` exists).

The installer refuses to clobber files you have customized: if any installed file (an `opsx-*`
agent or a file under `.claude/skills/opsx-loop/`) has been edited since it was last installed, the
installer lists every such path on stderr, writes nothing, and exits `1`. Pass `--force` (or `-f`,
in any position) to overwrite those files anyway. Routine upgrades — files that only changed
upstream, not at the destination — install without needing the flag.

**One-time friction on the first upgrade after adding this guard:** targets installed before this
guard existed have no provenance manifest yet, so any file that has drifted from source is reported
as customized and needs `--force` once. After that first run, the manifest tracks what the
installer wrote and routine upgrades no longer prompt for the flag.

## Use

In Claude Code, from the target repo:

```
/opsx-loop add rate limiting to the public API
```

The orchestrator runs explore and propose, then **stops for your approval** before any code is
written. After you approve, it applies, verifies, and syncs.

## Design notes

### Why the explore brief exists

`/opsx:explore` deliberately writes no artifacts — no change folder, no proposal, no specs. Its
output normally lives in conversation context. But subagent context is destroyed on return, so a
naive one-subagent-per-stage pipeline **loses the entire explore stage**.

The `opsx-explorer` therefore writes a decision brief to `.opsx-run/<slug>/brief.md`: chosen scope,
non-goals, rejected approaches, codebase findings, and open questions each carrying a default
assumption. That file is the explore→propose contract. It is the one place this toolkit extends
OpenSpec rather than wrapping it.

Every other stage already hands off through OpenSpec's own files, so no other bridging is needed.

### Three tiers of context

| Tier | Lives in | Read by |
|---|---|---|
| OpenSpec artifacts | `openspec/changes/<id>/**`, `openspec/specs/**` | every subagent, fresh each stage |
| Bridge files | `.opsx-run/<slug>/brief.md`, `verify-<n>.md` | the next stage's subagent |
| Run ledger | `.opsx-run/<slug>/ledger.md` | the orchestrator, incl. after compaction |
| Return payloads | ≤30 lines per stage | the orchestrator only |

The orchestrator never reads specs, code, or diffs. It reads paths and
`openspec status --change <id> --json`. That is what lets a long run fit in one session.

### Model allocation

| Subagent | Stage | Model | Rationale |
|---|---|---|---|
| `opsx-explorer` | explore | opus | Divergent reasoning, tradeoffs, ambiguity resolution |
| `opsx-proposer` | propose | opus | A vague requirement propagates into every later stage |
| `opsx-implementer` | apply | sonnet → opus on retry 2 | Mechanical volume against an already-precise plan |
| `opsx-verifier` | verify | opus | Adversarial review needs capability *and* fresh context |
| `opsx-syncer` | sync/archive | sonnet | Deterministic delta merge, guarded by `openspec validate` |

Escalation works by passing `model: "opus"` to the Agent tool, which overrides the agent
definition's frontmatter.

### The separations that matter

- **Writer ≠ approver.** The verifier is always a separate spawn with its own context. An agent
  reviewing its own work confirms itself.
- **Implementer cannot edit specs.** If the spec is wrong, the implementer stops and reports; the
  orchestrator routes to the proposer for `/opsx:update`. Otherwise the loop's failure mode is an
  agent quietly rewriting the requirement to match its bug.
- **Retries get fresh context.** A retry spawns a new implementer with the findings file rather
  than continuing the old one — re-reading the specs cleanly is the point.
- **Serial stages.** `tasks.md` is shared mutable state; parallel implementers corrupt it.

### How subagents invoke OpenSpec

Subagents cannot type `/opsx:*` slash commands. Each resolves its stage instructions in order:
the `Skill` tool on the mapped skill, then `.claude/commands/opsx/<stage>.md`, then the CLI.

| Subagent | Skill | Command | CLI fallback |
|---|---|---|---|
| explorer | `openspec-explore` | `explore.md` | — |
| proposer | `openspec-propose` | `propose.md` | `openspec instructions <artifact> --change <id> --json` |
| proposer (revise) | `openspec-update-change` | `update.md` | — |
| implementer | `openspec-apply-change` | `apply.md` | `openspec instructions apply --change <id> --json` |
| syncer | `openspec-sync-specs` / `openspec-archive-change` | `sync.md` / `archive.md` | `openspec instructions archive --change <id> --json` |
| verifier | **none** | **none** | `openspec show` / `validate` / `status --json` |

**The verify gate is not an OpenSpec command.** The `spec-driven` core profile ships no `verify`
skill or `/opsx:verify` command, so `opsx-verifier` is self-contained: it reads the change through
`openspec show`/`status --json`, and judges code-against-spec itself. `openspec validate` only
checks that artifacts are well-formed — it says nothing about whether the code satisfies them.

## Layout

```
.claude/
  agents/
    opsx-explorer.md      opus     read-only + brief
    opsx-proposer.md      opus     artifacts only, no code
    opsx-implementer.md   sonnet   code only, no spec edits
    opsx-verifier.md      opus     read-only + findings
    opsx-syncer.md        sonnet   spec merge only
  skills/
    opsx-loop/
      SKILL.md            orchestrator
      preflight.sh
  .opsx-install-manifest  sha256 of each installed file; commit it
install.sh
```
