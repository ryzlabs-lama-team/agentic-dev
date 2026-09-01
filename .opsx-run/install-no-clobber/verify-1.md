# Verify round 1: add-install-clobber-guard

Tested on the deployment target: `GNU bash 3.2.57(1)-release (arm64-apple-darwin25)`, and
`which -a bash` resolves to `/bin/bash` only — so `#!/usr/bin/env bash` in `install.sh` genuinely
ran under 3.2 for every scenario below. No newer bash was on PATH to mask a 3.2 failure.

Method: the repo was rsync'd to a scratch copy (`scratchpad/src`) so source-side mutations
(simulated upstream drift) never touched the user's tree; every destination was a fresh
`mktemp -d`. 20 scratch targets were created and removed. The real repo is verified unchanged
(20 files under `.claude`, no `.opsx-install-manifest`, no probe files left behind).

## Verdict

PASS-WITH-ADVISORIES

## Requirement coverage

| Requirement | Status | Evidence |
|---|---|---|
| Every destination file is classified before any file is written | met | `install.sh:78-96` plan loop is write-free; `install.sh:120-132` commit loop is the only writer. Ran: dest with `opsx-explorer.md` stale (source drifted) + `opsx-syncer.md` customized → exit 1, explorer's sha256 identical before/after. All five classification scenarios reproduced: `new`, `identical` (even with a deliberately corrupted manifest entry — `install.sh:82` cmp precedes the manifest lookup), `stale`, `customized` (edited), `customized` (no manifest entry). |
| Installer refuses to overwrite customized files without force | met | `install.sh:100-114`. Ran: 3 customized files + 1 deleted file → stderr listed **all three** paths, hint names `--force (or -f)`, exit 1, the deleted `opsx-verifier.md` was **not** recreated, the user's edit survived, and `shasum` of the manifest was byte-identical before and after. |
| Force flag permits overwriting customized files | met | `install.sh:29-46` parses `--force`/`-f` in any position — verified `./install.sh --force $T`, `./install.sh $T -f`, and `./install.sh --force` with no dest (usage, exit 1). Forced run printed `  customized  <path>` for each of the 3 overwritten files and exited 0. |
| Routine upgrades proceed without the force flag | met | Source-side edit to `opsx-explorer.md` against a pristine dest → `  stale  .claude/agents/opsx-explorer.md`, exit 0, no flag, dest content now equals source (`cmp` clean). `new` reported and created on first install. |
| Re-running against an unmodified destination is a clean no-op | met | Second run reports 7× `identical`, exit 0, zero conflicts. Self-install (`./install.sh .`) → 7× `identical`, exit 0, `find .claude -type f -size 0` empty (the pre-existing `cp` file-onto-itself abort is genuinely fixed). |
| Installer records provenance of every file it writes | met | `install.sh:119-132,141-143`. Manifest has 7 lines; `cd $T && shasum -a 256 -c .claude/.opsx-install-manifest` → 7× `OK`, so the two-space format is exactly `shasum -c` compatible. Covers `identical` files. After a forced overwrite the very next run classifies all 7 `identical` (exit 0) — the conflict does not repeat. `grep -c opsx-install-manifest $T/.gitignore` → 0. The manifest path never appears in the classified/reported set (it lives outside both copied trees). |
| Installer degrades gracefully without a sha256 tool | met | Ran with a PATH built from `/usr/bin`+`/bin` minus `shasum`/`sha256sum`/`md5`/`openssl`/`perl`/`python3`: empty dest → 7 files installed, exit 0, **no** manifest written. Then edited a dest file → refused with exit 1 naming it (conservative `customized`), and `--force` overwrote it, exit 0. See advisory 3 — the task's own 6.4 command cannot have produced this. |
| Files present at the destination but absent from the source are preserved | met | `.claude/skills/opsx-loop/my-notes.md` and a nested `sub/deep.md` both survived a plain run and a `--force` run with content intact, and neither appears in the manifest (`grep -c my-notes` → 0). Nothing in `install.sh` deletes. |

**8/8 requirements met. 24/24 scenarios reproduced.**

## Non-regression of the four unspecified pre-existing behaviors

Checked against `.opsx-run/install-no-clobber/install.sh.pre-apply`:

- **Argument shape** — no args → usage/exit 1; non-directory → `error: ... is not a directory`/exit 1;
  unknown `-*` → usage/exit 1; two non-flag args → usage/exit 1. The "not a directory" guard is kept.
- **File set** — 7 files installed, identical to the old script's set. A nested probe
  (`skills/opsx-loop/lib/probe.sh`) proved the per-file enumeration reaches subdirectories that the
  old `cp -R` covered; the plan array survives the here-string loop (7 entries, not 0).
- **`chmod +x`** — `preflight.sh` is `-rwxr-xr-x` after install; it does **not** run on a refusing run.
- **`.gitignore` append** — `diff <(sed -n '136,139p' install.sh) <(sed -n '29,32p' install.sh.pre-apply)`
  is empty: byte-identical. Two runs against a `.git` dir → `grep -c '^\.opsx-run'` = 1 (idempotent).
- **Upgrade from an old-script install** — dest installed by the pre-apply script, source unchanged →
  new script reports 7× `identical`, exit 0, writes the manifest. No spurious first-run friction.
  With source drifted, it refuses once and `--force` clears it permanently — exactly what README
  documents.

## Blocking findings

None.

## Advisory findings

### 1. `install.sh:87` — manifest lookup treats the relative path as a regex, so a filename containing BRE metacharacters is misclassified `customized` instead of `stale`

