# Technical Design Document: Fix Question Suggestion Prompt Priority

**PRD:** N/A (bug fix — user-reported issue)
**Status:** Draft
**Created:** 2026-02-20

---

## Overview

The AI question suggestion feature is generating questions that "riff off" previously asked questions instead of being driven primarily by the user's intent/prompt and the selected storyline. The current `BuildUserPromptAsync` method sends up to 50 previous questions and 20 recent Q&A pairs to the AI with instructions to "suggest deeper follow-up questions" and "build on details from previous answers." This causes the AI to heavily weight old history over the current intent.

### Problem

When a user generates suggestions a second time (even with a different intent), the AI is influenced by:
1. **50 previous questions** — sent as de-duplication context but takes up significant prompt space
2. **20 recent Q&A pairs** — sent with explicit instruction to "use these to suggest deeper follow-up questions"
3. **Final instructions** that say "Questions should build on details from previous answers when relevant"

The old questions/answers may be completely unrelated to the current intent. The AI gives them too much weight.

### Solution

Remove previous questions and recent answers from the prompt entirely. The priority should be:
1. **Primary**: The user's intent (what they typed)
2. **Secondary**: The storyline context (if provided)
3. **Not used**: Old questions and answers

Old questions are unrelated noise — the user provides a fresh intent each time they want suggestions. The intent and storyline provide all the context needed.

---

## Phase 1: Remove History Context from Prompt

### 1.1 Backend: Update `BuildUserPromptAsync`

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionSuggestionService.cs`

Remove the previous questions query (lines 213-229), remove the recent answers query (lines 231-257), and simplify the final instructions.

Also update XML doc comments:
- Class-level comment (line 18): change `"using intent, history, and storyline context"` → `"using intent and optional storyline context"`
- `BuildUserPromptAsync` comment (line 203): change `"with intent, previous questions, recent answers, and optional storyline context"` → `"with intent and optional storyline context"`

**Before (current code):**
```csharp
private async Task<string> BuildUserPromptAsync(
    int userId,
    string intent,
    int? storylineId)
{
    var sb = new StringBuilder();
    sb.AppendLine($"The user wants to learn about: {intent}");

    // Previous questions for de-duplication
    var previousQuestions = await Context.Questions
        .Where(q => q.QuestionSet.UserId == userId && !q.QuestionSet.Archived)
        .OrderByDescending(q => q.QuestionSet.CreatedAt)
        .Select(q => q.Text)
        .Take(50)
        .ToListAsync();

    if (previousQuestions.Count > 0)
    {
        sb.AppendLine();
        sb.AppendLine("PREVIOUSLY ASKED QUESTIONS (do NOT suggest similar questions):");
        foreach (var q in previousQuestions)
        {
            sb.AppendLine($"- {q}");
        }
    }

    // Recent answer content for follow-up depth
    var recentAnswers = await Context.QuestionResponses
        .Where(qr => qr.Recipient.QuestionRequest.CreatorUserId == userId
            && qr.AnsweredAt != DateTime.MinValue)
        .OrderByDescending(qr => qr.AnsweredAt)
        .Take(20)
        .Select(qr => new
        {
            Question = qr.Question.Text,
            Answer = qr.Drop.ContentDrop.Stuff
        })
        .ToListAsync();

    if (recentAnswers.Count > 0)
    {
        sb.AppendLine();
        sb.AppendLine("RECENT ANSWERS RECEIVED (use these to suggest deeper follow-up questions):");
        foreach (var a in recentAnswers)
        {
            var answer = a.Answer != null && a.Answer.Length > 300
                ? a.Answer.Substring(0, 300) + "..."
                : a.Answer;
            sb.AppendLine($"Q: {a.Question}");
            sb.AppendLine($"A: {answer}");
            sb.AppendLine();
        }
    }

    // Storyline context
    var hasStorylineContext = false;
    if (storylineId.HasValue)
    {
        hasStorylineContext = await AppendStorylineContextAsync(
            sb, storylineId.Value, userId);
    }

    sb.AppendLine();
    sb.AppendLine("Generate 5 specific, storytelling-focused questions about this topic.");
    if (previousQuestions.Count > 0 || recentAnswers.Count > 0 || hasStorylineContext)
    {
        if (hasStorylineContext)
        {
            sb.AppendLine("When storyline context is provided, suggest questions that deepen the storyline's narrative.");
        }
        sb.AppendLine("Questions should build on details from previous answers when relevant.");
        sb.AppendLine("Never repeat or closely resemble previously asked questions.");
    }

    return sb.ToString();
}
```

**After (updated code):**
```csharp
private async Task<string> BuildUserPromptAsync(
    int userId,
    string intent,
    int? storylineId)
{
    var sb = new StringBuilder();
    sb.AppendLine($"The user wants to learn about: {intent}");

    // Storyline context (secondary driver)
    var hasStorylineContext = false;
    if (storylineId.HasValue)
    {
        hasStorylineContext = await AppendStorylineContextAsync(
            sb, storylineId.Value, userId);
    }

    sb.AppendLine();
    sb.AppendLine("Generate 5 specific, storytelling-focused questions about this topic.");
    if (hasStorylineContext)
    {
        sb.AppendLine("Use the storyline context to suggest questions that deepen the storyline's narrative.");
    }

    return sb.ToString();
}
```

**Key changes:**
- Removed previous questions query and prompt section entirely
- Removed recent answers query and prompt section entirely
- Removed "build on details from previous answers" instruction
- Removed "Never repeat or closely resemble previously asked questions" instruction (no longer needed since we don't send old questions)
- Kept storyline context as the secondary driver
- Simplified final instructions to focus on intent + storyline only
- Updated class-level and method-level XML doc comments

### 1.2 Backend: Update Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionSuggestionServiceTest.cs`

