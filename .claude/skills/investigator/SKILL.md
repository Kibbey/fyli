---
name: investigator
description: Solve a problem through recursive root cause analysis. Generates ranked hypotheses, lets the user choose which to test, and tracks all progress in a living investigation doc.
allowed-tools: Read, Grep, Glob, Task, Edit, Write, Bash, AskUserQuestion
---

# Investigator Skill

Systematically investigate problems through hypothesis-driven root cause analysis. Maintain a living investigation document that tracks hypotheses, tests, findings, and resolution.

## Process

### Phase 1: Define the Problem

1. **Gather context** — Read error logs, user reports, code, and any other relevant sources to understand the symptom.
2. **Write a clear problem statement** — One sentence describing the observable behavior and expected behavior.
3. **Create the investigation doc** at `docs/investigations/YYYY-MM-DD-<slug>.md` using the template below.

### Phase 2: Generate Hypotheses

Produce a ranked list of hypotheses. For each hypothesis provide:

| Field | Description |
|-------|-------------|
| **ID** | H1, H2, H3… |
| **Hypothesis** | A falsifiable statement of what might be causing the problem |
| **Reasoning** | Why this is plausible given the evidence so far |
| **Likelihood** | Score from 1-10 (10 = most likely) |
| **Test** | Concrete steps to confirm or rule out this hypothesis |

Sort by likelihood descending.

### Phase 3: User Selects Hypothesis

Use `AskUserQuestion` to present the hypotheses and ask which one to test first. Always include an option for "Let me provide a different hypothesis" so the user can inject their own ideas.

### Phase 4: Test the Hypothesis

1. Execute the test plan for the selected hypothesis.
2. Record **findings** — what you observed, with evidence (file paths, line numbers, log excerpts, command output).
3. Update the hypothesis status to one of: `✅ Confirmed`, `❌ Ruled Out`, `⚠️ Partially Confirmed`.

### Phase 5: Update & Recurse

After each test:

1. **Update the investigation doc** with findings and status.
2. **Re-evaluate remaining hypotheses** — adjust likelihood scores based on new evidence. Add new hypotheses if the findings suggest them.
3. **If root cause is confirmed** → proceed to Phase 6.
4. **If not resolved** → return to Phase 3 with the updated hypothesis list.

### Phase 6: Resolution

1. Document the confirmed root cause in the investigation doc.
2. Summarize the resolution and any recommended next steps (e.g., "run /fixer to implement the fix").
3. Mark the investigation status as `Resolved`.

## Investigation Doc Template

Create this file at `docs/investigations/YYYY-MM-DD-<slug>.md`:

```markdown
# Investigation: <Title>

**Status:** 🔍 Active | ✅ Resolved
**Date opened:** YYYY-MM-DD
**Date resolved:** —

## Problem Statement

<Clear description of the symptom and expected behavior>

## Evidence

- <Initial evidence collected during Phase 1>

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | ... | 8/10 | 🔍 Untested |
| H2 | ... | 6/10 | 🔍 Untested |

## Investigation Log

### Round 1 — Testing H<N>

**Test performed:** <what you did>

**Findings:** <what you observed, with evidence>

**Conclusion:** ✅ Confirmed | ❌ Ruled Out | ⚠️ Partially Confirmed

**Hypothesis updates:**
- H<N> likelihood adjusted to X/10 because ...
- New hypothesis H<M> added: ...

---

## Resolution

**Root Cause:** <confirmed root cause>

**Recommended Action:** <next steps>
```

## Rules

- Never skip asking the user which hypothesis to test. The user drives the investigation.
- Always update the investigation doc after every test round — it is the source of truth.
- When generating hypotheses, think broadly at first (could be code, config, data, infra, external dependency) then narrow based on evidence.
- Keep hypothesis descriptions concise but specific enough to be falsifiable.
- If a round produces no new information, note that explicitly and suggest a different angle of investigation.
- Limit to 5-7 hypotheses per round to avoid overwhelming the user. Prioritize quality over quantity.
