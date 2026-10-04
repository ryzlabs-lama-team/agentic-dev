---
name: git-commit-message
description: Generates Conventional Commits v1.0.0 compliant commit messages. Use when committing code changes, when the user asks to write a commit message, or when preparing to commit staged changes.
---

# Git Commit Message (Conventional Commits v1.0.0)

Generates commit messages that follow the [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

## How It Works

1. Analyze the staged diff (`git diff --cached`) to understand what changed
2. Determine the correct commit type from the change semantics
3. Optionally detect a scope from the affected files/modules
4. Identify if the change is a breaking change
5. Generate the commit message following the spec format
6. Present the message for user approval before committing

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Description | SemVer |
|------|-------------|--------|
| `feat` | A new feature | MINOR |
| `fix` | A bug fix | PATCH |
| `docs` | Documentation only changes | — |
| `style` | Changes that do not affect the meaning of the code (white-space, formatting, etc.) | — |
| `refactor` | A code change that neither fixes a bug nor adds a feature | — |
| `perf` | A code change that improves performance | — |
| `test` | Adding missing tests or correcting existing tests | — |
| `build` | Changes that affect the build system or external dependencies | — |
| `ci` | Changes to CI configuration files and scripts | — |
| `chore` | Other changes that don't modify src or test files | — |
| `revert` | Reverts a previous commit | — |

## Breaking Changes

Indicate a breaking change in one of two ways:

1. Append `!` after the type/scope: `feat!: remove deprecated API`
2. Add a `BREAKING CHANGE:` footer:
   ```
   feat: add new config option

   BREAKING CHANGE: `extends` key now only accepts absolute paths
   ```

## Rules

1. Type is REQUIRED and MUST be lowercase
2. Scope is OPTIONAL and MUST be a noun in parentheses: `feat(parser):`
3. Description is REQUIRED, MUST be imperative mood, MUST NOT end with period
4. Body is OPTIONAL, MUST begin one blank line after description
5. Footer is OPTIONAL, MUST begin one blank line after body
6. `BREAKING CHANGE` in footer MUST be uppercase

## Usage

The agent will:

1. Run `git diff --cached` to inspect staged changes
2. Run `git status` to see affected files
3. Determine type, scope, and description
4. Present the commit message for approval
5. Run `git commit` with the approved message

**Manual invocation:**
```bash
bash ./scripts/generate-commit.sh
```

## Examples

```
feat: allow provided config object to extend other configs
```

```
fix: prevent racing of requests
```

```
feat(api)!: send email when product is shipped

BREAKING CHANGE: email endpoint now requires authentication
```

```
docs: correct spelling of CHANGELOG
```

```
refactor: extract validation logic into shared module
```

## Output

The agent presents a formatted commit message and asks for confirmation before executing `git commit`.

## Present Results to User

```
Suggested commit message:

<type>(<scope>): <description>

<body>

<footer>

Proceed with this commit? (y/n)
```

## Troubleshooting

- **No staged changes:** Run `git add` before invoking the skill
- **Ambiguous type:** The agent will ask clarifying questions about the nature of the change
- **Multiple unrelated changes:** Recommend splitting into separate commits
