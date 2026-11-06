# sw-factory

An agentic software factory for Claude Code that implements the
[AI-SDLC approach](ai-sdlc-approach-v1-notes.txt). The engineer manages the factory, and a
Software Development Manager agent (`sw-manager`) runs it. It turns ideas into PRDs with a product
owner agent (`po`), designs them with an architect agent (`sw-architect`), plans them in phases,
builds each phase on the implementation track that fits its complexity, and gates every phase on
an independent QA agent.

```
          HUMAN-DRIVEN                                   AI-DRIVEN
 frame ─► requirements ─► design ─[G1,G2]─► plan ─[G3]─► implement ──► verify ─[G4]─► release
            po            sw-architect      sw-planner    per phase:     sw-qa          (human
                                            + sw-manager  direct │ subagents │          deploys,
                                                          opsx-loop │ openspec │        monitors)
                ▲                  ▲                          │
                └── clarify ───────┴──── builders ask ────────┘
```

## How it maps to the AI-SDLC notes

| AI-SDLC notes | sw-factory |
|---|---|
| Requirements management: PRDs in `docs/prds/`, agreed with the Product team | `po` writes and maintains `docs/prds/<slug>/prd.md` and `stories.md`. The human confirms agreement at gate G1 |
| Systems architecture: HLDs, LLDs, ADRs in `docs/tech-designs/`, `docs/adrs/` | `sw-architect` drafts and evolves them. Only the human approves designs and accepts ADRs, at G2 |
| Planning: plans in `docs/plans/` (`opsx-planner`) | `sw-planner` writes phased plans: infrastructure → scaffolding → basic → complex, test first |
| Implementation: opsx-loop, opsx-loop turbo, direct input | `sw-manager` picks a track **per phase**: `direct`, `subagents`, `opsx-loop`, `openspec` |
| Gates: >90% coverage, build passing, 100% tests passing | `sw-qa` measures them itself. They are configured in `.sw-factory/config.yaml` |
| Artifacts: code + docs (build, run, test, deploy, configure, monitor) | `sw-builder` keeps the operational docs current, and `sw-qa` blocks on undocumented config |
| Ideas: EM agent with PO, Architect, QA agents; talks to the user when AI can't decide | `sw-manager` is the only agent that talks to the human. Everyone else returns `needs-human` |

## Install

```sh
./install.sh [--force] /path/to/your-repo
cd /path/to/your-repo
bash .claude/sw-factory/preflight.sh
claude --agent sw-manager
```

To make `sw-manager` the default for the repository, add `"agent": "sw-manager"` to
`.claude/settings.json`. The installer leaves your settings alone.

The installer copies six agents and `.claude/sw-factory/` (protocol, references, templates, guard
hook, preflight, usage report). It also:

- creates `.sw-factory/config.yaml` **once** and never overwrites it;
- merges two hooks into `.claude/settings.json`, keeping your existing settings: the ownership
  guard (`hooks.PreToolUse`) and the usage snapshot (`hooks.SessionEnd`). It never touches invalid
  JSON and prints the entries for you to add instead;
- gitignores `.sw-factory/runs/`.

Like opsx-loop's installer, it refuses to overwrite files you have customized since the last
install unless you pass `--force`. It tracks them in `.claude/.sw-factory-install-manifest`.

Nested subagents surface their permission prompts to you. For long unattended runs, run with
`--permission-mode acceptEdits` and allow the read-only shell commands your agents need. The guard
keeps edits inside each agent's lane either way.

Optional tracks need their own tooling. The preflight's `TRACKS:` line reports what it found, and
the sw-manager never installs anything itself:

| Track | Needs |
|---|---|
| `direct`, `subagents` | nothing |
| `opsx-loop`, `openspec` | `openspec` CLI, `openspec init`, and [opsx-loop](../openspec-agents/opsx-loop/README.md) installed |

## Use

With `claude --agent sw-manager`, ask for whatever stage you need. The examples from the AI-SDLC
notes work as written:

