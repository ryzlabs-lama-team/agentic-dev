---
name: terraform
description: Routes Terraform work to the matching reference skill in "../../skills-library/terraform/". Use whenever a task touches Terraform — writing or reviewing HCL, module design and refactoring, style and naming conventions, Azure Verified Modules, .tftest.hcl tests, Stacks (.tfcomponent.hcl/.tfdeploy.hcl), policy files (.policy.hcl), search and bulk import, or building a Terraform provider in Go with the Plugin Framework — before answering Terraform questions from memory or writing HCL.
---

# Terraform

`../../skills-library/terraform/` holds 16 reference skills covering Terraform configuration authoring and Terraform provider development. They are a library, not auto-loaded context: nothing reaches you until you read it. This skill decides which one to open.

Unlike the Azure library, these files are guidance you can act on directly — conventions, worked examples, decision trees — not URL indexes. Several carry `references/`, `examples/`, `assets/` or `scripts/` companion directories alongside `SKILL.md`; the `SKILL.md` says when to load them.

## Procedure

1. Match the task against the routing tables below. More than one row can apply — a new Azure module that needs AVM certification and tests is three.
2. Open `../../skills-library/terraform/<skill>/SKILL.md`. The small ones (40–75 lines) read whole. For the 200–615 line ones, read the headings first and then only the sections the task needs.
3. Follow the companion-file pointers the skill gives you, on demand. Do not read a `references/` directory speculatively.
4. Apply the guidance as written. When it fixes a version, a file name, a block syntax or a required attribute, follow it rather than recalling from memory — that is what drifts.

## Writing Terraform configuration

This is the family that applies to `terraform/`, this repo's Azure infrastructure.

| Read this skill | When the task involves |
|---|---|
| `terraform-style-guide` | Writing or reviewing any HCL: file organization, formatting, naming, variable and output conventions, `for_each` vs `count`, version pinning, provider blocks, validation tooling. The default entry point for authoring work |
| `refactor-module` | Turning a monolithic configuration into reusable modules, module interface design, module README and input/output documentation |
| `azure-verified-modules` | Azure modules that must meet AVM certification: TFFR/TFNFR requirements, mandatory variable and output shapes, cross-module referencing with pinned registry versions, the compliance checklist |
| `terraform-test` | `.tftest.hcl` files, `run` blocks, assertions, mocking providers and data sources, testing module outputs, running and troubleshooting `terraform test` |
| `terraform-stacks` | `.tfcomponent.hcl` and `.tfdeploy.hcl`, components and deployments, multi-region or multi-environment topologies, linked stacks, the Stacks CLI |
| `terraform-search-import` | Bringing existing unmanaged cloud resources under Terraform, Search queries, list blocks, bulk `import`, generated configuration. Requires Terraform 1.14+ and provider list-resource support; its decision tree covers the unsupported case |
| `terraform-policy` | `.policy.hcl` and `.policytest.hcl` authoring and testing, converting Sentinel policies to tfpolicy |

## Building a Terraform provider

This family is about writing a `terraform-provider-*` in Go with the Plugin Framework. It does not apply to consuming providers such as `azurerm` — reach for it only when the task is to build or change a provider itself.

| Read this skill | When the task involves |
|---|---|
| `new-terraform-provider` | Scaffolding a new provider: workspace layout, Go module setup, `main.go` provider server, initial `provider.go` schema and `Configure` |
| `provider-configuration` | Provider schema for credentials, environment-variable fallbacks, credential provider chains, unknown-value guards in `Configure()`, secret redaction, "no valid credential sources" errors |
| `provider-resources` | Resource and data source CRUD, schema design, plan modifiers and validators, not-found and drift handling, waiters for eventually consistent APIs, import support |
| `provider-ephemeral-resources` | Open/Renew/Close lifecycle, values that must never persist in state or plan, write-only attributes, short-lived credentials feeding another provider |
| `provider-actions` | Imperative operations that run at lifecycle events — before/after create, update, destroy |
| `provider-framework-migration` | SDKv2 → Plugin Framework conversion, muxing with `terraform-plugin-mux`, schema mapping (`ForceNew`, `ValidateFunc`, `DiffSuppressFunc`, `Default`, blocks), null-vs-zero-value traps, post-migration plan diffs |
| `provider-test-patterns` | Writing acceptance tests: `TestCase`/`TestStep`, `ConfigStateChecks`, plan checks, `CompareValue`, import testing, sweepers, scenario patterns |
| `run-acceptance-tests` | Actually running `TestAcc*` tests, missing environment variables, diagnosing a failing or suspiciously passing acceptance test |
| `provider-docs` | Registry documentation, `tfplugindocs` templates, schema descriptions, validating generated docs |

## When nothing matches

The library covers configuration authoring and provider development. It has no skill for backends and remote state, workspaces, HCP Terraform / Terraform Cloud workspace administration, CI/CD pipelines that run `plan` and `apply`, or the resource schemas of any particular provider.

For `azurerm` resource arguments and Azure service behavior, use the `azure-cloud` skill and the provider registry docs, not this library. For anything else uncovered, say so and work from the official Terraform documentation — do not substitute a neighbouring skill, and do not answer from memory on versions, block syntax, or required attributes.
