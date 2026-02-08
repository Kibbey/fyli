---
name: fixer
description: Debug and fix broken code. Use when errors occur, tests fail, or the application isn't working as expected. Performs root cause analysis, implements fixes, adds regression tests, and documents the bug.
allowed-tools: Read, Grep, Glob, Task, Edit, Write, Bash, Skill
---

# Fixer Skill

Systematically debug issues, implement fixes, and document bugs to prevent recurrence.

## Debugging Process

### Phase 1: Gather Information

1. **Check error logs** in order of priority:
   - `docs/issue.md` - User-reported issues if logs are empty
   - Application logs - Recent errors with stack traces
   - Server logs are in cimplur-core/Memento/logs
   - Combined log output including info/debug

2. **Identify the error pattern**:
   - Error message and error code
   - Stack trace (file paths, line numbers)
   - Timestamp and frequency (how often does it occur?)
   - Request context (URL, method, user action)

3. **Check if this is a known bug** - Review `common_bugs.md` for similar errors

```
Information Gathering Checklist:
[ ] Read error.log for recent errors
[ ] Identify the error message and stack trace
[ ] Note the file(s) and line number(s) involved
[ ] Check common_bugs.md for existing documentation
[ ] Understand what user action triggered the error
```

### Phase 2: Root Cause Analysis

1. **Read the code** at the locations identified in the stack trace
2. **Trace the data flow** - Follow the path from request to error
3. **Identify the root cause** - Not just the symptom, but WHY it happened
4. **Verify understanding** - Explain the bug before attempting to fix

Common root causes to check:
- **Data issues**: Null values, type mismatches, invalid formats
- **Schema mismatches**: Code expects columns/tables that don't exist
- **Race conditions**: Async operations completing out of order
- **State issues**: Stale data, missing updates, cache inconsistency
- **External dependencies**: API changes, missing environment variables
- **Migration gaps**: FK constraints, missing indexes, schema drift

### Phase 3: Implement Fix

1. **Fix the root cause** - Not just the symptom
2. **Follow existing patterns** - Match the codebase style
3. **Keep changes minimal** - Only change what's necessary
4. **Handle edge cases** - Consider what else could go wrong

```
Fix Implementation Checklist:
[ ] Root cause identified and understood
[ ] Fix addresses the root cause (not just symptom)
[ ] Changes follow existing code patterns
[ ] Edge cases considered and handled
[ ] No new security vulnerabilities introduced
```

### Phase 4: Add Tests

Add regression tests to prevent the bug from recurring:

1. **Unit test** - Test the specific function that was fixed
2. **Edge case tests** - Cover the scenario that caused the bug
3. **Run existing tests** - Ensure fix doesn't break other functionality

```bash
# Run tests to verify fix
dotnet test
```

### Phase 5: Document the Bug

Update `common_bugs.md` following the established format:

**If this is a NEW bug type**, add a new section:
```markdown
## [N]. [Brief Bug Title]

**Count:** 1

**Error Message:**
```
[Exact error message from logs]
```

**Root Cause:**
[Clear explanation of why this happened]

**Location:**
- `[file-path]` - `[method-name]` (line X)

**Fix:**
[Description and code example of the fix]

**Prevention:**
- [How to avoid this in the future]
- [What patterns to follow]
```

**If this bug already exists**, increment the Count field only.

### Phase 6: Verify and Review

1. **Run the designer skill** (if frontend changes were made):
   ```
   /designer
   ```
   Make changes based on feedback to ensure design compliance.

2. **Run the code-review skill**:
   ```
   /code-review
   ```
   Address any critical issues or improvements identified.

### Phase 7: Restart and Verify

Clear logs and restart the server to verify the fix:

```bash
dotnet run
```

This restarts the application to verify the fix works.

## Log Interpretation Guide

### error.log format
```json
{
  "level": "error",
  "message": "Error description",
  "stack": "Error: ...\n    at functionName (file:line:col)",
  "method": "POST",
  "url": "/api/endpoint",
  "statusCode": 500,
  "timestamp": "2026-01-24 10:00:00"
}
```

Key fields to examine:
- `message` - What went wrong
- `stack` - Where it happened (read bottom-to-top for call chain)
- `url` - Which endpoint was called
- `statusCode` - HTTP response code

### Common Error Patterns

| Error Type | Typical Cause | Where to Look |
|------------|---------------|---------------|
| `foreign key constraint` | FK references wrong/missing table | Migrations, schema |
| `column does not exist` | Query uses non-existent column | Repository, DATA_SCHEMA.md |
| `invalid input syntax` | Bad data format (dates, UUIDs) | Service layer, input validation |
| `ECONNREFUSED` | Database/service not running | Docker, connection config |
| `NullReferenceException` | Null access | Add null checks |

## Pre-Completion Checklist

Before marking the fix complete:

```
[ ] Root cause identified and documented
[ ] Fix implemented and tested locally
[ ] Regression test added (if applicable)
[ ] common_bugs.md updated
[ ] All tests passing
[ ] Code review completed (via /code-review)
[ ] Designer review completed (if frontend changes)
[ ] Server restarted with dotnet run
[ ] Verified fix works in running application
```

## Output Format

When reporting a fix, provide:

```markdown
## Bug Fix Summary

**Error:** [Brief description]

**Root Cause:** [Why it happened]

**Fix:** [What was changed]

**Files Modified:**
- [File1.cs] - [what changed]
- [File2.cs] - [what changed]

**Tests Added:**
- [TestFile.cs] - [what it tests]

**Verified:** [How you confirmed the fix works]
```