```
build a prd for docs/ideas/customer-portal.md          → po → G1
add authentication to this system                       → triage → lifecycle scaled to the level
build a hld for docs/prds/customer-portal/prd.md        → sw-architect → G2
build a lld for database migrations                     → sw-architect → G2
document technical decision "use Postgres" as an adr    → sw-architect → human accepts/rejects
build a plan for docs/prds/customer-portal/prd.md       → sw-planner → G3
implement P2 of docs/plans/customer-portal.md           → track for P2 → sw-qa
fix the 500 on GET /orders when the cart is empty       → triage → usually L0 direct
status   |   resume customer-portal                     → from the run ledger
```

## The team

| Agent | Role | Writes | Model | May consult |
|---|---|---|---|---|
| `sw-manager` | Orchestrates the AI-SDLC, picks tracks, holds human gates. **Main session** | run state only | opus | everyone |
| `po` | Turns ideas and needs into requirements; owns *what/why* | PRDs, stories | opus | — |
| `sw-architect` | Designs and evolves the solution; owns *how*; triages complexity | HLDs, LLDs, ADRs, triage | opus | `po` |
| `sw-planner` | Phased plans with per-phase complexity signals | plans | opus | `po`, `sw-architect` |
| `sw-builder` | Implements one work package test-first, with ops docs | code, tests, ops docs | sonnet → opus on retry 2 | `po`, `sw-architect` |
| `sw-qa` | Independent gate: coverage, tests, build, ACs, design conformance, drift | findings only | opus | — |

On the `opsx-loop` and `openspec` tracks, the opsx-loop stage agents (`opsx-explorer`,
`-proposer`, `-implementer`, `-verifier`, `-syncer`) do the building. `sw-qa` runs between
opsx-verify and sync.

## Choosing a track

The sw-architect triages each change against the real codebase and returns five signals. These
are R (requirements delta), D (design delta), K (risk flags), S (size) and G (greenfield). The
sw-manager maps them to a level and a track per work item. Full rules:
[`track-selection.md`](.claude/sw-factory/references/track-selection.md).

| Level | Typical work | Track | Human gates |
|---|---|---|---|
| L0 trivial | Defect restoring documented behaviour, a few files | `direct` | final report (+ commit question) |
| L1 small | A story or two inside the existing design | `subagents` | G1/G2 only if docs changed, G3 brief, G4 |
| L2 medium | Changed behaviour across components, a new PRD, or a new (greenfield) component | `opsx-loop` | G1–G4 + opsx spec gate |
| L3 high-risk | Migration, security, breaking API, irreversible ops | `openspec` (opsx agents, 4 supervised checkpoints) | G1–G4 + accepted ADR per risk |

Each signal sets a minimum level, and the work item takes the highest of them. Every combination
maps to exactly one level. Greenfield work lands at L2 at least, so its first OpenSpec change
seeds the specs that later brownfield changes build on. Risk only escalates: any risk flag other
than `perf-critical` means L3 at least, plus an accepted ADR per flag. When a track is unavailable, the sw-manager uses the
documented fallback and says what it gives up. The human can override any choice, and the
override is recorded.

## How builders talk to the po and the sw-architect

[`protocols/clarification.md`](.claude/sw-factory/protocols/clarification.md) is the contract
every builder follows. In short:

1. **Docs first.** Most questions are answered by the stories, the PRD, the HLD/LLD/ADRs or the
   code.
2. **What vs how.** If a user or the Product team would notice the answer, ask the **po**. If only
   engineers would, ask the **sw-architect**. Ask both, po first, when the documents contradict
   each other.
3. **Direct when possible.** Claude Code subagents can spawn subagents (up to 3 levels below the
   main session), so `sw-builder` and `sw-planner` spawn `po` / `sw-architect` themselves.
   Builders without the Agent tool (the `opsx-*` agents) return `STATUS: needs-clarification`
   with tagged questions, and the sw-manager relays them.
4. **Answers land in documents.** The owner answers by updating its PRD or design (with a version
   bump and a decision-log row) and logs the exchange in `.sw-factory/runs/<run>/clarifications.md`.
   This is how the documents stay current as the work reveals gaps.
5. **Owners don't overreach.** A clarification may refine agreed scope or approved design. If it
   would *change* them, the owner returns `needs-human`, and the sw-manager takes it to the human.
   Subagents cannot use `AskUserQuestion`.
6. **Budget.** At most 5 questions per work package. Beyond that the package is
   `under-specified`, and the fix is an upstream document revision.

## Document ownership is enforced

