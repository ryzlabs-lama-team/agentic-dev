# github-copilot-loop-runtime Specification

## Purpose

Defines the GitHub Copilot distribution of the opsx loop, with VS Code as the required orchestration runtime and portable custom-agent profiles for other Copilot runtimes where supported.

Toolkit source files live under `opsx-loop/` in this repository. Unless stated otherwise, paths in
the requirements below are paths in a target repository after installation; source paths add the
`opsx-loop/` prefix. The toolkit README is `opsx-loop/README.md`.

## Requirements

### Requirement: The Copilot distribution exposes one coordinator and six worker agents

The toolkit SHALL ship exactly seven custom-agent profiles under `.github/agents/`: `opsx-loop`, `opsx-explorer`, `opsx-proposer`, `opsx-implementer`, `opsx-implementer-hard`, `opsx-verifier`, and `opsx-syncer`. `opsx-loop` SHALL be selectable by a user as the primary coordinator. The other six SHALL be worker subagents and SHALL NOT be user-selectable. `opsx-implementer-hard` SHALL remain separately addressable for retry escalation.

The coordinator SHALL be allowed to delegate only to those six workers. Workers SHALL NOT delegate to other agents, keeping the topology flat.

#### Scenario: VS Code discovers the complete topology
- **WHEN** VS Code loads a repository containing the distribution
- **THEN** `opsx-loop` is user-selectable, all six workers are available to it as subagents, and none of the workers is user-selectable

#### Scenario: Worker cannot create a nested delegation
- **WHEN** any worker attempts to delegate work to another agent
- **THEN** the runtime does not make an agent-delegation capability available to that worker

### Requirement: Every Copilot agent retains an explicit model allocation

Every Copilot agent profile SHALL declare a non-empty `model` configuration rather than relying solely on the active runtime default. The allocation SHALL retain the existing intent: Luna for `opsx-loop` and `opsx-syncer`, Terra for `opsx-explorer` and `opsx-implementer`, and Sol for `opsx-proposer`, `opsx-implementer-hard`, and `opsx-verifier`.

The profiles and `opsx-loop/README.md` SHALL identify any ordered model fallback values and SHALL state that model availability and fallback selection depend on the Copilot client and subscription. Release validation SHALL confirm that each profile has at least one configured model available in the supported VS Code environment.

#### Scenario: Every profile declares its allocated tier
- **WHEN** the seven Copilot profiles are inspected
- **THEN** each contains a non-empty model configuration matching its Luna, Terra, or Sol allocation

#### Scenario: Primary environment lacks every configured value
- **WHEN** no configured model value for an agent is available in the supported VS Code environment
- **THEN** release validation reports that agent and fails

### Requirement: Coordinator preserves the governed serial loop

The Copilot coordinator SHALL run the stages serially in this order: explore, propose, human gate, apply, verify, sync, with archive only when requested. It SHALL delegate each stage to a fresh purpose-specific worker and SHALL NOT perform stage work itself. The verifier SHALL always be a different spawn from the implementer whose work it reviews, and implementers SHALL report a specification conflict rather than edit OpenSpec artifacts.

The coordinator SHALL pass context between isolated workers through `openspec/changes/<id>/**`, `.opsx-run/<slug>/brief.md`, `.opsx-run/<slug>/verify-<n>.md`, and `.opsx-run/<slug>/ledger.md`; worker return payloads SHALL remain at most 30 lines. The coordinator SHALL maintain the ledger but SHALL NOT read application code, specifications, or diffs.

#### Scenario: Successful run uses isolated serial stages
- **WHEN** a run succeeds without retries
- **THEN** each stage is handled by a fresh matching worker in the prescribed order and sync starts only after an independent verify result passes

#### Scenario: Implementer detects a specification conflict
- **WHEN** an implementer finds that the approved delta specification is incorrect
- **THEN** it stops without editing the specification and the coordinator routes the issue to the proposer

### Requirement: Human approval is mandatory before implementation

After propose succeeds, the coordinator SHALL stop before any apply delegation and present the change id, artifact paths, requirement and task counts, and encoded assumptions. It SHALL require an explicit approve, revise, or abandon decision and SHALL NOT interpret silence or an ambiguous response as approval.

On approve it SHALL proceed to apply. On revise it SHALL delegate revision to a fresh proposer and present the gate again. On abandon it SHALL stop the run without writing application code.

