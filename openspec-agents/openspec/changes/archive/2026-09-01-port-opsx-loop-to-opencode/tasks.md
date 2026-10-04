> Read `design.md` first — especially **D2** (the OpenCode installed set is enumerated, never
> discovered), **D5** (the orchestrator gets *no* deny rules), and the **Assumptions encoded** table.
> Requirement names below refer to `specs/opencode-loop-runtime/spec.md` and
> `specs/toolkit-install/spec.md` in this change folder. Do not edit anything under
> `openspec/specs/` — that is the sync stage's job.

## 1. Dogfood scaffold and model-id resolution

Prerequisite group. Everything later depends on knowing the real model ids and on `.opencode/`
existing. Groups 2-4 depend on 1.2; group 5 depends on 1.1.

- [x] 1.1 Run `openspec init --tools opencode` in the repo root so `.opencode/commands/opsx-*.md`
      and `.opencode/skills/openspec-*/SKILL.md` are generated as dogfood config. Verify with
      `ls .opencode/commands/ .opencode/skills/` that the six `opsx-<stage>.md` commands and six
      `openspec-*/SKILL.md` skills exist. Do not hand-edit any generated file. Satisfies the
      dogfood half of assumption 10.
- [x] 1.2 Run `opencode models` and pick one high-capability (opus-class) id and one fast
      (sonnet-class) id in `provider/model` form. Record both in a scratch note for use in groups
      2-4 and in task 6.2. Verify each chosen id appears verbatim in the `opencode models` output.
      Satisfies "Each OpenCode agent declares an explicit model matching the Claude-tree
      allocation" (assumption 2 — the ids are deliberately absent from the spec).

**Group verification:** `ls -d .opencode/commands .opencode/skills` succeeds and both model ids
appear in `opencode models`.

## 2. The five stage subagents

Each file is a port of its `.claude/agents/` counterpart. Copy the body **verbatim**, then apply
exactly two edits: rewrite the "Resolve the stage instructions first" block, and fix any other
`.claude/` path. Change nothing else — keeping the diff to that one block is the drift mitigation
in `design.md`. Tasks 2.1-2.5 are independent of one another and may be done in any order.

Frontmatter for all five: `description`, `mode: subagent`, `model` (from 1.2), and a `permission`
map. Use `permission:`, never the deprecated `tools:`. Remember OpenCode defaults to **allow**, so
withheld capabilities need an explicit `deny`. Every subagent denies subagent spawning (`task`) and
is allowed `skill`.

- [x] 2.1 Create `.opencode/agents/opsx-explorer.md` from `.claude/agents/opsx-explorer.md`:
      high-tier model; `webfetch`/`websearch` allowed; `task` denied;
      `edit: {"*": "deny", ".opsx-run/**": "allow"}`. Resolution block: skill `openspec-explore`,
      then `.opencode/commands/opsx-explore.md`. Verify `grep -c '\.claude/' <file>` returns 0.
      Satisfies "The read-only agents can write only their own run-state file" and "OpenCode agents
      resolve stage instructions from OpenCode paths".
- [x] 2.2 Create `.opencode/agents/opsx-proposer.md` from `.claude/agents/opsx-proposer.md`:
      high-tier model; `websearch`/`webfetch`/`task` denied. Resolution block: skill
      `openspec-propose`, then `.opencode/commands/opsx-propose.md`, then
      `openspec instructions <artifact> --change <id> --json`. Verify no `.claude/` string remains.
- [x] 2.3 Create `.opencode/agents/opsx-implementer.md` from `.claude/agents/opsx-implementer.md`:
      fast-tier model; `websearch`/`webfetch`/`task` denied; drop `NotebookEdit` (no OpenCode
      equivalent). Resolution block: skill `openspec-apply-change`, then
      `.opencode/commands/opsx-apply.md`, then `openspec instructions apply --change <id> --json`.
      Verify no `.claude/` string remains. Satisfies "Claude tool allowlists are translated into
      explicit OpenCode denies".
- [x] 2.4 Create `.opencode/agents/opsx-verifier.md` from `.claude/agents/opsx-verifier.md`:
      high-tier model; `websearch`/`webfetch`/`task` denied;
      `edit: {"*": "deny", ".opsx-run/**": "allow"}`. It names **no** skill and **no** command file
      — rewrite its "not an OpenSpec command" section to keep that true and to drop the
      `/opsx:verify` phrasing. Verify no `.claude/` string remains and the body still lists the
      `openspec status/show/validate/list` calls.
- [x] 2.5 Create `.opencode/agents/opsx-syncer.md` from `.claude/agents/opsx-syncer.md`: fast-tier
      model; `websearch`/`webfetch`/`task` denied. Resolution block: skills `openspec-sync-specs` /
      `openspec-archive-change`, then `.opencode/commands/opsx-sync.md` /
      `.opencode/commands/opsx-archive.md`, then `openspec instructions archive --change <id>
      --json`. Verify no `.claude/` string remains.

