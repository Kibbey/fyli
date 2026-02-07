# TDD: Question Answer UX Consistency

**PRD:** `docs/prd/PRD_QUESTION_ANSWER_UX_CONSISTENCY.md`
**Status:** Draft
**Created:** 2026-02-07

---

## Overview

Unify the user experience for viewing and interacting with question-generated memories across all views. This TDD addresses five areas: edit permission enforcement, unified respondent identity, unified question management view, consistent question-answer cards, and navigation cleanup.

### !IMPORTANT! — Anonymous User Edit Permissions (PRD Section 2.2)

The PRD raises the question of how to enforce edit permissions for anonymous users who don't have a `userId`. After analyzing the codebase, **creating shadow users is not recommended** because:

1. **UserProfile has an implicit email uniqueness constraint** — `AddUser` rejects duplicate usernames (set to email). Shadow users would conflict when the real user registers.
2. **Backwards compatibility risk** — Every query touching `UserProfile` or `Drop.UserId` would need to account for shadow users.
3. **The current system already works cleanly** — Anonymous answers are owned by the question creator (`Drop.UserId = creatorUserId`), and ownership transfers on registration via `RegisterAndLinkAnswers`.

**Chosen approach: Token-based edit authorization for anonymous users, userId-based for registered users.**

The backend already enforces this correctly:
- `PUT /questions/answer/{token}` validates the token matches the recipient, and checks the 7-day window for anonymous users.
- Registered users can always edit their own answers (unlimited).
- The `canEdit` flag in `AnswerViewModel` already reflects this logic.

The gap is on the **frontend and API response side** — the `canEdit` flag doesn't distinguish between "this is my answer and I can edit it" vs. "this is someone else's answer". We fix this by adding context about answer ownership to API responses viewed by the question asker.

---

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Frontend                                │
│                                                              │
│  ┌──────────────────┐  ┌─────────────────────────────────┐  │
│  │ RespondentName   │  │ QuestionAnswerCard               │  │
│  │ (utility fn)     │  │ (unified display component)      │  │
│  └──────────────────┘  └─────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ QuestionRequestsView (unified dashboard + responses)  │   │
│  │  ├── QuestionRequestCard (expandable per request)     │   │
│  │  │    ├── RecipientSection (per recipient)            │   │
│  │  │    │    └── QuestionAnswerCard (per answer)        │   │
│  │  │    └── RecipientStatus (pending recipients)        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │ MemoryCard       │  │ QuestionAnswerView (anon page) │   │
│  │ (uses QA card)   │  │ (uses AnswerPreview)           │   │
│  └──────────────────┘  └───────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                       Backend                                 │
│                                                               │
│  QuestionController ──→ QuestionService                       │
│  GET /questions/requests/sent  (enhanced with inline answers) │
│  GET /questions/responses      (enhanced with media)          │
│                                                               │
│  New unified endpoint:                                        │
│  GET /questions/requests/detailed                             │
│    Returns: requests + recipients + answers + media inline    │
└──────────────────────────────────────────────────────────────┘
```

---

## Implementation Phases

### Phase 1a: Backend — Identity Resolution, Edit Permissions & Email Fixes

**Goal:** Add the `ResolveRespondentName` helper, fix all existing callsites using incorrect identity fallbacks, add `isOwnAnswer` and `editWindowExpiresAt` to answer models, and fix email notification identity/links.

#### 1a.1 Identity Resolution Algorithm (`QuestionService.cs`)

Add a private helper method that implements the PRD's identity resolution:

```csharp
/// <summary>
/// Resolves display name for a recipient using the canonical order:
/// 1. Alias (from QuestionRequestRecipient)
/// 2. User's full name (if respondent has account)
/// 3. User's email (if respondent has account)
/// 4. Recipient email (from QuestionRequestRecipient)
/// 5. "Family Member" (fallback)
/// </summary>
private static string ResolveRespondentName(QuestionRequestRecipient recipient)
{
    if (!string.IsNullOrWhiteSpace(recipient.Alias))
        return recipient.Alias;

    if (recipient.Respondent != null)
    {
        if (!string.IsNullOrWhiteSpace(recipient.Respondent.Name))
            return recipient.Respondent.Name;
        if (!string.IsNullOrWhiteSpace(recipient.Respondent.UserName))
            return recipient.Respondent.UserName;
    }

    if (!string.IsNullOrWhiteSpace(recipient.Email))
        return recipient.Email;

    return "Family Member";
}
```

#### 1a.2 Fix Existing Identity Resolution Callsites

**`SubmitAnswer` (line 524)** — currently `recipient.Alias ?? "Someone"`:

First, add `.Include(r => r.Respondent)` to the `SubmitAnswer` query (lines 461-466) so `ResolveRespondentName` can access the respondent's name and email:
```csharp
var recipient = await Context.QuestionRequestRecipients
    .Include(r => r.QuestionRequest)
        .ThenInclude(qr => qr.QuestionSet)
            .ThenInclude(qs => qs.Questions)
    .Include(r => r.Responses)
    .Include(r => r.Respondent)  // ADD: needed for ResolveRespondentName
    .SingleOrDefaultAsync(r => r.Token == token);
```

Then fix the identity resolution:
```csharp
// Before:
var respondentName = recipient.Alias ?? "Someone";

// After:
var respondentName = ResolveRespondentName(recipient);
```

**`GetMyQuestionResponses` (line 719)** — currently `rec.Alias ?? rec.Respondent?.Name ?? "Anonymous"`:
```csharp
// Before:
RespondentName = rec.Alias ?? rec.Respondent?.Name ?? "Anonymous"

