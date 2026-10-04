---
name: engineering-practices
description: Routes engineering-practice work to one reference skill in "../../skills-library/engineering-practices/". Consult before any non-trivial coding task, and before falling back on your own default approach — vague idea, spec, task breakdown, multi-file implementation, tests, debugging a failure, code review, simplification, API or UI design, security hardening, performance profiling, commits and branching, CI/CD, docs and ADRs, deprecation or migration, shipping to production.
---

# Engineering Practices

`../../skills-library/engineering-practices/` holds one reference skill per practice. They are a library, not loaded context — nothing reaches you until you read it. This skill decides which one to open.

## Procedure

1. Match the task against the routing table. More than one row can apply; a feature is usually a sequence.
2. If no row matches, say so and proceed without one. Do not stretch the nearest row to fit. The table covers process practices, not every engineering topic — data modeling and schema design, for instance, have no row here.
3. Read `../../skills-library/engineering-practices/<name>/SKILL.md`. These are plain Markdown files, not registered skills — use Read, not the Skill tool.
4. They run 3.5–16.5 KB. Read the small ones whole; for the large ones read the headings first, then only the sections the task needs.
5. Follow the steps in order. Do not skip the verification step.

## Routing table

| Read this | When the task involves |
|---|---|
| `idea-refine` | Vague or half-formed idea; exploring options before committing to a shape |
| `spec-driven-development` | New project, feature or significant change with no spec; unclear requirements |
| `planning-and-task-breakdown` | Turning a spec into ordered tasks; scope estimate; finding parallelizable work |
| `context-engineering` | Session setup, rules files, degraded output quality, switching tasks |
| `source-driven-development` | Framework or library correctness matters; need doc-grounded, non-stale code |
| `incremental-implementation` | Change touches more than one file; about to write a lot of code at once |
| `doubt-driven-development` | High stakes — production, security, irreversible ops — or unfamiliar code |
| `api-and-interface-design` | Public interface, module boundary, REST/GraphQL endpoint, cross-module contract |
| `frontend-ui-engineering` | User-facing UI — components, layout, state; output must not look AI-generated |
| `code-structure` | Duplicated operational logic across workflows; actions vs shared services |
| `test-driven-development` | Implementing logic, fixing a bug, changing behavior; a bug report arrives |
| `browser-testing-with-devtools` | Anything in a browser — DOM, console errors, network, profiling, visual output |
| `debugging-and-error-recovery` | Tests fail, build breaks, behavior unexpected; need root cause, not a guess |
| `code-review-and-quality` | Before merging any change, whoever or whatever wrote it |
| `code-simplification` | Code works but is harder to read, maintain or extend than it should be |
| `security-and-hardening` | Untrusted input, auth, sessions, data storage, third-party integrations |
| `performance-optimization` | Perf requirements or regressions, Core Web Vitals, load times, profiled bottlenecks |
| `git-commit-message` | Writing a commit message (Conventional Commits v1.0.0) |
| `git-workflow-and-versioning` | Committing, branching, resolving conflicts, parallel work streams |
| `ci-cd-and-automation` | Build and deploy pipelines, quality gates, CI test runners, deployment strategy |
| `documentation-and-adrs` | Architectural decision, public API change, recording context for later |
| `deprecation-and-migration` | Removing an old system, API or feature; migrating users; maintain vs sunset |
| `shipping-and-launch` | Production deploy, pre-launch checklist, monitoring, staged rollout, rollback |

## Notes

`idea-refine` carries companions (`examples.md`, `frameworks.md`, `refinement-criteria.md`, `scripts/`) and `git-commit-message` carries `scripts/`. Read those only when that skill's SKILL.md points at them.

Typical feature sequence: `idea-refine` → `spec-driven-development` → `planning-and-task-breakdown` → `incremental-implementation` → `test-driven-development` → `code-review-and-quality` → `shipping-and-launch`. A bug fix is usually `debugging-and-error-recovery` → `test-driven-development` → `code-review-and-quality`.

Project rules win. Where a repo's `AGENTS.md` or `CLAUDE.md` conflicts with a practice here, the repo's rules take precedence.
