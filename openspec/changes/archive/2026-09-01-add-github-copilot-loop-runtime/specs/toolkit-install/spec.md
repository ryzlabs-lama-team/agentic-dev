## MODIFIED Requirements

### Requirement: The installed set is determined by the selected target

The **installed set** SHALL be a function of the selected target, and this requirement SHALL be the authoritative definition of it for every other requirement in this capability. Each member of the installed set is written to the destination path mirroring its path under the source.

For the `claude` target the installed set SHALL be the five `.claude/agents/opsx-*.md` agent files plus every regular file found by recursively enumerating the source `.claude/skills/opsx-loop/` directory at run time.

For the `opencode` target the installed set SHALL be an **explicitly enumerated** list: the seven `.opencode/agents/opsx-*.md` agent files, `.opencode/commands/opsx-loop.md`, and every regular file found by recursively enumerating the source `.opencode/opsx-loop/` directory at run time. The installer SHALL NOT build this list by recursively enumerating `.opencode/` as a whole.

For the `copilot` target the installed set SHALL be an **explicitly enumerated** list: the seven `.github/agents/opsx-*.agent.md` files and every regular file found by recursively enumerating the source `.github/opsx-loop/` directory at run time. The installer SHALL NOT build this list by recursively enumerating `.github/` as a whole.

For the `all` target the installed set SHALL be exactly the union of the `claude`, `opencode`, and `copilot` sets.

Files under `.opencode/commands/` other than `opsx-loop.md`, everything under `.opencode/skills/`, everything under `.github/skills/`, everything under `.github/prompts/`, and repository-wide Copilot instruction files are produced or owned outside this toolkit. They SHALL never be classified, written, reported, or recorded in a manifest by the installer, including when present in the installer's source tree.

#### Scenario: Copilot target installs exactly the enumerated files
- **WHEN** the installer runs with the `copilot` target against an empty destination
- **THEN** it creates the seven `.github/agents/opsx-*.agent.md` files and contents of `.github/opsx-loop/`, and creates nothing else under `.github/`

#### Scenario: OpenCode target installs exactly the enumerated files
- **WHEN** the installer runs with the `opencode` target against an empty destination
- **THEN** it creates the seven `.opencode/agents/opsx-*.md` files, `.opencode/commands/opsx-loop.md`, and the contents of `.opencode/opsx-loop/`, and creates nothing else under `.opencode/`

#### Scenario: OpenSpec-generated command files are ignored in the source
- **WHEN** the source contains `.opencode/commands/opsx-explore.md` and other OpenSpec-generated stage commands and the installer runs with `opencode` or `all`
- **THEN** none of those files is classified, written, reported, or recorded

#### Scenario: OpenSpec-generated skills are ignored in the source
- **WHEN** the source contains `.opencode/skills/openspec-*/SKILL.md` and the installer runs with `opencode` or `all`
- **THEN** no file under `.opencode/skills/` is classified, written, reported, or recorded

#### Scenario: OpenSpec GitHub assets are ignored
- **WHEN** the source contains `.github/skills/openspec-*` and `.github/prompts/opsx-*.prompt.md` files and the installer runs with `copilot` or `all`
- **THEN** none of those files is classified, written, reported, or recorded

#### Scenario: Claude target installed set is unchanged
- **WHEN** the installer runs with the `claude` target
- **THEN** the installed set is exactly the five `.claude/agents/opsx-*.md` files plus every regular file under `.claude/skills/opsx-loop/`, and no OpenCode or Copilot file is classified, written, or recorded

#### Scenario: Both target installs the union
- **WHEN** the installer is invoked with the removed target value `both`
- **THEN** no installed set is selected and the invocation is rejected without writing any file

#### Scenario: All target installs all distributions
- **WHEN** the installer runs with the `all` target against an empty destination
- **THEN** it writes every member of the Claude, OpenCode, and Copilot installed sets

### Requirement: The target is selected by a flag that defaults to the Claude Code distribution

The installer SHALL accept a `--target <value>` flag whose value is one of `claude`, `opencode`, `copilot`, or `all`, in any position relative to the destination argument and force flag. When omitted, the target SHALL be `claude`, so every invocation that remains valid produces byte-for-byte the same result.

An unrecognized value, including the previously accepted value `both`, a repeated flag, or a flag with no value SHALL cause a usage message on stderr and exit `1` without modifying the destination. For `all`, classification SHALL cover exactly the complete union of the Claude, OpenCode, and Copilot distributions before any write; any `customized` file in that union SHALL block all three distributions unless force is enabled.

#### Scenario: Omitted flag preserves current behavior
- **WHEN** the installer is invoked with only a destination argument
- **THEN** it installs only the Claude set exactly as before

#### Scenario: Copilot target is accepted in either position
- **WHEN** `--target copilot` is placed before the destination and then after it
- **THEN** both invocations produce the same Copilot-only result

#### Scenario: Flag position does not matter
- **WHEN** `--target opencode` is placed before the destination and then after it
- **THEN** both invocations produce the same result

#### Scenario: Invalid target is rejected
- **WHEN** the installer is invoked with an unrecognized target such as `vscode`
- **THEN** it prints usage to stderr, exits `1`, and modifies no destination file

#### Scenario: Removed target is rejected
- **WHEN** the installer is invoked with `--target both`
- **THEN** it prints usage to stderr, exits `1`, and modifies no destination file

