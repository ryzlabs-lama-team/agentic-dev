# Track: spec-kit (L4 greenfield)

Use for building a new product, service or component from nothing, where spec-kit is installed.
spec-kit's stages map onto the factory's roles, so each stage is run by the agent that owns that
kind of decision. Nobody writes a spec they will later implement.

```
constitution ─► specify ─► clarify ─► plan ─► tasks ─► analyze ─► [HUMAN GATE] ─► implement ─► sw-qa
 sw-architect     po          po    sw-architect sw-planner sw-qa                    sw-builder     │
 (once/repo)                                                                            ▲          │
                                                                                        └ retry ≤2 ┘
```

## Preconditions

- spec-kit is initialized: `.specify/` exists, and the Claude integration put skills in
  `.claude/skills/speckit-*/SKILL.md`. The preflight checks both.
- The PRD for the work item is `agreed`, or `in-review` by explicit human choice. The HLD is
  approved. spec-kit artifacts are **derived from** the AI-SDLC documents and never replace them.

## How stage agents load spec-kit instructions

Pass this resolution order to each stage agent in its prompt:

1. `Skill` tool with skill **`speckit-<stage>`** (e.g. `speckit-specify`).
2. If the Skill tool refuses (spec-kit can install skills with `disable-model-invocation: true`),
   read `.claude/skills/speckit-<stage>/SKILL.md` and follow it as instructions. Use the prompt
   text given here as the skill's arguments.

Those files define spec-kit's formats and scripts. The agent's own definition governs inputs,
constraints, and the return payload.

## Feature selection

spec-kit tracks the active feature in `.specify/feature.json` (machine-local), not by git branch.
Map **one plan phase to one spec-kit feature** (`specs/NNN-<phase-slug>/`). After `specify`,
record the feature directory, branch and files from the po's `FEATURE:` line in the ledger.
After each later stage, record the files that stage wrote. sw-qa's drift check relies on these
entries. Pass it to every later stage as
`FEATURE DIR: specs/NNN-<phase-slug>` and tell the agent to export
`SPECIFY_FEATURE_DIRECTORY=<dir>` for any spec-kit script it runs. This keeps stages pinned to the
right feature even if `feature.json` changes. If the repo has spec-kit's optional `git` extension,
`specify` may create a branch. Record the branch in the ledger and do not switch branches
yourself.

Run features serially. `feature.json` and `tasks.md` are shared state.

## Stage map

| Stage | Agent | MODE | Input | Notes |
|---|---|---|---|---|
| constitution | sw-architect | `speckit-constitution` | HLD, ADRs, config gates | Written before G3, once per repo and again when an ADR accepted in the run changes a principle. Must encode the config's coverage and test gates and test-first development. The human approves it at G3, with the plan. |
| specify | po | `speckit-specify` | PRD + the phase's stories | The spec restates only this phase's stories and their acceptance criteria. No new requirements. |
| clarify | po | `speckit-clarify` | feature dir | The po generates spec-kit's clarification questions **and answers them from the PRD**. It escalates only true product decisions, as `needs-human`. |
| plan | sw-architect | `speckit-plan` | feature dir, HLD/LLD/ADRs | Must conform to the HLD. If it cannot, propose an ADR. Do not let the plan diverge silently. |
| tasks | sw-planner | `speckit-tasks` | feature dir, plan phase | Test-first ordering. Task ids map back to plan-phase tasks. |
| analyze | sw-qa | `speckit-analyze` | feature dir, `RUN`, `FINDINGS PATH: <runs>/<slug>/analyze-P<n>.md` | Read-only consistency report. Any `CRITICAL` → `BLOCKING`, which blocks the gate. Route each finding to the owner of the artifact. |
| **gate** | sw-manager | — | — | Present spec, plan, tasks and analyze results, with the assumptions encoded. Approve / revise / abandon. Revise routes to the owner of the artifact. |
| implement | sw-builder | `TRACK: spec-kit` | feature dir | Runs `speckit-implement`. If `speckit-converge` exists, the builder runs it afterwards and completes any appended tasks, up to 2 converge passes. |
| verify | sw-qa | `TRACK: spec-kit` | the sw-manager's QA block: `FEATURE DIR`, `STORIES`, `BASE`, `ROUND`, `FINDINGS PATH: <runs>/<slug>/qa-P<n>-<round>.md` | The factory gates. Same retry rules as the subagents track. |

## What this track must not do

- Let spec-kit's `spec.md` become the requirements of record. When the po changes a requirement,
  it updates the PRD **first** and then re-derives the spec.
- Run `/speckit-*` stages from the sw-manager. Every stage runs in the agent that owns it.
