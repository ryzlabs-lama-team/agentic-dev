---
id: PLAN-<KEY>
title: <what this plan delivers>
status: draft            # draft | approved | in-progress | done | superseded
version: 0.1.0
prds: []                 # docs/prds/<slug>/prd.md
designs: []              # docs/tech-designs/... (HLD, LLDs)
adrs: []
approved_by: ~
---

# Plan: <title>

## Overview
<2–4 sentences: the end state, the deployment target it builds towards, and the phase strategy.>

## Phase map
Phases run in order: infrastructure → scaffolding → basic features → complex features.
A phase is the unit sw-manager assigns to one implementation track.

| Phase | Goal | Stories | Level | Track (recommended) | Depends on | Status |
|---|---|---|---|---|---|---|
| P1 | <goal> | US-<KEY>-001 | L1 | subagents | — | todo |

Status values: todo | in-progress | blocked | done. The run ledger is authoritative, and
sw-planner syncs this column from it. `done` phases are immutable: a later change adds a new phase
rather than rewriting a finished one.

---

## P1 — <name>
- **Goal:** <one sentence a QA agent can check>
- **Stories / requirements:** US-<KEY>-001 (AC1–AC3), FR-001, NFR-001
- **Design references:** `docs/tech-designs/<system>/hld.md#4`, `docs/adrs/NNNN-*.md`
- **Deliverables:** <code, tests, operational docs>
- **Out of scope:** <what is deliberately left for later phases>
- **Complexity signals:** R=<none|clarify|extend|new> · D=<none|local|cross|new> ·
  K=<risk flags or none> · S=<files/components estimate> · greenfield=<yes|no>
- **Recommended track:** <direct | subagents | opsx-loop | openspec | spec-kit> — <one-line why>

### Tasks
Write the test first for every behaviour task.

- [ ] **1.1** <task> — files: `<paths>` — satisfies: US-<KEY>-001 AC1
- [ ] **1.2** <task> — files: `<paths>` — satisfies: FR-001

### Exit criteria
- [ ] Build passes; 100% of tests pass; coverage ≥ gate in `.sw-factory/config.yaml`
- [ ] Acceptance criteria above each have at least one test that exercises them
- [ ] Operational docs updated for anything this phase changes (build, run, test, deploy, configure, monitor)

---

## Traceability
| Story | Phase |
|---|---|
| US-<KEY>-001 | P1 |

## Changelog
| Version | Date | Change | Trigger |
|---|---|---|---|
| 0.1.0 | <YYYY-MM-DD> | Initial plan | PRD-<KEY> v<x>, HLD-<SYSTEM> v<y> |
