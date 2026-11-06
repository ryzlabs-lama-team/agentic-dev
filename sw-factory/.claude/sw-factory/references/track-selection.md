# Track selection

The sw-manager assigns an implementation track to every **work item**. A work item is a plan
phase, or the whole request when no plan is needed. Tracks are chosen per item, not per run. A
greenfield plan can put scaffolding through `subagents` and run its riskiest feature through
`openspec`.

## 1. Signals

The sw-architect's triage gives you these signals (`<runs>/<slug>/triage.md`). The sw-planner
repeats them for each phase. Do not estimate them yourself from code. If you do not have them,
spawn the triage.

| Signal | Values | Meaning |
|---|---|---|
| **R** requirements delta | `none` · `clarify` · `extend` · `new` | none: no documented behaviour changes. clarify: makes behaviour match the documented intent (defects). extend: new or changed stories in an existing PRD. new: a new PRD |
| **D** design delta | `none` · `local` · `cross` · `new` | local: inside one component, no interface change. cross: several components, or any interface, contract or data-model change. new: a new component, service or architecture |
| **K** risk flags | list, or `none` | `data-migration`, `security` (authn/authz/secrets/PII), `breaking-api` (public or cross-team contract), `irreversible` (destructive ops, external side effects), `regulatory`/`money`, `perf-critical` |
| **S** size | files · components | Rough estimate |
| **G** greenfield | `yes` · `no` | yes when no code exists yet for the component the work item builds |

## 2. Level: the highest floor among the signals

Each signal sets a minimum level, called its **floor**. The work item's level is the **highest
floor** across all signals. Every combination of signals therefore maps to exactly one level.
Risk escalates the level, and nothing de-escalates it.

| Signal | → L0 | → L1 | → L2 | → L3 |
|---|---|---|---|---|
| R | none, clarify | extend (≤ 2 stories) | extend (> 2 stories), new | — |
| D | none | local | cross, new | cross **and** S > ~15 files or > 3 components |
| K | none | — | perf-critical | any other flag |
| S | ≤ 3 files | ≤ ~15 files, ≤ 3 components | larger | — |
| G | no | — | yes | — |

Examples:
- A defect touching an interface (R=clarify, D=cross, small) → L2.
- A new PRD on an existing system (R=new, D=local, G=no) → L2.
- A new service (G=yes, D=new) → L2. Its first OpenSpec change seeds `openspec/specs/` for it.
- Auth for a new service (G=yes, K=security) → L3.

## 3. Level → track

| Level | Track | Fallback when unavailable |
|---|---|---|
| **L0** trivial | `direct` | — |
| **L1** small | `subagents` | — |
| **L2** medium | `opsx-loop` | `subagents` with the plan gate and a human checkpoint after QA |
| **L3** high-risk | `openspec` (supervised) | `subagents` with a human checkpoint after every phase |

Any work item with a K flag other than `perf-critical` needs an **accepted ADR** for each such
flag before implementation starts, at whatever level it lands. The ADR records how the risk is
handled.

## 4. Availability

The preflight prints a `TRACKS:` line. A track is available only when it is installed **and**
listed in `tracks.enabled` in the config. If the default track is unavailable, use the fallback
and tell the human what the fallback gives up. For example, `subagents` instead of `opsx-loop`
loses the delta specs that keep `openspec/specs/` in sync. Never install or initialize a tool to
make a track available: no `openspec init` or toolkit installs. Recommend the
command to the human and continue with the fallback unless they choose to install it.

## 5. Overrides

- **Human names a track:** use it, and record `override: human` in the ledger. If it is lighter
  than the level requires, for example `direct` for an item with a `security` flag, say so once,
  citing the flag, and then comply. The human owns that decision.
- **Builder reports `STATUS: out-of-track`:** the item is bigger than triage thought. Stop the
  item, re-run triage with the builder's findings, and re-select. Do not let a builder keep going
  on the wrong track.

## 6. Recording the decision

Write one line per work item into the ledger's Phases table:
`P<n> · L<x> · <track> · <the signal that decided it>`. For example:
`P3 · L3 · openspec · K=data-migration`. At the plan gate the human approves these lines, not the
reasoning behind them.
