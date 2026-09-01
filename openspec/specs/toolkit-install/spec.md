# toolkit-install Specification

## Purpose

Defines the clobber guard on the opsx-loop toolkit installer: how it classifies files already
present at the destination, when it refuses to write, and how it records the provenance of what it
wrote so a later upgrade can tell a stale copy apart from a user's customization.

Throughout this capability the **installed set** means the files the installer copies into the
destination on a given run — the five `.claude/agents/opsx-*.md` agent files plus every regular file
found by recursively enumerating the source `.claude/skills/opsx-loop/` directory at run time — each
written to the destination path mirroring its path under the source.

The installer's pre-existing behavior (its argument shape, which files it copies, the `chmod +x` on
`preflight.sh`, and the `.gitignore` append) is deliberately **not** restated here as requirements.
This capability specifies the clobber guard and nothing else.

## Requirements

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

On every successful install the installer SHALL write a manifest at
`.claude/.opsx-install-manifest` under the destination. The manifest SHALL be plain text with one
line per file in the installed set, each line containing the sha256 hash of the installed content
followed by two spaces and the file's path relative to the destination. The manifest SHALL record
every file in the installed set, including files that were already `identical` and files that were
overwritten under force. The manifest SHALL NOT be one of the files the installer installs, and the
installer SHALL NOT add it to the destination's `.gitignore`.

#### Scenario: Manifest written on first install

- **WHEN** the installer completes successfully against a destination that had no manifest
- **THEN** `.claude/.opsx-install-manifest` exists and contains one line per installed file

#### Scenario: Manifest refreshed after a forced overwrite

- **WHEN** the installer overwrites a `customized` file under force and completes successfully
- **THEN** that file's manifest entry records the hash of the newly written content, so an
  immediately following run classifies the file `identical` rather than `customized`

#### Scenario: Manifest covers identical files

- **WHEN** a file was already `identical` and the install completes successfully
- **THEN** the manifest contains an entry for that file

#### Scenario: Manifest is not gitignored

- **WHEN** the installer completes successfully against a git repository
- **THEN** the destination `.gitignore` contains no entry for the manifest

#### Scenario: Manifest is not itself installed

- **WHEN** the installer runs
- **THEN** the manifest path is absent from the set of files it classifies and reports

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

#### Scenario: User file under the skill directory

- **WHEN** the destination contains `.claude/skills/opsx-loop/my-notes.md`, which has no
  counterpart in the source, and the installer runs
- **THEN** that file still exists with unchanged content after the run

#### Scenario: User file survives a forced install

- **WHEN** the destination contains a file absent from the source and the installer runs with force
  enabled
- **THEN** that file still exists with unchanged content after the run
