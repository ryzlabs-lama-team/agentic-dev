# toolkit-install Specification

## Purpose

Defines the clobber guard on the opsx-loop toolkit installer: how it classifies files already
present at the destination, when it refuses to write, and how it records the provenance of what it
wrote so a later upgrade can tell a stale copy apart from a user's customization.

The toolkit ships two distributions — Claude Code and OpenCode — selected by the installer's
`--target` flag, each with its own installed set and its own provenance manifest. The **installed
set** for a given target is defined normatively by "Requirement: The installed set is determined by
the selected target" below; this Purpose section does not restate that list and should not be
treated as authoritative if it ever appears to diverge from the requirement.

The installer's pre-existing behavior (its argument shape, which files it copies, the `chmod +x` on
`preflight.sh`, and the `.gitignore` append) is deliberately **not** restated here as requirements.
This capability specifies the clobber guard and nothing else.

## Requirements

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

For the `copilot` target the installed set SHALL be an **explicitly enumerated** list: the seven `.github/agents/opsx-*.agent.md` files and every regular file found by recursively enumerating the source `.github/opsx-loop/` directory at run time. The installer SHALL NOT build this list by recursively enumerating `.github/` as a whole.

For the `all` target the installed set SHALL be exactly the union of the `claude`, `opencode`, and `copilot` sets.

Files under `.opencode/commands/` other than `opsx-loop.md`, everything under `.opencode/skills/`,
everything under `.github/skills/`, everything under `.github/prompts/`, and repository-wide Copilot
instruction files are produced or owned outside this toolkit. They SHALL never be classified,
written, reported, or recorded in a manifest by the installer, including when present in the
installer's source tree.

#### Scenario: Copilot target installs exactly the enumerated files

- **WHEN** the installer runs with the `copilot` target against an empty destination
- **THEN** it creates the seven `.github/agents/opsx-*.agent.md` files and contents of `.github/opsx-loop/`, and creates nothing else under `.github/`

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
  the installer runs with the `opencode` or `all` target
- **THEN** no file under `.opencode/skills/` is classified, written, or recorded

#### Scenario: Claude target installed set is unchanged

- **WHEN** the installer runs with the `claude` target
- **THEN** the installed set is exactly the five `.claude/agents/opsx-*.md` files plus every regular
  file under the source `.claude/skills/opsx-loop/`, and no file under `.opencode/` is classified,
  written, or recorded

#### Scenario: OpenSpec GitHub assets are ignored

- **WHEN** the source contains `.github/skills/openspec-*` and `.github/prompts/opsx-*.prompt.md` files and the installer runs with `copilot` or `all`
- **THEN** none of those files is classified, written, or recorded

#### Scenario: All target installs all distributions

- **WHEN** the installer runs with the `all` target against an empty destination
- **THEN** it writes every member of the Claude, OpenCode, and Copilot installed sets

### Requirement: The target is selected by a flag that defaults to the Claude Code distribution

The installer SHALL accept a `--target <value>` flag whose value is one of `claude`, `opencode`,
`copilot`, or `all`, in any position relative to the destination argument and force flag. When
omitted, the target SHALL be `claude`, so every invocation that remains valid produces byte-for-byte
the same result.

An unrecognized value, including the previously accepted value `both`, a repeated flag, or a flag
with no value SHALL cause a usage message on stderr and exit `1` without modifying the destination.

For `all`, classification SHALL cover exactly the complete union of the Claude, OpenCode, and
Copilot distributions before any write; any `customized` file in that union SHALL block all three
distributions unless force is enabled.

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

#### Scenario: Removed target is rejected

- **WHEN** the installer is invoked with `--target both`
- **THEN** it prints usage to stderr, exits `1`, and modifies no destination file

#### Scenario: A conflict in one distribution blocks the other

- **WHEN** the target is `all`, force is disabled, and exactly one file in the `opencode`
  installed set is `customized`
- **THEN** no file of either distribution is written and the destination is byte-for-byte unchanged

#### Scenario: Next-step hint matches the target

- **WHEN** the installer completes successfully with the `opencode` target
- **THEN** the next-step it prints names `.opencode/opsx-loop/preflight.sh` rather than the Claude
  Code preflight path

#### Scenario: Copilot next-step hint is target-specific

- **WHEN** a Copilot-only install succeeds
- **THEN** the printed next step names the Copilot preflight command

### Requirement: Every destination file is classified before any file is written

The installer SHALL operate in two ordered passes. In the first pass it SHALL classify every file
in the installed set without modifying the destination in any way. In the second pass it SHALL
write files, set permissions, and update the manifest. No file content, permission, or manifest
change SHALL occur before the first pass has completed and the installer has decided to proceed.

Each destination path SHALL be classified as exactly one of:

- `new` — no file exists at the destination path.
- `identical` — the destination file's content is byte-for-byte equal to the source file's content.
- `stale` — the destination file differs from the source, a manifest entry exists for that path,
  and the destination file's current hash equals the hash recorded in that entry.
- `customized` — the destination file differs from the source and is not `stale`, including the
  case where no manifest entry exists for that path.

#### Scenario: Conflict detected in a later file

- **WHEN** the installed set contains a `customized` file that is enumerated after one or more
  `new` or `stale` files, and force is disabled
- **THEN** none of the earlier files are written, and the destination is byte-for-byte unchanged
  from before the run

#### Scenario: Classification of an untouched previously installed file

- **WHEN** a destination file was installed by a previous run, the source has since changed, and
  the destination file still hashes to its recorded manifest value
- **THEN** it is classified `stale`

