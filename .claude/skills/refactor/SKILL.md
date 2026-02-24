---
name: refactor
description: Audit the codebase for dead code, duplicate code, inefficient code, overloaded code, missing test coverage, non-conforming code, stale documentation, and other best practice violations. Uses parallel subagents for discovery and hands off findings to /architect to create a TDD for fixes.
allowed-tools: Read, Grep, Glob, Task, Skill, AskUserQuestion, Bash
---

# Refactor Skill

Systematically audit the codebase for code health issues using parallel subagents for discovery, then hand off findings to `/architect` to produce a TDD for remediation.

## Invocation

```
# Audit everything
/refactor

# Audit a specific area
/refactor cimplur-core/Memento/Domain/Repositories

# Audit a specific category only
/refactor --category dead-code
/refactor --category duplicates
```

**Arguments:**
- First argument (optional): path to scope the audit (directory or file)
- `--category <name>`: limit to a single audit category (see categories below)

## Process

```
┌──────────────────────────────────────────────────────┐
│  Phase 1: Scope & Plan                               │
│  Phase 2: Parallel Discovery (7 subagents)           │
│  Phase 3: Consolidate & Deduplicate Findings         │
│  Phase 4: User Prioritization                        │
│  Phase 5: Hand Off to /architect for TDD             │
└──────────────────────────────────────────────────────┘
```

### Phase 1: Scope & Plan

Determine audit scope based on arguments:

1. **If a path is provided** — audit only that directory/file
2. **If a category is provided** — run only that audit category
3. **If no arguments** — audit the full codebase (both `cimplur-core` and `fyli-fe-v2`)

Before launching subagents, read key project files for context:
- `CLAUDE.md` — project conventions and structure
- `docs/FRONTEND_STYLE_GUIDE.md` — frontend style standards
- `docs/TESTING_BEST_PRACTICES.md` — testing standards

### Phase 2: Parallel Discovery

Launch **up to 7 subagents in parallel** using the Task tool (`subagent_type: Explore`). Each subagent focuses on one audit category. Give each subagent the audit scope (path) and project conventions so it can work independently.

Each subagent must return findings in this format:

```
## [Category Name] Findings

### Finding 1: [Short title]
- **Severity:** Critical | High | Medium | Low
- **Location:** file_path:line_number
- **Description:** What the issue is
- **Evidence:** Code snippet or explanation proving the issue
- **Suggested fix:** Brief description of how to resolve

### Finding 2: ...
```

#### Category 1: Dead Code

Search for code that is never called, never imported, or unreachable.