A project-level `PreToolUse` hook ([`hooks/guard.sh`](.claude/sw-factory/hooks/guard.sh)), which
`install.sh` merges into `.claude/settings.json`, identifies the calling agent from the hook
input's `agent_type`. It blocks:

- `Write`/`Edit` outside the documents that agent owns. Builders cannot touch PRDs, designs, ADRs,
  OpenSpec specs, the factory config or `.claude/`. The `opsx-*` agents cannot touch the
  AI-SDLC documents.
- Spawns outside the consultation graph. Builders and the planner may spawn only `po` and
  `sw-architect`, the architect only `po`, and `po` and `sw-qa` nothing.

The plain main session and non-factory agents are not governed. The hook reads paths from
`.sw-factory/config.yaml`, resolves `..` and symlinks, and needs `jq` or `python3`. Without either
it allows the call. Shell redirection is not covered, so `sw-qa`'s drift check is the backstop. It
covers the AI-SDLC documents, the config and `.claude/`, tracked and untracked. A change is
legitimate only if the run ledger or the clarification log accounts for it, or it only ticks
checkboxes. Anything else is `DOC DRIFT` and stops the run. On the opsx tracks, `opsx-verifier`
reports drift in `openspec/` itself. `tests/guard-test.sh` covers the hook policy (46 cases).

Why settings rather than agent frontmatter: the docs say frontmatter `hooks:` fire for subagents
and `--agent` sessions. In Claude Code 2.1.318 they did not fire in either mode. A project
`settings.json` hook did, and `agent_type` was present for both subagents and `--agent` sessions.

## Measuring consumption

[`usage.py`](.claude/sw-factory/usage.py) reports what a run consumed: tokens, cost, API calls and
peak context per agent, phase, track, model or session. It reads the transcripts Claude Code
already writes for every session and subagent. No agent runs it, reads its output or knows it
exists, so measuring adds nothing to any agent's context.

```sh
python3 .claude/sw-factory/usage.py report                   # every run, by phase and agent
python3 .claude/sw-factory/usage.py report customer-portal   # one run
python3 .claude/sw-factory/usage.py report --by track        # or phase | model | session | run
python3 .claude/sw-factory/usage.py report --format csv      # or json
```

```
sw-factory usage · run customer-portal · 3 sessions (2 ended) · 2026-11-06 → 2026-11-07 · ~$14.82

Phase  Agent       Track      Models      Spawns  Calls  Input  Cache W  Cache R  Output  Peak ctx    Cost
—      sw-manager  —          opus-5-5         —    212   1.2k   310.4k     8.1M   41.3k     96.2k   $5.10
—      po          —          opus-5-5         2     38     90    61.2k     1.1M   12.4k     48.0k   $0.92
P2     sw-builder  subagents  sonnet-5-5       2    141    310   190.7k    11.6M   60.2k     71.5k   $2.31
P2     sw-qa       subagents  opus-5-5         2     57    120    88.0k     2.2M    9.3k     55.1k  ~$1.40
```

Run it **in a terminal of its own**. Running it with `!` inside the sw-manager session would put
the report into that session's context.

- **Attribution.** A subagent's run, phase and track come from its spawn prompt (`RUN:`,
  `TRACK:`, the `#P<n>` work package, the `qa-P<n>-…` findings path). A nested consultation, such as
  a po asked by a builder, inherits from the agent that spawned it. A spawn without these fields,
  such as an `opsx-*` stage agent, inherits the sw-manager's current run. The sw-manager's own usage
  is split by the run it was working on, which comes from the last run it spawned for or whose
  run-state files it touched. Peak context is the largest single prompt. It shows how well the
  sw-manager's context discipline holds over a long run.
- **Cost.** When a session ends, Claude Code records its own cost per model, subagents included.
  The report splits that figure across the session's agents by weighted tokens, so its totals
  match Claude Code. Usage that has no recorded cost yet, such as a session still open, is priced
  at the rate seen in ended sessions and marked `~`.
- **Snapshots.** The `SessionEnd` hook saves a summary of each factory session to
  `.sw-factory/runs/.usage/<session>.json`. It runs after the session's last turn, so its output
  reaches no model. It returns at once and does the parsing in a detached process. Reports read
  these summaries, so they keep working after Claude Code deletes old transcripts (30 days by
  default, `cleanupPeriodDays`).
