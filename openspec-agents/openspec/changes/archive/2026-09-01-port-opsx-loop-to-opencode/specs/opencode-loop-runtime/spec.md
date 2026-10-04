## Purpose

Defines the OpenCode distribution of the opsx-loop toolkit: which agent files exist and where, the
mode and model tier of each, the permission posture that replaces Claude Code's tool allowlists,
how retry escalation works without a per-call model override, how agents resolve their stage
instructions, how the human gate is presented, and what preflight must assert before a run starts.

## ADDED Requirements

### Requirement: The OpenCode agent set is seven files under `.opencode/agents/`

The toolkit SHALL ship exactly seven agent definitions as markdown files in the directory
`.opencode/agents/` (plural spelling), named `opsx-loop.md`, `opsx-explorer.md`, `opsx-proposer.md`,
`opsx-implementer.md`, `opsx-implementer-hard.md`, `opsx-verifier.md`, and `opsx-syncer.md`.

`opsx-loop` SHALL declare `mode: primary`. The other six SHALL declare `mode: subagent`.
`opsx-implementer-hard` SHALL additionally declare `hidden: true`, so it does not appear in `@`
autocomplete while remaining invocable as a subagent.

Every agent file SHALL declare `description` in its frontmatter, and its markdown body SHALL be the
agent's prompt.

#### Scenario: All seven agents are discovered

- **WHEN** OpenCode is started in a repo where the toolkit is installed and the agent list is
  enumerated
- **THEN** all seven `opsx-*` agents are present, `opsx-loop` is listed as a primary agent, and the
  other six are listed as subagents

#### Scenario: The escalation agent is hidden but invocable

- **WHEN** the user types `@opsx-` in OpenCode
- **THEN** `opsx-implementer-hard` is not offered in the completion list, and invoking it by name
  as a subagent from the orchestrator still succeeds

#### Scenario: No OpenCode config file is shipped

- **WHEN** the toolkit's OpenCode tree is installed into a repo
- **THEN** no `opencode.json` or `opencode.jsonc` is created or modified at the destination

### Requirement: Each OpenCode agent declares an explicit model matching the Claude-tree allocation

Every one of the seven agent files SHALL declare an explicit `model` in its frontmatter; none SHALL
rely on the caller's or the runtime's default model.

