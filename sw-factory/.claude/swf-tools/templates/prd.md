---
id: PRD-<KEY>
title: <product or feature name>
status: draft            # draft | in-review | agreed | superseded
version: 0.1.0           # minor = requirements added/changed, patch = wording/clarification
product_owner: <human accountable for agreeing this PRD>
agreed_by: ~             # "<name(s)>, <YYYY-MM-DD>" — set only after the human gate confirms agreement
confluence: ~            # page URL once published; the repository copy is the source of truth
related:
  designs: []            # docs/tech-designs/... paths
  adrs: []               # docs/adrs/... paths
  plans: []              # docs/plans/... paths
---

# <title>

## 1. Problem statement
<Who has the problem, what it is, and why it matters now. 3–6 sentences. No solution language.>

## 2. Goals and success metrics
| ID | Goal | Metric | Target |
|---|---|---|---|
| G-01 | <outcome, not output> | <how it is measured> | <threshold, date> |

## 3. Non-goals
- <explicitly out of scope — this list is what stops downstream agents expanding scope>

## 4. Context and users
- **Personas:** <persona — need — current workaround>
- **Current state:** <what exists today, linked to code or docs where relevant>
- **Constraints:** <regulatory, contractual, deadlines, platforms>

## 5. Scope
| ID | Feature | Priority | Stories |
|---|---|---|---|
| F-01 | <feature> | must / should / could | US-<KEY>-001, … |

## 6. Functional requirements
Each requirement is independently testable: a QA agent must be able to write a check for it.

- **FR-001** — <the system shall …> _(F-01; stories: US-<KEY>-001)_

## 7. Non-functional requirements
Targets only. *How* they are met belongs to the HLD.

- **NFR-001** — <quality attribute>: <measurable target> _(e.g. p95 latency < 300 ms at 50 rps)_

## 8. Assumptions and constraints
- **A-01** — <assumption the requirements depend on; who can confirm it>

## 9. Dependencies
- <team, system, vendor, or decision this PRD depends on>

## 10. Open questions
Every open question carries the default assumption work proceeds under until it is answered.

- **Q-01** — <question> — **Assume:** <default> — **Owner:** <human/role>

## 11. Decision log
| Date | Decision | Decided by | Source |
|---|---|---|---|
| <YYYY-MM-DD> | <decision> | <human name or role> | human gate / clarification <run>/Q<n> |

## 12. Changelog
| Version | Date | Change | Reason |
|---|---|---|---|
| 0.1.0 | <YYYY-MM-DD> | Initial draft | <request / run slug> |
