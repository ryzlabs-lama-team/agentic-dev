Read `design.md` before starting. Two constraints break naive implementations:

- Target bash **3.2** (macOS default). No `declare -A`, no `mapfile`/`readarray`. Use parallel
  indexed arrays.
- `install.sh` runs under `set -euo pipefail`. Every `cmp`/`grep`/hash comparison must sit inside
  an `if` or end with `|| true`, or the script aborts.
- Never build the plan with `find ... | while read`. The pipe runs the loop in a subshell and every
  array element is lost. Use `while read ...; done <<< "$list"`.

All work is in two files: `install.sh` and `README.md`. Groups 1-4 are strictly sequential; each
leaves `install.sh` working. Group 5 (README) is independent of groups 2-4 and may be done at any
point after group 1. Group 6 depends on groups 1-4.

Tasks 1.1, 2.1, 3.3, and 3.4 preserve or extend behavior `install.sh` already has. That behavior is
intentionally not specified (see proposal.md — Non-goals); it is held by the per-group verification
commands below, so run them.

## 1. Argument parsing and hash helper

Files: `install.sh`. Satisfies: *Force flag permits overwriting customized files*, *Installer
degrades gracefully without a sha256 tool*.

- [x] 1.1 In `install.sh`, replace the positional `DEST="${1:-}"` handling (currently lines 7-16)
      with a loop over `"$@"` that sets `FORCE=1` for `--force` or `-f`, treats the first non-flag
      argument as `DEST`, errors on a second non-flag argument, and errors on any unrecognized
      `-*` argument. Keep the existing "not a directory" guard. Update the usage string to
      `usage: $0 [--force] /path/to/target-repo`. Verify: `bash -n install.sh` exits 0.
- [x] 1.2 Add a `sha256_of()` helper near the top of `install.sh` that echoes the bare sha256 hex
      of the file given as `$1`. Detect the tool **once** at startup into a variable using
      `command -v sha256sum` then `command -v shasum -a 256`; if neither exists set `HAVE_SHA=0`.
      Verify: `bash -n install.sh` exits 0, and
      `bash -c 'source <(sed -n "/^sha256_of/,/^}/p" install.sh); sha256_of install.sh'` prints a
      64-character hex string.

**Group 1 verification** — run from the repo root:

```sh
bash -n install.sh
./install.sh                        # expect: usage message on stderr, exit 1
./install.sh /nonexistent-path      # expect: error on stderr, exit 1
./install.sh --bogus /tmp           # expect: usage message on stderr, exit 1
T=$(mktemp -d); ./install.sh "$T" && ./install.sh --force "$T" && ./install.sh "$T" -f
echo "exit=$?"                      # expect: exit=0 for all three
```

## 2. Plan pass: enumerate and classify

Files: `install.sh`. Satisfies: *Every destination file is classified before any file is written*
(partial — `stale` arrives in group 4).

- [x] 2.1 Build the installed-set list in `install.sh` as newline-separated paths **relative to
      `$SRC`**: the five hardcoded `.claude/agents/opsx-<name>.md` paths plus the output of
      `find "$SRC/.claude/skills/opsx-loop" -type f` with the `$SRC/` prefix stripped, piped
      through `LC_ALL=C sort`. Verify: a temporary `echo` of the list prints exactly 7 lines
      against the current source tree, and 8 after `touch .claude/skills/opsx-loop/tmp-probe.md`
      (delete the probe afterward).
- [x] 2.2 Add a plan loop that reads that list with `while read rel; do ...; done <<< "$LIST"`
      (**not** a pipe) and fills parallel indexed arrays `PLAN_REL` and `PLAN_CLASS`. Classify
      `new` when `$DEST/$rel` does not exist, `identical` when `cmp -s "$SRC/$rel" "$DEST/$rel"`
      succeeds, else `customized`. Guard `cmp` inside an `if`. Verify: after the loop,
      `echo "${#PLAN_REL[@]}"` prints 7.
- [x] 2.3 Make the plan loop write nothing. Leave the existing `cp`/`cp -R`/`chmod` block in place
      for now so the script still installs; group 3 replaces it. Verify: `bash -n install.sh` and
      `T=$(mktemp -d); ./install.sh "$T"` still installs all 7 files
      (`find "$T/.claude" -type f | wc -l` prints 7).

