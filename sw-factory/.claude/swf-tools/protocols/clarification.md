# sw-factory clarification protocol

Read this whenever you build, plan, or design inside the sw-factory and the documents do not tell
you what to do. A builder guessing at a requirement is how a passing build ships the wrong
feature.

## Who owns what

| Owner | Owns | Documents | Ask about |
|---|---|---|---|
| **swf-po** | *What* and *why* | `<prds>/<slug>/prd.md`, `stories.md` | Scope, user-visible behaviour, acceptance criteria, edge cases a user would notice, priorities, NFR **targets**, wording users see |
| **swf-architect** | *How* | `<tech_designs>/**`, `<adrs>/**` | Components, where code goes, interfaces and contracts, data model and migrations, technology and library choices, patterns, NFR **tactics**, security mechanisms |

Paths in `<…>` come from `.sw-factory/config.yaml`.

Use this to decide between them: if a user or the Product team would notice the answer, ask the
**swf-po**. If only engineers would notice it, ask the **swf-architect**. When the PRD and the design
contradict each other, ask both. Tag the question `[swf-po+swf-architect]` and ask the swf-po first,
because requirements constrain design and not the other way round.

## Before you ask

1. **Look it up.** Check the stories and acceptance criteria, then the PRD, then the HLD, LLD and
   ADRs, then the plan phase, then the existing code. Most questions are answered there.
2. **Do not ask** about anything you can determine from code or documents, about style already
   settled by neighbouring code, or for permission to do what the plan already says.
3. **Decide whether the question blocks you.**
   - **Blocking:** two plausible answers lead to materially different behaviour, tests, interfaces
     or data. Also blocking: the answer is expensive to reverse, such as a public API, a persisted
     format, a schema, or a security boundary.
   - **Non-blocking:** the choice is local, reversible and cheap. Proceed under the most
     conservative reading of the documents. Record it under `ASSUMPTIONS` in your return payload so
     the owner can confirm it afterwards.

## How to ask

How you ask depends on whether you have the `Agent` tool.

### If you have the `Agent` tool (swf-builder, swf-planner, swf-architect)

Spawn the owner directly. Use `subagent_type: swf-po` or `subagent_type: swf-architect`, and nothing
else. Send **one spawn per owner per need**, with every question for that owner in it:

```
MODE: clarify
RUN: <slug>                      # so the owner logs to <runs>/<slug>/clarifications.md
ASKED BY: <your agent name>, <work package / task id>
QUESTIONS:
- Q1 <the question, answerable in one paragraph>
  Context: <story/AC id, doc path#section, or path:line that is silent or ambiguous>
  Options: (a) <…> (b) <…>
  Default: <what you would do without an answer, and why>
```

The owner answers. Where the answer adds information, the owner updates their document and
returns the path#section. **The updated document is authoritative, not the reply text.** Re-read
that section before you continue.

If the owner lists questions under `MISROUTED`, they belong to the other owner. Re-ask them there
once. Ask the swf-po first and the swf-architect second, never both at the same time: they share the
clarification log.

If the owner returns `STATUS: needs-human`, the decision is above both of you. Stop at a safe
point: the build compiles, or the in-progress task is reverted. Then return to your caller with
`STATUS: needs-human` and `NEEDS HUMAN: owner: <swf-po | swf-architect> — <the owner's framed decision,
verbatim>`. The swf-manager takes it to the human, has that owner record the decision, and
resumes you with the answer.

### If you do not have the `Agent` tool (opsx-* agents, anything else)

Stop at a safe point and return to your caller with:

```
STATUS: needs-clarification
RESUME POINT: <task id you stopped at; does the tree build; do tests pass>
QUESTIONS:
- Q1 [swf-po | swf-architect | swf-po+swf-architect] <question>
  Context: <…>
  Options: (a) <…> (b) <…>
  Default: <…>
  Blocks: <task ids>
```

The swf-manager routes the questions to the owners, swf-po first and then swf-architect, and resumes
you with the answers and the updated document paths.

## Budget

Ask at most **5 questions per work package**, across every spawn. Before asking, check the count
with `python3 .sw-factory/tools/swf-cli.py clar count <run> --wp <work package> --adding <n>`. If you
need more, it exits 1: the work package is under-specified. Stop and return
`STATUS: under-specified` and list the gaps. The fix is an upstream document revision, not a
longer conversation.

## Never

- Edit a document you do not own, even to fix an obvious typo. Report it instead. Hooks block
  this for sw-factory agents, and swf-qa reports any edits that get through as `DOC DRIFT`.
- Treat an owner's answer as permission to expand scope. A clarification resolves an ambiguity;
  a scope change goes through the swf-manager and the human.
- Hide a disagreement. If an answer contradicts the code or another document, say so in your
  payload.