// After:
RespondentName = ResolveRespondentName(rec)
```

This eliminates "Someone", "Anonymous", and "Recipient" from ever appearing.

#### 1a.3 Fix Email Notification Links

**`QuestionAnswerNotification` template** (`EmailTemplates.cs` line 75-76) — currently links to generic BaseUrl with no path to the response:

```csharp
// Before:
return @"<p>@Model.User answered your question!</p>
<p><i><b>@Model.Question</b></i></p>
<p>View their answer on <a href='@Model.Link'>Fyli</a>.</p>";

// After:
return @"<p>@Model.User answered your question!</p>
<p><i><b>@Model.Question</b></i></p>
<p>View their answer on <a href='@Model.Link/questions/requests'>Fyli</a>.</p>";
```

The `@Model.User` value is set by `SubmitAnswer` which now uses `ResolveRespondentName`, so the identity will be correct.

#### 1a.4 Add `isOwnAnswer` and `editWindowExpiresAt` to AnswerViewModel

Update `AnswerViewModel` in `QuestionModels.cs`:

```csharp
public class AnswerViewModel
{
    public int DropId { get; set; }
    public string Content { get; set; }
    public DateTime Date { get; set; }
    public int DateType { get; set; }
    public bool CanEdit { get; set; }
    public bool IsOwnAnswer { get; set; }  // NEW: true only for the token holder's own answers
    public DateTime? EditWindowExpiresAt { get; set; }  // NEW: null for registered users (unlimited)
    public List<AnswerImageModel> Images { get; set; } = new();
    public List<AnswerMovieModel> Movies { get; set; } = new();
}
```

Update `BuildAnswerViewModel` in `QuestionService.cs` to populate the new fields:

```csharp
// In BuildAnswerViewModel:
var canEdit = hasAccount || (now - response.AnsweredAt).TotalDays <= 7;

answerModel.CanEdit = canEdit;
answerModel.IsOwnAnswer = true;  // Always true on the /q/{token} page (only token holder sees this)
answerModel.EditWindowExpiresAt = hasAccount
    ? null  // Registered users have unlimited edit access
    : response.AnsweredAt.AddDays(7);  // Anonymous: 7 days from answer time
```

On the anonymous answer page, `IsOwnAnswer` is always `true` because the token holder is the answer author. In the memory feed, `Drop.editable` already handles ownership. The key gap is the "Edit window closed" message — see Phase 2.

#### 1a.5 Interface Updates (`IQuestionService.cs`)

No new methods in 1a — only updates to existing method return types (adding fields to `AnswerViewModel`).

#### 1a.6 Raw SQL for Reference

No schema changes needed — only DTO model updates and service logic fixes.

---

### Phase 1b: Backend — Unified API Endpoint

**Goal:** Create a new unified API endpoint that merges dashboard + responses with full content and media inline.

#### 1b.1 New/Updated Models (`QuestionModels.cs`)

Add a new unified response model that combines dashboard status with full answer content:

```csharp
// New: Unified request detail model combining dashboard + responses
public class QuestionRequestDetailModel
{
    public int QuestionRequestId { get; set; }
    public string QuestionSetName { get; set; }
    public DateTime CreatedAt { get; set; }
    public string Message { get; set; }
    public List<RecipientDetailModel> Recipients { get; set; } = new();
}

public class RecipientDetailModel
{
    public int QuestionRequestRecipientId { get; set; }
    public string Token { get; set; }  // For copy-link
    public string DisplayName { get; set; }  // Resolved via identity algorithm
    public string Email { get; set; }  // Only for creator, masked for others
    public string Alias { get; set; }
    public bool IsActive { get; set; }
    public int RemindersSent { get; set; }
    public DateTime? LastReminderAt { get; set; }
    public List<RecipientAnswerModel> Answers { get; set; } = new();
}