- **Where:** `install.sh:87` — `grep " $rel\$" "$MANIFEST"`
- **Failure (reproduced):** add `.claude/skills/opsx-loop/note[1].md` to the source, install (exit 0,
  manifest written), then change the source file and re-run against the pristine destination.
  Expected `stale` + exit 0; actual: `error: refusing to overwrite customized files: .claude/skills/opsx-loop/note[1].md`,
  exit 1. `[1]` is parsed as a bracket expression, so the pattern searches for `note1.md` and misses.
  A control file named `note1.md` under the identical procedure correctly reports `stale`, exit 0.
- **Why advisory, not blocking:** no file in today's installed set (five `opsx-*.md` agents,
  `SKILL.md`, `preflight.sh`) contains a metacharacter, and the failure direction is fail-safe —
  it refuses rather than clobbers. But it is a latent violation of the `stale` rule in *Every
  destination file is classified before any file is written*, and it would resurface as exactly the
  `--force` habituation that design.md names as the primary risk. Paths with **spaces** were tested
  separately and work correctly end-to-end (new → identical → customized → stale).
- **Fix direction:** match on the literal path instead of a BRE — e.g. `grep -F` on the two-space
  `"  $rel"` suffix, or read the manifest line-wise and compare the field.

### 2. `install.sh:57` — `mkdir -p` runs before the plan pass, so a refusing run can still leave a new empty directory in the destination

- **Failure (reproduced):** destination containing only a customized `.claude/agents/opsx-explorer.md`
  and no `.claude/skills` directory. Run without `--force` → correctly refuses with exit 1, but
  `.claude/skills/` now exists where it did not before.
- **Requirement text at issue:** "In the first pass it SHALL classify every file ... **without
  modifying the destination in any way**". The scenario's assertion ("byte-for-byte unchanged") and
  the requirement's own narrower enumeration ("no file content, permission, or manifest change")
  both hold — only an empty directory appears — which is why this is advisory rather than blocking.
  It is nonetheless the one place the implementation touches the destination before the go/no-go.
- **Fix direction:** the commit loop already does `mkdir -p "$(dirname ...)"` per file
  (`install.sh:124`), so line 57 is redundant and can move below the decision or be deleted.

### 3. `openspec/changes/add-install-clobber-guard/tasks.md:192` — the ticked task 6.4's own verification command cannot pass as written

- The command is `PATH=$(mktemp -d):/bin ./install.sh "$T3"`. `/bin` does not contain `dirname`
  or `find` on macOS (they are in `/usr/bin`), so the script dies with
  `./install.sh: line 6: dirname: command not found` / `line 67: find: command not found`, exit **127**,
  installing zero files — the opposite of the task's stated expectation ("must install into an
  empty target and exit 0, not abort"). I reproduced this exactly, then re-ran with a correct
  minus-hash-tools PATH and the requirement **does** hold (see the coverage table).
- The requirement is met; the ticked evidence is not. Worth noting as a signal about how much of
  the "19/19 ticked, all verification blocks passing" claim rests on commands that were run and
  read versus ticked.

### 4. `install.sh:134` — `chmod +x` is unconditional, so an "all identical" no-op run still changes a file's mode

- **Failure (reproduced):** `chmod -x $T/.claude/skills/opsx-loop/preflight.sh`, then re-run. Output
  reports `  identical  .claude/skills/opsx-loop/preflight.sh` and exits 0, but the mode silently
  goes `-rw-r--r--` → `-rwxr-xr-x`.
- *Re-running against an unmodified destination is a clean no-op* only guarantees **content**, so
  this is not a violation — but the reported classification and the actual effect disagree.

### 5. `install.sh:65` — `find -type f` silently drops symlinks and empty directories that the old `cp -R` would have copied

- No symlink or empty directory exists under `.claude/skills/opsx-loop/` today, so nothing is lost
  now. Flagged only because it is a real behavior delta from the pre-apply baseline in a file set
  that the spec deliberately does not pin.

### 6. `install.sh:125` — a destination path occupied by a *directory* where a file belongs makes a forced run exit 0 without installing that file

- **Failure (reproduced):** `mkdir -p $T/.claude/agents/opsx-syncer.md`, then `./install.sh --force $T`.
  `cp` copies *into* the directory, producing `.claude/agents/opsx-syncer.md/opsx-syncer.md`; the run
  prints `  customized  .claude/agents/opsx-syncer.md` and exits 0 while the file is not installed,
  and the manifest records a hash for a path that is a directory.
- Contrived destination shape; listed for completeness only.

## Scope creep

None found. `install.sh` implements what proposal.md lists and nothing more — no `--dry-run`, no
`.bak` copies, no interactive prompt, no per-file force, no versioning, no touching
`.claude/skills/openspec-*`. README changes are documentation only.

## Spec drift

**None.** This is not a git repo, so coherence was checked against the pre-apply baseline:

- `design.md:3-5` still cites the *pre-apply* `install.sh` line numbers — copy loop `:20-23`,
  `cp -R` `:25`, `chmod` `:26`, `.gitignore` `:29-32`, args `:9-16` — and every one of those matches
  `install.sh.pre-apply` exactly. Had design.md been retrofitted to the implementation, these would
  have been renumbered.
- `tasks.md:23` ("currently lines 7-16"), `tasks.md:94` ("currently lines 29-32"),
  `proposal.md:60-62` (`:9-16`, `:20-23`, `:25-26`, `:29-32`, `README.md:12-18`, `README.md:93-108`)
  are all consistent with the pre-apply files, not the post-apply ones (the README layout tree is
  now at 104-120 after the additions).
- The delta spec's ADDED requirements each map onto behavior that exists; nothing reads as
  written-after-the-fact.
- Only checkbox state appears to have changed under `openspec/`. `openspec validate
  add-install-clobber-guard --strict` → "Change 'add-install-clobber-guard' is valid".
- Trimming held: 8 requirements / 24 scenarios, matching the human gate.
