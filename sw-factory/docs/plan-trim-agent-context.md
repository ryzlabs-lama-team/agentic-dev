# Plan: trim sw-factory subagent startup context

Status: proposed, not started (2026-11-11)

## Context
The goal is to cut the tokens each sw-factory agent spends before it does any work. I measured the first request of 178 subagents from a real factory run (transcripts under `~/.claude/projects/<project>/<session>/subagents/`):

| agent | starting context (median) |
|---|---|
| sw-architect | ~17.3k |
| sw-builder | ~16.9k |
| sw-planner | ~15.6k |
| sw-qa / po | ~14.4k |
| opsx-* | ~13–14k |
| sw-manager (main session) | ~24k |

So the baseline is 13–24k tokens, not 40k. A 40k figure probably also counts the agent's first file reads.

**Tools are already restricted.** Every agent has a `tools:` allowlist, and MCP tools don't reach subagents: only WebFetch and WebSearch showed up as deferred tools for sw-architect.

The remaining context breaks down as:
- Claude Code base prompt and tool schemas: fixed.
- The agent's own prompt: 5–19 KB.
- **`skill_listing`: ~19k chars, about 5k tokens per agent.** It lists every installed skill, including dataviz, docx, pptx, xlsx, artifact-*, schedule and loop. This is the biggest piece we can control.
- gitStatus: ~0.7k tokens. User CLAUDE.md: ~0.25k tokens.
- sw-manager only: claude.ai connector MCP instructions and deferred tool names (~1k tokens).

po, sw-architect, sw-builder, sw-planner and sw-qa list the `Skill` tool, but none of their prompts names a skill to use. The only skill they need is the `engineering-practices` router.

**Caveat:** the Claude Code docs don't say whether removing `Skill` from `tools:` also removes the skill listing. They also don't say whether `skills:` preloading works without the `Skill` tool. Step 2 checks both with real numbers before we go further.

## Plan

### Step 1: Preload engineering-practices instead of listing every skill
Files: `.claude/agents/{po,sw-architect,sw-builder,sw-planner,sw-qa}.md`.

The sw-* agents keep access to the `engineering-practices` router (`~/.claude/skills/engineering-practices/SKILL.md`, 4.6k chars ≈ 1.2k tokens). They get it by preloading rather than through the Skill tool's full listing (~19k chars ≈ 5k tokens). The router only points to reference skills under `~/.aitools/skills/engineering-practices/`, which the agent opens with `Read`, so the `Skill` tool isn't needed to follow it.
- Remove `Skill` from `tools:` and add `skills: [engineering-practices]` to the frontmatter of all five.
- Add one line to each agent body: "The `engineering-practices` router is preloaded. Consult it before non-trivial work and open the reference it points to with Read."
- Expected net saving: about 3.8k tokens per spawn.
- Fallback if Step 2 shows that preloading needs the `Skill` tool, or that the listing doesn't depend on it: put `Skill` back, drop `skills:`, and rely on Step 3 to shrink the listing.
- The router is a user-level skill that `install.sh` doesn't ship. Check in Step 2 that a target repo without it still spawns cleanly. The missing skill should just be skipped.
- Remove `ToolSearch` from `sw-planner`. Nothing on its list is deferred, so it has nothing to search for.
- Leave `sw-manager` as it is. It needs `Skill` for the opsx-loop track, plus `SendMessage` and `ToolSearch`.
- Leave `sw-builder`'s `NotebookEdit` and `ToolSearch`. Notebook projects may need them.
- Update `tests/guard-test.sh` or `README.md` only if either one lists the agents' tools.

### Step 2: Measure
In a smoke project, reinstall with `./install.sh --force <repo>`, then spawn po or sw-qa once.
- Read the new subagent transcript and take the token count of its first request: `usage` on the first assistant record, plus the `attachment` types listed before it.
- Success means three things: the `skill_listing` attachment is gone, the router text is in the first request, and the baseline drops by about 3.8k.
- Also ask the agent to name the engineering-practices reference it would use for a test task. This confirms it can actually follow the router.
- If preloading fails or the listing is still there, apply the Step 1 fallback.

### Step 3: Opt-in project-wide trims via `install.sh --lean`
These settings apply to every session in the target repo, including the user's own sessions, so they are opt-in rather than the default.
- Add a `--lean` flag to `install.sh`. It merges keys into the target's `.claude/settings.json` using the same jq/python3 merge the hook wiring already uses (`install.sh:86-120`): add a generic `merge_setting <key> <json>` helper beside `hook_entry`.
- Keys to merge:
  - `"disableClaudeAiConnectors": true`: removes the Atlassian, Docs and other connector instructions from sw-manager.
  - `"disableBundledSkills": true` and `"enabledPlugins": {"anthropic-skills@<marketplace>": false}`: shrink the skill listing for sw-manager. Confirm the exact plugin id with `/plugin` first.
  - `"skillListingMaxDescChars": 250`: cap each remaining description.
- Leave out `includeGitInstructions: false`. sw-manager commits per phase and needs the git instructions.
- Leave out `omitClaudeMd`. The target repo's CLAUDE.md has build and test commands that sw-builder and sw-qa need.
- Document `--lean` and the measured savings in `README.md`.

## Out of scope
- The opsx-* agents in `openspec-agents/` are not changed.

## Verification
- `bash tests/guard-test.sh` and `bash tests/usage-test.sh` still pass.
- Smoke run, as in Step 2: confirm the first-request token count per agent type has dropped. Optionally run `python3 .claude/sw-factory/usage.py report --by agent` before and after to compare per-agent totals.
- After `--lean`, `jq . .claude/settings.json` shows the merged keys and the existing hooks unchanged. Running install twice changes nothing the second time (it prints "kept").
