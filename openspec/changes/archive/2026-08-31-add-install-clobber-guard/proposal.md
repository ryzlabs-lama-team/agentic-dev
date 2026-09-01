## Why

`install.sh` copies 7 toolkit files into a target repo unconditionally (`install.sh:20-23` and
`install.sh:25`), with no existence or content check. A user who customizes an installed
`opsx-*` agent or the `opsx-loop` skill loses that work silently on the next install, with no
warning and no way to recover. The installer must refuse to destroy work it did not write.

## What Changes

- `install.sh` becomes provenance-aware and two-pass: it **plans** every file it would install and
  classifies each destination before writing anything, then **commits** only if the plan is safe.
- Each destination file is classified as `new` (absent), `identical` (byte-equal to source),
  `stale` (differs from source but matches the hash this installer previously recorded — a routine
  upgrade), or `customized` (differs from both source and recorded hash, or has no recorded hash).
- If any file classifies as `customized` and `--force` was not passed, the installer lists every
  conflicting path on stderr, writes **nothing**, and exits `1`.
- New `--force` / `-f` flag, accepted in any argument position, overrides the refusal.
- New manifest `.claude/.opsx-install-manifest` in the target repo: plain text, one
  `<sha256>  <path-relative-to-DEST>` line per installed file. Written on every successful install,
  including forced ones. Committed to the target repo, not gitignored.
- The `opsx-loop` skill is copied by enumerating the source tree per file rather than one
  `cp -R`, so every file participates in the plan.
- `chmod +x` on `preflight.sh` moves into the commit pass, so an aborted install touches nothing.
- If neither `shasum` nor `sha256sum` is available, the installer degrades to source-comparison
  classification rather than aborting.
- README documents the flag, the refusal behavior, and the manifest.

**Non-goals** (carried forward from exploration — do not implement these):

- Deleting or reconciling destination files absent from the source. User-added files under
  `opsx-loop/` must keep surviving untouched.
- `.bak` backups, three-way merge, or any attempt to preserve customizations while upgrading.
  Detect-and-refuse is the whole ask.
- Interactive prompting (`cp -i` style). The installer must stay usable non-interactively.
- Per-file or selective force (`--force path/to/one.md`). One global flag only.
- Changing the `.gitignore` append at `install.sh:29-32`. It is already `grep`-guarded and
  idempotent; it is not a clobber path.
- A `--dry-run` flag.
- Toolkit versioning or release numbering. The manifest stores hashes, not versions.
- Managing `.claude/skills/openspec-*`. Those are shipped by `openspec init`, not by this
  installer.
- Writing requirements that merely pin `install.sh`'s pre-existing behavior (its argument shape,
  the set of files it copies, the `chmod +x`, the `.gitignore` append) as regression guards. Those
  behaviors are preserved by the implementation and checked by task-level verification, but they
  are not specified — the spec covers the clobber guard only.

## Capabilities

### New Capabilities
- `toolkit-install`: How the installer classifies existing destination files against source and
  recorded provenance, the refusal contract and its exit code, the `--force` override, and the
  install manifest format and lifecycle. Scoped to the clobber guard; the installer's
  pre-existing behavior is deliberately left unspecified.

### Modified Capabilities
<!-- None. openspec/specs/ is empty; there is no existing capability to modify. -->

## Impact

- `install.sh` — substantially rewritten: argument parsing (`:9-16`), agent copy loop (`:20-23`),
  skill copy (`:25-26`). The `.gitignore` block (`:29-32`) is unchanged.
- `README.md:12-18` (install flow) and `README.md:93-108` (layout tree) — documentation only.
- New file in **target** repos: `.claude/.opsx-install-manifest`. No new file in this repo.
- New runtime dependency preference on `shasum` or `sha256sum`, with a `cmp`-based fallback path
  when neither exists. No hard new dependency.
- Behavior change for existing users: the first upgrade after this lands has no manifest, so any
  target file that differs from source is reported as customized and requires `--force` once.
