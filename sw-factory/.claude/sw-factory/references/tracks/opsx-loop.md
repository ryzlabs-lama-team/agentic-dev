# Tracks: opsx-loop (L2) and openspec (L3, supervised)

Both tracks run an OpenSpec change through the opsx-loop stage agents. They differ only in how
often the human is asked.

| | `opsx-loop` | `openspec` (supervised) |
|---|---|---|
| Level | L2 — behaviour change in an existing capability | L3 — any high-risk flag |
| Human checkpoints | the opsx spec gate only | after explore, at the spec gate, before sync, before archive |
| Precondition | — | an **accepted** ADR per risk flag |

Requires the opsx-loop toolkit installed (`.claude/skills/opsx-loop/SKILL.md` and the five
`opsx-*` agents), the `openspec` CLI, and an initialized `openspec/`. The preflight reports this.

## How to run it

Invoke the **`opsx-loop`** skill and follow its procedure: ledger, stage map, context discipline,
retry budget, and spec gate. Its own ledger lives in `.opsx-run/<slug>/`. Record that path in the
sw-factory ledger, and do not duplicate its rows.

Apply the **sw-factory overrides** below. Where they conflict with the skill, the overrides win,
because they add AI-SDLC inputs and gates and never remove the skill's own gate.

### Override 1: upstream documents are inputs

Use this goal for the explorer:

```
<phase goal, one line>.
Authoritative upstream inputs. Read them before the codebase, and do not contradict them:
- Requirements: <prds>/<slug>/prd.md (FR/NFR ids …), stories <ids> in <prds>/<slug>/stories.md
- Design: <tech_designs>/<system>/hld.md#<sections>, <llds>, <adrs>
- Plan: <plans>/<slug>.md#P<n>. The change scope must not exceed this phase; its "Out of scope" is a non-goal.
Tag every open question in the brief [po] or [sw-architect].
If the OpenSpec specs would have to contradict an upstream document, report STATUS: needs-human
and name the contradiction. Do not pick a side.
```

Use one OpenSpec change per plan phase. Change id: `<slug>-p<n>`, unless the explorer recommends
a split.

### Override 2: route open questions before the spec gate

After explore, if the brief lists open questions, spawn **po** (`MODE: clarify`) with the `[po]`
questions. Then spawn **sw-architect** (`MODE: clarify`) with the `[sw-architect]` ones, plus any
questions the po returned as `MISROUTED`. Run them one after the other, never in parallel: they
share the clarification log. Each owner confirms the brief's assumption or replaces it, and
updates its own documents. Send the proposer the answers file path,
`<runs>/<slug>/clarifications.md`, with the brief. The spec gate then shows the human only the
assumptions the owners could not settle.

### Override 3: every opsx spawn carries the clarification addendum

Append this to the prompt of every `opsx-*` spawn:

```
sw-factory: you cannot reach the po or sw-architect yourself. If the change artifacts and the
upstream documents above do not answer a question you need answered, follow
.claude/sw-factory/protocols/clarification.md, "If you do not have the Agent tool".
Be concise. Work without commentary or progress narration. Your only output is your return
payload, once you have results.
```

When `opsx-implementer` returns `needs-clarification` or `spec-conflict`, route the questions to
their owners first. Then:
- the **spec** is wrong → fresh `opsx-proposer` for `/opsx:update`, then re-apply. This is the
  skill's own route.
- the **upstream document** is wrong → the owner updates it. If that changes agreed requirements
  or approved design, stop for the human first. Then `/opsx:update` the spec to match.
- the spec was right and the implementer misread it → resume the implementer with
  `SendMessage` and the answer.

### Override 4: sw-qa runs between verify and sync

After `opsx-verifier` returns `PASS` or `PASS-WITH-ADVISORIES`, spawn **sw-qa** with the
sw-manager's QA block: `TRACK: opsx-loop`, `RUN`, `CHANGE: <change-id>`, the phase's `STORIES`,
`BASE` (the ref the phase started from), `ROUND`, and
`FINDINGS PATH: <runs>/<slug>/qa-P<n>-<round>.md`. It checks
the AI-SDLC gates that opsx-verify does not: coverage, PRD acceptance criteria, design and ADR
conformance, operational docs, and document drift.
- `BLOCKING` → retry apply with a fresh `opsx-implementer` given the QA findings path. This uses
  the **same** ≤2-round budget as opsx-verify. A third failure of either gate stops the run.
- `PASS` → sync, as in the skill.

### Override 5: archive per config

Archive only when `tracks.opsx_archive` is `yes`, or it is `ask` and the human approves.

## Supervised mode (openspec track)

All of the above, plus a human checkpoint at each of these points. Each is a short gate in the
sw-manager format:

1. **After explore and clarification.** Show the brief path, the chosen scope, and the remaining
   open questions. This is where the human catches a wrong approach before any spec exists.
2. **The opsx spec gate.** Unchanged.
3. **After apply, verify and sw-qa, before sync.** Show the verify and QA verdicts, coverage, and
   the files touched. Sync rewrites `openspec/specs/**`, the team's source of truth.
4. **Before archive.**

Do not start supervised mode until the sw-architect reports an `accepted` ADR for every K flag
in triage. If one is still `proposed`, take it to the human at the design gate first.
