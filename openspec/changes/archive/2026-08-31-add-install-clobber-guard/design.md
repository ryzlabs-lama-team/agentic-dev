## Context

`install.sh` is a single ~35-line bash script with `set -euo pipefail` (`install.sh:4`). It copies
5 agent files in a loop (`:20-23`) and the whole skill directory with one `cp -R` (`:25`), then
`chmod +x` (`:26`) and appends to `.gitignore` (`:29-32`). Argument handling is positional-only
(`:9-16`). See proposal.md — Why for motivation, and `specs/toolkit-install/spec.md` for the
behavior contract.

Two environment constraints shape everything below:

- **The installer runs on the user's machine, not ours.** macOS ships `shasum` and bash **3.2**;
  Linux ships `sha256sum` and bash 4+. The script must work on both, which rules out bash 4
  features — no associative arrays (`declare -A`), no `mapfile`/`readarray`, no `${x,,}`.
- **`set -e` is already on.** Any comparison used as a value (`cmp`, `grep`, a hash mismatch) must
  sit inside an `if`/`||` context or it aborts the script.

## Goals / Non-Goals

**Goals:**

- A clean re-run against an unmodified target is a silent no-op with zero conflicts. This is the
  measure of whether the guard is worth having.
- No destination byte changes before the go/no-go decision.
- Degrade, never abort, when the environment is missing a tool.

**Non-Goals (design level, beyond the proposal's):**

- No new runtime dependency. `jq` is not used; the manifest is deliberately not JSON because bash
  cannot parse JSON without it.
- No refactor of the `.gitignore` block. It is already correct and idempotent; leave it in place,
  unchanged, after the commit pass.
- No change to `preflight.sh`.
- No spec requirements pinning the installer's pre-existing behavior. The argument shape, the copied
  file set, the `chmod +x`, and the `.gitignore` append must all keep working, but they are held by
  task-level verification rather than by the spec (see proposal.md — Non-goals).

## Decisions

### Hash manifest with source-comparison fallback

Chosen. The manifest records what the installer wrote, so a destination that still matches its
recorded hash is provably untouched by the user and may be overwritten freely — the ordinary
upgrade path. Only a file differing from *both* source and recorded hash is a customization.

*Alternative rejected: compare destination against source only, no manifest.* Simpler (one `cmp`
per file, no new state) but cannot distinguish an edit from an older toolkit version. Every
upgrade would report all 7 files as conflicts and the user would type `--force` reflexively —
training away the exact protection being added. It survives only as the **fallback** when no
manifest or no hash tool exists.

*Alternative rejected: overwrite but write `.bak` copies.* Still overwrites silently; the ask is
refusal plus an explicit flag, not post-hoc recovery.

### Parallel indexed arrays, not associative arrays

The plan pass must carry (source path, destination path, classification) per file into the commit
pass. Bash 3.2 has no `declare -A`, so use three parallel indexed arrays indexed by the same `i`,
or one array of `class<TAB>relpath` records split at commit time. Either is fine; associative
arrays are not.

### Enumeration must not run the loop in a subshell

Building the plan with `find ... | while read` puts the loop body in a **subshell**, and every
array element accumulated inside it is lost when the pipe ends — the plan comes back empty and the
installer silently installs nothing. Feed the loop from a here-string or process substitution
instead (`while read ...; do ...; done <<< "$list"`). This is the single most likely way to get a
plausible-looking but broken implementation.

Enumerate with `find "$SRC/.claude/skills/opsx-loop" -type f` piped through `LC_ALL=C sort` for
deterministic, reproducible manifest ordering.

### `sha256_of()` helper resolved once

Detect the tool once at startup with `command -v` (prefer `sha256sum`, then `shasum -a 256`) and
store the choice in a variable; do not probe per file. When neither exists, set a flag that
switches classification to source-comparison and suppresses the manifest write. `command -v`
inside `if` is `set -e` safe.

### Manifest format is `shasum -c` compatible

`<sha256><two spaces><path relative to DEST>`, one line per installed file, at
`.claude/.opsx-install-manifest`. This is exactly the output format of both `sha256sum` and
`shasum -a 256`, so generation is trivial and a user can verify by hand with
`cd "$DEST" && shasum -a 256 -c .claude/.opsx-install-manifest`. It lives outside both copied
trees, so it is never itself an install target and never classifies itself.

Lookup is a `grep`-and-cut on the file's relative path, guarded with `|| true` so a miss does not
trip `set -e`. A miss means "no recorded provenance" → `customized`.

### Manifest is committed, not gitignored

Provenance is useful to teammates, and gitignoring it means every fresh clone loses history and
flags all files as customized on its next install — reintroducing the habituation problem.

### Manifest is rewritten in full on every successful install

Including forced ones, and including files that were already `identical`. A forced write that did
not refresh the entry would report the same conflict forever. Build the new manifest content in a
variable during the commit pass and write it once at the end, so a manifest is never left half
written.

## Risks / Trade-offs

- **`--force` habituation** → The `stale` classification exists precisely so routine upgrades
  never prompt for the flag. Early signal: a clean re-run reports any conflict at all. Task 6.1
  tests this directly.
- **Partial install** → Strict plan-then-commit split; `chmod` moves into the commit pass. Early
  signal during review: any `cp` or `chmod` appearing before the conflict decision.
- **Subshell-swallowed plan** → See the enumeration decision above; verified by a scenario test
  that asserts 7 files are reported, not 0.
- **No sha256 binary** → Detected once, degrades to source-comparison. Under `set -e` an
  undetected missing binary would abort the installer entirely.
- **First upgrade after this lands is noisy.** No manifest exists yet, so any target whose files
  drifted from source reports them all as customized and needs `--force` once. Accepted: a
  one-time friction is the right price for not guessing about a user's edits. Document it in the
  README.
- **Self-install (`SRC` == `DEST`)** → `cp` a file onto itself errors and `set -e` kills the
  script. The `identical` check now short-circuits every file into a no-op before any `cp` runs,
  which fixes this pre-existing bug as a side effect. Worth one explicit test.

## Migration Plan

No migration step for users. The first run after upgrading writes a manifest; from then on
upgrades are quiet. A user who hits the one-time first-upgrade refusal either inspects the listed
paths (the point of the change) or re-runs with `--force`.

Rollback is reverting `install.sh`. A stale `.claude/.opsx-install-manifest` left in a target repo
is inert — the old script never reads it.
