## Context

See `proposal.md` — Why. The constraints that shape this design, all verified against the OpenCode
source (`sst/opencode@dev`) during explore:

- OpenCode reads agents only from `.opencode/` directories walked up from cwd, plus the global
  config dir. `.claude/agents/` is invisible to it. Skills, however, are shared: OpenCode's skill
  tool discovers `.opencode/skills/*/SKILL.md`, `.claude/skills/*/SKILL.md` and
  `.agents/skills/*/SKILL.md`, and ignores unknown frontmatter keys such as `allowed-tools`.
- **Permission defaults are inverted.** Claude Code's `tools:` is an allowlist — omission means
  denied. OpenCode's `permission:` defaults to allow-all — omission means allowed. A faithful port
  must write explicit denies. `tools:` still works in OpenCode but is deprecated and normalised into
  `permission:`, collapsing `write`/`edit`/`patch` onto one `edit` key.
- **Parent `deny` rules can propagate into a subagent session**
  (`packages/opencode/src/agent/subagent-permissions.ts` keeps every rule whose action is `deny`
  from the parent session's permission set). Whether an agent's own frontmatter denies ever reach
  that set depends on how the session was started, so treat this as a hazard to design against,
  not a guarantee.
- **The subagent-invocation tool takes no `model` parameter** (`packages/opencode/src/tool/task.ts`);
  model resolution is the subagent's own configured model, else the invoking agent's.
- Permission values may be a glob→action map for `read, edit, glob, grep, list, bash, task,
  external_directory, lsp, skill`, where the **last matching rule wins**.
- `openspec init --tools opencode` writes `.opencode/commands/opsx-<stage>.md` (flat, hyphenated)
  and `.opencode/skills/openspec-*/SKILL.md` into the target repo.
- The repo's `.claude/` tree is simultaneously the shipped source and this repo's own dogfood
  config. `install.sh` is source-relative and self-installable.

## Goals / Non-Goals

**Goals:**

- One installer, one clobber-guard implementation, one two-pass classifier — parameterised by
  target rather than duplicated.
- The OpenCode tree is runnable in this repo the moment it lands, so it can be tested by using it.
- Behavioral parity with the Claude distribution; only mechanism differs.

**Non-Goals (design level, on top of the proposal's):**

- No shared prompt-body source between the two trees. The bodies are hand-maintained duplicates and
  will be allowed to drift within the tolerance of the known path/tool-name deltas.
- No CI diff check between corresponding agent bodies. Noted as a future option only.
- No attempt to make `--target both` transactional across a mid-write failure; the two-pass
  classify-then-write discipline is extended to span both targets, which is the same guarantee the
  single-target installer offers today.

## Decisions

### D1 — `.opencode/` at the repo root, not a sibling `opencode/` source tree

Chosen so the shipped tree doubles as this repo's dogfood config, exactly as `.claude/` does. The
alternative (a separate `opencode/` staging tree, or a separate repo) forfeits dogfooding-in-place
and forces a second installer and a second clobber guard. Cost: the installer's source tree now
contains `.opencode/` files it must *not* install (see D2). Revisit only if the trees diverge
structurally.

### D2 — The OpenCode installed set is enumerated; the Claude one keeps its `find`

The Claude target may keep discovering `.claude/skills/opsx-loop/**` with `find`, because that
directory contains nothing but toolkit files. `.opencode/` cannot use the same trick: in this repo
it will also hold `openspec init`-generated commands and skills, and a naive `find` would sweep them
into the installed set and start clobbering OpenSpec's own output in every destination.

So the OpenCode target uses an explicit list for agents and the command, and a `find` scoped to
`.opencode/opsx-loop/` only. This is stated as a requirement, not a code comment, because it is the
single most expensive thing to get wrong.

Alternative rejected: an exclusion filter over a whole-`.opencode/` `find`. Blocklists rot — a new
OpenSpec-generated filename silently joins the installed set.

### D3 — Escalation becomes a second agent, `opsx-implementer-hard`

Forced by the runtime: the Task tool has no `model` parameter. Alternatives considered:

- *Drop retry-2 escalation.* Rejected — it is a documented design property of the toolkit; losing it
  makes the port a weaker toolkit rather than a port.
- *Define the escalated agent in `opencode.json` with `prompt: "{file:...}"`.* This is the only
  mechanism that genuinely shares a prompt body (a markdown body always overrides a frontmatter
  `prompt`). Rejected as the default because shipping/merging an `opencode.json` into a user's
  existing config is a far worse clobber problem than copying files. Retained as the fallback if
  D4's delegation proves unreliable.

`hidden: true` keeps it out of `@` autocomplete while leaving it invocable as a subagent.

### D4 — `opsx-implementer-hard` delegates rather than duplicating

Its body reads: follow `.opencode/agents/opsx-implementer.md`'s body as your instructions, ignore
its frontmatter — plus round-2-specific framing. This keeps the drift surface at one file instead of
two. If in practice the escalated agent skips the delegated read, fall back to D3's
`opencode.json` + `prompt: "{file:...}"` option; that is a mechanism change only, and does not
change any requirement in the spec.

### D5 — Permission posture: tighten where OpenCode can, but never on the orchestrator

Two separate moves:

1. *Subagents*: translate each Claude allowlist into explicit denies, and go further where OpenCode
   allows it — `edit: {"*": "deny", ".opsx-run/**": "allow"}` on `opsx-explorer` and `opsx-verifier`
   turns "the brief/findings file is the only file you may write" from prompt guidance into an
   enforced constraint. `NotebookEdit` has no OpenCode equivalent and is dropped. MCP tools are left
   alone rather than denied by a guessed wildcard that could also match built-ins.
2. *Orchestrator*: **no `read`/`edit`/`bash` deny of any kind.** The obvious move — encoding "the
   orchestrator never reads specs, code, or diffs" as a `read` deny — risks propagating that deny into
   every subagent and breaking the whole loop. The orchestrator's restriction is
   `task: {"*": "deny", "opsx-*": "allow"}` plus `websearch`/`webfetch` denies, and its coordination
   discipline stays prompt-only, exactly as it is today under Claude Code.

### D6 — The `question` tool for the human gate, plain text as fallback

OpenCode ships a first-class `question` capability with labelled options; it makes the gate harder
to accidentally sail past than free text. The plain-text summary still precedes it, because the
options list is not where the change id, paths, counts and encoded assumptions belong.

### D7 — Preflight asserts model ids and runtime agent resolution

Two of the three top risks (stale model ids, OpenCode schema drift) have the same early signal:
something is wrong at spawn time, which is *after* the human gate. Both are cheap to check up front,
so preflight runs the model listing and the agent listing and asserts against them, rather than
merely checking that files exist on disk.

### D8 — `--target` defaults to `claude`

So that every existing `toolkit-install` scenario passes verbatim and no current user's invocation
changes behavior. `both` is the union with a single classification pass spanning both.

### D9 — Delta placement for the "installed set" definition

The current main spec defines the installed set in prose inside its `## Purpose` preamble
(`openspec/specs/toolkit-install/spec.md:9-12`), where it is not a requirement and not testable.
This change promotes it to a normative `### Requirement: The installed set is determined by the
selected target`, declared as authoritative for the rest of the capability.

**Follow-up for sync/archive:** the Purpose preamble in the main spec will then be stale — it still
names the Claude-only set — and a delta cannot modify a Purpose section. It must be edited by hand
in `openspec/specs/toolkit-install/spec.md` at sync time. This was deliberately not done during
propose, so that nothing in the source of truth is mutated before the human gate.

## Risks / Trade-offs

- **Parent-deny propagation silently disables every subagent** → Stated as a spec requirement (no
  deny rules on `opsx-loop`), not just a comment. Early signal: the first apply returns `blocked`
  with permission errors, or the explorer cannot write `brief.md`.
- **Stale or wrong `provider/model` ids fail at spawn, mid-run, after the gate** → Ids are resolved
  from `opencode models` at implementation time, kept out of the spec, documented in one README
  table, and asserted by preflight (D7).
- **OpenCode moves fast; a port pinned to today's schema rots** → Prefer the documented spellings
  (`agents/`, `commands/`, `permission:` over the deprecated `tools:`), and make "the runtime
  resolves all seven agents" a preflight assertion rather than an assumption.
- **The installer sweeps OpenSpec-generated files** → D2's enumerated set, plus explicit scenarios
  asserting exclusion both in the source tree and at the destination. Early signal: a self-install
  reports files the toolkit does not own.
- **Two prompt trees drift** → Confine the per-agent difference to a single, clearly-marked
  "Resolve the stage instructions first" block. Accepted risk; a CI diff check is out of scope.
- **Escalation differs visibly between runtimes** → A docs risk only. One comparison table in the
  README instead of two divergent narratives.
- **`--target both` doubles the blast radius of a refusal** → Intentional: classifying the union
  before writing anything is the conservative reading, and it keeps a `both` install all-or-nothing.

## Assumptions encoded from the explore brief

The explore brief left eleven open questions. Each was resolved by adopting the brief's recommended
assumption. **These are what the human is being asked to check at the gate.**

| # | Question | Assumption encoded | Where |
|---|---|---|---|
| 1 | `agents/`+`commands/` or `agent/`+`command/`? | **Plural** — matches the docs and the directory `openspec init --tools opencode` already writes into | spec: agent-set requirement |
| 2 | Concrete `provider/model` ids | **Not verified, deliberately not in the spec.** The spec requires only that each agent pins an explicit model in the correct tier; ids are resolved with `opencode models` during implementation and documented in one README table | spec: model requirement; task 2.1 |
| 3 | Escalation with no per-call model override | **Second subagent** `opsx-implementer-hard` (hidden, high tier); orchestrator picks by `subagent_type` per round | D3; spec: escalation requirement |
| 4 | Avoiding a duplicated implementer body | **Delegation** — hard agent reads and follows `opsx-implementer.md`'s body. Fallback: `opencode.json` + `prompt: "{file:...}"` | D4 |
| 5 | Faithfulness of the permission translation | **Explicit denies**, plus tightening the two read-only agents to `edit` only under `.opsx-run/`. Drop `NotebookEdit`. Leave MCP alone | D5; spec: two permission requirements |
| 6 | Orchestrator's permissions | `task` limited to `opsx-*`; `bash`/`read`/`edit`/`question` allowed; web denied; **no read/edit/bash denies at all** | D5; spec: orchestrator requirement |
| 7 | Human gate: `question` tool or plain text? | **`question`** with approve (first, recommended) / revise / abandon, preceded by the plain-text summary; plain text is the fallback | D6; spec: gate requirement |
| 8 | Installer default target | **`claude`** — every existing scenario passes unchanged | D8 |
| 9 | Manifest path per target | **Two manifests**, each scoped to its own distribution, neither installed nor gitignored | spec: provenance requirement |
| 10 | Does this repo get a dogfood `.opencode/` runtime? | **Yes** — run `openspec init --tools opencode` here and commit its output as dogfood config, explicitly excluded from the installed set | D1, D2; task group 1 |
| 11 | One change or two? | **One.** The asset tree and the installer are coupled through the installed-set definition. If task count balloons, the clean seam is (a) agents+command+preflight, (b) installer `--target` | this change |