**Backend (C#):**
- Public methods never referenced outside their class
- Unused `using` statements
- Commented-out code blocks (more than 3 lines)
- Unreachable code after `return`/`throw`
- Unused private fields or properties
- Empty catch blocks that swallow exceptions
- Unused constructor parameters

**Frontend (Vue/TypeScript):**
- Exported functions/types never imported elsewhere
- Components never used in templates or router
- Dead store actions/getters never called
- Unused composable return values
- CSS classes defined but never applied
- Unused event handlers or watchers

#### Category 2: Duplicate Code

Search for code that is repeated and should be abstracted.

- Methods or functions with near-identical logic (>10 lines of similar structure)
- Copy-pasted validation logic across controllers or components
- Repeated API call patterns that could be a shared utility
- Duplicate type definitions or interfaces
- Repeated error handling blocks with identical structure
- Similar LINQ/EF query patterns across repositories

**Note:** 3 similar lines is fine — only flag genuine duplication where abstraction would reduce bugs.

#### Category 3: Inefficient Code

Search for performance problems and wasteful patterns.

**Backend:**
- N+1 query patterns (loading in loops without `Include`)
- Missing `AsNoTracking` on read-only queries
- Large datasets loaded into memory when paging is needed
- Synchronous I/O in async methods
- String concatenation in loops (should use `StringBuilder`)
- Unnecessary `ToList()` before further LINQ operations

**Frontend:**
- Large reactive objects that should use `shallowRef`
- Missing `v-once` on static content in hot paths
- Watchers that could be computed properties
- Unnecessary re-renders from improper reactivity
- Unbounded list rendering without virtual scroll
- API calls in components that should be in stores/composables
- Large synchronous imports that should be lazy-loaded

#### Category 4: Overloaded Code

Search for classes, methods, or components doing too much.

- Methods over 100 lines
- Classes with more than 10 public methods (God class)
- Components with more than 300 lines of `<script>` (should be split)
- Controllers with business logic (should be in services)
- Services mixing data access with business rules
- Functions with more than 5 parameters
- Deeply nested conditionals (>3 levels)

#### Category 5: Missing Test Coverage

Search for untested code paths.

**Backend:**
- Services without corresponding test files in `DomainTest/`
- Public methods without any test exercising them
- Error/exception paths without tests
- Edge cases (null inputs, empty collections, boundary values) untested

**Frontend:**
- Components without `.test.ts` files
- Stores without test files
- Composables without test files
- API service files without test files
- Only happy-path tests (missing error path coverage)

Cross-reference existing test files against source files to find gaps.

#### Category 6: Non-Conforming Code

Search for violations of project conventions defined in `CLAUDE.md`, `FRONTEND_STYLE_GUIDE.md`, and `TESTING_BEST_PRACTICES.md`.

**Backend:**
- Non-PascalCase method/property names
- Non-camelCase local variables or parameters
- Missing `I` prefix on interfaces
- Hardcoded connection strings or secrets
- Raw SQL instead of EF Core
- Missing async/Task patterns on I/O methods
- Switch statements where factory pattern is appropriate

**Frontend:**
- Options API instead of Composition API with `<script setup>`
- Hardcoded hex colors instead of CSS variables or Bootstrap classes
- Missing TypeScript types (implicit `any`)
- Index-based `v-for` keys
- Props without `defineProps<T>()` typing
- Emits without `defineEmits<T>()` typing
- Business logic in components instead of stores/composables

#### Category 7: Stale Documentation & Other Issues

Search for documentation that is out of sync and other best practice violations.

**Documentation:**
- API endpoints in swagger not matching controller routes
- README or guide references to renamed/deleted files
- TDDs in `docs/tdd/` that are fully complete but not archived
- Outdated code examples in documentation
- Missing release notes for shipped features

**Other Best Practices:**
- Missing input validation at system boundaries
- Inconsistent error response formats
- Missing null checks on external data
- Magic numbers/strings that should be constants
- TODO/FIXME/HACK comments left in code
- Inconsistent naming between frontend API services and backend endpoints
- Missing `try/catch` on fire-and-forget async calls

### Phase 3: Consolidate & Deduplicate

After all subagents return:

1. **Merge findings** from all 7 categories into a single list
2. **Deduplicate** — if multiple categories flagged the same code, merge into one finding
3. **Sort by severity** — Critical > High > Medium > Low
4. **Group by area** — Backend vs. Frontend, then by directory

Present a summary table to the user:

```markdown
## Audit Summary

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| Dead Code | 0 | 2 | 5 | 3 | 10 |
| Duplicates | 0 | 1 | 3 | 0 | 4 |
| Inefficient | 1 | 0 | 2 | 1 | 4 |
| Overloaded | 0 | 1 | 2 | 0 | 3 |
| Test Coverage | 0 | 3 | 5 | 0 | 8 |
| Non-Conforming | 0 | 0 | 4 | 6 | 10 |
| Documentation | 0 | 0 | 2 | 3 | 5 |
| **Total** | **1** | **7** | **23** | **13** | **44** |
```

Then list all findings grouped by severity.

### Phase 4: User Prioritization

Use `AskUserQuestion` to let the user decide what to address:

- **Fix all** — create a TDD covering all findings
- **Critical & High only** — skip medium/low
- **Select specific categories** — pick which categories to fix
- **Select specific findings** — cherry-pick individual items

### Phase 5: Hand Off to /architect

Invoke the `/architect` skill with the selected findings:

```
/architect Create a TDD at docs/tdd/refactor-<slug>.md for the following codebase issues found during audit:

[paste consolidated findings here]

Group fixes into logical phases. Each phase should be independently buildable and testable.
```

The architect skill will:
1. Create the TDD with phased implementation plan
2. Run `/code-review` on the TDD
3. Return the TDD path for `/builder` or `/builder-r` to implement

## Severity Definitions

| Severity | Definition | Examples |
|----------|-----------|----------|
| **Critical** | Active bugs, security vulnerabilities, data corruption risks | SQL injection, missing auth checks, race conditions |
| **High** | Significant maintainability or performance problems | God classes, N+1 queries, zero test coverage on critical paths |
| **Medium** | Code smells that increase maintenance burden over time | Duplicate code, overlong methods, missing types |
| **Low** | Style nits, minor improvements, nice-to-haves | Naming conventions, minor doc gaps, unused imports |

## Rules

- Never modify code during the audit — this skill is discovery only
- Always back findings with evidence (file path, line number, code snippet)
- Do not flag intentional patterns documented in `CLAUDE.md` as violations
- Do not flag test files for convention violations (test code has different standards)
- Respect the scope — if a path is provided, do not audit outside it
- If a category finds zero issues, report that explicitly (it is valuable signal)
- Cap findings at 20 per category to avoid overwhelming the user — prioritize by severity