#### Scenario: Conflict in all target is atomic
- **WHEN** target `all` contains one customized Copilot file and force is disabled
- **THEN** no selected distribution is written and the destination remains byte-for-byte unchanged

#### Scenario: A conflict in one distribution blocks the other
- **WHEN** target `all` includes a customized OpenCode file and force is disabled
- **THEN** no Claude, OpenCode, or Copilot file is written and the destination remains byte-for-byte unchanged

#### Scenario: Copilot next-step hint is target-specific
- **WHEN** a Copilot-only install succeeds
- **THEN** the printed next step names the Copilot preflight command

#### Scenario: Next-step hint matches the target
- **WHEN** an OpenCode-only install succeeds
- **THEN** the printed next step names `.opencode/opsx-loop/preflight.sh`

### Requirement: Installer records provenance of every file it writes

On every successful install the installer SHALL write one manifest per installed distribution: `.claude/.opsx-install-manifest`, `.opencode/.opsx-install-manifest`, or `.github/.opsx-install-manifest`. A multi-distribution target SHALL write the manifest for every selected distribution. Each manifest SHALL cover only its own distribution's installed set and SHALL be rewritten in full on success.

Each manifest SHALL be plain text with one line per installed-set file, containing the sha256 hash, two spaces, and the destination-relative path. It SHALL include identical and force-overwritten files. A manifest SHALL NOT be installed or gitignored, and an unselected distribution's manifest SHALL remain untouched. Classification SHALL consult the manifest belonging to the file's distribution.

#### Scenario: Copilot manifest is scoped to GitHub toolkit files
- **WHEN** a Copilot install succeeds
- **THEN** `.github/.opsx-install-manifest` records every Copilot installed-set file and records no `.github/skills/`, `.github/prompts/`, Claude, or OpenCode path

#### Scenario: Manifest written on first install
- **WHEN** an install succeeds against a destination with no selected-distribution manifest
- **THEN** each selected distribution has a manifest with one line per file in its installed set

#### Scenario: Manifest refreshed after a forced overwrite
- **WHEN** a customized file is overwritten under force and installation succeeds
- **THEN** its manifest records the new installed-content hash so an immediate rerun classifies it as identical

#### Scenario: Manifest covers identical files
- **WHEN** an installed-set file was already identical and installation succeeds
- **THEN** its distribution manifest contains an entry for that file

#### Scenario: Manifest is not gitignored
- **WHEN** installation succeeds in a Git repository
- **THEN** no distribution manifest is added to `.gitignore`

#### Scenario: Manifest is not itself installed
- **WHEN** the installer classifies the selected installed set
- **THEN** no manifest path is classified or reported as an installed file

#### Scenario: Untargeted distribution's manifest is untouched
- **WHEN** a Claude manifest exists and an OpenCode-only install succeeds
- **THEN** the Claude manifest remains unchanged and the OpenCode manifest is written

#### Scenario: Each manifest is scoped to its own distribution
- **WHEN** an `all` install succeeds
- **THEN** the Claude, OpenCode, and Copilot manifests contain only `.claude/`, `.opencode/`, and `.github/` paths, respectively

#### Scenario: All target writes three manifests
- **WHEN** an `all` install succeeds
- **THEN** each of the three distribution manifests exists and contains only paths owned by that distribution

#### Scenario: Copilot-only install leaves other manifests untouched
- **WHEN** Claude and OpenCode manifests exist and a Copilot-only install succeeds
- **THEN** both existing manifests are unchanged and the Copilot manifest is rewritten

### Requirement: Files present at the destination but absent from the source are preserved

The installer SHALL NOT delete or modify any destination file outside the selected installed set, whether or not force is enabled. User-added files in toolkit directories SHALL survive.

OpenSpec-generated files under `.opencode/commands/`, `.opencode/skills/`, `.github/skills/`, and `.github/prompts/`, plus repository-wide Copilot instruction files, SHALL survive every applicable install unchanged and SHALL never appear in classification output.

#### Scenario: OpenSpec GitHub files survive forced all install
- **WHEN** the destination contains GitHub OpenSpec skills and prompts and the installer runs with `--target all --force`
- **THEN** those files retain their original content and are not reported

#### Scenario: User file under the skill directory
- **WHEN** `.claude/skills/opsx-loop/my-notes.md` has no source counterpart and an install runs
- **THEN** the file remains with unchanged content

#### Scenario: User file survives a forced install
- **WHEN** a destination file absent from the source exists and force is enabled
- **THEN** the file remains with unchanged content

#### Scenario: OpenSpec-generated destination files survive
- **WHEN** the destination contains `.opencode/commands/opsx-propose.md` and `.opencode/skills/openspec-propose/SKILL.md` and an OpenCode-containing target runs
- **THEN** both files remain unchanged and neither is reported

#### Scenario: OpenSpec-generated destination files survive a forced install
- **WHEN** OpenSpec-generated files exist under `.opencode/skills/` and a force-enabled `all` install runs
- **THEN** those files remain unchanged and are not reported

#### Scenario: User-added Copilot agent survives
- **WHEN** `.github/agents/my-agent.agent.md` has no source counterpart and a Copilot install runs
- **THEN** the file remains unchanged and is not reported
