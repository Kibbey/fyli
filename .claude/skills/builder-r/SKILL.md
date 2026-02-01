---
name: builder-r
description: Recursively build multi-phase TDDs end-to-end. Coordinates architect, builder, and code-review skills to work through each phase of a TDD — reviewing, improving, building, reviewing code, fixing issues, updating the TDD, then advancing to the next phase.
allowed-tools: Read, Grep, Glob, Task, Edit, Write, Bash, Skill, AskUserQuestion
---

# Builder-R (Recursive TDD Builder)

Orchestrates the full lifecycle of a multi-phase TDD. For each phase, it reviews the TDD, proposes improvements, builds the phase, iterates on code review feedback until clean, updates the TDD to reflect progress, then moves to the next phase.

## Core Loop

For each phase in the TDD, execute the following cycle:

```
┌─────────────────────────────────────────────────┐
│  Step 1: Review TDD phase                       │
│  Step 2: Suggest improvements to the TDD phase  │
│  Step 3: User confirms which improvements       │
│  Step 4: Build phase (/builder)                 │
│  Step 5: Code review (/code-review)             │
│  Step 6: Apply all code review suggestions      │
│  Step 7a: Make sure all tests are passing       │
│  Step 7b: Re-review until clean                 │─┐
│  Step 8: Update TDD with progress               │ │
│  Step 9: /compact                               │ │
│  Step 10: Advance to next phase → Step 1        │ │
└─────────────────────────────────────────────────┘ │
         ▲                                          │
         └── (repeat steps 5-6 until no findings) ──┘
```

## Detailed Steps

### Step 1: Review TDD Phase

Read the TDD document and identify the next incomplete phase.

- Read the full TDD to understand context and dependencies
- Identify which phase is next (look for phases not marked COMPLETE)
- Read the phase requirements: tasks, components, tests, deliverables
- Check that prerequisites from earlier phases are satisfied

### Step 2: Suggest Improvements

Invoke the architect skill to review the upcoming phase for completeness and feasibility:

```
/architect Review phase [N] of the TDD at [path]. Check for completeness, accuracy, missing details, and feasibility. Suggest specific improvements.
```

Accept all suggestions and proceed to step 3

### Step 3: User Confirms Improvements

Use `AskUserQuestion` to present the improvement suggestions. Let the user choose which to accept, modify, or reject. Options:

- Accept all suggestions
- Select specific suggestions by number
- Skip improvements and build as-is
- Add their own modifications

If the user accepts improvements, apply them to the TDD before building.

### Step 4: Build the Phase

Invoke the builder skill to implement the phase:

```
/builder build [phase name] from TDD at [path]
```

The builder skill handles the actual implementation — writing code, creating tests, and following the TDD specification.

### Step 5: Code Review

After the builder completes, invoke code-review:

```
/code-review review the phase [N] implementation
```

Collect all findings (critical issues, improvements, suggestions).

Accept all findings for the user.

### Step 6: Apply Code Review Feedback

Address **all** findings from the code review:

- **Critical issues** — must fix, these are blockers
- **Improvements** — apply all recommended changes
- **Suggestions** — apply all unless they conflict with the TDD

### Step 7: Re-Review Until Clean

Validate all tests are passing.  Fix any broken tests.

After applying fixes, run code-review again:

```
/code-review review the changes made to address previous review feedback
```

Repeat steps 5-6 until the code review returns no critical issues and no meaningful improvements. Minor nitpicks or purely optional suggestions are acceptable to stop on.

**Maximum iterations:** Cap at 3 review cycles per phase. If issues persist after 3 rounds, present remaining findings to the user and ask how to proceed.

### Step 8: Update TDD

Invoke the architect skill to update the TDD:

```
/architect update TDD at [path] based on progress — mark phase [N] as complete, update code examples to match implementation, note any decisions or deviations made during building
```

This ensures the TDD always reflects reality.

### Step 9: Advance to Next Phase

run /compact

### Step 10: Advance to Next Phase

Check if there are remaining phases:

- If yes → return to Step 1 for the next phase
- If no → report completion summary

Before starting the next phase, present a brief summary to the user:

```
Phase [N] complete. [X] tests passing, [Y] review iterations.
Next up: Phase [N+1] — [phase name].
Proceed?
```

Wait for user confirmation before starting the next phase.

## Invocation

```
# Start from the beginning
/builder-r [path-to-tdd]

# Resume from a specific phase
/builder-r [path-to-tdd] --start-phase [N]

# Example
/builder-r docs/tdd/angularjs-to-vue-migration.md
```

**Arguments:**
- First argument: path to the TDD markdown file (required)
- `--start-phase N`: skip to phase N (optional, useful for resuming)

## Entry Behavior

On invocation:

1. Read the TDD document at the provided path
2. Identify all phases and their completion status
3. Find the first incomplete phase (or the phase specified by `--start-phase`)
4. Present a summary to the user:

```markdown
## TDD: [Title]

### Phase Status
- Phase 0: Foundation — COMPLETE
- Phase 1: Auth & Account — NEXT
- Phase 2: Stream — pending
- ...

Starting with Phase [N]: [Name]
```

5. Begin the core loop at Step 1

## Handling Interruptions

If the process is interrupted or context runs low:

- The TDD document itself tracks progress (phases marked COMPLETE)
- Re-invoke `/builder-r [path] --start-phase [N]` to resume
- The TDD is the persistent state — no other state tracking needed

## Completion

When all phases are complete, provide a final summary:

```markdown
## TDD Implementation Complete

### Phases Completed
- Phase 0: Foundation — [X] tests
- Phase 1: Auth & Account — [X] tests
- ...

### Total Tests: [N]
### Review Iterations: [N] total across all phases
### TDD Status: Fully implemented and up to date
```