**Group verification:**
`grep -rl '\.claude/' .opencode/agents/ | wc -l` prints `0`, and
`grep -L 'mode: subagent' .opencode/agents/opsx-{explorer,proposer,implementer,verifier,syncer}.md`
prints nothing.

## 3. Escalation agent, orchestrator, and command

Depends on group 2 (3.1 references `opsx-implementer.md`; 3.2 names all six subagents).

- [x] 3.1 Create `.opencode/agents/opsx-implementer-hard.md`: `mode: subagent`, `hidden: true`,
      high-tier model, same permission map as `opsx-implementer`. Its body must **not** restate the
      apply procedure — it instructs the agent to read `.opencode/agents/opsx-implementer.md` and
      follow that file's body while ignoring its frontmatter, plus a short round-2 framing (you are
      the escalated second retry; the findings file is authoritative; do not redesign the plan).
      Verify the file is under 30 lines and contains the literal path
      `.opencode/agents/opsx-implementer.md`. Satisfies "The escalation agent delegates its prompt
      rather than duplicating it".
- [x] 3.2 Create `.opencode/agents/opsx-loop.md`: `mode: primary`, high-tier model, body = the
      body of `.claude/skills/opsx-loop/SKILL.md` (everything after its frontmatter) with three
      edits — preflight path becomes `.opencode/opsx-loop/preflight.sh`; the stage-map "Escalate by
      passing `model: \"opus\"`" sentence and the section 6 retry paragraph are rewritten to say
      round 1 spawns `opsx-implementer` and round 2 spawns `opsx-implementer-hard` with no model
      parameter; the `.claude/commands/opsx/` mention in section 0 becomes `.opencode/commands/`.
      Verify `grep -c '\.claude' .opencode/agents/opsx-loop.md` returns 0.
- [x] 3.3 Give `opsx-loop` its permission map: `task: {"*": "deny", "opsx-*": "allow"}`;
      `websearch: deny`; `webfetch: deny`; `question: allow`. **It must contain no `deny` value for
      `read`, `edit`, or `bash`** — OpenCode propagates parent denies into every subagent and that
      would break the loop. Verify with
      `sed -n '/^---$/,/^---$/p' .opencode/agents/opsx-loop.md | grep -E '^\s*(read|edit|bash):.*deny'`
      returning nothing. Satisfies "The orchestrator carries no deny rule that a subagent would
      inherit".
