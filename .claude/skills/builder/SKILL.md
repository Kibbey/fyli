---
name: builder
description: Implement code from a TDD (Technical Design Document). Use when asked to build a feature from a TDD, implement a design, or code from a specification. Follows the TDD precisely, implements in phases, and submits for code review.
allowed-tools: Read, Grep, Glob, Task, Edit, Write, Bash, Skill, AskUserQuestion
---

# Builder

Implements features and functionality from Technical Design Documents (TDDs). This skill takes a completed TDD as input, methodically implements each component following the specification, and ensures quality through the code-review skill.

## Core Principles

1. **TDD is the Source of Truth** - Never deviate from the TDD without explicit user approval
2. **Incremental Implementation** - Build in phases, validating each before proceeding
3. **Test-Driven Development** - Write tests before implementation code
4. **Fail Fast** - Surface blockers and ambiguities immediately
5. **Review Before Completion** - Always submit to code-review skill

## Implementation Process

### Phase 1: TDD Analysis

Before writing any code:

1. **Read the TDD completely** - Understand the full scope before starting
2. **Identify dependencies** - Map out what needs to be built first
3. **Validate prerequisites** - Ensure required infrastructure exists
4. **Clarify ambiguities** - Ask user about any unclear requirements
5. **Create implementation order** - Sequence tasks based on dependencies

```
TDD Analysis Checklist:
[ ] Read entire TDD document
[ ] List all components to be created
[ ] Identify database migrations needed
[ ] Map API endpoints to controllers
[ ] Note integration points with existing code
[ ] Flag any ambiguous requirements for clarification
```

**Create Task List**: After analysis, use `TaskCreate` to create tasks for each implementation phase. Update task status to `in_progress` when starting a phase and `completed` when finished. This provides visibility into progress and helps resume interrupted work.

### Phase 2: Foundation Layer

Build from the bottom up following the 3-tier architecture:

#### 2.1 Database Layer (EF Core Code-First)
This project uses **EF Core Code-First migrations** with **SQL Server** (not PostgreSQL). Never write raw SQL for schema changes.
1. Create/update POCO entity class in `cimplur-core/Memento/Domain/Entities/`
2. Add FK and index configuration in `StreamContext.cs` → `OnModelCreating`
3. Add `DbSet<T>` property to `StreamContext.cs`
4. Generate migration: `cd cimplur-core/Memento && dotnet ef migrations add <Name>`
5. Generate SQL script for production: `cd cimplur-core/Memento && dotnet ef migrations script <PreviousMigration> <NewMigration> --project Domain --startup-project Memento --idempotent` and save to `docs/migrations/<Name>.sql`
6. Update `cimplur-core/docs/DATA_SCHEMA.md` with schema changes
7. Run migrations to verify they work

**SQL Server Syntax Reminder:** When TDDs include raw SQL reference scripts, ensure they use SQL Server syntax:
- `INT IDENTITY(1,1)` (not `SERIAL`), `DATETIME2` (not `TIMESTAMPTZ`), `BIT` (not `BOOLEAN`), `UNIQUEIDENTIFIER` (not `UUID`), `NVARCHAR` (not `VARCHAR` for Unicode), square brackets for identifiers

#### 2.2 Repository Layer
1. Create repository files in `cimplur-core/Repositories/`
2. Implement CRUD operations as specified in TDD
3. Write unit tests in `cimplur-core/Tests/Unit/Repositories/`

```csharp
// Repository Pattern Example
public class ExampleRepository : IExampleRepository
{
    private readonly AppDbContext _context;

    public ExampleRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Example?> FindByIdAsync(string id)
    {
        // Data access only - no business logic
    }

    public async Task<Example> CreateAsync(CreateExampleData data)
    {
        // Return domain model
    }
}
```

### Phase 3: Business Layer

Implement services following domain-driven design:

1. Create service files in `cimplur-core/Services/`
2. Implement business logic as specified in TDD
3. Use repositories for data access
4. Write unit tests in `cimplur-core/Tests/Unit/Services/`

```csharp
// Service Pattern Example
public class ExampleService
{
    private readonly IExampleRepository _exampleRepository;

    public ExampleService(IExampleRepository exampleRepository)
    {
        _exampleRepository = exampleRepository;
    }

    public async Task<ExampleResult> ProcessExampleAsync(ExampleInput input)
    {
        // Business logic here
        // Validation, transformations, orchestration
    }
}
```

### Phase 4: Presentation Layer

Implement controllers:

1. Create controller files in `cimplur-core/Controllers/`
2. Configure routing via attributes
3. Implement request/response model translation
4. Write integration tests

```csharp
// Controller Pattern Example
[ApiController]
[Route("api/[controller]")]
public class ExampleController : ControllerBase
{
    private readonly ExampleService _exampleService;

    public ExampleController(ExampleService exampleService)
    {
        _exampleService = exampleService;
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<ExampleResponse>> Get(string id)
    {
        // 1. Validate request
        // 2. Transform to domain model
        // 3. Call service
        // 4. Transform to response model
        // 5. Return response
    }
}
```

