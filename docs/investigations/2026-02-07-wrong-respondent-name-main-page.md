# Investigation: Wrong Respondent Name on Main Questions Page

**Status:** ✅ Resolved
**Date opened:** 2026-02-07
**Date resolved:** —

## Problem Statement

When viewing a question on the "on page" questions/requests view, the name of who answered the question displays correctly. However, on the "main page" the wrong name is shown for who answered the question.

## Evidence

### Two Views That Display Question Answers

1. **On-page view (QuestionRequestsView → QuestionRequestCard)** — Uses `GET /api/questions/requests/detailed` → `GetDetailedRequests()`. Groups answers by recipient, with `recipient.displayName` resolved via `ResolveRespondentName()`. Each recipient section shows their name in a header, and answers are shown underneath via `QuestionAnswerCard` components. **Name shows correctly here.**

2. **Main page (QuestionResponsesView)** — Uses `GET /api/questions/responses` → `GetMyQuestionResponses()`. Groups answers by question, with each response showing `resp.respondentName` resolved via `ResolveRespondentName()`. **Name shows incorrectly here.**

### Backend Name Resolution

Both endpoints use the same `ResolveRespondentName()` method (QuestionService.cs:413-430) which resolves in order: Alias → User Name → Username → Email → "Family Member".

### Key Difference in Data Structure

- **GetDetailedRequests** (line 865): Iterates `request.Recipients` and for each recipient calls `ResolveRespondentName(r)` → assigns to `RecipientDetailModel.DisplayName`. Then iterates `questions` for each recipient to build answers. **Correct: name is per-recipient.**

- **GetMyQuestionResponses** (line 743): Iterates `r.Recipients.SelectMany(rec => rec.Responses.Where(...))` and calls `ResolveRespondentName(rec)` for each response. **The `rec` variable comes from the outer `SelectMany` so it should be the correct recipient for each response.**

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | The `SelectMany` in `GetMyQuestionResponses` is pairing the wrong recipient with the wrong response due to how EF Core loads/joins the data | 7/10 | 🔍 Untested |
| H2 | The `Respondent` navigation property is not being loaded (null) in `GetMyQuestionResponses` causing fallback to wrong value (Alias or Email instead of User Name) | 8/10 | 🔍 Untested |
| H3 | There's a frontend mapping issue — the `QuestionResponsesView` is displaying a name from a different field than `respondentName` | 3/10 | 🔍 Untested |
| H4 | Recipients have aliases set that don't match their actual names, and alias takes priority over user name in `ResolveRespondentName()` | 5/10 | 🔍 Untested |
| H5 | The EF Include chain in `GetMyQuestionResponses` doesn't load `Respondent` (the registered user profile), so it falls back to Alias/Email | 8/10 | 🔍 Untested |

## Investigation Log

### Round 1 — Testing H1: EF Include not loading Respondent

**Test performed:** Compared EF Core query structure and wrote integration tests with registered respondents.

**Findings:** Both tests pass — EF Core IS correctly loading the `Respondent` navigation property even without `.AsSplitQuery()`. The Include chain works fine.

**Conclusion:** ❌ Ruled Out

### Round 2 — Testing actual data flow on main page (StreamView/MemoryCard)

**Test performed:** Traced how the "main page" (StreamView → MemoryCard) displays question answer attribution vs. the on-page question views.

**Findings:**

**MemoryCard.vue:124** displays:
```vue
<strong>{{ memory.createdBy }}</strong> answered a question
```

`memory.createdBy` is populated from `DropModel.CreatedBy`, which is set in **DropsService.cs**:
1. Line 335: Initially set to `s.CreatedBy.Name` (the drop owner's `UserProfile.Name`)
2. Line 287-288: `MapUserNames()` overrides it with `UserUser.ReaderName` (the viewing user's connection nickname for the drop creator)

**The bug:** `memory.createdBy` is the **drop creator's name**, NOT the respondent's name.

When an anonymous respondent answers, `SubmitAnswer` (QuestionService.cs:515) sets `dropUserId = creatorUserId` — the **question asker** owns the drop. So on the feed, `memory.createdBy` shows the question asker's name, not the person who answered.

Even when the respondent HAS an account, `createdBy` may show the **connection nickname** (from `UserUser.ReaderName`), which may not match the respondent's display name from `ResolveRespondentName()`.

**The on-page views work correctly because:**
- **QuestionResponsesView** uses `resp.respondentName` from `GetMyQuestionResponses()` which calls `ResolveRespondentName()`
- **QuestionRequestCard** shows `recipient.displayName` from `GetDetailedRequests()` which also calls `ResolveRespondentName()`

Neither uses `memory.createdBy`.

**Conclusion:** ✅ Confirmed — Root cause identified

**Evidence:**
- `MemoryCard.vue:124`: Uses `memory.createdBy` (drop owner) not respondent name
- `QuestionService.cs:515`: `dropUserId = recipient.RespondentUserId ?? creatorUserId`
- `DropsService.cs:335`: `CreatedBy = s.CreatedBy.Name` (drop owner's name)
- `DropsService.cs:287-288`: `MapUserNames` overrides with connection nickname
- `QuestionContextModel` (QuestionModels.cs:190-195): Has no `RespondentName` field

---

## Resolution

**Root Cause:** The main feed page (`MemoryCard.vue:124`) uses `memory.createdBy` (the drop creator's name) to label who answered a question. But for anonymous respondents, the drop is owned by the **question asker**, not the answerer. So the feed incorrectly shows the asker's name as the answerer. Even for registered respondents, `createdBy` may show a connection nickname instead of the resolved respondent name.

**Fix required (two parts):**

1. **Backend:** Add `RespondentName` to `QuestionContextModel` and populate it using `ResolveRespondentName()` when building question context in `DropsService.AddQuestionContext()`.

2. **Frontend:** Update `MemoryCard.vue:124` to use `memory.questionContext.respondentName` instead of `memory.createdBy`.

**Recommended Action:** Run `/fixer` to implement the fix.