- **Caveat.** The transcript format is internal to Claude Code and may change between versions.
  If the report finds factory sessions it cannot parse, it says so on stderr rather than
  reporting zero.

`tests/usage-test.sh` covers parsing, attribution, cost splitting and the hook (21 cases).

## Artifacts in the target repo

```
docs/
  prds/<slug>/prd.md, stories.md          po
  tech-designs/<system>/hld.md, lld-*.md  sw-architect
  adrs/NNNN-<title>.md                    sw-architect (accepted only by humans)
  plans/<slug>.md                         sw-planner
  operations/                             sw-builder (if the repo has no better place)
.sw-factory/
  config.yaml                             yours; created once
  runs/<slug>/                            gitignored run state
    ledger.md                             sw-manager's memory and the record of who wrote what
    triage.md                             sw-architect
    clarifications.md                     po / sw-architect (one at a time)
    qa-<P<n>|direct>-<round>.md           sw-qa
    .usage/<session>.json                 usage snapshots (SessionEnd hook; no agent reads them)
```

Templates for every document are in [`.claude/sw-factory/templates/`](.claude/sw-factory/templates/).

## Design notes

- **sw-manager is the main session, not a subagent.** Only the main session can ask the human,
  and the human gates are the reason the factory can be trusted. Run as `--agent`, its body
  replaces Claude Code's default system prompt, so it carries its own rules for talking to the
  human and for git. If it is spawned as a subagent anyway, it detects that (no
  `AskUserQuestion`) and only triages and recommends.
- **The manager never reads documents, code or diffs.** It reads document front matter, payloads
  (≤ 30 lines) and its ledger. This is opsx-loop's context discipline applied to the whole
  lifecycle, and it is what lets one session go from idea to release.
- **Tracks are per phase, not per project.** A greenfield plan can scaffold on `subagents` and run
  its auth phase on `openspec`. The planner isolates risky concerns into their own phases for
  exactly this reason.
- **Quiet while working.** No agent narrates work in progress. Subagents speak only through their
  return payload. The sw-manager speaks to you at gates, at questions and at results, with at most
  one line when a phase starts. The `opsx-*` agents get the same rule in their spawn prompt.
- **Writer ≠ approver.** sw-qa is always a fresh spawn. On the opsx tracks it adds the AI-SDLC
  gates that opsx-verify does not check. It shares opsx's 2-round retry budget, so the two gates
  cannot loop forever between them.
- **Resume for answers, respawn for retries.** A builder waiting on a human decision is
  mid-task, so it is resumed with `SendMessage` and keeps its context. A QA retry gets a fresh
  builder that re-reads the documents with the findings in hand.
- **Documents evolve, they are not one-shot.** When a requirement changes, the po bumps the PRD
  and the sw-architect `evolve`s the design. Superseded ADRs get a new ADR, not an edit. The
  sw-planner replans only the phases not yet started.

## Not implemented yet

- **Confluence sync.** The notes say to update Confluence. The documents carry a `confluence:`
  front-matter field, but publishing (e.g. through the Atlassian MCP) is left as a follow-up. The
  repository is the source of truth.
- **"opsx-loop with turbo option".** The notes do not define it, so no turbo mode was invented.
  The `openspec` track is the opposite: a supervised opsx-loop.
- **OpenCode and GitHub Copilot ports.** opsx-loop ships for both. This toolkit is Claude Code
  only for now.
- **`docs/ards`** in the notes is read as `docs/adrs`. Change `paths.adrs` in the config if the
  typo was intended.

## Layout

```
.claude/
  agents/
    sw-manager.md   po.md   sw-architect.md   sw-planner.md   sw-builder.md   sw-qa.md
  sw-factory/
    preflight.sh                    factory checks + TRACKS line
    usage.py                        token and cost report (for the human; agents never read it)
    hooks/guard.sh                  document ownership + spawn allowlist
    protocols/clarification.md      the builder ↔ po / sw-architect contract
    references/
      track-selection.md            signals → level → track
      tracks/{direct,subagents,opsx-loop}.md   playbooks
    templates/                      prd, stories, hld, lld, adr, plan, ledger, config
tests/guard-test.sh   tests/usage-test.sh
install.sh
```
