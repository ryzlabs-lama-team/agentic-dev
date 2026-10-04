## ADDED Requirements

### Requirement: The installed set is determined by the selected target

The **installed set** SHALL be a function of the selected target, and this requirement SHALL be the
authoritative definition of it for every other requirement in this capability. Each member of the
installed set is written to the destination path mirroring its path under the source.

For the `claude` target the installed set SHALL be the five `.claude/agents/opsx-*.md` agent files
plus every regular file found by recursively enumerating the source `.claude/skills/opsx-loop/`
directory at run time.

For the `opencode` target the installed set SHALL be an **explicitly enumerated** list: the seven
`.opencode/agents/opsx-*.md` agent files, `.opencode/commands/opsx-loop.md`, and every regular file
found by recursively enumerating the source `.opencode/opsx-loop/` directory at run time. The
installer SHALL NOT build this list by recursively enumerating `.opencode/` as a whole.

For the `both` target the installed set SHALL be the union of the two.

Files under `.opencode/commands/` other than `opsx-loop.md`, and everything under
`.opencode/skills/`, are produced in the target repo by `openspec init --tools opencode` and belong
to OpenSpec, not to this toolkit. They SHALL never be classified, written, reported, or recorded in
a manifest by the installer — including when they are present in the installer's own source tree.

#### Scenario: OpenCode target installs exactly the enumerated files

- **WHEN** the installer runs with the `opencode` target against an empty destination
- **THEN** it creates the seven `.opencode/agents/opsx-*.md` files, `.opencode/commands/opsx-loop.md`,
  and the contents of `.opencode/opsx-loop/`, and creates nothing else under `.opencode/`

#### Scenario: OpenSpec-generated command files are ignored in the source

- **WHEN** the installer's source tree contains `.opencode/commands/opsx-explore.md` and other
  OpenSpec-generated stage commands, and the installer runs with the `opencode` target
- **THEN** none of those files appear in the installer's classification output, none is written to
  the destination, and none appears in any manifest

#### Scenario: OpenSpec-generated skills are ignored in the source

- **WHEN** the installer's source tree contains `.opencode/skills/openspec-*/SKILL.md` files and
  the installer runs with the `opencode` or `both` target
- **THEN** no file under `.opencode/skills/` is classified, written, or recorded

#### Scenario: Claude target installed set is unchanged

- **WHEN** the installer runs with the `claude` target
- **THEN** the installed set is exactly the five `.claude/agents/opsx-*.md` files plus every regular
  file under the source `.claude/skills/opsx-loop/`, and no file under `.opencode/` is classified,
  written, or recorded

#### Scenario: Both target installs the union

- **WHEN** the installer runs with the `both` target against an empty destination
- **THEN** it writes every member of the `claude` installed set and every member of the `opencode`
  installed set

### Requirement: The target is selected by a flag that defaults to the Claude Code distribution

The installer SHALL accept a `--target <value>` flag whose value is one of `claude`, `opencode`, or
`both`, in any position relative to the destination argument and relative to the force flag. When
the flag is omitted the target SHALL be `claude`, so that every invocation that was valid before
this flag existed continues to produce byte-for-byte the same result.

An unrecognized target value, a repeated `--target` flag, or a `--target` flag with no value SHALL
cause the installer to print a usage message to stderr and exit `1` without modifying the
destination.

When the target is `both`, the two-pass discipline SHALL span both distributions: the installer
SHALL classify the complete union before writing anything, and a `customized` file in either
distribution SHALL block the writing of both unless force is enabled.

#### Scenario: Omitted flag preserves current behavior

- **WHEN** the installer is invoked with only a destination argument
- **THEN** it behaves exactly as it did before the flag existed, installing only the `claude`
  installed set

#### Scenario: Flag position does not matter

- **WHEN** the installer is invoked with `--target opencode` before the destination argument, and
  again with it after the destination argument
- **THEN** both invocations produce the same result

#### Scenario: Invalid target is rejected

- **WHEN** the installer is invoked with `--target vscode`
- **THEN** it prints a usage message to stderr, exits `1`, and modifies no file at the destination

#### Scenario: A conflict in one distribution blocks the other

- **WHEN** the target is `both`, force is disabled, and exactly one file in the `opencode`
  installed set is `customized`
- **THEN** no file of either distribution is written and the destination is byte-for-byte unchanged