**Group 2 verification** — nested-file enumeration and no-subshell-loss:

```sh
mkdir -p .claude/skills/opsx-loop/lib && touch .claude/skills/opsx-loop/lib/probe.sh
T=$(mktemp -d); ./install.sh "$T"
test -f "$T/.claude/skills/opsx-loop/lib/probe.sh" && echo "nested OK"
rm -rf .claude/skills/opsx-loop/lib
```

## 3. Decision and commit pass

Files: `install.sh`. Satisfies: *Installer refuses to overwrite customized files without force*,
*Force flag permits overwriting customized files*, *Routine upgrades proceed without the force
flag*, *Re-running against an unmodified destination is a clean no-op*, *Files present at the
destination but absent from the source are preserved*.

- [x] 3.1 After the plan loop, add the decision: collect every `customized` entry; if that list is
      non-empty and `FORCE` is unset, print all of them to stderr (one path per line), print a hint
      naming `--force`, and `exit 1` before any write. Verify with the group 3 command block below.
- [x] 3.2 Delete the old copy block (`for a in explorer ...` loop, `cp -R .../opsx-loop`, and the
      `chmod +x`) and replace it with a commit loop over `PLAN_REL`: `mkdir -p "$(dirname
      "$DEST/$rel")"` then `cp "$SRC/$rel" "$DEST/$rel"`, printing `  <class>  <rel>` per file.
      Skip the `cp` when class is `identical`. Verify: `T=$(mktemp -d); ./install.sh "$T"` installs
      7 files and prints 7 lines.
- [x] 3.3 Move `chmod +x "$DEST/.claude/skills/opsx-loop/preflight.sh"` into the commit loop's
      tail, after all copies, so a refusing run changes no permissions. Verify:
      `test -x "$T/.claude/skills/opsx-loop/preflight.sh"` after a successful install.
- [x] 3.4 Leave the `.gitignore` block (currently lines 29-32) byte-identical and positioned after
      the commit loop. Verify: `bash -n install.sh`, and
      `T4=$(mktemp -d); mkdir "$T4/.git"; ./install.sh "$T4" >/dev/null; ./install.sh "$T4" >/dev/null; grep -c '^\.opsx-run' "$T4/.gitignore"`
      prints `1`.

**Group 3 verification** — refusal is total and preserves the destination:

```sh
T=$(mktemp -d); ./install.sh "$T"
echo "MY EDIT" >> "$T/.claude/agents/opsx-explorer.md"
rm "$T/.claude/agents/opsx-verifier.md"
./install.sh "$T"; echo "exit=$?"            # expect: exit=1, stderr names opsx-explorer.md
test ! -f "$T/.claude/agents/opsx-verifier.md" && echo "nothing written on refusal: OK"
grep -q "MY EDIT" "$T/.claude/agents/opsx-explorer.md" && echo "edit preserved: OK"
./install.sh --force "$T"; echo "exit=$?"    # expect: exit=0
grep -q "MY EDIT" "$T/.claude/agents/opsx-explorer.md" || echo "forced overwrite: OK"
```

## 4. Manifest read and write

Files: `install.sh`. Satisfies: *Installer records provenance of every file it writes*, the `stale`
half of *Every destination file is classified before any file is written*, *Installer degrades
gracefully without a sha256 tool*.

- [x] 4.1 In the plan loop, before falling through to `customized`, look up `$rel` in
      `$DEST/.claude/.opsx-install-manifest`. Use `grep " $rel\$" <file> 2>/dev/null || true` and
      take the first field. If a recorded hash exists and equals `sha256_of "$DEST/$rel"`, classify
      `stale` instead of `customized`. Skip this entirely when `HAVE_SHA=0` or the manifest is
      absent. Verify with the group 4 command block.
