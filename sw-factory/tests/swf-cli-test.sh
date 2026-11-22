#!/usr/bin/env bash
# Tests for .sw-factory/tools/swf-cli.py against a throwaway git repository.
#   bash tests/swf-cli-test.sh
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SF="$SRC/.sw-factory/tools/swf-cli.py"
command -v python3 >/dev/null 2>&1 || { echo 'SKIP  python3 not found'; exit 0; }
command -v git >/dev/null 2>&1 || { echo 'SKIP  git not found'; exit 0; }
BASE_DIR="$(mktemp -d)"; trap 'rm -rf "$BASE_DIR"' EXIT
PROJ="$BASE_DIR/proj"
mkdir -p "$PROJ"

pass=0 fail=0
# t <want-exit> <want-substring or ""> <description> <swf-cli args…>
t() {
  local want="$1" sub="$2" desc="$3" out code; shift 3
  out="$(cd "$PROJ" && python3 "$SF" "$@" 2>&1)"; code=$?
  if [ "$code" != "$want" ]; then
    fail=$((fail + 1)); printf 'FAIL  %s: want exit %s, got %s\n' "$desc" "$want" "$code"; sed 's/^/        /' <<<"$out"
  elif [ -n "$sub" ] && ! grep -qF -- "$sub" <<<"$out"; then
    fail=$((fail + 1)); printf 'FAIL  %s: output lacks %q\n' "$desc" "$sub"; sed 's/^/        /' <<<"$out"
  else pass=$((pass + 1)); fi
}
# has <file> <regex> <description>: the file (relative to the project) matches the regex
has() {
  if grep -qE -- "$2" "$PROJ/$1" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); printf 'FAIL  %s: %s lacks /%s/\n' "$3" "$1" "$2"; fi
}
hasnt() {
  if ! grep -qE -- "$2" "$PROJ/$1" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); printf 'FAIL  %s: %s matches /%s/\n' "$3" "$1" "$2"; fi
}
g() { git -C "$PROJ" "$@" >/dev/null 2>&1; }

# ------------------------------------------------------------------------------------- fixtures
cd "$PROJ" || exit 1
mkdir -p .sw-factory docs/prds/demo docs/tech-designs/core docs/adrs docs/plans src
# A customized config: quoted plans path with a trailing slash; a `prds` key outside `paths:`.
cat > .sw-factory/config.yaml <<'YAML'
paths:
  plans: "docs/plans/"           # quoted, trailing slash
  runs: .sw-factory/runs
gates:
  prds: not-a-path               # same key outside `paths:` must be ignored
  coverage_min: 80
  coverage_scope: changed
commands:
  build: "sh fail.sh"
  test: "sh pass-test.sh"
  lint: ""
YAML
printf '.sw-factory/runs/\n' > .gitignore
printf 'echo compiling\necho boom\nexit 3\n' > fail.sh
printf 'echo collected 3 items\necho "============ 3 passed, 1 skipped in 0.02s ============"\n' > pass-test.sh
printf 'echo "=== 1 failed, 2 passed in 0.10s ==="\nexit 0\n' > lying-test.sh

cat > docs/prds/demo/prd.md <<'MD'
---
id: PRD-DEMO
title: Demo
status: draft            # draft | in-review | agreed | superseded
version: 0.1.0           # minor = requirements added/changed, patch = wording/clarification
agreed_by: ~             # set only after the human gate
---

# Demo

## 6. Functional requirements
- **FR-001** — the system shall a _(F-01)_
- **FR-002** — the system shall b _(F-01)_
- ~~FR-003~~ (removed in v0.1: not needed)

## 7. Non-functional requirements
- **NFR-001** — latency: p95 < 300 ms

## 11. Decision log
| Date | Decision | Decided by | Source |
|---|---|---|---|

## 12. Changelog
| Version | Date | Change | Reason |
|---|---|---|---|
| 0.1.0 | 2026-01-01 | Initial draft | demo |
MD

story() { # story <n> <priority> <status> <requirements>
  printf '\n## US-DEMO-%s: story %s\n- **Status:** %s            <!-- draft | ready -->\n- **Priority:** %s           <!-- must | should | could -->\n- **Requirements:** %s\n\n### Acceptance criteria\n- **AC1** — Given x, when y, then z.\n' "$1" "$1" "$3" "$2" "$4"
}
{
  printf -- '---\nprd: PRD-DEMO\nupdated: 2026-01-01\n---\n\n# User stories — Demo\n\n'
  printf '| ID | Title | Priority | Status | Requirements |\n|---|---|---|---|---|\n'
  for n in 001 002 003 004; do printf '| US-DEMO-%s | story | must | ready | FR-001 |\n' "$n"; done
  printf '\n---\n'
  story 001 must ready FR-001
  story 002 must ready 'FR-002, NFR-001'
  story 003 must draft FR-001
  story 004 could draft FR-002
} > docs/prds/demo/stories.md