#### Scenario: Next-step hint matches the target

- **WHEN** the installer completes successfully with the `opencode` target
- **THEN** the next-step it prints names `.opencode/opsx-loop/preflight.sh` rather than the Claude
  Code preflight path

## MODIFIED Requirements

### Requirement: Installer records provenance of every file it writes

On every successful install the installer SHALL write one manifest per installed distribution under
the destination: `.claude/.opsx-install-manifest` when the `claude` distribution was installed, and
`.opencode/.opsx-install-manifest` when the `opencode` distribution was installed. With the `both`
target it SHALL write both. Each manifest SHALL cover only its own distribution's portion of the
installed set, and SHALL be rewritten in full on each successful run.

Each manifest SHALL be plain text with one line per file in that distribution's installed set, each
line containing the sha256 hash of the installed content followed by two spaces and the file's path
relative to the destination. Each manifest SHALL record every file in that distribution's installed
set, including files that were already `identical` and files that were overwritten under force. A
manifest SHALL NOT be one of the files the installer installs, and the installer SHALL NOT add any
manifest to the destination's `.gitignore`. The installer SHALL NOT create or modify the manifest of
a distribution that the selected target did not install.

Classification of a destination file SHALL consult the manifest belonging to that file's own
distribution.

#### Scenario: Manifest written on first install

- **WHEN** the installer completes successfully against a destination that had no manifest
- **THEN** a manifest exists for each installed distribution and contains one line per file that
  distribution installed

#### Scenario: Manifest refreshed after a forced overwrite

- **WHEN** the installer overwrites a `customized` file under force and completes successfully
- **THEN** that file's manifest entry records the hash of the newly written content, so an
  immediately following run classifies the file `identical` rather than `customized`

#### Scenario: Manifest covers identical files

- **WHEN** a file was already `identical` and the install completes successfully
- **THEN** that distribution's manifest contains an entry for that file

#### Scenario: Manifest is not gitignored

- **WHEN** the installer completes successfully against a git repository
- **THEN** the destination `.gitignore` contains no entry for any manifest

#### Scenario: Manifest is not itself installed

- **WHEN** the installer runs
- **THEN** no manifest path appears in the set of files it classifies and reports

#### Scenario: Untargeted distribution's manifest is untouched

- **WHEN** a destination already has a `.claude/.opsx-install-manifest` and the installer runs with
  the `opencode` target
- **THEN** `.claude/.opsx-install-manifest` is unchanged and `.opencode/.opsx-install-manifest` is
  written

#### Scenario: Each manifest is scoped to its own distribution

- **WHEN** the installer runs with the `both` target and completes successfully
- **THEN** `.claude/.opsx-install-manifest` contains only paths under `.claude/` and
  `.opencode/.opsx-install-manifest` contains only paths under `.opencode/`

### Requirement: Files present at the destination but absent from the source are preserved

The installer SHALL NOT delete or modify any file under the destination that is not in the
installed set. In particular, user-added files inside the destination `.claude/skills/opsx-loop/`
directory SHALL survive every install, whether or not force is enabled.

The same guarantee SHALL hold under `.opencode/`. Because `.opencode/commands/` and
`.opencode/skills/` at the destination hold files that `openspec init --tools opencode` generated
and that this toolkit does not own, those files SHALL survive every install unchanged, whether or
not force is enabled, and SHALL never appear in the installer's classification output.

#### Scenario: User file under the skill directory

- **WHEN** the destination contains `.claude/skills/opsx-loop/my-notes.md`, which has no
  counterpart in the source, and the installer runs
- **THEN** that file still exists with unchanged content after the run

#### Scenario: User file survives a forced install

- **WHEN** the destination contains a file absent from the source and the installer runs with force
  enabled
- **THEN** that file still exists with unchanged content after the run

#### Scenario: OpenSpec-generated destination files survive

- **WHEN** the destination contains `.opencode/commands/opsx-propose.md` and
  `.opencode/skills/openspec-propose/SKILL.md`, and the installer runs with the `opencode` target
- **THEN** both files exist with unchanged content after the run and neither was reported

#### Scenario: OpenSpec-generated destination files survive a forced install

- **WHEN** the destination contains OpenSpec-generated files under `.opencode/skills/` and the
  installer runs with force enabled and the `both` target
- **THEN** those files exist with unchanged content after the run
