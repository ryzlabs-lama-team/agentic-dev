# Run: <slug>
Request: <verbatim from the human>
Started: <YYYY-MM-DD>
Base ref: <git rev-parse HEAD at run start, or "no git">
Branch: <git branch at run start>
Entry point: <idea | change | defect | prd-only | design-only | plan-only | execute>
Level: <L0–L3, once triaged>
Tracks available: <from preflight TRACKS line>
Commit policy: <ask | per-phase | never>

## Frame
- **Problem:** <one line>
- **Goals:** <one line>
- **Context:** <one line, or links>

## Documents
Every document or artifact an agent reports writing, one row per file. swf-qa's drift check
treats unlisted changes as drift.

| Kind | Path | Version | Status | Written by |
|---|---|---|---|---|

## Phases
Authoritative for phase status. swf-planner syncs the plan's Status column from this table.
Retries counts QA retry rounds spent (budget 2); `swf-cli.py ledger phase --retry` maintains it.

| Phase | Level | Track | Status | Base ref | Retries | Notes |
|---|---|---|---|---|---|---|

## Log
| # | Stage | Agent | Agent id | Status | Artifact | Notes |
|---|---|---|---|---|---|---|

## Human decisions
| # | Gate / question | Decision | Recorded in |
|---|---|---|---|
