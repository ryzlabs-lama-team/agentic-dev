# Run: install-no-clobber
Goal: install.sh must not silently overwrite existing opsx-* agent/skill files that a user has customized; detect and require an explicit flag to overwrite.
Change id: add-install-clobber-guard
Started: 2026-08-31

| Stage | Status | Artifact | Notes |
|---|---|---|---|
| preflight | ok | — | openspec 1.11.0, schema spec-driven, 6 commands + 6 skills |
| explore | ok | .opsx-run/install-no-clobber/brief.md | scope: hash-manifest guard, plan-then-commit, --force; 7 open Qs w/ assumptions |
| propose | ok | openspec/changes/add-install-clobber-guard/ | 12 reqs / 39 scenarios, 20 tasks in 6 groups, validate pass |
| gate | awaiting | — | human approval required before apply |
| gate | revise | — | human: trim 4 regression-pinning reqs, keep 8 guard reqs |
| update | ok | openspec/changes/add-install-clobber-guard/ | trimmed 12->8 reqs, 39->24 scenarios, 20->19 tasks; strict pass |
| apply r1 | ok | install.sh, README.md | 19/19 tasks ticked; all 6 group verifications pass |
| verify r1 | pass-with-advisories | .opsx-run/install-no-clobber/verify-1.md | 8/8 reqs, 0 blocking, 6 advisory; bash 3.2.57; no spec drift |
| sync | ok | openspec/specs/toolkit-install/spec.md | 8 added, 0 mod/rem/ren; validate pass; change still active |
| archive | ok | openspec/changes/archive/2026-08-31-add-install-clobber-guard | validate --all --strict pass; no active changes |
| archive | note | — | syncer used mv instead of `openspec archive`; end state correct, agent file hardened with --skip-specs guidance |