- [x] 4.2 In the commit pass, accumulate `<sha256-of-source-file>  <rel>` lines for **every** entry
      in `PLAN_REL` (including `identical` and force-overwritten ones) into a variable, and write
      the whole variable to `$DEST/.claude/.opsx-install-manifest` once, after the commit loop.
      Skip the write when `HAVE_SHA=0`. Verify: `wc -l < "$T/.claude/.opsx-install-manifest"`
      prints 7.
- [x] 4.3 Confirm the manifest path is not in the installed set and is never added to `.gitignore`.
      Verify: `grep -c opsx-install-manifest "$T/.gitignore"` prints 0 (or the file does not exist),
      and the install output never names the manifest as an installed file.

**Group 4 verification** — the routine-upgrade path must not require the flag:

```sh
T=$(mktemp -d); ./install.sh "$T"
cd "$T" && shasum -a 256 -c .claude/.opsx-install-manifest >/dev/null && echo "manifest valid"; cd -
# simulate a toolkit upgrade: source changes, destination is still pristine
cp .claude/agents/opsx-explorer.md /tmp/opsx-explorer.bak
echo "# upstream change" >> .claude/agents/opsx-explorer.md
./install.sh "$T"; echo "exit=$?"     # expect: exit=0, no --force needed, reports "stale"/updated
cp /tmp/opsx-explorer.bak .claude/agents/opsx-explorer.md
# forced write must refresh the manifest so the conflict does not repeat
T2=$(mktemp -d); ./install.sh "$T2"; echo "EDIT" >> "$T2/.claude/agents/opsx-syncer.md"
./install.sh --force "$T2" && ./install.sh "$T2"; echo "exit=$?"   # expect: exit=0
```

## 5. Documentation

Files: `README.md`. Independent of groups 2-4.

- [x] 5.1 Update the install block at `README.md:12-18` to show `./install.sh [--force] /path/to/
      your-repo` and describe the refusal: the installer lists customized files, writes nothing,
      and exits 1 unless `--force` is passed. Verify: the flag and the word "force" appear in that
      section.
- [x] 5.2 Note the one-time first-upgrade friction: targets installed before this change have no
      manifest, so any drifted file is reported as customized and needs `--force` once. Verify:
      the note is present in the install section.
- [x] 5.3 Add `.claude/.opsx-install-manifest` to the layout tree at `README.md:93-108` with a
      one-line description (records the sha256 of each installed file; commit it). Verify: the
      path appears in the layout block.

**Group 5 verification**: `grep -n 'force\|opsx-install-manifest' README.md` shows hits in both the
install section and the layout tree.

## 6. Full scenario verification

Files: none (verification only). Run every scenario after groups 1-5 are complete.

- [x] 6.1 Clean no-op: install twice in a row with no edits; the second run must exit 0, require no
      flag, and report zero conflicts. This is the primary anti-habituation check.
- [x] 6.2 Self-install: run `./install.sh .` from the repo root; must exit 0 with every file
      classified identical and no file truncated (`git status` clean if the repo is under git,
      otherwise `find .claude -size 0` prints nothing).
- [x] 6.3 Destination-only files survive: create `.claude/skills/opsx-loop/my-notes.md` in the
      target, install both with and without `--force`, and confirm it still exists unchanged.
- [x] 6.4 No-hash-tool fallback: run the installer with `PATH` restricted so neither `shasum` nor
      `sha256sum` resolves; it must install into an empty target and exit 0, not abort.

**Group 6 verification** — run from the repo root:

```sh
bash -n install.sh
# 6.1 clean no-op
T=$(mktemp -d); ./install.sh "$T" >/dev/null; ./install.sh "$T"; echo "no-op exit=$?"
# 6.2 self install
./install.sh .; echo "self exit=$?"; find .claude -type f -size 0
# 6.3 destination-only file survives
echo "keep me" > "$T/.claude/skills/opsx-loop/my-notes.md"
./install.sh "$T" >/dev/null; ./install.sh --force "$T" >/dev/null
grep -q "keep me" "$T/.claude/skills/opsx-loop/my-notes.md" && echo "user file survived: OK"
# 6.4 no hash tool
T3=$(mktemp -d); env PATH=/usr/bin:/bin bash -c 'PATH=$(mktemp -d):/bin ./install.sh '"$T3"'; echo "fallback exit=$?"'
```
