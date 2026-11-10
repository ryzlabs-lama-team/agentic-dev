# Track: direct (L0)

Use for trivial work items: no documented behaviour changes, no design change, no risk flag, and
a handful of files. Typical examples are a defect fix that restores documented behaviour, a
dependency bump with no API change, a config value, or a copy fix.

```
swf-builder ──► swf-qa ──┬──► done
     ▲                 │
     └── retry ≤2 ─────┘
```

## Procedure

1. **Spawn `swf-builder`** with:
   - `TRACK: direct`
   - `RUN: <slug>`
   - `TASK:` the human's request verbatim, plus the triage line if triage ran
   - `STORIES:` the story or AC ids the fix restores, if known. Otherwise `none`.
   - `BASE:` the run's base ref from the ledger
2. **Handle the builder's status** (see the swf-manager's status table). For `out-of-track`, stop
   and re-triage. The builder found that documented behaviour or design would change.
3. **Spawn `swf-qa`** with the swf-manager's QA block: `TRACK: direct`, the same `TASK`, `STORIES`
   and `BASE`, `ROUND: 0`, and `FINDINGS PATH: <runs>/<slug>/qa-direct-0.md`.
4. **Verdict:** `PASS` or `PASS-WITH-ADVISORIES` means done. `BLOCKING` means a fresh `swf-builder`
   with the findings path, up to 2 rounds, with round 2 passing `model: "opus"`. After 2 failed
   rounds, stop and report to the human.

## Gates

There is no human gate before or during this track. The human sees the final report. If
`git.commit` is `ask`, the final report also asks whether to commit. Never commit without that
answer, or with the policy set to `never`.

## What this track must not do

- Change a PRD, design or ADR. If one needs to change, the item is not L0.
- Skip swf-qa because the change "is obviously fine". Coverage and test gates apply to every track.
