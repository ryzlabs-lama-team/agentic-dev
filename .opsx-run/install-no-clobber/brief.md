# Explore brief: install.sh must not silently overwrite user-customized opsx-* agent/skill files

## Recommended scope

Make `install.sh` provenance-aware. Before writing anything, it plans every file it would install
and classifies each destination as *absent*, *identical*, *pristine-but-stale* (matches the hash
this installer previously recorded), or *customized/unknown*. If any file is customized/unknown and
`--force` was not passed, it prints the full list of conflicting paths, writes **nothing**, and
exits non-zero. Otherwise it writes the files and records a manifest of `sha256 <path>` lines for
every file it wrote, so the next run can tell a routine upgrade apart from a user edit.

The scope covers the 5 agent files (`install.sh:20-23`) and every file under the `opsx-loop` skill
directory (`install.sh:25`), argument parsing for the new flag (`install.sh:9-16` is positional-only
today), the manifest read/write, and a README update for the new behavior and flag.

## Non-goals

- Deleting or reconciling files present in the destination but absent from the source. `cp -R` at
  `install.sh:25` merges rather than replaces; user-added files under `opsx-loop/` must keep
  surviving untouched. Removal is a separate, destructive feature.
- `.bak` backups, three-way merge, or any attempt to preserve customizations while upgrading.
  Detect-and-refuse is the whole ask.
- Interactive prompting (`cp -i` style). The goal explicitly asks for a flag, and install.sh must
  stay usable non-interactively.
- Per-file or selective force (`--force path/to/one.md`). One global flag.
- Changing the `.gitignore` append at `install.sh:29-32`. It is already guarded by a `grep` and is
  idempotent — it is not a clobber path.
- A `--dry-run` flag. The two-pass plan makes it nearly free later, but it is not required here.
- Toolkit versioning / release numbering. The manifest stores hashes, not versions.

## Approach

**Chosen: hash manifest with a source-comparison fallback.** `install.sh` writes
`.claude/.opsx-install-manifest` recording the sha256 of each file it installed. On re-run, a
destination whose current hash equals the recorded hash is known-pristine and may be overwritten
freely — that is the ordinary upgrade path. Only a destination that differs from *both* the source
and its recorded hash (or has no manifest entry at all) is treated as customized and blocks on
`--force`. This is the only option that distinguishes "user edited this" from "this is just an
older copy of the toolkit", which is precisely the distinction the goal names.

**Rejected: compare destination bytes against source bytes only** (no manifest). Much simpler — a
`cmp -s` per file and no new state — but it cannot tell an edit from a stale version. Every
toolkit upgrade would report all 7 files as conflicts, and the user would learn to type `--force`
reflexively on every install. That trains away the exact protection being added, so the simplicity
is not worth it. It survives as the *fallback* classification when no manifest exists or no sha256
tool is available.

**Rejected: always overwrite but write `.bak` copies.** Preserves data but still overwrites
silently, and the goal asks for refusal plus an explicit flag, not recovery after the fact.

## Codebase findings

- `install.sh:20-23` — the clobber. `cp "$SRC/.claude/agents/opsx-$a.md" "$DEST/.claude/agents/"`
  in a loop over 5 agents, unconditional, no existence check. This is the primary target.
- `install.sh:25` — `cp -R "$SRC/.claude/skills/opsx-loop" "$DEST/.claude/skills/"`. Because the
  destination `opsx-loop/` may already exist, this **merges**: same-named files are overwritten,
  extra files are left alone. To participate in the plan it must be expanded to per-file
  enumeration of the source tree, not a single recursive `cp`.
- Source files that get installed today are exactly 7: `.claude/agents/opsx-{explorer,proposer,
  implementer,verifier,syncer}.md` plus `.claude/skills/opsx-loop/{SKILL.md,preflight.sh}`. The
  implementation must enumerate the skill tree dynamically, not hardcode 2 files, since the skill
  dir is expected to grow.
- `install.sh:4` — `set -euo pipefail` is already on. Hash/`cmp` calls inside conditionals need the
  usual care so a non-zero comparison does not abort the script.
- `install.sh:9-16` — argument handling is `DEST="${1:-}"` plus two guards; there is no flag parsing
  at all. Adding `--force` means a real loop over `"$@"` and an updated usage string.