#### Scenario: Classification of an edited file

- **WHEN** a destination file was installed by a previous run and has since been edited so that it
  matches neither the source nor its recorded manifest hash
- **THEN** it is classified `customized`

#### Scenario: Classification with no manifest entry

- **WHEN** a destination file exists, differs from the source, and has no entry in the manifest
- **THEN** it is classified `customized`

#### Scenario: Classification of an unchanged file

- **WHEN** a destination file is byte-for-byte equal to the source file
- **THEN** it is classified `identical` regardless of whether a manifest entry exists for it

### Requirement: Installer refuses to overwrite customized files without force

When at least one file in the installed set is classified `customized` and force is disabled, the
installer SHALL make no change to any destination file's content or permissions and no change to the
manifest, SHALL print every `customized` destination path (not only the first) to stderr, SHALL
print a hint naming the `--force` flag, and SHALL exit with status `1`.

#### Scenario: Single customized file blocks the install

- **WHEN** exactly one installed file is `customized` and force is disabled
- **THEN** the installer exits `1`, its stderr names that file's path, and no destination file is
  modified

#### Scenario: All conflicts are reported

- **WHEN** three installed files are `customized` and force is disabled
- **THEN** the installer's stderr names all three paths

#### Scenario: Refusal hint

- **WHEN** the installer refuses due to customized files
- **THEN** its stderr includes text naming `--force` as the way to proceed

#### Scenario: Manifest is not modified on refusal

- **WHEN** the installer refuses due to customized files and a manifest already exists
- **THEN** the manifest file's content is unchanged

### Requirement: Force flag permits overwriting customized files

Force SHALL be enabled by a `--force` flag, or its alias `-f`, accepted in any position relative to
the destination argument. When force is enabled, the installer SHALL proceed to write regardless of
any `customized` classification. It SHALL still report each overwritten `customized` path so the
overwrite is visible in the output.

#### Scenario: Forced install over a customized file

- **WHEN** an installed file is `customized` and force is enabled
- **THEN** the installer overwrites it with the source content and exits `0`

#### Scenario: Forced overwrite is announced

- **WHEN** the installer overwrites a `customized` file under force
- **THEN** its output names that path

### Requirement: Routine upgrades proceed without the force flag

Files classified `new` or `stale` SHALL be written without requiring force. The installer SHALL
report each written file with its classification so that a routine upgrade is visible, and SHALL
exit `0`.

#### Scenario: Stale file is upgraded

- **WHEN** a destination file is `stale` and force is disabled
- **THEN** the installer overwrites it with the source content, reports it as updated, and exits
  `0`

#### Scenario: New file is installed

- **WHEN** a destination path is `new`
- **THEN** the installer creates it with the source content and reports it

### Requirement: Re-running against an unmodified destination is a clean no-op

When every file in the installed set is classified `identical`, the installer SHALL report no
conflict, SHALL require no force flag, and SHALL exit `0`. It SHALL leave every destination file's
content unchanged.

#### Scenario: Immediate re-run

- **WHEN** the installer runs successfully and is then run again against the same destination with
  no intervening edit to either source or destination
- **THEN** the second run exits `0`, reports no conflict, and requires no flag

#### Scenario: Self install

- **WHEN** the installer runs with a destination equal to its own source directory
- **THEN** every file classifies `identical`, the run exits `0`, and no file is corrupted or
  truncated

### Requirement: Installer records provenance of every file it writes

On every successful install the installer SHALL write one manifest per installed distribution under
the destination: `.claude/.opsx-install-manifest`, `.opencode/.opsx-install-manifest`, or
`.github/.opsx-install-manifest`. A multi-distribution target SHALL write the manifest for every
selected distribution. Each manifest SHALL cover only its own distribution's installed set and
SHALL be rewritten in full on success.

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

#### Scenario: Copilot manifest is scoped to GitHub toolkit files

- **WHEN** a Copilot install succeeds
- **THEN** `.github/.opsx-install-manifest` records every Copilot installed-set file and records no `.github/skills/`, `.github/prompts/`, Claude, or OpenCode path

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

- **WHEN** the installer runs with the `all` target and completes successfully
- **THEN** the Claude, OpenCode, and Copilot manifests contain only paths owned by their respective distributions

#### Scenario: All target writes three manifests

- **WHEN** an `all` install succeeds
- **THEN** each of the three distribution manifests exists and contains only paths owned by that distribution

### Requirement: Installer degrades gracefully without a sha256 tool

The installer SHALL compute sha256 hashes using whichever of the available system tools it finds.
When no sha256 tool is available, the installer SHALL NOT abort; it SHALL fall back to classifying
every destination file by direct comparison against the source, treating equal files as `identical`
and all other existing files as `customized`, and SHALL skip writing the manifest.

#### Scenario: No hashing tool on PATH

- **WHEN** no sha256 tool is available and the destination is empty
- **THEN** the installer installs all files and exits `0` rather than aborting

#### Scenario: Fallback classification is conservative

- **WHEN** no sha256 tool is available and a destination file differs from its source
- **THEN** that file is classified `customized` and blocks the install unless force is enabled

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

#### Scenario: OpenSpec GitHub files survive forced all install

- **WHEN** the destination contains GitHub OpenSpec skills and prompts and the installer runs with `--target all --force`
- **THEN** those files retain their original content and are not reported

#### Scenario: User-added Copilot agent survives

- **WHEN** `.github/agents/my-agent.agent.md` has no source counterpart and a Copilot install runs
- **THEN** the file remains unchanged and is not reported