#### Scenario: Approval permits apply
- **WHEN** propose succeeds and the human explicitly approves the presented plan
- **THEN** the coordinator records approval and delegates apply to a fresh implementer

#### Scenario: Ambiguous gate response
- **WHEN** the response is not a clear approve, revise, or abandon decision
- **THEN** the coordinator asks again and does not delegate apply

### Requirement: Blocking verification has a two-round fresh-worker retry budget

The coordinator SHALL delegate the initial apply and retry round one to fresh `opsx-implementer` workers. If verification remains blocking after round one, it SHALL delegate retry round two to a fresh `opsx-implementer-hard` worker. Each retry SHALL receive the latest findings path and re-read the approved artifacts. After blocking verification following round two, the coordinator SHALL stop and report the outstanding findings without a third retry.

#### Scenario: First blocking verification uses standard implementer
- **WHEN** verification is blocking and no retry round has yet run
- **THEN** a fresh `opsx-implementer` receives the findings path for retry round one

#### Scenario: Second blocking verification escalates by worker identity
- **WHEN** verification is blocking after retry round one
- **THEN** a fresh `opsx-implementer-hard` receives the findings path for retry round two

#### Scenario: Retry budget is exhausted
- **WHEN** verification remains blocking after retry round two
- **THEN** the coordinator stops and reports the findings path and attempted rounds without spawning another implementer

### Requirement: Workers resolve GitHub OpenSpec stage instructions without toolkit-owned copies

Explorer, proposer, implementer, and syncer profiles SHALL resolve their stage procedure from the corresponding installed OpenSpec skill under `.github/skills/`, then from the corresponding OpenSpec prompt under `.github/prompts/`, then from an OpenSpec CLI instruction where that fallback exists. The verifier SHALL remain self-contained and SHALL use OpenSpec status, show, and validation commands rather than depend on a nonexistent verify skill or prompt.

The Copilot distribution SHALL NOT install or overwrite `.github/skills/openspec-*`, `.github/prompts/opsx-*.prompt.md`, or repository-wide Copilot instruction files.

#### Scenario: OpenSpec-owned assets remain prerequisites
- **WHEN** the toolkit distribution is enumerated or installed
- **THEN** it contains no OpenSpec skill, OpenSpec stage prompt, or repository-wide Copilot instructions

#### Scenario: Verifier resolves independently
- **WHEN** `opsx-verifier` starts
- **THEN** it requires no verify skill or prompt and reads change state through the OpenSpec CLI

### Requirement: VS Code is the required runtime and other Copilot runtimes are best effort

The agent profiles SHALL omit a target restriction so runtimes that recognize workspace profiles can discover them. Documentation and acceptance tests SHALL identify current VS Code as the only required full-loop runtime. Copilot CLI and Copilot cloud agent SHALL be described as experimental or best effort until each runtime has passed an end-to-end test demonstrating coordinator-to-worker delegation and the complete loop topology.

#### Scenario: VS Code completes acceptance run
- **WHEN** the distribution is released
- **THEN** a VS Code end-to-end acceptance run has exercised delegation, the human gate, independent verification, and successful completion

#### Scenario: CLI has not passed end-to-end validation
- **WHEN** Copilot CLI can discover the profiles but has not passed the topology acceptance run
- **THEN** documentation does not claim full-loop CLI parity or support

### Requirement: Copilot preflight validates files, prerequisites, and primary-runtime readiness

The distribution SHALL provide a Copilot preflight command that can be run from the target repository root and exits non-zero when required static prerequisites are absent. It SHALL verify the OpenSpec CLI, an OpenSpec root, all seven Copilot profiles, required profile role/delegation declarations, explicit model declarations, and writable `.opsx-run/` state. Missing OpenSpec GitHub skills or prompts and an unignored `.opsx-run/` SHALL be warnings because stage fallbacks or local policy can vary.

The preflight SHALL report when VS Code runtime or model availability cannot be verified automatically and SHALL provide the documented manual validation step rather than claiming success for an unperformed runtime check.

#### Scenario: Copilot agent profile is missing
- **WHEN** one of the seven profiles is absent
- **THEN** preflight names the missing profile and exits non-zero

#### Scenario: Runtime validation cannot be automated
- **WHEN** static checks pass but preflight cannot query VS Code agent or model availability
- **THEN** preflight reports the manual VS Code validation still required and does not claim that runtime readiness was verified