Tests that verify previous questions/answers are included in the prompt need to be updated:

| Existing Test | Action |
|---|---|
| `GenerateSuggestions_WithPreviousQuestions_IncludesThemInPrompt` | **Update** → rename to `GenerateSuggestions_WithPreviousQuestions_DoesNotIncludeThemInPrompt` and assert the prompt does NOT contain previous questions. Keep entity setup to prove questions are intentionally excluded even when they exist in the DB. |
| `GenerateSuggestions_WithPreviousAnswers_IncludesThemInPrompt` | **Update** → rename to `GenerateSuggestions_WithPreviousAnswers_DoesNotIncludeThemInPrompt` and assert the prompt does NOT contain previous answers. Keep entity setup to prove answers are intentionally excluded even when they exist in the DB. |
| `GenerateSuggestions_WithNoPreviousHistory_StillGenerates` | **Keep** — still valid, intent-only generation still works |

All other existing tests remain unchanged (rate limiting, parsing, sanitization, storyline context, etc.).

### 1.3 Documentation: Update `docs/AI_PROMPTS.md`

**File:** `docs/AI_PROMPTS.md`

Replace the "User Prompt Template (Phase 2 — History-Enriched)" section (lines 46-65) with the simplified intent-only template. Remove all references to `PREVIOUSLY ASKED QUESTIONS` and `RECENT ANSWERS RECEIVED` sections from the documented prompt.

**Before:**
```
**User Prompt Template (Phase 2 — History-Enriched):**

The user wants to learn about: {intent}

PREVIOUSLY ASKED QUESTIONS (do NOT suggest similar questions):
- {question1}
- {question2}
...

RECENT ANSWERS RECEIVED (use these to suggest deeper follow-up questions):
Q: {questionText}
A: {answerContent, truncated to 300 chars}

Generate 5 specific, storytelling-focused questions about this topic.
Questions should build on details from previous answers when relevant.
Never repeat or closely resemble previously asked questions.

The PREVIOUSLY ASKED QUESTIONS section includes up to 50 most recent questions...
```

**After:**
```
**User Prompt Template:**

The user wants to learn about: {intent}

Generate 5 specific, storytelling-focused questions about this topic.

When a storyline is selected, the prompt also includes storyline context (see below),
and the instruction: "Use the storyline context to suggest questions that deepen
the storyline's narrative."
```

The Storyline Context section (Phase 3) remains unchanged.

---

## Implementation Order

1. Update `BuildUserPromptAsync` in `QuestionSuggestionService.cs` — remove history queries, prompt sections, and update XML doc comments
2. Update tests in `QuestionSuggestionServiceTest.cs` — flip assertions for history tests
3. Update `docs/AI_PROMPTS.md` — replace history-enriched prompt template with simplified version
4. Run all backend tests to verify nothing breaks

---

## Testing Plan

| Test | Description |
|---|---|
| `GenerateSuggestions_WithPreviousQuestions_DoesNotIncludeThemInPrompt` | Create QuestionSets, verify AI prompt does NOT contain them (entities kept to prove intentional exclusion) |
| `GenerateSuggestions_WithPreviousAnswers_DoesNotIncludeThemInPrompt` | Create QuestionResponses, verify AI prompt does NOT contain answer text (entities kept to prove intentional exclusion) |
| `GenerateSuggestions_WithNoPreviousHistory_StillGenerates` | New user with no history gets suggestions (unchanged) |
| `GenerateSuggestions_WithStorylineId_IncludesStorylineContext` | Storyline context still included (unchanged) |
| All existing tests | Rate limiting, parsing, sanitization, storyline access — all pass unchanged |

---

## Risk Assessment

- **Low risk**: This is a prompt-only change. No database schema changes, no API contract changes, no frontend changes needed.
- **Benefit**: Questions will be more relevant to what the user actually asked about, rather than being influenced by unrelated past history.
- **Token savings**: Removing up to 50 questions + 20 Q&A pairs from the prompt significantly reduces token usage per request.

---

*Document Version: 1.1*
*Created: 2026-02-20*
*Status: Draft*