public class RecipientAnswerModel
{
    public int QuestionId { get; set; }
    public string QuestionText { get; set; }
    public int SortOrder { get; set; }
    public bool IsAnswered { get; set; }
    // Answer data (null if not answered)
    public int? DropId { get; set; }
    public string Content { get; set; }
    public DateTime? Date { get; set; }
    public int DateType { get; set; }  // Non-nullable: matches Drop.DateType (default 0 = Exact)
    public DateTime? AnsweredAt { get; set; }
    public List<AnswerImageModel> Images { get; set; }
    public List<AnswerMovieModel> Movies { get; set; }
}
```

Update `ResponseSummary` to include full content and media:

```csharp
// Updated: ResponseSummary now includes full content + media + identity
public class ResponseSummary
{
    public int DropId { get; set; }
    public string RespondentName { get; set; }  // Resolved via identity algorithm
    public DateTime AnsweredAt { get; set; }
    public string ContentPreview { get; set; }  // Keep for backward compat
    public string Content { get; set; }  // Full content (new)
    public DateTime? Date { get; set; }  // Memory date (new)
    public int? DateType { get; set; }  // (new)
    public List<AnswerImageModel> Images { get; set; } = new();  // (new)
    public List<AnswerMovieModel> Movies { get; set; } = new();  // (new)
}
```

#### 1b.2 New Endpoint: `GET /questions/requests/detailed`

Add to `QuestionController.cs`:

```csharp
[HttpGet("requests/detailed")]
[CustomAuthorization]
public async Task<IActionResult> GetDetailedRequests(
    [FromQuery] int skip = 0,
    [FromQuery] int take = 20)
{
    var result = await _questionService.GetDetailedRequests(UserId, skip, take);
    return Ok(result);
}
```

Add to `QuestionService.cs`:

```csharp
public async Task<List<QuestionRequestDetailModel>> GetDetailedRequests(
    int userId, int skip, int take)
{
    take = Math.Min(take, 100);

    var requests = await Context.QuestionRequests
        .Where(qr => qr.CreatorUserId == userId)
        .OrderByDescending(qr => qr.CreatedAt)
        .Skip(skip)
        .Take(take)
        .Include(qr => qr.QuestionSet)
            .ThenInclude(qs => qs.Questions)
        .Include(qr => qr.Recipients)
            .ThenInclude(r => r.Respondent)
        .Include(qr => qr.Recipients)
            .ThenInclude(r => r.Responses)
                .ThenInclude(resp => resp.Drop)
                    .ThenInclude(d => d.ContentDrop)
        .Include(qr => qr.Recipients)
            .ThenInclude(r => r.Responses)
                .ThenInclude(resp => resp.Drop)
                    .ThenInclude(d => d.ImageDrops.Where(i => !i.CommentId.HasValue))
        .Include(qr => qr.Recipients)
            .ThenInclude(r => r.Responses)
                .ThenInclude(resp => resp.Drop)
                    .ThenInclude(d => d.MovieDrops)
        .Include(qr => qr.Recipients)
            .ThenInclude(r => r.Responses)
                .ThenInclude(resp => resp.Question)
        .AsSplitQuery()
        .ToListAsync();

    var result = new List<QuestionRequestDetailModel>();

    foreach (var request in requests)
    {
        var questions = request.QuestionSet.Questions
            .OrderBy(q => q.SortOrder)
            .ToList();

        var model = new QuestionRequestDetailModel
        {
            QuestionRequestId = request.QuestionRequestId,
            QuestionSetName = request.QuestionSet.Name,
            CreatedAt = request.CreatedAt,
            Message = request.Message,
            Recipients = request.Recipients.Select(r =>
            {
                var answers = questions.Select(q =>
                {
                    var response = r.Responses
                        .FirstOrDefault(resp => resp.QuestionId == q.QuestionId);

                    var answerModel = new RecipientAnswerModel
                    {
                        QuestionId = q.QuestionId,
                        QuestionText = q.Text,
                        SortOrder = q.SortOrder,
                        IsAnswered = response != null
                    };

                    if (response?.Drop != null)
                    {
                        var drop = response.Drop;
                        answerModel.DropId = drop.DropId;
                        answerModel.Content = drop.ContentDrop?.Stuff;
                        answerModel.Date = drop.Date;
                        answerModel.DateType = drop.DateType;
                        answerModel.AnsweredAt = response.AnsweredAt;
                        answerModel.Images = drop.ImageDrops?
                            .Where(i => !i.CommentId.HasValue)
                            .Select(i => new AnswerImageModel
                            {
                                ImageDropId = i.ImageDropId,
                                Url = _imageService.GetPresignedUrl(i, userId)
                            }).ToList();
                        answerModel.Movies = drop.MovieDrops?
                            .Select(m => new AnswerMovieModel
                            {
                                MovieDropId = m.MovieDropId,
                                ThumbnailUrl = _movieService.GetThumbnailUrl(m),
                                VideoUrl = _movieService.GetVideoUrl(m)
                            }).ToList();
                    }

                    return answerModel;
                }).ToList();

                return new RecipientDetailModel
                {
                    QuestionRequestRecipientId = r.QuestionRequestRecipientId,
                    Token = r.Token.ToString(),
                    DisplayName = ResolveRespondentName(r),
                    Email = r.Email,
                    Alias = r.Alias,
                    IsActive = r.IsActive,
                    RemindersSent = r.RemindersSent,
                    LastReminderAt = r.LastReminderAt,
                    Answers = answers
                };
            }).ToList()
        };

        result.Add(model);
    }

    return result;
}
```

#### 1b.3 Update Existing Response Endpoint

Update `GetMyQuestionResponses` to include full content + media in `ResponseSummary`. (Identity resolution already fixed in Phase 1a.2.) This ensures the existing `/questions/responses` endpoint returns rich data.

#### 1b.4 Interface Updates (`IQuestionService.cs`)

```csharp
Task<List<QuestionRequestDetailModel>> GetDetailedRequests(int userId, int skip, int take);
```

#### 1b.5 Security Note: Token Exposure

The `RecipientDetailModel` includes `Token` (the recipient's answer link GUID) to enable the "Copy Link" feature. These tokens grant unauthenticated write access to submit/edit answers. This mirrors the existing `/questions/requests/sent` endpoint behavior (which also returns tokens). The exposure surface is unchanged — the new endpoint consolidates data already available to the authenticated creator.

#### 1b.6 Raw SQL for Reference

No schema changes are needed — this phase only adds new query patterns and models. No migration required.

---

### Phase 2: Frontend — Identity Resolution & Edit Permission Guards

**Goal:** Create unified identity resolution utility, guard edit buttons, update all views.

#### 2.1 Identity Resolution Utility

Create `fyli-fe-v2/src/utils/respondentName.ts`:

```typescript
interface RespondentIdentity {
  alias?: string;
  name?: string;       // User's full name (if registered)
  email?: string;
  displayName?: string; // Pre-resolved by backend
}

/**
 * Resolves respondent display name using canonical order:
 * 1. Alias (from QuestionRequestRecipient)
 * 2. User's full name (if respondent has account)
 * 3. Email
 * 4. "Family Member" (fallback)
 *
 * Replaces ad-hoc resolution like `r.alias || r.email || "Recipient"`
 */