`opsx-loop`, `opsx-explorer`, `opsx-proposer`, `opsx-verifier`, and `opsx-implementer-hard` SHALL
use the high-capability model tier (the OpenCode equivalent of the Claude tree's `opus`).
`opsx-implementer` and `opsx-syncer` SHALL use the fast model tier (the equivalent of `sonnet`).

The concrete `provider/model` identifiers SHALL be confirmed against the models the OpenCode
installation actually offers, and SHALL be documented in a single table in `README.md`. This
specification SHALL NOT be read as pinning any particular identifier string.

#### Scenario: Every agent pins a model

- **WHEN** the frontmatter of each of the seven agent files is inspected
- **THEN** each contains a `model` key with a non-empty value

#### Scenario: Configured model ids are real

- **WHEN** the configured model identifiers are checked against the set of models the OpenCode
  installation reports as available
- **THEN** every configured identifier is present in that set

#### Scenario: Tier allocation matches the Claude tree

- **WHEN** the OpenCode model table in `README.md` is compared against the Claude-tree model
  allocation
- **THEN** each stage is served by the same tier in both runtimes, with `opsx-implementer-hard`
  occupying the high tier that the Claude tree reaches via retry-round escalation

### Requirement: Retry escalation is expressed as a second subagent, not a per-call model override

OpenCode's subagent-invocation tool accepts no model parameter, so the orchestrator SHALL NOT
attempt to override a subagent's model at call time.

The orchestrator SHALL invoke `opsx-implementer` for the initial apply and for apply retry round 1,
and SHALL invoke `opsx-implementer-hard` for apply retry round 2. The retry budget SHALL remain at
most two rounds; after a second failing verify the orchestrator SHALL stop and report to the human
rather than attempting a third round.

#### Scenario: First retry stays on the fast tier

- **WHEN** verify returns `BLOCKING` and zero retry rounds have been used
- **THEN** the orchestrator spawns a fresh `opsx-implementer` with the findings path

#### Scenario: Second retry escalates by agent identity

- **WHEN** verify returns `BLOCKING` and exactly one retry round has been used
- **THEN** the orchestrator spawns a fresh `opsx-implementer-hard` with the findings path, and
  passes no model parameter of any kind

#### Scenario: Budget is still two rounds

- **WHEN** verify returns `BLOCKING` after the `opsx-implementer-hard` round
- **THEN** the orchestrator stops and hands the human the findings path, what was tried, and what
  is still failing

### Requirement: The escalation agent delegates its prompt rather than duplicating it

`opsx-implementer-hard.md` SHALL NOT restate the apply-stage procedure, tool discipline, or return
payload format that `opsx-implementer.md` already defines. Its body SHALL instruct the agent to read
`.opencode/agents/opsx-implementer.md` and follow that file's body as its instructions while
ignoring that file's frontmatter, and SHALL add only guidance specific to being a second, escalated
retry round.

#### Scenario: No duplicated stage procedure

- **WHEN** `opsx-implementer-hard.md` and `opsx-implementer.md` are compared
- **THEN** `opsx-implementer-hard.md` contains no copy of the apply procedure or return payload
  template, and instead names `.opencode/agents/opsx-implementer.md` as the source of its
  instructions

#### Scenario: A fix to the implementer reaches the escalation path

- **WHEN** `opsx-implementer.md`'s body is edited
- **THEN** `opsx-implementer-hard` picks up that edit with no corresponding change to its own file

### Requirement: Claude tool allowlists are translated into explicit OpenCode denies

OpenCode grants tools by default, which inverts Claude Code's allowlist semantics where an omitted
tool is denied. Each subagent's `permission` map SHALL therefore state explicit `deny` entries for
every capability that the corresponding Claude agent's `tools:` list withholds, so that the two
runtimes grant the same effective capability set.

Specifically: `opsx-explorer` and `opsx-verifier` SHALL be denied the ability to spawn subagents;
`opsx-proposer`, `opsx-implementer`, `opsx-implementer-hard`, `opsx-syncer`, and `opsx-verifier`
SHALL be denied web search and web fetch; all six subagents SHALL be denied the ability to spawn
further subagents, keeping the topology flat. Every subagent SHALL be permitted the skill tool, as
the instruction-resolution chain depends on it.

Capabilities with no OpenCode equivalent SHALL be dropped rather than approximated. MCP tools SHALL
be left at their default posture rather than denied by a guessed wildcard.

#### Scenario: Explorer keeps web access, loses delegation

- **WHEN** `opsx-explorer`'s permission map is inspected
- **THEN** web search and web fetch are not denied, and subagent spawning is denied

#### Scenario: Implementer loses web access

- **WHEN** `opsx-implementer`'s permission map is inspected
- **THEN** web search and web fetch are explicitly denied

#### Scenario: Flat topology is explicit

- **WHEN** any of the six subagents' permission maps is inspected
- **THEN** subagent spawning is explicitly denied rather than left to the runtime default

### Requirement: The read-only agents can write only their own run-state file

`opsx-explorer` and `opsx-verifier` SHALL have an edit permission map that denies edits everywhere
by default and allows them only under `.opsx-run/`. This converts the Claude tree's instruction that
the brief or findings file is the only permitted write into an enforced constraint.

#### Scenario: Explorer writes its brief

- **WHEN** `opsx-explorer` writes `.opsx-run/<slug>/brief.md`
- **THEN** the write is permitted

#### Scenario: Explorer cannot touch source

- **WHEN** `opsx-explorer` attempts to write or edit any file outside `.opsx-run/`
- **THEN** the write is denied by permission, not merely discouraged by the prompt

#### Scenario: Verifier cannot edit the implementation it reviews

- **WHEN** `opsx-verifier` attempts to edit a source file or an OpenSpec artifact
- **THEN** the write is denied, and only `.opsx-run/<slug>/verify-<n>.md` remains writable

### Requirement: The orchestrator carries no deny rule that a subagent would inherit

OpenCode can propagate a parent session's `deny` rules into the subagent sessions it spawns:
subagent permissions are derived by carrying forward every rule whose action is `deny` from the
parent session's permission set. Whether an orchestrator's own frontmatter denies reach that set
depends on how the session was started, so the propagation is a hazard to design against rather
than a guarantee.
`opsx-loop` SHALL therefore declare no `deny` entry for reading, editing, or running shell commands.
Its "coordination only — never read specs, code, or diffs; never edit artifacts or code" discipline
SHALL be enforced by its prompt alone.

`opsx-loop` SHALL restrict subagent spawning to the `opsx-*` agents, denying all others, and SHALL
deny web search and web fetch. It SHALL be permitted the shell, reading, editing, and the
user-question capability so it can run preflight, maintain the run ledger, and hold the human gate.

#### Scenario: Subagents are not crippled by inherited denies

- **WHEN** `opsx-loop` spawns `opsx-implementer` and that subagent edits a source file
- **THEN** the edit succeeds, because no inherited `deny` from the orchestrator applies

#### Scenario: Orchestrator cannot reach non-toolkit subagents

- **WHEN** `opsx-loop`'s permission map is inspected
- **THEN** subagent spawning is denied for all names and re-allowed only for the `opsx-*` pattern

#### Scenario: Coordination discipline is prompt-level

- **WHEN** `opsx-loop`'s frontmatter is inspected
- **THEN** it contains no `deny` value for read, edit, or bash, and its body states the
  never-read-specs-code-or-diffs rule

### Requirement: A single `/opsx-loop` command starts a run in the orchestrator

The toolkit SHALL ship exactly one command file, `.opencode/commands/opsx-loop.md`, which routes to
the `opsx-loop` primary agent and forwards the user's goal as the command's arguments. Because
`opsx-loop` is a primary agent, the command SHALL run in that agent rather than spawning it as a
subtask.

The toolkit SHALL NOT ship any other command file, and SHALL NOT ship copies of OpenSpec's own
`opsx-<stage>` commands or `openspec-*` skills; those are produced in the target repo by
`openspec init --tools opencode`.

#### Scenario: Command starts the loop

- **WHEN** the user runs `/opsx-loop <goal>` in OpenCode
- **THEN** the `opsx-loop` primary agent is engaged with `<goal>` as its input

#### Scenario: OpenSpec's own files are not shipped

- **WHEN** the toolkit's OpenCode tree is enumerated
- **THEN** it contains no `openspec-*` skill directory and no `opsx-<stage>` command other than
  `opsx-loop.md`

### Requirement: OpenCode agents resolve stage instructions from OpenCode paths

Each stage subagent's body SHALL open with an instruction-resolution block that names, in order:
the skill tool with the mapped `openspec-*` skill, then the OpenCode command file at
`.opencode/commands/opsx-<stage>.md`, then the `openspec instructions` CLI fallback where one
exists. No OpenCode agent body SHALL reference `.claude/commands/opsx/<stage>.md`.

`opsx-verifier` SHALL remain self-contained with no skill and no command file, reading the change's
state through the OpenSpec CLI.

The resolution chain SHALL be documented in `README.md` for both runtimes.

#### Scenario: No stale Claude paths

- **WHEN** the seven OpenCode agent files are searched for the string `.claude/`
- **THEN** no match is found

#### Scenario: Command fallback uses the flat naming

- **WHEN** an OpenCode stage subagent's resolution block is read
- **THEN** the command path it names uses the flat hyphenated form `opsx-<stage>.md`, matching what
  `openspec init --tools opencode` writes

#### Scenario: Verifier has no stage command

- **WHEN** `opsx-verifier`'s body is read
- **THEN** it names no skill and no command file, and instead names the OpenSpec CLI calls it uses

### Requirement: The human gate is a structured question with a plain-text fallback

After the propose stage the orchestrator SHALL stop and obtain explicit human approval before any
code is written. It SHALL first present, as plain text, the change id, the artifact paths, the
requirement and task counts, and the assumptions the proposer encoded. It SHALL then ask for a
decision using OpenCode's user-question capability with exactly three options — approve, revise,
abandon — with approve listed first and marked as recommended.

If the user-question capability is unavailable or denied, the orchestrator SHALL ask the same
question as plain text. It SHALL NOT proceed on silence or on an ambiguous reply.

#### Scenario: Gate is presented before apply

- **WHEN** the propose stage returns successfully
- **THEN** the orchestrator presents the plain-text summary and asks for approval, and spawns no
  implementer until an approval is received

#### Scenario: Question offers exactly three options

- **WHEN** the gate question is asked
- **THEN** the offered options are approve, revise, and abandon, in that order

#### Scenario: Fallback when the question capability is denied

- **WHEN** the user-question capability is denied for `opsx-loop`
- **THEN** the orchestrator asks for the same approve/revise/abandon decision in plain text and
  still refuses to proceed without an explicit answer

#### Scenario: Ambiguous reply does not advance the loop

- **WHEN** the human's reply is neither a clear approval, a clear revision request, nor a clear
  abandonment
- **THEN** the orchestrator asks again rather than proceeding

### Requirement: OpenCode preflight verifies the runtime before a loop starts

The toolkit SHALL ship an executable preflight script at `.opencode/opsx-loop/preflight.sh` that
runs from the target repo root and exits non-zero when the loop cannot run. It SHALL check that the
`openspec` CLI is on PATH, that an `openspec/` directory exists, that `.opencode/commands/` contains
OpenSpec's `opsx-<stage>` command files, that `.opencode/skills/openspec-*` skills are present, that
all seven `.opencode/agents/opsx-*.md` files exist, and that `.opsx-run/` is writable.

It SHALL additionally assert that the OpenCode runtime actually resolves all seven `opsx-*` agents,
and that every model identifier configured in those agent files appears in the set of models the
OpenCode installation reports. A missing model identifier SHALL be reported by preflight rather than
discovered when a subagent is spawned mid-run.

Missing OpenSpec skills and an un-ignored `.opsx-run/` SHALL be warnings; the remaining checks SHALL
be failures.

#### Scenario: Missing agent fails preflight

- **WHEN** one of the seven `.opencode/agents/opsx-*.md` files is absent
- **THEN** preflight reports the missing agent and exits non-zero

#### Scenario: Unresolvable model fails preflight

- **WHEN** an agent file declares a model identifier that the OpenCode installation does not offer
- **THEN** preflight reports that identifier and exits non-zero

#### Scenario: Runtime does not see an agent

- **WHEN** all seven agent files exist but the OpenCode runtime resolves fewer than seven `opsx-*`
  agents
- **THEN** preflight reports the discrepancy and exits non-zero

#### Scenario: Missing OpenSpec skills only warn

- **WHEN** no `.opencode/skills/openspec-*` directory exists but every other check passes
- **THEN** preflight prints a warning and exits zero

### Requirement: Stage semantics are ported unchanged from the Claude Code distribution

The OpenCode distribution SHALL preserve the loop's behavior exactly, changing only the runtime
mechanism. The stage sequence, the three-tier context discipline in which context moves between
stages through files on disk, the run ledger, the ≤30-line return payloads, the mandatory human
gate, the separation of writer from approver, the rule that the implementer never edits specs, the
rule that retries get a fresh subagent, and the rule that stages run serially SHALL all hold
identically in both distributions.

Where the two runtimes necessarily differ — the escalation mechanism and the instruction-resolution
paths — `README.md` SHALL present the difference in a single comparison rather than as two divergent
narratives.

#### Scenario: Verifier is always a separate spawn

- **WHEN** an apply round completes under OpenCode
- **THEN** verification is performed by a freshly spawned `opsx-verifier`, never by the agent that
  wrote the code

#### Scenario: Implementer reports spec conflicts instead of fixing them

- **WHEN** an OpenCode implementer finds the delta spec wrong
- **THEN** it stops and reports a spec conflict, and the orchestrator routes to the proposer rather
  than letting the implementer edit the spec

#### Scenario: Runtime differences are documented once

- **WHEN** `README.md` is read
- **THEN** it contains one comparison covering the escalation mechanism and instruction-resolution
  differences between the Claude Code and OpenCode distributions
