---
name: code-structure
description: Use when multiple workflows duplicate the same operational logic, when deciding what belongs in actions vs shared services, or when refactoring repeated operational blocks across domain flows. Use when adding new features that share mechanics with existing ones.
---

# Service Layer Architecture

## Overview

**Two-layer separation:** Actions orchestrate domain rules (the "why/when"), while a service layer centralizes reusable operational mechanics (the "how").

This prevents duplicated code, inconsistent behavior, and bugs fixed in one path but not others.

## When to Use

- Multiple callers need the same low-level operation (sandbox creation, email sending, payment processing)
- You're copy-pasting operational logic between action files
- A bug fix in one workflow doesn't propagate to others doing the same thing
- Adding a new feature that shares mechanics with existing flows

**Don't use when:** Logic is truly domain-specific and used by only one caller.

## Core Pattern

```
Orchestration Layer (Workflow)          Service Layer (Shared Mechanics)
├── owns business rules                ├── owns reusable operations
├── owns state transitions             ├── owns provider/SDK interactions
├── owns auth/ownership checks         ├── owns command execution details
├── owns failure classification        ├── owns health checks / readiness
├── owns retries / user-facing errors  └── returns structured results
└── calls service functions
```

**Rule of thumb:**

- "What this product flow means" → keep in workflow
- "How to do this operation reliably" → move to service layer

## Quick Reference

| Design Principle   | Do                                                               | Don't                                    |
| ------------------ | ---------------------------------------------------------------- | ---------------------------------------- |
| API shape          | Composable capability blocks                                     | One giant "do everything" method         |
| Inputs/outputs     | Explicit params, structured returns                              | Hidden global state, reaching into DB    |
| Migration          | Extract one block, replace one caller, verify, then migrate rest | Refactor everything at once              |
| Domain logic       | Keep auth, policy, error classification in workflow              | Let service mutate domain state directly |
| Extraction trigger | Logic repeated across 2+ callers                                 | Logic used once (over-abstraction)       |

## Designing Services

Services should be designed with retry safety in mind:

- prefer idempotent operations
- return retry-safe structured failures
- avoid partial hidden mutations
- expose enough state for callers to recover intelligently

Create a new service when:

- a capability has its own lifecycle or operational complexity
- it interacts with an external provider/system
- multiple workflows depend on it
- it requires isolated testing/mocking

Services should emit operational telemetry appropriate for debugging and reliability monitoring.

Services may own persistence related to their operational responsibility, but should avoid implicitly coordinating unrelated domain mutations.

## Designing Service Functions

Design as **capability blocks**, not monoliths:

```ts
// Good: composable, each caller chooses what to use
createManagedSandbox(...)
prepareRepo(...)
detectPackageManager(...)
installDependencies(...)
runBuildCommand(...)
startSandboxRuntime(...)
```

Each function should:

- Accept all required data as **explicit parameters**
- Return **structured outputs** <br/> (e.g.,
  ```ts
  type BuildResult =
    | { ok: true; artifactPath: string; durationMs: number }
    | { ok: false; reason: "timeout" | "compile_error"; logs: string };
  ```
  )
- Avoid implicitly reaching into unrelated domain state or global mutable state.
- Prefer explicit dependencies and explicit ownership boundaries.
- Make failure explicit (structured results, not swallowed errors)
- Prefer discriminated unions / typed result objects over:
  - throwing generic errors
  - booleans
  - null/undefined
  - ambiguous return values

This lets callers choose strict vs relaxed behavior per flow.

### Side Effect Ownership

Service functions should ideally perform one operational responsibility.

Avoid hidden secondary side effects such as:

- analytics emission
- DB mutation outside their scope
- notifications
- cache invalidation
- unrelated orchestration

Keep orchestration decisions in workflow so flows remain understandable and composable.

## Service Layer Constraints

Services should NOT:

- know authenticated user/session context
- perform authorization decisions
- mutate unrelated domain state
- contain UI/business-policy branching
- depend on HTTP/request transport concerns

Services SHOULD:

- have explicit, well-defined operational behavior
- receive required context explicitly
- return structured operational results

## Migration Checklist

When extracting shared logic:

1. Write the flow in workflow code first (clear behavior)
2. Mark repeated operational chunks across callers
3. Extract **only** repeated, non-domain chunks to service
4. Replace one caller → verify → replace remaining callers
5. Keep domain policy in workflows (auth, status transitions, error classification)
6. Run verification: typecheck, lint, confirm all flows still work

## Anti-Patterns

| Anti-Pattern                      | Problem                                                                |
| --------------------------------- | ---------------------------------------------------------------------- |
| **God service**                   | One huge function hides all control flow                               |
| **Leaky service**                 | Service mutates database tables directly                               |
| **Inconsistent API**              | Each function uses different argument styles and error semantics       |
| **Over-abstraction**              | Extracting logic used by only one caller                               |
| **Service orchestration leakage** | Services begin coordinating unrelated workflows and business processes |

## Example: Email Service (Simple)

```ts
// emailService.ts — shared mechanics
export async function sendWelcomeEmail(params: { to: string; name: string }) {
  const html = `<h1>Welcome ${params.name}</h1>`;
  await emailProvider.send(params.to, "Welcome", html);
}

// userSignup.ts — orchestration (owns WHEN to send)
if (user.marketingOptIn) {
  await sendWelcomeEmail({ to: user.email, name: user.name });
}

// adminInvite.ts — orchestration (different business rule, same mechanic)
await sendWelcomeEmail({ to: invitee.email, name: invitee.name });
```

## Example: Bad Refactor

```ts
// BAD: service owns business workflow
completeOnboarding(userId);

// GOOD: service owns capability only
// onboardingAction.ts
await createDefaultWorkspace();
await provisionSandbox();
await sendWelcomeEmail();
```

## Mental Model

```
New feature? → Write in workflow first → See repeated ops? → Extract to service
                                      → No repetition?  → Keep in workflow
```

Your architecture in one sentence: **Workflows orchestrate domain rules, while the service layer centralizes reusable operational mechanics with a composable, explicit-input API.**