export function resolveRespondentName(identity: RespondentIdentity): string {
  if (identity.displayName) return identity.displayName;
  if (identity.alias?.trim()) return identity.alias.trim();
  if (identity.name?.trim()) return identity.name.trim();
  if (identity.email?.trim()) return identity.email.trim();
  return 'Family Member';
}
```

#### 2.2 Update AnswerPreview Edit Guard

**Problem:** `AnswerPreview.vue` currently shows "Edit window closed" (lines 52-55) whenever `canEdit` is false. This message should **never** appear for someone else's answer — it should only appear for the token holder's own answer after the 7-day window expires. The backend now returns `isOwnAnswer` (Phase 1a.4) to distinguish.

Update `AnswerPreview.vue` edit section:

```html
<!-- Before: -->
<button v-if="question.answer.canEdit" ...>Edit</button>
<span v-else class="text-muted small">
  <span class="mdi mdi-lock-outline me-1"></span>
  Edit window closed
</span>

<!-- After: -->
<template v-if="question.answer.isOwnAnswer">
  <button v-if="question.answer.canEdit" type="button"
    class="btn btn-sm btn-outline-secondary"
    @click="$emit('edit', question.questionId)">
    <span class="mdi mdi-pencil me-1" aria-hidden="true"></span>
    Edit
  </button>
  <span v-else class="text-muted small">
    <span class="mdi mdi-lock-outline me-1" aria-hidden="true"></span>
    Edit window closed
  </span>
</template>
<!-- No edit UI at all for answers that aren't yours -->
```

#### 2.3 Edit Window Countdown Display (PRD User Story 6)

For anonymous respondents viewing their own answers within the 7-day window, show remaining edit time. The backend now returns `editWindowExpiresAt` (Phase 1a.4).

Add to `AnswerPreview.vue` below the edit button:

```html
<small v-if="question.answer.canEdit && question.answer.editWindowExpiresAt"
  class="text-muted ms-2">
  <span class="mdi mdi-clock-outline me-1"></span>
  {{ editTimeRemaining }} left to edit
</small>
```

```typescript
const editTimeRemaining = computed(() => {
  if (!props.question.answer.editWindowExpiresAt) return '';
  const expires = new Date(props.question.answer.editWindowExpiresAt);
  const now = new Date();
  const diffMs = expires.getTime() - now.getTime();
  if (diffMs <= 0) return '';
  const days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  if (days > 1) return `${days} days`;
  if (days === 1) return '1 day';
  const hours = Math.floor(diffMs / (1000 * 60 * 60));
  return `${hours} hours`;
});
```

For registered users, `editWindowExpiresAt` is `null` so the countdown is hidden (they have unlimited edit access).

#### 2.4 Memory Feed Edit Button — Already Correct

For the **memory feed** (`MemoryCard.vue`), the edit button already uses `memory.editable` which is a backend-computed flag based on `Drop.UserId == currentUserId`. This is already correct — no changes needed.

For the **QuestionResponsesView** (asker viewing responses), there is no edit button currently shown — only text preview. The new unified view (Phase 4) will not show edit buttons for the asker either.

#### 2.5 Update QuestionDashboardView Identity Display

Change line 38 from:
```html
<span>{{ r.alias || r.email || "Recipient" }}</span>
```
To:
```html
<span>{{ resolveRespondentName(r) }}</span>
```

Import the utility:
```typescript
import { resolveRespondentName } from '@/utils/respondentName';
```

#### 2.6 Update QuestionResponsesView Identity Display

Currently uses `resp.respondentName` from the API — this will be updated on the backend (Phase 1a.2) to use the canonical resolution. No frontend change needed here since the backend will return the correct name.

#### 2.7 TypeScript Types

Update `AnswerView` in `fyli-fe-v2/src/types/question.ts` to include new fields:

```typescript
export interface AnswerView {
  dropId: number;
  content: string;
  date: string;
  dateType: DateType;
  canEdit: boolean;
  isOwnAnswer: boolean;               // NEW: true only for the token holder's own answers
  editWindowExpiresAt?: string;        // NEW: ISO date; null for registered users (unlimited)
  images: AnswerImage[];
  movies: AnswerMovie[];
}
```

Add new types for the unified endpoint:

```typescript
/** Unified request detail from GET /questions/requests/detailed */
export interface QuestionRequestDetail {
  questionRequestId: number;
  questionSetName: string;
  createdAt: string;
  message?: string;
  recipients: RecipientDetail[];
}

export interface RecipientDetail {
  questionRequestRecipientId: number;
  token: string;
  displayName: string;
  email?: string;
  alias?: string;
  isActive: boolean;
  remindersSent: number;
  lastReminderAt?: string;
  answers: RecipientAnswer[];
}

export interface RecipientAnswer {
  questionId: number;
  questionText: string;
  sortOrder: number;
  isAnswered: boolean;
  dropId?: number;
  content?: string;
  date?: string;
  dateType?: DateType;
  answeredAt?: string;
  images?: AnswerImage[];
  movies?: AnswerMovie[];
}
```

#### 2.8 API Service

Add to `fyli-fe-v2/src/services/questionApi.ts`:

```typescript
import type { QuestionRequestDetail } from '@/types';