- [x] 3.4 Rewrite the human-gate section (section 4) of `.opencode/agents/opsx-loop.md` to keep the
      existing plain-text presentation (change id, artifact paths, requirement and task counts, the
      proposer's encoded assumptions) and then ask via the `question` tool with options approve
      (first, marked Recommended) / revise / abandon, falling back to plain text if `question` is
      denied, and never proceeding on silence or an ambiguous reply. Verify the section names all
      three options and the fallback. Satisfies "The human gate is a structured question with a
      plain-text fallback".
- [x] 3.5 Create `.opencode/commands/opsx-loop.md` with `description` and `agent: opsx-loop`,
      forwarding `$ARGUMENTS` as the goal. Because `opsx-loop` is a primary agent this runs the
      command in that agent. Verify the file exists and that no other toolkit-owned command file
      was added under `.opencode/commands/`. Satisfies "A single `/opsx-loop` command starts a run
      in the orchestrator".

**Group verification:** `opencode agent list` (or the equivalent listing) shows all seven `opsx-*`
agents with `opsx-loop` primary and the other six as subagents; `/opsx-loop` is offered as a
command.

## 4. OpenCode preflight

Depends on group 3 (checks for all seven agents).

- [x] 4.1 Create `.opencode/opsx-loop/preflight.sh` from `.claude/skills/opsx-loop/preflight.sh`,
      `chmod +x` it, and repoint its three path checks: `.opencode/commands/` must contain
      `opsx-<stage>.md` files (fail if absent), `.opencode/skills/openspec-*` (warn if absent), and
      all **seven** `.opencode/agents/opsx-*.md` files including `opsx-loop` and
      `opsx-implementer-hard` (fail if any absent). Verify `bash .opencode/opsx-loop/preflight.sh`
      exits 0 in this repo, and exits non-zero after temporarily renaming one agent file.
- [x] 4.2 Add two runtime assertions to the same script: every `model:` value found in the seven
      agent files appears in the output of the OpenCode model listing, and the OpenCode agent
      listing resolves all seven `opsx-*` agents. Both are failures, not warnings. If the
      `opencode` binary is not on PATH, warn and skip these two checks rather than failing. Verify
      by editing one agent's `model:` to a bogus id and confirming preflight exits non-zero naming
      that id, then reverting. Satisfies "OpenCode preflight verifies the runtime before a loop
      starts".

**Group verification:** `bash .opencode/opsx-loop/preflight.sh; echo $?` prints `0` in this repo
once an `anthropic` provider is configured for the `opencode` binary. Without one, `opencode models`
omits `anthropic/*` ids and the model-availability check in 4.2 fails as designed — that failure was
observed and accepted as environmental (see `verify-1.md`), not a defect in the script.

## 5. Installer target support

Independent of groups 2-4 in terms of code, but its end-to-end verification (5.5) needs the files
those groups produce. Only 5.1 needs group 1 (for the `.opencode/skills/` exclusion test to be
meaningful). All edits in this group are to `install.sh`.

- [x] 5.1 Parse `--target <value>` in the existing argument loop: accept `claude`, `opencode`,
      `both`, in any position, default `claude`; on an unknown value, a repeat, or a missing value,
      print the usage line to stderr and `exit 1` before touching the destination. Update the usage
      string. Verify `./install.sh --target vscode /tmp/x` exits 1 and `./install.sh /tmp/x` still
      installs only `.claude/`. Satisfies "The target is selected by a flag that defaults to the
      Claude Code distribution".
- [x] 5.2 Make the installed set target-dependent. Keep the existing Claude list (five agents +
      `find` over `.claude/skills/opsx-loop`) for `claude`. For `opencode`, build an **explicitly
      enumerated** list: the seven `.opencode/agents/opsx-*.md` files, `.opencode/commands/opsx-loop.md`,
      and a `find` scoped to `.opencode/opsx-loop/` only. Never `find` over `.opencode/` as a whole.
      `both` is the sorted union. Verify that with `--target opencode` the printed set contains no
      path under `.opencode/skills/` and no `.opencode/commands/opsx-` file other than
      `opsx-loop.md`. Satisfies "The installed set is determined by the selected target".
- [x] 5.3 Make the manifest per-distribution: `.claude/.opsx-install-manifest` and
      `.opencode/.opsx-install-manifest`, each written only when its distribution was installed and
      containing only that distribution's paths. Classification of a file must consult the manifest
      of that file's own distribution. Leave the untargeted distribution's manifest untouched.
      Verify by installing `--target claude` then `--target opencode` into the same scratch dir and
      checking each manifest's paths are confined to its own prefix and that the first is unchanged
      by the second run. Satisfies "Installer records provenance of every file it writes".
- [x] 5.4 Keep the classify-then-write discipline spanning the whole union: with `--target both`,
      classify every file of both distributions before any write, and let a single `customized`
      file in either block both. Also make the target-dependent tail work: `mkdir -p` only the
      needed directories, `chmod +x` the preflight script of each installed distribution, and print
      a next-step hint naming the installed target's preflight path. Verify by making one
      `.opencode/` destination file customized and confirming a `--target both` run without
      `--force` writes nothing at all, including nothing under `.claude/`.
- [x] 5.5 Run the regression sweep against a scratch destination and confirm every pre-existing
      `toolkit-install` scenario still holds under the default target, plus the new ones: empty
      install, immediate re-run is a clean no-op, self-install (`./install.sh --target both .`)
      classifies everything `identical`, a `customized` file refuses with `--force` in the hint, and
      a destination file at `.opencode/skills/openspec-propose/SKILL.md` survives untouched and
      unreported. Verify each by observing exit status and stdout/stderr.

**Group verification:** the 5.5 sweep passes, and `./install.sh --target both .` (self-install)
exits `0` reporting every file `identical`.

## 6. Documentation

Depends on groups 1-5. All edits are to `README.md`.

- [x] 6.1 Add the `.opencode/` tree to the Layout section beside the existing `.claude/` tree, and
      update the install and usage instructions to
      `./install.sh [--force] [--target claude|opencode|both] /path/to/repo`, then
      `bash .opencode/opsx-loop/preflight.sh`, then `opencode` + `/opsx-loop <goal>`. Verify the
      documented paths match what group 5 actually installs.
- [x] 6.2 Extend the model-allocation table with the concrete OpenCode `provider/model` ids chosen
      in 1.2, one row per agent including `opsx-implementer-hard`. This table is the single
      documented home for the ids. Verify each id in the table matches the `model:` value in the
      corresponding agent file.
- [x] 6.3 Extend the instruction-resolution table to cover both runtimes (Claude
      `.claude/commands/opsx/<stage>.md` vs OpenCode `.opencode/commands/opsx-<stage>.md`), and
      replace the "Escalation works by passing `model: \"opus\"` to the Agent tool" sentence with a
      single comparison covering both mechanisms — per-call override under Claude Code, the
      `opsx-implementer-hard` agent under OpenCode. Verify the README no longer implies the Agent
      tool override applies to OpenCode. Satisfies "Stage semantics are ported unchanged from the
      Claude Code distribution".
- [x] 6.4 State in the README that `.opencode/commands/opsx-<stage>.md` and
      `.opencode/skills/openspec-*/` come from `openspec init --tools opencode` in the target repo
      and are not installed by `install.sh`. Verify the statement matches 5.2's enumerated set.

**Group verification:** `bash .opencode/opsx-loop/preflight.sh` and
`bash .claude/skills/opsx-loop/preflight.sh` both exit `0`, and every path named in the README
exists in this repo.