- `install.sh:26` — `chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh"` runs unconditionally
  after the copy; it must move inside the commit pass so an aborted install touches nothing.
- `install.sh:29-32` — the `.gitignore` append is already conflict-safe (`grep -qs '^\.opsx-run'`
  guard) and gated on `$DEST/.git` existing. Leave it as is.
- `.claude/skills/opsx-loop/preflight.sh:40-43` — preflight only checks that the 5 agent files
  *exist*, never their contents. It will not notice a half-finished install, which is the argument
  for the two-pass plan/commit split rather than aborting mid-loop.
- `.claude/skills/opsx-loop/preflight.sh:33-37` — preflight warns when `.claude/skills/openspec-*`
  is missing. Those skills are shipped by `openspec init`, **not** by install.sh; the change must
  not start managing them.
- `README.md:12-18` — the documented install flow (`./install.sh /path/to/your-repo`) needs the
  flag and the refusal behavior documented. `README.md:93-108` has a layout tree that should gain
  the manifest file.
- `jq`, `shasum`, `sha256sum`, and `cmp` are all present on this machine, but a target user's
  machine may have only one of the sha tools (macOS ships `shasum`, Linux ships `sha256sum`). A
  small `sha256_of()` helper that tries both and degrades to source-comparison is required. Avoid
  JSON for the manifest — bash cannot parse it without depending on `jq`.

## Affected capabilities

- `toolkit-install` (suggested id) — **new**. `openspec/specs/` is empty and `openspec list --json`
  returns zero changes, so there is nothing to contradict and no overlapping active change. This
  capability should cover what install.sh copies, how it classifies existing destination files, the
  refusal contract, and the manifest format. Worth writing the *existing* install behavior into the
  spec as requirements too, since it is currently unspecified anywhere.

## Open questions

- **Flag name?** — **Assume:** `--force`, with `-f` as an alias, accepted in any position relative
  to the destination path.
- **Should the manifest be committed to the target repo or gitignored?** — **Assume:** committed.
  Provenance is useful to teammates, and gitignoring it means every fresh clone loses history and
  flags all 7 files as customized on the next install. Do **not** add it to `.gitignore`.
- **Manifest location and format?** — **Assume:** `.claude/.opsx-install-manifest`, plain text, one
  `<sha256>  <path-relative-to-DEST>` line per installed file. Located outside the copied trees so
  it is never itself an install target.
- **What happens to a pristine-but-stale file — silent overwrite or announced?** — **Assume:**
  overwrite without requiring the flag, but print it as `updated` so the normal upgrade is visible.
- **No manifest present (installed by today's install.sh) and destination differs from source?**
  — **Assume:** fail safe. Treat as customized and require `--force`. A one-time friction on the
  first upgrade is the correct price for not guessing.
- **Exit code on refusal?** — **Assume:** `1`, with the conflicting paths listed on stderr and a
  hint naming `--force`.
- **Does `--force` still rewrite the manifest?** — **Assume:** yes. Every successful write updates
  the manifest entry, including forced ones, otherwise the next run re-reports the same conflict.

## Risks

- **`--force` habituation.** If classification is too coarse the flag becomes muscle memory and the
  guard is worthless. Early signal: a clean re-run of `install.sh` against an unmodified target
  reports any conflict at all. That case must be a silent no-op.
- **Partial install.** Aborting inside the copy loop leaves a target with a mix of old and new
  files that preflight cannot detect (`preflight.sh:40-43` only checks existence). Mitigation is
  the strict plan-then-commit split: classify all files, decide, then write. Early signal: any
  `cp` appearing before the conflict decision in the final script.
- **No sha256 binary on the user's PATH.** Under `set -e` this aborts the installer. The helper
  must detect and degrade to source-comparison, not die.
- **Manifest and reality drift** if a user edits a file and the manifest is not refreshed on the
  next forced write — the same conflict is reported forever. Covered by the assumption above; worth
  an explicit requirement.
- **Self-install (`SRC` == `DEST`).** `cp` a file onto itself errors, and with `set -e` the script
  dies mid-way. Pre-existing, but the new identical-hash check will now short-circuit it into a
  clean no-op, so it is worth one test.