export function getDetailedRequests(skip = 0, take = 20) {
  return api.get<QuestionRequestDetail[]>('/questions/requests/detailed', {
    params: { skip, take }
  });
}
```

#### 2.9 Tests

**File:** `fyli-fe-v2/src/utils/respondentName.test.ts`

Test cases:
1. Returns alias when all fields present
2. Returns name when no alias
3. Returns email when no alias or name
4. Returns "Family Member" when all empty
5. Returns displayName when provided (backend pre-resolved)
6. Trims whitespace from all fields
7. Treats whitespace-only strings as empty

**File:** `fyli-fe-v2/src/services/questionApi.test.ts` (update)

Test cases:
1. `getDetailedRequests()` calls correct endpoint with params
2. `getDetailedRequests(10, 30)` passes skip/take

**File:** `fyli-fe-v2/src/components/question/AnswerPreview.test.ts` (update existing)

Test cases:
1. Shows edit button when `isOwnAnswer=true` and `canEdit=true`
2. Shows "Edit window closed" when `isOwnAnswer=true` and `canEdit=false`
3. Shows NO edit UI when `isOwnAnswer=false` (regardless of `canEdit`)
4. Shows edit countdown when `canEdit=true` and `editWindowExpiresAt` is in future
5. Hides countdown when `editWindowExpiresAt` is null (registered user)
6. Shows "X days left to edit" for multi-day remaining
7. Shows "X hours left to edit" for last day

---

### Phase 3: Frontend — QuestionAnswerCard & Memory Feed Integration

**Goal:** Create the reusable `QuestionAnswerCard` component first, then integrate it into the memory feed. This component must exist before Phase 4 so the unified view can use it.

#### 3.1 QuestionAnswerCard Component

Create `fyli-fe-v2/src/components/question/QuestionAnswerCard.vue`:

This is a pure display component used in the memory feed (Phase 3.2), the unified requests view (Phase 4), and any other context showing a question-answer pair.

**Props:**
```typescript
interface Props {
  questionText: string;
  answerContent: string;
  respondentName?: string;    // Optional — shown in "X answered a question" header
  date?: string;
  dateType?: DateType;
  images?: AnswerImage[] | ImageLink[];
  movies?: AnswerMovie[];
  questionSetName?: string;   // Optional — shows "From: {name}" footer
  questionRequestId?: number; // For "View Set" link
  variant?: 'full' | 'compact'; // compact = truncated, used in request expansion
}
```

**Template (full variant):**
```html
<div class="question-answer-card card mb-3">
  <!-- Header: respondent attribution -->
  <div v-if="respondentName" class="card-header bg-transparent border-bottom-0 pb-0">
    <small class="text-muted">
      <span class="mdi mdi-message-reply-text-outline me-1"></span>
      <strong>{{ respondentName }}</strong> answered a question
    </small>
  </div>

  <div class="card-body" :class="{ 'pt-2': respondentName }">
    <!-- Question (quoted style) -->
    <div class="question-quote p-3 bg-light rounded border-start border-primary border-4 mb-3">
      <p class="mb-0 fst-italic">"{{ questionText }}"</p>
    </div>

    <!-- Answer content -->
    <div class="answer-content">
      <p v-if="variant === 'compact'" class="mb-2">{{ truncated }}</p>
      <p v-else class="mb-2">{{ answerContent }}</p>
    </div>

    <!-- Date -->
    <p v-if="date" class="text-muted small mb-3">
      <span class="mdi mdi-calendar-outline me-1"></span>
      {{ formattedDate }}
    </p>

    <!-- Media -->
    <PhotoGrid v-if="normalizedImages.length" :images="normalizedImages" class="mb-3" />
    <div v-for="vid in movies" :key="vid.movieDropId" class="mb-2">
      <video v-if="vid.videoUrl" :src="vid.videoUrl" :poster="vid.thumbnailUrl"
        controls class="img-fluid rounded" style="max-height: 400px;"></video>
    </div>

    <!-- Footer: question set reference -->
    <div v-if="questionSetName" class="border-top pt-2 mt-2">
      <small class="text-muted">
        From: {{ questionSetName }}
        <router-link v-if="questionRequestId" :to="`/questions/requests`" class="ms-2">
          View all responses
        </router-link>
      </small>
    </div>
  </div>
</div>
```

#### 3.2 Memory Feed Integration

Update `MemoryCard.vue` to enhance the question context display and add a "View all responses" link (PRD Section 5.3).

Currently, `MemoryCard.vue` shows a simple inline quote. We keep the inline approach (not importing `QuestionAnswerCard` since `MemoryCard` has its own layout) but ensure the styling matches and add the missing link:

```html
<!-- Question context (for answers to question requests) -->
<div v-if="memory.questionContext" class="question-context mb-3">
  <small class="text-muted d-block mb-2">
    <span class="mdi mdi-message-reply-text-outline me-1"></span>
    <strong>{{ memory.createdBy }}</strong> answered a question
  </small>
  <div class="question-quote p-3 bg-light rounded border-start border-primary border-4">
    <p class="mb-0 fst-italic">"{{ memory.questionContext.questionText }}"</p>
  </div>
  <router-link
    :to="`/questions/requests`"
    class="text-muted small mt-1 d-inline-block"
  >
    View all responses
  </router-link>
</div>
```

#### 3.3 Tests

**File:** `fyli-fe-v2/src/components/question/QuestionAnswerCard.test.ts`

Test cases:
1. Renders question text in quoted style
2. Renders answer content
3. Shows respondent name header when provided
4. Hides respondent name header when not provided
5. Shows date formatted correctly for each dateType
6. Shows images via PhotoGrid
7. Shows videos with controls
8. Shows question set footer with "View all responses" link when provided
9. Compact variant truncates long content
10. Full variant shows complete content

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.test.ts` (update existing)

Test cases:
1. Shows "X answered a question" header for question-answer memories
2. Shows "View all responses" link when `questionContext` is present
3. Does NOT show question context for non-question memories

---

### Phase 4: Frontend — Unified Question Requests View