### Phase 5: Frontend Implementation

If TDD includes frontend components:

1. Create Vue components in `client/src/components/`
2. Use Composition API with `<script setup>`
3. Create/update stores in `client/src/stores/`
4. Add routes in `client/src/router/`
5. Implement API services in `client/src/services/`

```vue
<!-- Component Pattern Example -->
<template>
	<div class="example-component">
		<!-- Template content -->
	</div>
</template>

<script setup lang="ts">
import { ref, computed } from "vue";
import type { ExampleProps } from "@/types/example.types";

const props = defineProps<ExampleProps>();
const emit = defineEmits<{
	(e: "update", value: string): void;
}>();
</script>

<style scoped>
/* Scoped styles */
</style>
```

### Phase 6: Testing

Implement tests as specified in TDD:

1. **Unit Tests** - Test individual functions and methods
2. **Integration Tests** - Test API endpoints end-to-end
3. **Component Tests** - Test Vue components in isolation

**Run the test suites** to verify all tests pass before proceeding:

```bash
# Backend tests
cd cimplur-core/Memento && dotnet test

# Frontend tests
cd fyli-fe-v2 && npm run test:unit -- --run
```

Fix any failing tests before moving to Phase 7.

```
Testing Checklist:
[ ] All repository methods have unit tests
[ ] All service methods have unit tests
[ ] All API endpoints have integration tests
[ ] Edge cases and error conditions tested
[ ] Test coverage meets 70% minimum
[ ] All tests passing (verified by running test suite)
```

> **Full testing standards:** See `docs/TESTING_BEST_PRACTICES.md` for detailed backend and frontend testing patterns, examples, and checklists.

### Phase 7: Documentation Updates

Update documentation as required:

1. Update `cimplur-core/docs/DATA_SCHEMA.md` for schema changes
2. Update `/docs/AI_PROMPTS.md` for any AI prompt changes
3. Add release notes to `/docs/release_note.md`
4. Update README.md if needed

### Phase 8: Code Review

**MANDATORY**: Before completing, invoke the code-review skill:

```
/code-review
```

Address all critical issues and improvements identified by the review.

## Error Handling

Follow the global error handling pattern:

```csharp
// Throw typed exceptions - let global handler process
if (!authorized)
{
    throw new UnauthorizedException("User does not have access to this resource");
}

if (!valid)
{
    throw new ValidationException("Invalid input", validationErrors);
}
```

## Implementation Guidelines

### Do
- Follow the TDD specification exactly
- Write tests before implementation
- Use existing patterns from the codebase
- Keep methods under 100 lines
- Use factory patterns over if/else chains
- Commit logical chunks of work
- Ask for clarification on ambiguities

### Don't
- Deviate from TDD without approval
- Skip writing tests
- Add features not in the TDD
- Over-engineer or add unnecessary abstractions
- Ignore existing code patterns
- Leave TODO comments without creating tasks

## Handling TDD Gaps

If the TDD is missing information:

1. **Minor gaps** - Make reasonable assumptions, document in code comments
2. **Significant gaps** - Ask the user for clarification before proceeding
3. **Contradictions** - Stop and clarify with the user

## Pre-Completion Checklist

Before marking implementation complete:

```
[ ] All TDD components implemented
[ ] All tests written and passing
[ ] No C# compiler errors
[ ] Code analysis passes with no errors
[ ] Database migrations applied successfully
[ ] Documentation updated (DATA_SCHEMA.md, AI_PROMPTS.md if applicable)
[ ] Release notes added to /docs/release_note.md
[ ] Code review completed via /code-review skill
[ ] All critical review issues addressed
```

## Invocation Examples

```
# Build from a specific TDD
/builder docs/tdd/user-authentication.md

# Build with a focus area
/builder docs/tdd/payment-system.md --focus backend

# Build and skip to a specific phase
/builder docs/tdd/dashboard-feature.md --start-phase 3
```

## Output Format

When starting implementation, provide a summary:

```markdown
## Implementation Plan for [TDD Name]

### Components to Build
1. [Component 1] - [Brief description]
2. [Component 2] - [Brief description]

### Implementation Order
1. [First task]
2. [Second task]
...

### Estimated Phases
- Phase 2 (Foundation): [components]
- Phase 3 (Business): [components]
- Phase 4 (Presentation): [components]
- Phase 5 (Frontend): [components]

### Dependencies/Prerequisites
- [Any required setup or existing components]

### Questions/Clarifications Needed
- [Any ambiguities found in TDD]
```

When completing implementation:

```markdown
## Implementation Complete

### Components Built
- [x] [Component 1]
- [x] [Component 2]

### Tests Added
- [x] [Test file 1] - [X tests]
- [x] [Test file 2] - [X tests]

### Documentation Updated
- [x] DATA_SCHEMA.md
- [x] release_note.md

### Code Review Results
- Critical Issues: [X] (all resolved)
- Improvements: [X] (addressed)
- Suggestions: [X] (optional, [X] implemented)

### Next Steps (if any)
- [Any follow-up items]
```