cat > docs/tech-designs/core/hld.md <<'MD'
---
id: HLD-CORE
status: draft
version: 0.1.0
---

# core

```mermaid
flowchart LR
  a --> b
```

- Inline code that looks like a fence must not open one (doc bump must still find the Changelog):
    ```` ```mermaid ```` block per diagram.

## 9. Traceability
| Requirement | Satisfied by (section / component) |
|---|---|
| FR-001 | §4 api |
| NFR-001 | §7 cache |

## 12. Changelog
| Version | Date | Change | Trigger |
|---|---|---|---|
| 0.1.0 | 2026-01-01 | Initial draft | PRD-DEMO v0.1.0 |
MD

cat > docs/adrs/0001-use-postgres.md <<'MD'
---
id: ADR-0001
status: proposed         # proposed | accepted | rejected
deciders: ~
---

# ADR-0001: use postgres
MD

cat > docs/plans/demo.md <<'MD'
---
id: PLAN-DEMO
title: demo
status: approved         # draft | approved | in-progress | done | superseded
version: 0.1.0
approved_by: ~
---

# Plan: demo

## Phase map
| Phase | Goal | Stories | Level | Track (recommended) | Depends on | Status |
|---|---|---|---|---|---|---|
| P1 | scaffold | US-DEMO-001 | L1 | subagents | — | todo |
| P2 | feature | US-DEMO-002, US-DEMO-001 | L1 | subagents | P1 | todo |

---

## P1 — scaffold
### Tasks
- [ ] **1.1** do a — files: `src/a.py` — satisfies: US-DEMO-001 AC1
- [ ] **1.2** do b — files: `src/b.py` — satisfies: US-DEMO-001 AC1

### Exit criteria
- [ ] Build passes
- [ ] Docs updated for anything this phase changes, wrapped
  onto a second line
  - [ ] a nested checkbox is part of item 2, not an exit criterion
- [ ] Coverage report written

---

## P2 — feature
### Tasks
- [x] **2.1** do c — files: `src/c.py` — satisfies: US-DEMO-002 AC1
- [ ] **2.2** do d

```text
- [ ] **9.9** a task inside a code fence is not a task
```

## Changelog
| Version | Date | Change | Trigger |
|---|---|---|---|
| 0.1.0 | 2026-01-01 | Initial plan | PRD-DEMO v0.1.0 |
MD

printf 'import os\n\ndef a():\n    return 1\n\ndef b():\n    return 2\n' > src/app.py

g init -q && g config user.email t@example.com && g config user.name t && g config commit.gpgsign false
g add -A && g commit -qm base
BASE="$(git -C "$PROJ" rev-parse HEAD)"

# ----------------------------------------------------------------------------------------- misc
t 0 "swf-cli 1."                "--version"                       --version
t 2 ""                          "unknown group is a usage error"  nope

# ------------------------------------------------------------------------------------------ plan
t 0 "P1 tasks 0/2 · open: 1.1 1.2 · exit 0/3 · open exit: 1 2 3" "plan status P1" plan status docs/plans/demo.md --phase P1
t 0 "P2 tasks 1/2 · open: 2.2"  "plan status ignores fenced tasks" plan status docs/plans/demo.md
t 0 "TOTAL 1/4"                 "plan status total"               plan status docs/plans/demo.md
t 2 "has no phase P9"           "plan status unknown phase"       plan status docs/plans/demo.md --phase P9
t 1 "unknown task ids in P1: 9.9" "tick unknown id"               plan tick docs/plans/demo.md P1 1.1 9.9
hasnt docs/plans/demo.md '\[x\] \*\*1\.1' "unknown id ticks nothing"
t 0 "ticked: 1.1"               "tick a task"                     plan tick docs/plans/demo.md p1 1.1
has docs/plans/demo.md '^- \[x\] \*\*1\.1\*\* do a' "task 1.1 ticked in the file"
has docs/plans/demo.md '^- \[ \] Build passes' "exit criteria untouched"
t 0 "already ticked: 1.1"       "tick is idempotent"              plan tick docs/plans/demo.md P1 1.1 1.2
t 0 "P1 tasks 2/2"              "tick reports the new count"      plan status docs/plans/demo.md --phase P1
t 2 "give task ids, --exit"     "tick needs something to tick"    plan tick docs/plans/demo.md P1
t 1 "unknown exit criteria in P1: 4" "tick unknown exit criterion" plan tick docs/plans/demo.md P1 --exit 2 4
hasnt docs/plans/demo.md '^- \[x\] Docs updated' "unknown exit criterion ticks nothing"
t 1 "P2 has no \"### Exit criteria\" items" "tick exit on a phase without any" plan tick docs/plans/demo.md P2 --exit all
t 0 "ticked: exit 2"            "tick an exit criterion"          plan tick docs/plans/demo.md P1 --exit 2
has docs/plans/demo.md '^- \[x\] Docs updated'                 "exit criterion 2 ticked in the file"
has docs/plans/demo.md '^  - \[ \] a nested checkbox'           "nested checkbox untouched"
has docs/plans/demo.md '^- \[ \] Build passes'                  "other exit criteria untouched"
t 0 "exit 3/3"                  "tick --exit all reports the count" plan tick docs/plans/demo.md P1 --exit all
t 0 "already ticked: 1.1, exit 2" "--exit is idempotent"            plan tick docs/plans/demo.md P1 1.1 --exit 2
t 0 "P1 tasks 2/2 · all ticked · exit 3/3" "status after ticking exits" plan status docs/plans/demo.md --phase P1
cp docs/plans/demo.md docs/notaplan.md
t 2 "plan must be under docs/plans/" "tick outside the plans dir (config path read)" plan tick docs/notaplan.md P1 1.1
rm docs/notaplan.md
t 0 "P2 · feature · US-DEMO-002, US-DEMO-001" "plan phases"      plan phases docs/plans/demo.md

# ---------------------------------------------------------------------------------------- ledger
LEDGER=.sw-factory/runs/demo/ledger.md
t 0 "LEDGER: $LEDGER"           "ledger init"                     ledger init demo --request "add  the
thing" --entry change --tracks "TRACKS: direct=yes subagents=yes opsx-loop=no openspec=no"
has "$LEDGER" '^# Run: demo$'                    "ledger title"
has "$LEDGER" '^Request: add the thing$'         "request on one line"
has "$LEDGER" "^Base ref: $BASE\$"               "base ref recorded"
has "$LEDGER" '^Branch: '                        "branch recorded"
has "$LEDGER" '^Tracks available: direct=yes subagents=yes opsx-loop=no openspec=no$' "tracks recorded"
has "$LEDGER" '^Commit policy: ask$'             "commit policy from config default"
t 1 "ledger exists"             "ledger init refuses to overwrite" ledger init demo --request x --entry change --tracks x
# Without --tracks, ledger init runs the running runtime's preflight (runtime_dir()). Fake preflights
# say which one ran; they are removed again so later drift checks do not see them.
for rt in claude opencode; do
  mkdir -p "$PROJ/.$rt/swf-tools"; printf 'echo "TRACKS: direct=yes from=%s"\n' "$rt" > "$PROJ/.$rt/swf-tools/preflight.sh"
done
runtime_case() { # runtime_case <slug> <expected runtime> <description> <env assignments…>
  local slug="$1" want="$2" desc="$3"; shift 3
  (cd "$PROJ" && env -u SWF_RUNTIME -u OPENCODE -u CLAUDECODE "$@" python3 "$SF" ledger init "$slug" --request x --entry defect >/dev/null 2>&1)
  if grep -q "^Tracks available: direct=yes from=$want\$" "$PROJ/.sw-factory/runs/$slug/ledger.md" 2>/dev/null; then pass=$((pass + 1))
  else fail=$((fail + 1)); printf 'FAIL  %s\n' "$desc"; fi
}
runtime_case rt-sw  opencode "SWF_RUNTIME picks the runtime's preflight"   SWF_RUNTIME=opencode CLAUDECODE=1
runtime_case rt-oc  opencode "OPENCODE=1 wins over an inherited CLAUDECODE" OPENCODE=1 CLAUDECODE=1
runtime_case rt-cc  claude   "CLAUDECODE=1 picks Claude Code's preflight"   CLAUDECODE=1
runtime_case rt-any claude   "outside both runtimes, the installed one"     X=1
rm "$PROJ/.claude/swf-tools/preflight.sh"
runtime_case rt-one opencode "only OpenCode installed"                      X=1
rm -rf "$PROJ/.claude" "$PROJ/.opencode"
t 0 "TRACKS: unknown (no preflight" "no preflight installed is reported, not fatal" ledger init other --request x --entry defect
t 2 "invalid run slug"          "slug validated"                  ledger init ../x --request x --entry change --tracks x
t 2 "no ledger for run nope"    "missing ledger"                  ledger summary nope
t 0 "Level: L1"                 "ledger set"                      ledger set demo level L1
has "$LEDGER" '^Level: L1$'                      "level written"
t 0 "frame set: problem, goals" "ledger frame"                    ledger frame demo --problem "it is slow" --goals "make it fast"
has "$LEDGER" '^- \*\*Problem:\*\* it is slow$'  "frame written"
t 0 "log #1"                    "ledger log #1"                   ledger log demo --stage triage --agent swf-architect --agent-id a1b2c3 --status ok --artifact .sw-factory/runs/demo/triage.md
has "$LEDGER" '^\| 1 \| triage \| swf-architect \| a1b2c3 \| ok \| ' "log row records agent id"
t 0 "log #2"                    "ledger log #2"                   ledger log demo --stage requirements --agent swf-po --status ok --notes "a | pipe"
has "$LEDGER" '^\| 2 \| requirements \| swf-po \| — \| ok \| — \| a \\\| pipe \|$' "log row escapes pipes"
t 0 "doc PRD docs/prds/demo/prd.md v0.1.0 (draft) · added" "ledger doc reads front matter" ledger doc demo docs/prds/demo/prd.md --written-by swf-po
t 0 "· updated"                 "ledger doc upserts"              ledger doc demo docs/prds/demo/prd.md --written-by swf-po
t 0 "P1 · L1 · subagents · in-progress · retries 0" "ledger phase add" ledger phase demo p1 --level L1 --track subagents --status in-progress --base "$BASE"
t 0 "P2 · L2"                   "ledger phase second row"         ledger phase demo P2 --level L2 --track opsx-loop --status todo
t 0 "retry 1/2 · QA ROUND: 1 · builder model: default" "retry 1"  ledger phase demo P1 --retry
t 0 "retry 2/2 · QA ROUND: 2 · builder model: opus"    "retry 2"  ledger phase demo P1 --retry
t 1 "budget exhausted"          "retry 3 exhausts the budget"     ledger phase demo P1 --retry
t 0 "decision #1"               "ledger decision"                 ledger decision demo --gate G3 --decision "approved by Jane" --recorded-in docs/plans/demo.md
t 0 "NEXT: P1 (in-progress)"    "ledger summary next"             ledger summary demo
t 0 "PHASES: P1 L1 subagents in-progress r2 | P2 L2 opsx-loop todo r0" "ledger summary phases" ledger summary demo
t 0 "LOG #2 requirements · swf-po · ok" "ledger summary log"          ledger summary demo
t 0 "DECISIONS: 1"              "ledger summary decisions"        ledger summary demo

# ---------------------------------------------------------------------------- plan sync (ledger)
ledger_done() { python3 "$SF" ledger phase demo P1 --status done >/dev/null; }
(cd "$PROJ" && ledger_done)
t 0 "P1 todo → done; status approved → in-progress" "plan sync"   plan sync docs/plans/demo.md --ledger "$LEDGER"
has docs/plans/demo.md '^\| P1 \| scaffold \| US-DEMO-001 \| L1 \| subagents \| — \| done \|$' "Phase map status synced"
has docs/plans/demo.md '^status: in-progress {6}# draft' "front-matter status synced, comment column kept"
t 0 "synced: no changes"        "plan sync is idempotent"         plan sync docs/plans/demo.md --ledger "$LEDGER"

# ------------------------------------------------------------------------------------------- doc
t 0 "docs/prds/demo/prd.md id=PRD-DEMO status=draft version=0.1.0 agreed_by=~" "doc meta" doc meta docs/prds/demo/prd.md
t 0 "status=draft"              "doc meta --field"                doc meta docs/prds/demo/prd.md --field status
t 1 "missing"                   "doc meta on a missing file"      doc meta docs/prds/nope.md
t 0 "status: draft → agreed"    "doc set"                         doc set docs/prds/demo/prd.md status=agreed "agreed_by=Jane Doe, 2026-11-06"
has docs/prds/demo/prd.md '^status: agreed           # draft \| in-review' "doc set keeps the comment column"
has docs/prds/demo/prd.md '^agreed_by: Jane Doe, 2026-11-06 # set only'   "doc set long value keeps comment"
t 0 "confluence: ~ → "          "doc set adds a missing key"      doc set docs/prds/demo/prd.md "confluence=https://x/y"
has docs/prds/demo/prd.md '^confluence: https://x/y$'            "missing key inserted"
t 2 "document must be under"    "doc set outside document dirs"   doc set src/app.py status=x
t 2 "expected key=value"        "doc set validates pairs"         doc set docs/prds/demo/prd.md nonsense
t 0 "v0.1.0 → v0.2.0"           "doc bump minor"                  doc bump docs/prds/demo/prd.md minor --change "add FR-004" --trigger "run demo" --set status=in-review
has docs/prds/demo/prd.md '^version: 0\.2\.0 +# minor'          "version bumped, comment kept"
has docs/prds/demo/prd.md '^status: in-review'                    "bump --set"
has docs/prds/demo/prd.md "^\| 0\.2\.0 \| [0-9-]+ \| add FR-004 \| run demo \|\$" "changelog row (Reason column)"
t 0 "v0.1.0 → v0.1.1"           "doc bump patch on HLD"           doc bump docs/tech-designs/core/hld.md patch --change wording --trigger "PRD-DEMO v0.2.0"
has docs/tech-designs/core/hld.md "^\| 0\.1\.1 \| [0-9-]+ \| wording \| PRD-DEMO v0\.2\.0 \|\$" "changelog row (Trigger column)"
t 2 "no \"Changelog\" section"  "doc bump on an ADR without changelog" doc bump docs/adrs/0001-use-postgres.md patch --change x
t 0 "decision-log row added"    "doc decide"                      doc decide docs/prds/demo/prd.md --decision "keep FR-002" --by Jane --source "clarification demo/Q1" --date 2026-11-06
has docs/prds/demo/prd.md '^\| 2026-11-06 \| keep FR-002 \| Jane \| clarification demo/Q1 \|$' "decision row"
t 0 "docs/prds/demo/prd.md v0.1.0 → v0.2.0" "doc versions"       doc versions --since "$BASE"
t 0 "docs/plans/demo.md v0.1.0 (content changed, version not bumped)" "doc versions flags unbumped" doc versions --since "$BASE"

# -------------------------------------------------------------------------------------------- ids
t 0 "0002"                      "id next adr"                     id next adr
t 0 "FR-005"                    "id next fr skips every id ever mentioned (FR-004 is in a changelog row)" id next fr --doc docs/prds/demo/prd.md
t 0 "NFR-002"                   "id next nfr"                     id next nfr --doc docs/prds/demo/prd.md
t 0 "US-DEMO-005"               "id next us"                      id next us --doc docs/prds/demo/stories.md
t 2 "needs --doc"               "id next fr without --doc"        id next fr
t 0 "Q1"                        "id next q, empty log"            id next q --run demo

# ---------------------------------------------------------------------------------------- clar
t 0 "Q1 → .sw-factory/runs/demo/clarifications.md" "clar add Q1"  clar add demo --asked-by swf-builder --wp P2 --owner swf-po --q "what if empty?" --a "show a message" --recorded-in "docs/prds/demo/stories.md#US-DEMO-002 (v0.2.0)"
t 0 "Q2 →"                      "clar add Q2"                     clar add demo --asked-by swf-builder --wp P2 --owner swf-architect --q "where?" --a "in api" --recorded-in "docs/adrs/0001-use-postgres.md"
has .sw-factory/runs/demo/clarifications.md '^## Q2 · [0-9-]+ · asked by swf-builder \(P2\) · owner: swf-architect$' "clar entry heading"
t 0 "Q3"                        "id next q after entries"         id next q --run demo
t 0 "clarifications: 2/5 for P2" "clar count"                     clar count demo --wp P2
t 0 "clarifications: 0/5 for P1" "clar count other wp"            clar count demo --wp P1
t 1 "over budget"               "clar count --adding over budget" clar count demo --wp P2 --adding 4

# ----------------------------------------------------------------------------------------- trace
t 0 "FR 2 · NFR 1 · removed 1 · stories 4 (2 ready) · issues 0" "trace prd clean" trace prd docs/prds/demo
t 1 "missing: FR-002"           "trace hld gap"                   trace hld docs/tech-designs/core/hld.md --prd docs/prds/demo/prd.md
sed -i.bak 's/^| FR-001 | §4 api |$/| FR-001–FR-002 | §4 api |/' docs/tech-designs/core/hld.md && rm -f docs/tech-designs/core/hld.md.bak
t 0 "traced 3/3"                "trace hld with an id range"      trace hld docs/tech-designs/core/hld.md --prd docs/prds/demo/prd.md
t 1 "unplaced: US-DEMO-003"     "trace plan unplaced must story"  trace plan docs/plans/demo.md --stories docs/prds/demo/stories.md
t 1 "US-DEMO-001 in P1 P2"      "trace plan doubly placed story"  trace plan docs/plans/demo.md --stories docs/prds/demo/stories.md
t 1 "P2 2.2 lacks files and satisfies" "trace plan incomplete task" trace plan docs/plans/demo.md --stories docs/prds/demo/stories.md
# Renumbering: FR-002 disappears without a strike-through; a story links the retired FR-003.
sed -i.bak '/^- \*\*FR-002\*\*/d' docs/prds/demo/prd.md && rm -f docs/prds/demo/prd.md.bak
sed -i.bak 's/^- \*\*Requirements:\*\* FR-002, NFR-001$/- **Requirements:** FR-003, NFR-001/' docs/prds/demo/stories.md && rm -f docs/prds/demo/stories.md.bak
t 1 "FR-002 existed at BASE and is gone" "trace prd --base catches renumbering" trace prd docs/prds/demo --base "$BASE"
t 1 "US-DEMO-002 links removed FR-003"   "trace prd retired link"   trace prd docs/prds/demo
t 1 "US-DEMO-004 links unknown FR-002"   "trace prd unknown link"   trace prd docs/prds/demo

# ------------------------------------------------------------------------------------ qa changed
printf 'import os\n\ndef a():\n    return 10\n\ndef b():\n    return 2\n' > src/app.py            # line 4 changed
printf '# new module\ndef c():\n    return 3\n' > src/new.py                                       # untracked
mkdir -p tests && printf 'def test_a():\n    assert True\n' > tests/test_app.py                    # untracked test
t 0 "M src/app.py 4"            "qa changed --lines (tracked)"    qa changed "$BASE" --lines
t 0 "? src/new.py 1-3"          "qa changed --lines (untracked)"  qa changed "$BASE" --lines
t 0 "changed: 3 files"          "qa changed --under filters"      qa changed "$BASE" --under src tests
t 2 "BASE is not a commit"      "qa changed bad base"             qa changed not-a-ref

# ----------------------------------------------------------------------------------- qa coverage
t 3 "GATE UNMEASURABLE: no coverage report found" "no report"     qa coverage --base "$BASE"
t 3 "report not found"          "missing --report"                qa coverage --base "$BASE" --report nope.info
mkdir -p coverage
printf 'SF:src/app.py\nDA:1,1\nDA:3,1\nDA:4,0\nDA:6,1\nDA:7,0\nend_of_record\nSF:tests/test_app.py\nDA:1,1\nDA:2,1\nend_of_record\n' > coverage/lcov.info
# changed executable lines: app.py 4 (uncovered); new.py 2,3 not in the report (0%); test file excluded → 0/3
t 1 "coverage changed 0.0% (0/3 lines, 2 files) min 80 → FAIL" "lcov changed coverage" qa coverage --base "$BASE"
t 1 "not in report (counted as 0%): src/new.py (2 lines)" "untracked file missing from report" qa coverage --base "$BASE"
t 1 "src/app.py 0.0% (0/1) uncovered 4" "per-file uncovered ranges" qa coverage --base "$BASE"
printf 'SF:src/app.py\nDA:3,1\nDA:4,3\nend_of_record\nSF:%s/src/new.py\nDA:2,1\nDA:3,1\nend_of_record\n' "$PROJ" > coverage/lcov.info
t 0 "coverage changed 100.0% (3/3 lines, 2 files) min 80 → PASS" "lcov with an absolute SF path" qa coverage --base "$BASE"
t 0 "coverage overall 100.0%"   "overall scope"                   qa coverage --scope overall
t 1 "min 101 → FAIL"            "--min overrides config"          qa coverage --base "$BASE" --min 101
cat > coverage.xml <<XML
<?xml version="1.0" ?>
<coverage line-rate="0.5"><sources><source>$PROJ</source></sources><packages><package name="src"><classes>
<class name="app.py" filename="src/app.py"><lines><line number="4" hits="1"/></lines></class>
<class name="new.py" filename="src/new.py"><lines><line number="2" hits="0"/><line number="3" hits="1"/></lines></class>
</classes></package></packages></coverage>
XML
t 1 "coverage changed 66.7% (2/3 lines, 2 files)" "cobertura report" qa coverage --base "$BASE" --report coverage.xml
t 1 "report: coverage.xml (cobertura)" "auto-detect picks the newest report" qa coverage --base "$BASE"
printf '{"files": {"src/app.py": {"executed_lines": [4], "missing_lines": []}, "src/new.py": {"executed_lines": [2, 3], "missing_lines": []}}}' > coverage.json
t 0 "coverage changed 100.0%"   "coverage.py json report"         qa coverage --base "$BASE" --report coverage.json
printf '{"x": 1}' > bad.json
t 3 "unrecognised JSON coverage format" "unknown json format"     qa coverage --base "$BASE" --report bad.json
touch -t 203001010000 src/new.py
t 3 "is older than changed sources" "stale report"                qa coverage --base "$BASE" --report coverage.json
touch src/new.py
rm -rf coverage coverage.xml coverage.json bad.json

# -------------------------------------------------------------------------------------- qa drift
# So far: prd.md, stories.md, hld.md and plan changed. prd.md is in the ledger, stories.md in a
# clarification's Recorded in; the plan has more than ticks (synced status); hld.md is unaccounted.
t 1 "docs/tech-designs/core/hld.md — not in the ledger" "unaccounted HLD change" qa drift demo --base "$BASE"
t 1 "docs/plans/demo.md — not in the ledger"        "plan with more than ticks"  qa drift demo --base "$BASE"
(cd "$PROJ" && python3 "$SF" ledger doc demo docs/prds/demo/stories.md docs/tech-designs/core/hld.md docs/plans/demo.md --written-by owner >/dev/null)
t 0 "DRIFT: none (4 document changes accounted)" "all accounted via the Documents table" qa drift demo --base "$BASE"
printf -- '---\nid: ADR-0002\nstatus: proposed\n---\n' > docs/adrs/0002-cache.md
t 1 "docs/adrs/0002-cache.md — not in the ledger" "untracked ADR is drift" qa drift demo --base "$BASE"
(cd "$PROJ" && python3 "$SF" clar add demo --asked-by swf-builder --wp P2 --owner swf-architect --q q --a a --recorded-in "docs/adrs/0002-cache.md (proposed)" >/dev/null)
t 0 "DRIFT: none"               "ADR accounted via the clarification log" qa drift demo --base "$BASE"
printf -- '---\nid: ADR-0003\n---\n' > docs/adrs/0002-cache.md.bak
t 1 "0002-cache.md.bak"         "path match is exact, not a prefix" qa drift demo --base "$BASE"
rm docs/adrs/0002-cache.md.bak
# A tick-only plan change is legitimate without a ledger entry: commit, then tick.
g add -A && g commit -qm phase
BASE2="$(git -C "$PROJ" rev-parse HEAD)"
(cd "$PROJ" && python3 "$SF" ledger init demo2 --request x --entry execute --tracks x >/dev/null)
(cd "$PROJ" && python3 "$SF" plan tick docs/plans/demo.md P2 2.2 >/dev/null)
t 0 "DRIFT: none (1 document changes accounted)" "tick-only plan change" qa drift demo2 --base "$BASE2"
sed -i.bak 's/^| P2 | feature |/| P2 | feature!! |/' docs/plans/demo.md && rm -f docs/plans/demo.md.bak
t 1 "docs/plans/demo.md"        "ticks plus another edit is drift" qa drift demo2 --base "$BASE2"
g checkout -- docs/plans/demo.md
printf '  coverage_min: 10\n' >> .sw-factory/config.yaml
t 1 ".sw-factory/config.yaml — gates or guards altered" "config change is always drift" qa drift demo2 --base "$BASE2"
g checkout -- .sw-factory/config.yaml
t 2 "no ledger for run nope"    "drift without a ledger"          qa drift nope --base "$BASE2"

# ---------------------------------------------------------------------------------- qa weakening
t 0 "weakening: none"           "no weakening"                    qa weakening --base "$BASE2"
printf 'import pytest\n\n@pytest.mark.skip(reason="flaky")\ndef test_b():\n    assert False\n' > tests/test_b.py
printf 'def d():  # pragma: no cover\n    return 4\n' > src/d.py
printf '[run]\nomit = src/d.py\n' > .coveragerc
printf 'it.skip("x", () => {})\n' > src/e.test.js
t 1 "weakening: 4 (1 coverage-config, 1 exclusion, 2 skip)" "weakening counts" qa weakening --base "$BASE2"
t 1 "tests/test_b.py:3"         "skip marker location"            qa weakening --base "$BASE2"
t 1 "src/d.py:1"                "pragma no cover location"        qa weakening --base "$BASE2"
t 1 ".coveragerc:2"             "coverage config omit"            qa weakening --base "$BASE2"

# ----------------------------------------------------------------------------------------- level
t 0 "LEVEL: L2 · deciding: D=cross"        "defect touching an interface" level R=clarify D=cross K=none S=2 G=no
t 0 "TRACK: opsx-loop"                     "L2 → opsx-loop"               level R=clarify D=cross K=none S=2 G=no
t 0 "LEVEL: L2 · deciding: R=new"          "new PRD on an existing system" level R=new D=local K=none S=10 G=no
t 0 "LEVEL: L2 · deciding: R=new, D=new, G=yes" "new service"           level R=new D=new K=none S=10 G=yes
t 0 "LEVEL: L3 · deciding: K=security"     "auth for a new service"       level R=new D=new K=security S=10 G=yes
t 0 "ADR REQUIRED: accepted ADR per flag before implementation: security" "risk flag needs an ADR" level R=new D=new K=security S=10 G=yes
t 0 "ADR REQUIRED: none"                   "perf-critical needs no ADR"   level R=none D=none K=perf-critical S=1 G=no
t 0 "LEVEL: L0 · deciding: all signals at L0" "trivial"                   level R=none D=none K=none S=1 G=no
t 0 "TRACK: direct"                        "L0 → direct"                  level R=none D=none K=none S=1 G=no
t 0 "LEVEL: L1"                            "extend with 2 stories"        level R=extend D=local K=none S=8 G=no --stories 2
t 0 "NOTE: R=extend without --stories"     "extend without a story count" level R=extend D=local K=none S=8 G=no
t 0 "LEVEL: L3 · deciding: D=cross"        "cross and large"              level R=none D=cross K=none S=20 G=no
t 0 "LEVEL: L3"                            "cross and many components"    level R=none D=cross K=none S=5 C=4 G=no
t 0 "LEDGER: P3 · L3 · openspec · K=data-migration" "ledger line"         level R=none D=none K=data-migration S=2 G=no --phase p3
t 0 "FALLBACK: opsx-loop unavailable (no) → fallback subagents" "fallback" level R=new D=local K=none S=10 G=no --tracks "TRACKS: direct=yes subagents=yes opsx-loop=no openspec=no"
t 0 "TRACK: subagents"                     "fallback track"               level R=new D=local K=none S=10 G=no --tracks "direct=yes subagents=yes opsx-loop=no openspec=no"
t 1 "TRACK: none available"                "no usable track"              level R=none D=none K=none S=1 G=no --tracks "direct=no(disabled) subagents=yes"
t 2 "R must be one of"                     "invalid R"                    level R=foo D=none K=none S=1 G=no
t 2 "missing signals: G"                   "missing signal"               level R=none D=none K=none S=1
t 2 "unknown K flags: nope"                "invalid K"                    level R=none D=none K=nope S=1 G=no

# ----------------------------------------------------------------------------------------- gates
t 0 "test ✅ exit 0 · 3 passed, 1 skipped (pytest)" "gates run test (config command)" gates run test --run demo --label P1-r0
has .sw-factory/runs/demo/logs/P1-r0-test.log '3 passed' "test log written"
t 1 "build ❌ exit 3"            "failing build"                    gates run build --run demo --label P1-r0
t 1 "    boom"                  "failure prints the log tail"      gates run build --run demo --label P1-r0
t 2 "lint: not configured"      "unconfigured gate"                gates run lint --run demo
t 0 "lint ✅ exit 0"            "--cmd for a discovered command"   gates run lint --run demo --cmd "true"
t 1 "test ❌ exit 0 · 1 failed, 2 passed (pytest)" "failed tests fail the gate despite exit 0" gates run test --run demo --cmd "sh lying-test.sh"
t 1 "build ❌"                  "all: build fails"                 gates run all --run demo --label all
t 1 "coverage: not configured"  "all: unconfigured coverage reported" gates run all --run demo --label all
t 2 "--cmd overrides one gate"  "all with --cmd"                   gates run all --run demo --cmd x

# ----------------------------------------------------------------------------------- prompt lint
# Every `swf-cli …` command written in the agent prompts, protocols, references and README must name a
# real group/command and only options that command accepts. The CLI is the single source of truth;
# this catches a prompt left behind by a renamed command or flag.
lint="$(python3 -I - "$SRC" <<'PY'
import argparse, glob, importlib.util, os, re, sys
src = sys.argv[1]
spec = importlib.util.spec_from_file_location('sf', os.path.join(src, '.sw-factory/tools/swf-cli.py'))
sf = importlib.util.module_from_spec(spec); spec.loader.exec_module(sf)
top = sf.build_parser()

def subs(p):
    return next((a.choices for a in p._actions if isinstance(a, argparse._SubParsersAction)), None)

def options(p):
    return {o for a in p._actions for o in a.option_strings}

PREFIX = re.compile(r'^(swf-cli|python3 \.sw-factory/tools/swf-cli\.py)(\s+|$)')
FENCE = re.compile(r'```[^\n]*\n(.*?)```', re.S)
files = sorted(glob.glob(src + '/.claude/agents/swf/*.md') + glob.glob(src + '/.claude/swf-tools/**/*.md', recursive=True)
               + glob.glob(src + '/.opencode/agents/*.md') + glob.glob(src + '/.opencode/swf-tools/**/*.md', recursive=True)
               + glob.glob(src + '/.sw-factory/tools/**/*.md', recursive=True)
               + [src + '/README.md'])
checked = 0
for f in files:
    text = open(f, encoding='utf-8').read()
    cmds = []
    for block in FENCE.findall(text):
        for line in re.sub(r'\\\n\s*', ' ', block).splitlines():
            line = line.split(' #')[0].strip()
            if PREFIX.match(line):
                cmds.append(line)
    for span in re.findall(r'`([^`]+)`', FENCE.sub('', text)):
        span = ' '.join(span.split())
        if PREFIX.match(span):
            cmds.append(span)
    for cmd in cmds:
        tokens = PREFIX.sub('', cmd, count=1).split()
        if not tokens:
            continue                       # the bare definition: `swf-cli` = `python3 …/swf-cli.py`
        checked += 1
        p, path, err = top, [], None
        while subs(p) and tokens and not tokens[0].startswith('-'):
            t = tokens.pop(0)
            if t not in subs(p):
                err = 'unknown %s %r' % ('command' if path else 'group', t); break
            p = subs(p)[t]; path.append(t)
        rest = ' '.join(tokens)
        if not err and subs(p) and not re.search(r'--(help|version)\b', rest):
            err = 'incomplete command'
        if not err:
            bad = [o for o in re.findall(r'(?<![\w-])--[a-z][a-z-]*', rest) if o not in options(p)]
            if bad:
                err = 'unknown option %s for "%s"' % (', '.join(bad), ' '.join(path))
        if err:
            print('FAIL %s: `%s` — %s' % (os.path.relpath(f, src), cmd, err))
print('CHECKED %d' % checked)
PY
)"
lint_fail="$(grep -c '^FAIL' <<<"$lint")"
lint_n="$(sed -n 's/^CHECKED //p' <<<"$lint")"
if [ "$lint_fail" -eq 0 ] && [ "${lint_n:-0}" -ge 80 ]; then pass=$((pass + 1))
else fail=$((fail + 1)); printf 'FAIL  prompt lint (%s commands checked, expected ≥ 80)\n' "${lint_n:-0}"; grep '^FAIL' <<<"$lint" | sed 's/^/        /'; fi

echo "swf-cli: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