**Goal:** Replace separate "Sent Requests" and "View Responses" views with a single unified expandable view. Uses `QuestionAnswerCard` from Phase 3 for consistent answer display.

#### 4.1 QuestionRequestCard Component

Create `fyli-fe-v2/src/components/question/QuestionRequestCard.vue`:

**Props:**
```typescript
interface Props {
  request: QuestionRequestDetail;
}
```

**Template structure:**
```
Card (collapsed by default)
├── Header (always visible, clickable to expand)
│   ├── Question set name (h5, semi-bold)
│   ├── "Sent {date}" (text-muted small)
│   ├── "{respondedCount}/{totalRecipients} responded" badge
│   └── Expand/collapse chevron icon
│
└── Body (v-show for smooth animation, CSS max-height transition)
    └── For each recipient:
        ├── RecipientSection header
        │   ├── DisplayName (semi-bold)
        │   ├── Status indicator (green check / yellow partial / gray pending)
        │   └── Actions: Copy Link | Remind | Deactivate
        │
        └── If answered:
            └── For each answered question:
                └── <QuestionAnswerCard variant="compact" />

            If not answered:
                └── "Waiting for response..." + [Send Reminder] button
```

**Expand/collapse — use `v-show` for smooth animation:**
```typescript
const expanded = ref(false);

function toggle() {
  expanded.value = !expanded.value;
}
```

```html
<!-- Use v-show (not v-if) so CSS transition works on expand/collapse -->
<div v-show="expanded" class="card-body-expandable">
  <!-- recipient sections here -->
</div>
```

```css
.card-body-expandable {
  overflow: hidden;
  transition: max-height 0.3s ease-in-out, opacity 0.3s ease-in-out;
}
```

**Computed properties:**
```typescript
const respondedCount = computed(() =>
  props.request.recipients.filter(r =>
    r.answers.some(a => a.isAnswered)
  ).length
);

const totalRecipients = computed(() => props.request.recipients.length);
```

**Status indicator logic:**
```typescript
function recipientStatus(recipient: RecipientDetail): 'complete' | 'partial' | 'pending' | 'deactivated' {
  if (!recipient.isActive) return 'deactivated';
  const answeredCount = recipient.answers.filter(a => a.isAnswered).length;
  const totalQuestions = recipient.answers.length;
  if (answeredCount === totalQuestions) return 'complete';
  if (answeredCount > 0) return 'partial';
  return 'pending';
}
```

**Status indicator styling:**
| Status | Icon | Color | Bootstrap class |
|--------|------|-------|-----------------|
| complete | `mdi-check-circle` | Green | `text-success` |
| partial | `mdi-progress-clock` | Warning | `text-warning` |
| pending | `mdi-circle-outline` | Gray | `text-muted` |
| deactivated | `mdi-close-circle` | Secondary | `text-secondary` |

**Actions (emitted to parent):**
```typescript
const emit = defineEmits<{
  (e: 'copyLink', token: string): void;
  (e: 'remind', recipientId: number): void;
  (e: 'deactivate', recipientId: number): void;
  (e: 'viewFull', dropId: number): void;
}>();
```

**Answer content display — uses QuestionAnswerCard:**

For each answered question within a recipient section, render:

```html
<QuestionAnswerCard
  v-for="answer in answeredQuestions(recipient)"
  :key="answer.questionId"
  :question-text="answer.questionText"
  :answer-content="answer.content"
  :date="answer.date"
  :date-type="answer.dateType"
  :images="answer.images"
  :movies="answer.movies"
  variant="compact"
/>
<div class="text-end mt-1">
  <button class="btn btn-sm btn-link" @click="emit('viewFull', answer.dropId)">
    View Full
  </button>
</div>
```

#### 4.2 QuestionRequestsView (Unified View)

Create `fyli-fe-v2/src/views/question/QuestionRequestsView.vue`:

**Route:** `/questions/requests` (replaces both `/questions/dashboard` and `/questions/responses`)

**Template:**
```html
<div class="container py-4">
  <h1 class="h3 mb-4">My Requests</h1>

  <LoadingSpinner v-if="loading" />
  <ErrorAlert v-else-if="loadError" :message="loadError" @retry="loadData" />

  <div v-else-if="requests.length === 0" class="text-center py-5 text-muted">
    <span class="mdi mdi-comment-question-outline" style="font-size: 3rem;"></span>
    <p class="mt-2">You haven't sent any question requests yet.</p>
    <router-link to="/questions" class="btn btn-primary">
      Create Question Set
    </router-link>
  </div>

  <div v-else>
    <QuestionRequestCard
      v-for="req in requests"
      :key="req.questionRequestId"
      :request="req"
      @copyLink="handleCopyLink"
      @remind="handleRemind"
      @deactivate="handleDeactivate"
      @viewFull="handleViewFull"
    />
  </div>

  <!-- Toast for success messages -->
  <div v-if="toastMessage" class="toast-container position-fixed bottom-0 end-0 p-3">
    <div class="toast show" role="alert">
      <div class="toast-body">{{ toastMessage }}</div>
    </div>
  </div>
</div>
```

