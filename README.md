# opsx-loop

An orchestrator and stage subagents that drive an [OpenSpec](https://github.com/Fission-AI/OpenSpec)
change from a fuzzy idea to a synced spec. Shipped as two co-equal distributions — Claude Code and
OpenCode — with identical stage semantics; only the runtime mechanism differs (see
[Runtime differences](#runtime-differences) below).

```
explore ──► propose ──► [HUMAN GATE] ──► apply ──► verify ──┬──► sync ──► archive (optional)
                                           ▲                │
                                           └── retry ≤2 ────┘
```

## Install

```sh
./install.sh [--force] [--target claude|opencode|both] /path/to/your-repo
cd /path/to/your-repo
bash .claude/skills/opsx-loop/preflight.sh      # Claude Code
bash .opencode/opsx-loop/preflight.sh           # OpenCode
```

`--target` defaults to `claude`, so every invocation that predates this flag still installs only
the Claude Code distribution and behaves exactly as before. Pass `--target opencode` for the
OpenCode distribution alone, or `--target both` to install both in one run.

Requires OpenSpec already initialized in the target repo (`openspec init`), with the tool(s)
matching your chosen `--target` selected — Claude Code so `.claude/commands/opsx/` exists,
OpenCode so `.opencode/commands/` and `.opencode/skills/` exist.

The installer refuses to clobber files you have customized: if any installed file of a selected
distribution (an `opsx-*` agent, the `opsx-loop` command, or a file under `.claude/skills/opsx-loop/`
or `.opencode/opsx-loop/`) has been edited since it was last installed, the installer lists every
such path on stderr, writes nothing — for either distribution, when `--target both` — and exits
`1`. Pass `--force` (or `-f`, in any position) to overwrite those files anyway. Routine upgrades —
files that only changed upstream, not at the destination — install without needing the flag.

**One-time friction on the first upgrade after adding this guard:** targets installed before this
guard existed have no provenance manifest yet, so any file that has drifted from source is reported
as customized and needs `--force` once. After that first run, the manifest tracks what the
installer wrote and routine upgrades no longer prompt for the flag.

## Use

**Claude Code**, from the target repo:

```
/opsx-loop add rate limiting to the public API
```

**OpenCode**, from the target repo:

```
/opsx-loop add rate limiting to the public API
```

Either way, the orchestrator runs explore and propose, then **stops for your approval** before any
code is written. After you approve, it applies, verifies, and syncs.

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

**Claude Code**

| Subagent | Stage | Model | Rationale |
|---|---|---|---|
| `opsx-explorer` | explore | opus | Divergent reasoning, tradeoffs, ambiguity resolution |
| `opsx-proposer` | propose | opus | A vague requirement propagates into every later stage |
| `opsx-implementer` | apply | sonnet → opus on retry 2 | Mechanical volume against an already-precise plan |
| `opsx-verifier` | verify | opus | Adversarial review needs capability *and* fresh context |
| `opsx-syncer` | sync/archive | sonnet | Deterministic delta merge, guarded by `openspec validate` |

**OpenCode**

Concrete `provider/model` ids are confirmed against the GitHub Copilot provider. Your local
`opencode models github-copilot` output lists the models your configured Copilot subscription can
actually reach. If the provider's catalog changes, re-verify the ids and update this table — the
agent frontmatter and this table are the only two places these ids appear.

| Agent | Stage | Model | Rationale |
|---|---|---|---|
| `opsx-loop` | orchestrator | `github-copilot/gpt-5.6-luna` | Explicit state-machine coordination delegates substantive work to subagents |
| `opsx-explorer` | explore | `github-copilot/gpt-5.6-terra` | Cost-effective ambiguity resolution and tradeoff analysis |
| `opsx-proposer` | propose | `github-copilot/gpt-5.6-sol` | Planning mistakes propagate into every later stage |
| `opsx-implementer` | apply, rounds 0-1 | `github-copilot/gpt-5.6-terra` | Strong coding capability for execution against an already-precise plan |
| `opsx-implementer-hard` | apply, round 2 (hidden) | `github-copilot/gpt-5.6-sol` | Flagship escalation reached as a second subagent, not a per-call override |
| `opsx-verifier` | verify | `github-copilot/gpt-5.6-sol` | Adversarial review needs flagship capability and fresh context |
| `opsx-syncer` | sync/archive | `github-copilot/gpt-5.6-luna` | Deterministic delta merge, guarded by `openspec validate` |

### Runtime differences

Both distributions preserve the loop's stage sequence, three-tier context discipline, run ledger,
≤30-line return payloads, mandatory human gate, and ≤2-round retry budget identically. Only the
mechanism differs, in exactly two places:

| Mechanism | Claude Code | OpenCode |
|---|---|---|
| Retry-2 escalation | The orchestrator passes `model: "opus"` to the Agent tool for that one call, overriding the agent definition's frontmatter | The orchestrator spawns a different, hidden agent — `opsx-implementer-hard` — because OpenCode's subagent-invocation tool accepts no model parameter |
| Instruction resolution | `.claude/commands/opsx/<stage>.md` | `.opencode/commands/opsx-<stage>.md` (flat, hyphenated) |

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

Subagents cannot type `/opsx:*` slash commands. Each resolves its stage instructions in order: the
`Skill` tool on the mapped skill, then the runtime's own command file for that stage, then the CLI.
The skill and CLI fallback are the same in both runtimes; only the command path differs.

| Subagent | Skill | Command (Claude Code) | Command (OpenCode) | CLI fallback |
|---|---|---|---|---|
| explorer | `openspec-explore` | `.claude/commands/opsx/explore.md` | `.opencode/commands/opsx-explore.md` | — |
| proposer | `openspec-propose` | `.claude/commands/opsx/propose.md` | `.opencode/commands/opsx-propose.md` | `openspec instructions <artifact> --change <id> --json` |
| proposer (revise) | `openspec-update-change` | `.claude/commands/opsx/update.md` | `.opencode/commands/opsx-update.md` | — |
| implementer | `openspec-apply-change` | `.claude/commands/opsx/apply.md` | `.opencode/commands/opsx-apply.md` | `openspec instructions apply --change <id> --json` |
| syncer | `openspec-sync-specs` / `openspec-archive-change` | `.claude/commands/opsx/sync.md` / `archive.md` | `.opencode/commands/opsx-sync.md` / `opsx-archive.md` | `openspec instructions archive --change <id> --json` |
| verifier | **none** | **none** | **none** | `openspec show` / `validate` / `status --json` |

**The verify gate is not an OpenSpec command.** The `spec-driven` core profile ships no `verify`
skill or stage command in either runtime, so `opsx-verifier` is self-contained: it reads the change
through `openspec show`/`status --json`, and judges code-against-spec itself. `openspec validate`
only checks that artifacts are well-formed — it says nothing about whether the code satisfies them.

The Claude and OpenCode command files themselves are not part of this toolkit. Both
`.claude/commands/opsx/<stage>.md` and `.opencode/commands/opsx-<stage>.md`, and the matching
`openspec-*` skills, are produced by `openspec init` (`--tools claude` / `--tools opencode`) in the
target repo — they belong to OpenSpec, and `install.sh` never installs, classifies, or reports them.

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

.opencode/
  agents/
    opsx-loop.md              primary, opus-tier   orchestrator (permission map, no read/edit/bash deny)
    opsx-explorer.md          subagent, opus-tier  read-only + brief (edit denied outside .opsx-run/)
    opsx-proposer.md          subagent, opus-tier  artifacts only, no code
    opsx-implementer.md       subagent, sonnet-tier   code only, no spec edits
    opsx-implementer-hard.md  subagent, opus-tier, hidden   retry-2 escalation, delegates to opsx-implementer.md
    opsx-verifier.md          subagent, opus-tier  read-only + findings (edit denied outside .opsx-run/)
    opsx-syncer.md            subagent, sonnet-tier   spec merge only
  commands/
    opsx-loop.md            the only toolkit-owned command file
    opsx-<stage>.md         NOT installed by install.sh — from `openspec init --tools opencode`
  skills/
    openspec-*/SKILL.md     NOT installed by install.sh — from `openspec init --tools opencode`
  opsx-loop/
    preflight.sh
  .opsx-install-manifest  sha256 of each installed file; commit it

install.sh
```
