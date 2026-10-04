# Skill Routers

This directory demonstrates a two-layer skill layout that keeps an agent's
always-available skill catalog small while retaining a larger library of
specialized instructions.

- **Routers** are small `SKILL.md` files, such as `skills/terraform/SKILL.md`.
  Install these in a tool's discovered `skills/` directory. Their frontmatter
  is loaded into the skill catalog, so the agent knows when a router applies.
- **Routed skills** are the full, specialized skill files under
  `skills-library/`.
  Do not install these in a discovered `skills/` directory. The router directs
  the agent to read the one routed skill relevant to the current task.

This separates discovery from resolution. The agent sees the concise router
descriptions at session start, then receives the detailed instructions only
after a matching task triggers the router. It avoids loading frontmatter for
every specialized skill on every session.

## Layout

```text
skills/
  terraform/
    SKILL.md                  # Installed router

skills-library/
  terraform/
    provider-configuration/
      SKILL.md                # Routed skill, read only when needed
    provider-resources/
      SKILL.md
```

The example content in this repository is organized as:

```text
skill-routers/
  skills/                     # Install these as discovered skills
  skills-library/             # Keep these outside discovered skill locations
```

The router must name an unambiguous path to its routed library and instruct
the agent to use its file-reading tool, rather than its skill-loading tool, to
open the selected routed `SKILL.md`.

## Where Routed Skills Live

Routed skills can be stored in either location:

- **Project-local:** Keep the library in the repository, but outside the
  tool's discovered `skills/` directory, for example
  `.agent-library/skills/terraform/`. Commit it with the project. Agents that
  can read the repository can resolve it without extra filesystem access.
- **Global:** Keep the library in a user-owned directory, for example
  `~/.agent-libraries/skills/terraform/`. This makes a shared library available
  across projects, but the tool must explicitly be allowed to read that
  directory. A router alone does not grant filesystem access.

Use absolute paths in a global router. For a project-local library, make the
relative-path base explicit. The routers in this repository use paths relative
to their own `SKILL.md` file, for example
`../../skills-library/terraform/` from `skills/terraform/SKILL.md`.

## Tool Configuration

Install only the router directories in the locations each tool discovers as
skills. Keep the routed-library root separate from those locations.

### Claude Code

Install routers in `.claude/skills/<router>/SKILL.md` for a project or
`~/.claude/skills/<router>/SKILL.md` globally. Claude Code will catalog the
router, and the router can direct Claude to read an out-of-tree routed skill.

For a global routed library, grant Claude Code read access to the library
directory. The simplest session-scoped option is to start Claude Code with
`--add-dir /absolute/path/to/skills-library`; `/add-dir` can add it during a
session. `--add-dir` grants file access, but does not itself make arbitrary
files into skills. If permissions are managed in `settings.json`, allow the
`Read` tool for the library path instead. Do not place the routed library under
`.claude/skills/` or `~/.claude/skills/`, because Claude Code will discover
each routed `SKILL.md` as a separate skill.

Reference: [Claude Code skills](https://code.claude.com/docs/en/skills) and
[Claude Code permissions](https://code.claude.com/docs/en/permissions).

### OpenCode

Install routers in one of OpenCode's discovered skill locations, normally
`.opencode/skills/<router>/SKILL.md` for a project or
`~/.config/opencode/skills/<router>/SKILL.md` globally. OpenCode also supports
the compatible `.claude/skills/` and `.agents/skills/` locations.

For a global routed library, configure permission for the agent's file-reading
tool to read the library path. This repository instead demonstrates a
project-local library: its routers resolve paths such as
`../../skills-library/engineering-practices/` relative to their own
`SKILL.md` files. Keep either kind of library outside all OpenCode-discovered
skill directories so only the router's frontmatter is added to the `skill`
tool catalog. If the router itself is blocked, allow it with OpenCode's
`permission.skill` configuration; that permission controls loading the router,
not reading the routed files.

Reference: [OpenCode agent skills](https://opencode.ai/docs/skills/) and
[OpenCode permissions](https://opencode.ai/docs/permissions/).

### GitHub Copilot

Install routers in `.github/skills/<router>/SKILL.md`,
`.agents/skills/<router>/SKILL.md`, or `.claude/skills/<router>/SKILL.md` for
a project. For a personal installation, use `~/.copilot/skills/<router>/` or
`~/.agents/skills/<router>/`.

For a global routed library, make the directory readable to Copilot CLI with
`--add-dir /absolute/path/to/skills-library` at launch or `/add-dir` in a
session. To retain that path approval, add its absolute path to the repository
entry's `allowed_directories` in `~/.copilot/permissions-config.json`.
`--add-dir`/`allowed_directories` grant path access; they do not discover a
generic routed library as a skill catalog. Do not register the routed-library
directory with `COPILOT_SKILLS_DIRS`, `skillDirectories`, or `copilot skill
add`, since that would cause Copilot to discover its routed skills.

Reference: [About agent skills](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills),
[adding Copilot CLI skills](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills),
and the [Copilot CLI configuration reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference#permissions-configjson).

## Authoring Rules

1. Give the router a broad, precise `description` that covers the whole
   library's trigger space.
2. Keep the router focused on selecting and opening a routed skill.
3. Keep each routed skill narrowly scoped and place supporting reference files
   beside it.
4. Do not add the routed-library root to a tool's automatic skill-discovery
   paths.
5. Verify a fresh session lists the router but not individual routed skills,
   then verify a matching request causes the agent to read the intended file.