**Script:**
```typescript
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { getDetailedRequests, sendReminder, deactivateRecipient } from '@/services/questionApi';
import { getErrorMessage } from '@/utils/errorMessage';
import type { QuestionRequestDetail } from '@/types';

const router = useRouter();
const requests = ref<QuestionRequestDetail[]>([]);
const loading = ref(true);
const loadError = ref('');
const toastMessage = ref('');
const actionError = ref('');

onMounted(() => loadData());

async function loadData() {
  loading.value = true;
  loadError.value = '';
  try {
    const { data } = await getDetailedRequests();
    requests.value = data;
  } catch (e: unknown) {
    loadError.value = getErrorMessage(e, 'Failed to load requests');
  } finally {
    loading.value = false;
  }
}

async function handleCopyLink(token: string) {
  try {
    await navigator.clipboard.writeText(`${window.location.origin}/q/${token}`);
    showToast('Link copied!');
  } catch {
    showToast('Failed to copy link');
  }
}

async function handleRemind(recipientId: number) {
  try {
    await sendReminder(recipientId);
    showToast('Reminder sent');
  } catch (e: unknown) {
    actionError.value = getErrorMessage(e, 'Failed to send reminder');
  }
}

async function handleDeactivate(recipientId: number) {
  if (!confirm('Deactivate this link? The recipient will no longer be able to answer.')) return;
  try {
    await deactivateRecipient(recipientId);
    await loadData(); // Refresh
  } catch (e: unknown) {
    actionError.value = getErrorMessage(e, 'Failed to deactivate');
  }
}

function handleViewFull(dropId: number) {
  router.push(`/memory/${dropId}`);
}

function showToast(msg: string) {
  toastMessage.value = msg;
  setTimeout(() => { toastMessage.value = ''; }, 2000);
}
```

#### 4.3 Router Updates

In `fyli-fe-v2/src/router/index.ts`:

1. Add the new unified route:
```typescript
{
  path: '/questions/requests',
  name: 'question-requests',
  component: () => import('@/views/question/QuestionRequestsView.vue'),
  meta: { auth: true, layout: 'app' },
},
```

2. Add redirects for old routes:
```typescript
{
  path: '/questions/dashboard',
  redirect: '/questions/requests',
},
{
  path: '/questions/responses',
  redirect: '/questions/requests',
},
```

#### 4.4 Tests

**File:** `fyli-fe-v2/src/components/question/QuestionRequestCard.test.ts`

Test cases:
1. Renders collapsed card with set name, date, response count
2. Expands on header click, shows recipient sections
3. Shows correct status indicators per recipient
4. Renders `QuestionAnswerCard` with `variant="compact"` for each answered question
5. Shows "Waiting for response..." for unanswered recipients
6. Emits `copyLink` with token on Copy Link button click
7. Emits `remind` with recipientId on Remind button click
8. Hides Remind button for recipients without email
9. Hides Remind button for recipients who completed all questions
10. Emits `deactivate` with recipientId on Deactivate click
11. Shows deactivated badge and hides actions for inactive recipients
12. Emits `viewFull` with dropId on "View Full" link click
13. Uses `resolveRespondentName` for display names

**File:** `fyli-fe-v2/src/views/question/QuestionRequestsView.test.ts`

Test cases:
1. Shows loading spinner while fetching
2. Shows error alert with retry on fetch failure
3. Shows empty state when no requests
4. Renders QuestionRequestCard for each request
5. Handles copy link with clipboard API and shows toast
6. Handles copy link failure gracefully
7. Handles remind action and shows toast
8. Handles remind failure with error message
9. Handles deactivate with confirmation and refreshes data
10. Handles deactivate failure with error message
11. Navigates to memory detail on viewFull

---

### Phase 5: Frontend — Navigation Cleanup & Route Redirects

**Goal:** Update navigation to point to the unified view, remove deprecated views.

#### 5.1 QuestionSetListView Update

Replace the two separate navigation links at the bottom:

**Before (lines 43-50):**
```html
<div class="mt-4">
  <router-link to="/questions/dashboard" class="btn btn-outline-secondary me-2">
    View Sent Requests
  </router-link>
  <router-link to="/questions/responses" class="btn btn-outline-secondary">
    View Responses
  </router-link>
</div>
```

**After:**
```html
<div class="mt-4">
  <router-link to="/questions/requests" class="btn btn-outline-secondary">
    <span class="mdi mdi-format-list-bulleted me-1"></span>
    My Requests
  </router-link>
</div>
```

#### 5.2 AppBottomNav Update

The bottom nav currently points to `/questions` (QuestionSetListView). This stays the same — the QuestionSetListView acts as the hub with a link to the unified requests view.

No changes to `AppBottomNav.vue`.

#### 5.3 Remove Deprecated Views

Delete (or keep with redirect — redirects already added in Phase 4.3):
- `fyli-fe-v2/src/views/question/QuestionDashboardView.vue` — replaced by `QuestionRequestsView`
- `fyli-fe-v2/src/views/question/QuestionResponsesView.vue` — replaced by `QuestionRequestsView`

Also delete their test files:
- `QuestionDashboardView.test.ts`
- `QuestionResponsesView.test.ts`

#### 5.4 Tests

**File:** `fyli-fe-v2/src/views/question/QuestionSetListView.test.ts` (update existing)

Test cases:
1. Shows "My Requests" link pointing to `/questions/requests`
2. Does NOT show "View Sent Requests" or "View Responses" links

**Router tests (manual verification):**
1. `/questions/dashboard` redirects to `/questions/requests`
2. `/questions/responses` redirects to `/questions/requests`
3. `/questions/requests` loads QuestionRequestsView

---

### Phase 6: Testing

**Goal:** Comprehensive test coverage for all new components, utilities, and API changes.

#### 6.1 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs` (add tests)

Test cases for `GetDetailedRequests`:
1. Returns empty list when user has no requests
2. Returns requests with all recipients and their answer status
3. Includes full answer content and media URLs
4. Uses correct identity resolution (alias > name > email > "Family Member")
5. Orders requests by CreatedAt descending
6. Respects skip/take pagination
7. Caps take at 100

