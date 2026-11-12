# Cost analysis: minion agents and the `mission-control` run

- **Date:** 2026-11-11
- **Status:** exploration. Nothing has been changed yet.
- **Data:** `usage.py report mission-control` · 3 sessions · 2026-11-06 → 2026-11-09 · **$405.96**
- **Question:** would cheap "minion" agents (Haiku 5.5, low effort) for low-reasoning tasks reduce
  the cost of a factory run?

## TL;DR

- Minions help, but only somewhat: an estimated **$20–40 (5–10%)** on a run like this one. The
  savings land in `sw-qa`, `opsx-verifier` and `sw-builder` gate runs.
- Four other levers are larger: the unexplained `main` session ($71), orchestrator context growth,
  `opsx-proposer` on Opus ($62), and retries plus architect spawn churn.
- Recommended order: investigate `main` and the `opsx-proposer` attribution first, then add one
  minion (`swf-runner`).

## Model prices (per MTok, first-party API)

| Model | Input | Output | Cache read |
|---|---|---|---|
| Opus 5.5 | $4.00 | $20.00 | $0.20 |
| Sonnet 5.5 | $2.00 | $10.00 | $0.10 |
| Haiku 5.5 | $0.10 | $0.50 | — |

Haiku costs about 1/40th of Opus per token, so the cost of spawning a minion is negligible. The
real saving is the tokens a minion keeps **out of** an Opus context. Content that enters an Opus
context is paid for once as a cache write, then again as a cache read on every remaining turn.

## Where the money went

| Group | Cost | Share | What drives it |
|---|---|---|---|
| Orchestration (`sw-manager` + `main`) | ~$107 | 26% | One long-lived Opus context: 466 calls, peak context 349k / 485k |
| opsx stage agents | ~$116 | 29% | `opsx-proposer` ~$62, `opsx-verifier` ~$25, `opsx-implementer` ~$22, `opsx-explorer` ~$7 |
| `sw-architect` | ~$53 | 13% | 55 spawns, including 9 in each of P7 and P9 |
| `sw-qa` | ~$52 | 13% | P7 alone: $22.33 |
| `sw-builder` | ~$51 | 12% | P7: $20.57. Escalated to Opus in P5, P6, P8 and P9 |
| `sw-planner` + `po` | ~$27 | 7% | Fine as is |

By token type, **cache writes are the largest bucket**: 29M tokens of new content entering
contexts, almost all on Opus. Cache reads (441M) and output (4.9M, mostly Opus) come next. Raw input
is negligible.

Minions reduce cache writes because they stop tool output from entering an Opus context. They do
**not** reduce orchestrator context growth, the number of spawns, or what each spawn costs to
start.

## Findings

### F1: `main` is the most expensive row, and it is unexplained

- $71.01 (17%): 112 calls, 3.1M cache writes, peak context 485k.
- It is not `sw-manager`. It may be a session started without `--agent`, or conversation in the
  factory session outside the manager.
- Its cost per token is higher than the other rows, which fits long-context sessions.
- **Action:** identify what ran there before optimizing anything else.

### F2: the orchestrator's context keeps growing

- `sw-manager`: 354 calls, averaging about 160k tokens of context each (56.3M cache reads), peak
  349k.
- Minions do not help here. What does help:
  - tighter return payloads;
  - a fresh session at phase boundaries (the ledger already makes this possible);
  - compaction between phases.

### F3: `opsx-proposer` is expensive, and appears where it should not

- About $62 in total, on Opus, with peaks of 337k context.
- **Action:** test lower effort, or Sonnet.
- It shows up under the **subagents** track in P5–P7 (about $24, including $13.43 in P7). The
  subagents track should not spawn the proposer, so this is either an attribution bug in `usage.py`
  or wrong routing by the manager. **Action:** check against the transcripts.

### F4: retries and spawn churn

- Builders escalated to Opus (round 2) in 4 of 5 subagents-track phases (P5, P6, P8, P9). QA round
  1 fails as a rule. **Action:** find out why first attempts miss.
- `sw-architect` was spawned 9 times in P7 and again in P9, and each fresh spawn re-reads every
  design doc. **Action:** resume the architect for clarifications, the way owners are already
  resumed for decisions.

### F5: QA and verification read large tool output into Opus (the minion case)

- `sw-qa` P7: $22.33 from one spawn: 2.1M cache writes in 83 calls. This looks like test, build or
  coverage logs read into Opus.
- `opsx-verifier` P2 (openspec): $17.32, with 23.2M cache reads.
- `sw-builder` P7: 3.6M cache writes in 261 calls on Sonnet, looping on tests.

## Minion candidates

| Task | Today | Fit |
|---|---|---|
| Running build, tests and coverage, and reporting the numbers | `sw-qa`, `opsx-verifier` (Opus) read raw output | **Strong** |
| Test-loop runs inside `sw-builder` | Sonnet reads full output | **Good**, but a smaller saving |
| Codebase lookups ("where is X used") | builder, architect, proposer | **Good**, or reuse the built-in `Explore` type |
| Doc-drift check | `sw-qa` | **Better as a script**, like `guard.sh` |
| Preflight, ledger front matter, git status | manager, via Bash | **No.** A spawn costs more than the work |
| Judging a PRD, design or ADR | Opus agents | **No.** This is the reasoning Opus is paid for |

Order of preference: **script > minion > big agent**.

## Proposal: `swf-runner`

- **Model:** Haiku 5.5, low effort. **Tools:** Bash, Read, Grep, Glob. No Write.
- **Called by:** `sw-qa`, `opsx-verifier` and `swf-builder`. Never by the manager.
- **Input:** a named command (build, test, coverage) and a log path.
- **Returns** a fixed digest of 15 lines or fewer, containing only facts:
  - exit code;
  - pass, fail and skip counts;
  - failing test names;
  - coverage %;
  - the log path.
- **No verdict.** The calling agent keeps the verdict. An unmeasured gate stays
  `GATE UNMEASURABLE` and is never reported as a pass.
- **Risks:**
  - Confident misreads. Mitigation: the digest holds facts only, and the caller can read the log.
  - Spawn latency. Acceptable for test runs; not worth it for one-off lookups.

## Next steps

1. Identify the `main` session (F1).
2. Check the `opsx-proposer` subagents-track attribution in P5–P7 against the transcripts (F3).
3. Measure lower effort on `opsx-proposer` and the verifiers against this baseline.
4. Add `swf-runner` and re-run a comparable feature. Compare with `usage.py report --by agent`.
5. Resume, rather than respawn, the architect for clarifications. Investigate why QA round 1 fails
   (F4).
