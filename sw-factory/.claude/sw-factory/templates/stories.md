---
prd: PRD-<KEY>
updated: <YYYY-MM-DD>
---

# User stories — <PRD title>

A story is **ready** when: every acceptance criterion is testable, it links at least one FR/NFR,
and it has no open question without a stated assumption. Builders only implement ready stories.

| ID | Title | Priority | Status | Requirements |
|---|---|---|---|---|
| US-<KEY>-001 | <title> | must | draft | FR-001 |

---

## US-<KEY>-001: <title>
- **Status:** draft            <!-- draft | ready | in-progress | done | dropped -->
- **Priority:** must           <!-- must | should | could -->
- **Requirements:** FR-001, NFR-001
- **Plan phase:** ~            <!-- set by sw-planner, e.g. docs/plans/<slug>.md#P2 -->

As a **<persona>**, I want **<capability>**, so that **<benefit>**.

### Acceptance criteria
- **AC1** — Given <state>, when <action>, then <observable outcome>.
- **AC2** — Given <edge case>, when <action>, then <observable outcome>.

### Out of scope
- <what this story deliberately does not cover>

### Notes
- <clarifications recorded here with their source: run slug and question id>
