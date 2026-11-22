# Track: subagents (L1, and the fallback for L2–L3)

Use this track for small work inside an existing design. It also stands in for the spec-driven
tracks when OpenSpec is unavailable. The plan phase is the contract: its tasks,
acceptance criteria, design references and exit criteria are everything the builder needs.

```
[plan phase] ──► swf-builder ──► swf-qa ──┬──► (human checkpoint if fallback) ──► done
                     ▲                  │
                     └── retry ≤2 ──────┘
```

## Preconditions

- A plan phase exists at `<plans>/<slug>.md#P<n>` and its stories are **ready**. For a one-off L1
  request with no plan, spawn `swf-planner` in `MODE: plan-lite` first. It writes a single-phase
  plan.
- Earlier phases this one depends on are `done` in the ledger.

## Procedure

1. **Spawn `swf-builder`** with:
   - `TRACK: subagents`
   - `RUN: <slug>`
   - `WORK PACKAGE: <plans>/<slug>.md#P<n>`
   - `STORIES:` the story ids in scope
   - `BASE: <ref>`
2. **Handle the builder's status.** The builder talks to `swf-po` and `swf-architect` directly while it
   works. You only see `needs-human`, `under-specified`, `out-of-track`, `blocked`, `partial` or
   `ok`.
3. **Spawn `swf-qa`** with the swf-manager's QA block: `TRACK: subagents`, `RUN`, the same
   `WORK PACKAGE`, `STORIES` and `BASE`, `ROUND`, and
   `FINDINGS PATH: <runs>/<slug>/qa-P<n>-<round>.md`.
4. **Verdict handling:**

   | Verdict | Action |
   |---|---|
   | `PASS` / `PASS-WITH-ADVISORIES` | Phase done. Carry the advisories. Commit if the commit policy says so. |
   | `BLOCKING`, rounds < 2 | A fresh `swf-builder` with the findings path. Round 2 spawns `swf-builder-hard` instead. |
   | `BLOCKING`, rounds = 2 | Stop and report to the human. |
   | `DOC DRIFT` | Stop regardless of verdict. A builder edited a document it does not own. |
   | `GATE UNMEASURABLE` | Stop and ask the human. Never treat an unmeasured gate as passed. |

5. **Fallback checkpoint.** If this track is standing in for L2 or higher, present the QA result
   to the human before the next phase starts.

## Serial, always

Run phases, and builders within a phase, one at a time. The plan file and the working tree are
shared mutable state. Builders do not commit and the swf-manager does not edit code, so the output
of parallel worktrees could not be merged. A phase too big for one builder is a planning problem:
send it back to swf-planner to split.