Test cases for `ResolveRespondentName` (via existing methods that use it):
1. Returns alias when present
2. Returns user name when no alias but user registered
3. Returns user email when no alias or name
4. Returns recipient email when no user account
5. Returns "Family Member" when nothing available

Test cases for `AnswerViewModel` new fields:
1. `IsOwnAnswer` is `true` on the `/q/{token}` answer page
2. `EditWindowExpiresAt` is `AnsweredAt + 7 days` for anonymous users
3. `EditWindowExpiresAt` is `null` for registered users

Test cases for identity fix verification:
1. `SubmitAnswer` email notification uses resolved name (not "Someone")
2. `GetMyQuestionResponses` never returns "Anonymous" as respondent name

#### 6.2 Frontend Test Summary

All test files mentioned in phases above:

| File | Test Count | Phase |
|------|-----------|-------|
| `respondentName.test.ts` | 7 | 2 |
| `questionApi.test.ts` (additions) | 2 | 2 |
| `AnswerPreview.test.ts` (additions) | 7 | 2 |
| `QuestionAnswerCard.test.ts` | 10 | 3 |
| `MemoryCard.test.ts` (additions) | 3 | 3 |
| `QuestionRequestCard.test.ts` | 13 | 4 |
| `QuestionRequestsView.test.ts` | 11 | 4 |
| `QuestionSetListView.test.ts` (updates) | 2 | 5 |
| **Total new frontend tests** | **~55** | |

---

## File Structure Summary

### New Files

```
cimplur-core/Memento/
└── (No new files — updates to existing QuestionService, QuestionController, QuestionModels)

fyli-fe-v2/src/
├── utils/
│   ├── respondentName.ts          (identity resolution utility)
│   └── respondentName.test.ts
├── components/question/
│   ├── QuestionRequestCard.vue    (expandable request card)
│   ├── QuestionRequestCard.test.ts
│   ├── QuestionAnswerCard.vue     (unified Q&A display)
│   └── QuestionAnswerCard.test.ts
└── views/question/
    ├── QuestionRequestsView.vue   (unified view, replaces Dashboard + Responses)
    └── QuestionRequestsView.test.ts
```

### Modified Files

```
cimplur-core/Memento/
├── Memento/Controllers/QuestionController.cs   (new endpoint)
├── Domain/Repositories/QuestionService.cs      (new method + identity helper + fix callsites)
├── Domain/Repositories/IQuestionService.cs     (interface update)
├── Domain/Models/QuestionModels.cs             (new DTOs + isOwnAnswer + editWindowExpiresAt)
└── Domain/Emails/EmailTemplates.cs             (fix QuestionAnswerNotification link)

fyli-fe-v2/src/
├── types/question.ts                           (new types + isOwnAnswer + editWindowExpiresAt)
├── services/questionApi.ts                     (new API function)
├── router/index.ts                             (new route + redirects)
├── views/question/QuestionSetListView.vue      (updated nav links)
├── components/question/AnswerPreview.vue        (isOwnAnswer guard + countdown)
└── components/memory/MemoryCard.vue            (enhanced question context + "View all responses")
```

### Deleted Files

```
fyli-fe-v2/src/
├── views/question/QuestionDashboardView.vue
├── views/question/QuestionDashboardView.test.ts
├── views/question/QuestionResponsesView.vue
└── views/question/QuestionResponsesView.test.ts
```

---

## Implementation Order

1. **Phase 1a** — Backend: Identity resolution helper + fix existing callsites + email fixes + `isOwnAnswer`/`editWindowExpiresAt`
2. **Phase 1b** — Backend: New unified endpoint + updated response models
3. **Phase 2** — Frontend: Identity utility + types + API service + edit guard fixes + countdown
4. **Phase 3** — Frontend: QuestionAnswerCard + MemoryCard integration (must exist before Phase 4)
5. **Phase 4** — Frontend: Unified QuestionRequestsView + QuestionRequestCard (uses QuestionAnswerCard)
6. **Phase 5** — Frontend: Navigation cleanup + route redirects + remove deprecated views
7. **Phase 6** — Testing: Full test coverage pass

Phases 1a and 1b can be developed in parallel. Phase 2 depends on 1a (for `isOwnAnswer`/`editWindowExpiresAt` fields). Phase 3 depends on 2 (for types). Phase 4 depends on both 1b (for API) and 3 (for QuestionAnswerCard component). Phase 5 can begin once Phase 4 is complete.

---

## Open Questions from PRD

| Question | Recommendation |
|----------|---------------|
| **View name:** "Question Requests" vs "Questions I've Asked"? | **"My Requests"** — short, clear, consistent with "My Question Sets" |
| **Default state:** Collapsed or expanded? | **Collapsed** — saves space, users scan headers first |
| **"View Full" action:** Modal, navigate, or expand inline? | **Navigate to `/memory/{dropId}`** — reuses existing memory detail view, simplest |
| **Email masking:** Should fallback email be masked? | **No masking** — the asker already knows who they sent to; masking adds confusion |

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| N+1 queries on detailed endpoint | Use `.AsSplitQuery()` and `.Include()` chains to eager-load in controlled batches |
| Large response payload (many recipients with media) | Paginate at the request level (skip/take), lazy-load media URLs |
| Breaking bookmarks to old routes | Redirects from `/questions/dashboard` and `/questions/responses` |
| Backwards compatibility | Old API endpoints (`/requests/sent`, `/responses`) remain unchanged; new endpoint is additive |
| Token exposure in unified endpoint | Mirrors existing `/requests/sent` behavior; tokens only returned to authenticated creator (see 1b.5) |
