# Product Requirements Document: Unified Questions Page

## Overview

The Questions feature currently splits across two pages: `/questions` (question set management) and `/questions/requests` (sent requests & responses). This PRD defines a unified single-page experience where each question set is represented as a card showing its full lifecycle — draft, sent, response tracking — in one view. Responses from multiple sends of the same set aggregate under a single card.

## Problem Statement

Busy parents using Questions must navigate between two separate pages to complete what feels like one workflow: create questions, send them, and track responses. The current split creates confusion:

- **Mental model mismatch:** Users think in terms of "my questions" as a single concept, not "my question templates" vs "my sent requests"
- **Navigation tax:** After creating and sending a question set, the user lands back on the set list — not where responses will appear. They must manually navigate to `/questions/requests` to track progress
- **Discoverability:** The "My Requests" link at the bottom of `/questions` is easy to miss. New users may not realize responses live on a separate page
- **Low utility of the set list:** For most users, the set list is a pass-through — they create a set, send it, and rarely return to the set list itself. The set list adds a step without adding value for the common workflow
- **Fragmented create flow:** Users must create a set first, go back to the list, then click "Send" — three steps for what should feel like one action
- **Email is optional:** Recipients can be added with just a name (alias), which means they never receive a notification email, reminders don't work, and the user must manually share the link. This defeats the purpose of the sending flow.
- **No recipient memory:** When sending the same questions to family again next year, users must retype every email and name from scratch. There's no way to recall who you've sent to before.

## Goals

1. **Single destination** — One page for all question activity: creating, sending, and tracking responses
2. **Response-forward** — The primary information on screen should answer "did anyone respond?"
3. **Streamlined creation** — Combine "create set" and "send" into one flow so users can go from idea to sent in a single pass
4. **Aggregated view** — When the same question set is sent to different groups over time, responses aggregate under one card
5. **Reliable delivery** — Every recipient gets an email notification; no silent link-only sends
6. **Recipient memory** — Previously sent-to recipients are recalled and selectable so users don't retype emails

---

## User Stories

### Viewing Questions
1. As a busy parent, I want to see all my question sets and their response statuses on one page so that I can quickly check if grandma responded without navigating between pages.
2. As a user, I want unsent question sets to appear alongside sent ones so that I can see my drafts and pick up where I left off.
3. As a user, I want to see aggregated response counts across all sends of a question set so that I know the total picture without clicking into each send.

### Creating & Sending
4. As a busy parent, I want to create questions and send them in one flow so that I don't have to bounce between pages to go from idea to sent.
5. As a user, I want to send an existing question set to new recipients so that I can reuse good questions without recreating them.
6. As a user, I want to see people I've previously sent questions to so that I can quickly re-select them without retyping their email and name.
7. As a user, I want every recipient to receive an email notification so that I don't have to manually share links.

### Tracking Responses
6. As a user, I want to expand a question set card to see all recipients grouped by send so that I can track who has responded and who hasn't.
7. As a user, I want to send reminders, copy links, and deactivate recipients directly from the expanded card so that I can manage everything in one place.
8. As a user, I want to see inline answer previews with media thumbnails so that I get a quick sense of what people shared without leaving the page.

### Managing Sets
9. As a user, I want to edit a question set's name and questions from the unified page so that I don't need a separate management screen.
10. As a user, I want to delete an unsent question set so that I can clean up drafts I no longer need.

---

## Feature Requirements

### 1. Unified Question Set Cards

Each question set the user has created appears as a card in a single feed on `/questions`. Cards are sorted by most recent activity (latest response or latest send, falling back to creation date).

#### 1.1 Card States

A card has one of three visual states based on its lifecycle:

**Draft** — Set created but never sent
```
┌─────────────────────────────────────────────┐
│  Summer Vacation Qs                  (draft) │
│  Created Feb 1 · 3 questions                 │
│  [Ask Questions]  [Edit]  [Delete]           │
└─────────────────────────────────────────────┘
```
- Shows set name, creation date, question count
- Actions: Ask Questions (opens send flow), Edit, Delete
- Muted visual treatment to distinguish from active sets

**Sent — Awaiting Responses**
```
┌─────────────────────────────────────────────┐
│  Christmas Memories                      ▾   │
│  3 questions · 2/5 responded                 │
│  Most recent: "Uncle Jim answered 1 hour ago"│
└─────────────────────────────────────────────┘
```
- Shows set name, question count, aggregated response ratio
- Most recent activity line (latest answer or send)
- Expandable (chevron) to see full recipient details
- Sort priority: sets with new unread responses surface to top

**Fully Responded**
```
┌─────────────────────────────────────────────┐
│  Dad's Childhood Stories                 ▾   │
│  3 questions · 4/4 responded  ✓ Complete     │
│  Last response: Jan 15                       │
└─────────────────────────────────────────────┘
```
- Green checkmark or "Complete" badge
- Still expandable to review responses
- Sorted below sets with pending responses

#### 1.2 Expanded Card — Aggregated Responses

When expanded, a card shows all sends grouped chronologically, with recipients and their answer statuses:

```
┌─────────────────────────────────────────────┐
│  Christmas Memories                      ▴   │
│  3 questions · 5/8 responded                 │
│                                              │
│  ── Sent Dec 20 to 5 recipients ──────────  │
│  ✓ Grandma Betty      [link] [deactivate]   │
│     "It was Christmas of '72..."  [View Full]│
│  ◔ Uncle Jim (1/3)    [link] [remind] [deac] │
│  ○ Aunt Sarah         [link] [remind] [deac] │
│  ...                                         │
│                                              │
│  ── Sent Jan 5 to 3 recipients ────────────  │
│  ✓ Mom                [link] [deactivate]    │
│  ✓ Cousin Alex        [link] [deactivate]    │
│  ○ Uncle Bob           [link] [remind] [deac] │
│                                              │
│  [Ask More People]  [Edit Set]               │
└─────────────────────────────────────────────┘
```

- Sends are grouped with date headers ("Sent Dec 20 to 5 recipients")
- Each recipient shows: status icon, display name, actions
- Answered recipients show inline answer preview (compact QuestionAnswerCard)
- "View Full" links to the memory detail (`/memory/{dropId}`)
- Bottom actions: "Ask More People" (re-send to new recipients), "Edit Set"

#### 1.3 Aggregated Response Count

The card header shows a single aggregated response ratio across all sends:
- Numerator: total unique recipients who have answered at least one question
- Denominator: total unique recipients across all sends
- Example: Sent to 5 people on Dec 20, 3 people on Jan 5 → "X/8 responded"

### 2. Combined "Ask Questions" Flow

The current two-step process (create set → go back → click Send) is replaced by a single flow accessible from two entry points:

#### 2.1 New Questions (from "+ Ask Questions" button)
1. User clicks "+ Ask Questions" on the unified page
2. **Step 1 — Questions:** Enter set name and 1-5 questions (same as current QuestionSetEditView)
3. **Step 2 — Recipients:** Add recipients with email/alias, optional personal message (same as current QuestionSendView)
4. **Step 3 — Confirmation:** Show generated links, then redirect to unified page with the new card highlighted

This is a single multi-step view, not separate pages. The set is saved when the user completes the flow. The URL can be `/questions/new`.

#### 2.2 Send to More People (from existing card)
1. User clicks "Ask More People" on an expanded card
2. Jumps directly to Step 2 (Recipients) with the existing set pre-loaded
3. Same completion flow — links shown, redirect back to unified page

#### 2.3 Pick Existing Set
When the user clicks "+ Ask Questions", if they have existing question sets, show an option to pick an existing set or create new:

```
┌─────────────────────────────────────────────┐
│  Ask Questions                               │
│                                              │
│  ○ Create new questions                      │
│  ○ Use existing set:                         │
│     - Christmas Memories (5 Qs)              │
│     - Dad's Childhood Stories (3 Qs)         │
│                                              │
│  [Next →]                                    │
└─────────────────────────────────────────────┘
```

If "Create new" is selected → proceed to Step 1 (questions).
If an existing set is selected → skip to Step 2 (recipients).

### 3. Sending Improvements

#### 3.1 Email Required

Email is now **required** for every recipient. Name (alias) remains optional.

**Current behavior:** A recipient is valid if they have email OR alias. Recipients added with only a name never receive a notification email, and reminders cannot be sent to them.

**New behavior:** Email is required. Name is optional but encouraged. The email field has `required` validation and the form cannot submit without a valid email for every recipient row.

- Frontend: email input gets `required` attribute, placeholder changes from "Email (optional)" to "Email"
- Frontend: validation rejects rows with blank email (instead of current "email or alias" check)
- Backend: `CreateQuestionRequest` validates that every recipient has a non-empty, valid email (reject the request if any recipient is missing email)
- Backend: existing recipients with alias-only remain unchanged (backwards compatible data)

#### 3.2 Previous Recipients (Recipient Memory)

When a user enters the recipients step of the send flow, previously sent-to recipients appear as selectable suggestions. This applies both to "Ask Questions" (new send) and "Ask More People" (re-send from a card).

**How it works:**

1. A new endpoint returns the user's distinct past recipients:
   ```
   GET /api/questions/recipients/previous
   ```
   Returns a list of unique recipients the user has previously sent to, deduplicated by email:
   ```typescript
   interface PreviousRecipient {
     email: string
     alias: string | null      // most recent alias used for this email
     lastSentAt: string         // when they were last sent questions
     hasLink: boolean           // true if they have an active link for the current set
     activeToken: string | null // their existing token for this set (if re-sending same set)
   }
   ```

2. The recipients step shows these suggestions above the manual entry form:

```
┌─────────────────────────────────────────────┐
│  Who should answer these questions?          │
│                                              │
│  ── Previously sent to ────────────────────  │
│  ☐ grandma@email.com (Grandma Betty)        │
│     Last sent: Dec 20 · Has active link      │
│  ☐ uncle.jim@email.com (Uncle Jim)          │
│     Last sent: Dec 20                        │
│  ☐ mom@email.com (Mom)                      │
│     Last sent: Jan 5                         │
│                                              │
│  ── Add new recipients ────────────────────  │
│  [ Email (required) ] [ Name (optional) ]  ✕ │
│  [+ Add Recipient]                           │
│                                              │
│  Message (optional): [________________]      │
│  [Send Questions]                            │
└─────────────────────────────────────────────┘
```

3. **Selection behavior:**
   - Checking a previous recipient adds them to the send list
   - If the recipient already has an active link for *this specific question set*, show "Has active link" and include their existing token in the confirmation step (so the user can re-share it)
   - If they don't have a link for this set, a new token is generated on send
   - Users can still add new recipients manually below the suggestions

4. **Deduplication:**
   - If a user manually types an email that matches a previous recipient, show a hint: "You've sent to this person before"
   - Backend deduplication: if the same email already has an active token for this question set, don't create a duplicate — return the existing token instead

#### 3.3 Confirmation Step with Links

After sending, the confirmation step shows all recipient links (both new and existing):

```
┌─────────────────────────────────────────────┐
│  ✓ Questions sent!                           │
│                                              │
│  grandma@email.com (Grandma Betty)           │
│  https://app.cimplur.com/q/abc123  [Copy]    │
│                                              │
│  uncle.jim@email.com (Uncle Jim)             │
│  https://app.cimplur.com/q/def456  [Copy]    │
│                                              │
│  new.person@email.com                        │
│  https://app.cimplur.com/q/ghi789  [Copy]    │
│                                              │
│  [Back to Questions]                         │
└─────────────────────────────────────────────┘
```

Each row shows: email, name (if provided), full link, and copy button. This gives the user everything they need to also share via text message or other channels.

### 4. Page Layout

```
/questions
┌─────────────────────────────────────────────┐
│  Questions                [+ Ask Questions]  │
│                                              │
│  (Question set cards, sorted by activity)    │
│  ...                                         │
│                                              │
│  (Empty state if no sets)                    │
└─────────────────────────────────────────────┘
```

#### 3.1 Empty State
```
┌─────────────────────────────────────────────┐
│  Questions                                   │
│                                              │
│  (question mark icon)                        │
│  Ask your family to share their stories.     │
│  Create questions and send them to anyone —  │
│  they can answer without an account.         │
│                                              │
│  [+ Ask Questions]                           │
└─────────────────────────────────────────────┘
```

#### 3.2 Sorting
Cards are sorted by most recent activity descending:
1. Sets with pending (unanswered) responses — sorted by latest activity
2. Fully responded sets — sorted by last response date
3. Draft (unsent) sets — sorted by creation date

### 5. Routing Changes

| Current Route | New Behavior |
|---------------|-------------|
| `/questions` | Unified page (this PRD) |
| `/questions/requests` | Redirect to `/questions` |
| `/questions/dashboard` | Redirect to `/questions` |
| `/questions/responses` | Redirect to `/questions` |
| `/questions/new` | Combined create+send flow |
| `/questions/:id/edit` | Edit set (keep — linked from card actions) |
| `/questions/:id/send` | Redirect to `/questions/new?setId={id}` |
| `/q/:token` | Unchanged (public answer page) |

### 6. Backend API Changes

#### 5.1 New Endpoint: Unified Question Sets with Aggregated Status

```
GET /api/questions/sets/unified?skip=0&take=20
```

Returns question sets with aggregated request/response data:

```typescript
interface UnifiedQuestionSet {
  questionSetId: number
  name: string
  questionCount: number
  createdAt: string
  updatedAt: string

  // Aggregated across all sends
  totalRecipients: number       // across all requests
  respondedRecipients: number   // recipients with at least 1 answer
  latestActivity: string | null // most recent answer or send date
  latestActivityDescription: string | null // e.g. "Grandma answered 1 hour ago"

  // Grouped sends (for expanded view)
  requests: UnifiedRequest[]
}

interface UnifiedRequest {
  questionRequestId: number
  createdAt: string
  message: string | null
  recipients: RecipientDetail[]  // reuse existing type
}
```

Sorted by: `latestActivity` descending (nulls last — drafts at bottom).

#### 6.2 New Endpoint: Previous Recipients

```
GET /api/questions/recipients/previous
```

Returns distinct past recipients for the current user, deduplicated by email (case-insensitive). For each email, returns the most recently used alias. Sorted by `lastSentAt` descending.

Optionally accepts `?questionSetId={id}` to include `hasLink` and `activeToken` fields for detecting existing tokens on the specified set.

#### 6.3 Modified Endpoint: Create Question Request

`POST /api/questions/requests` — Updated validation:
- **Email is now required** for every recipient (was: email or alias)
- Returns `400 Bad Request` if any recipient has a blank or invalid email
- If a recipient email already has an active token for the same question set, return the existing token instead of creating a duplicate

#### 6.4 Existing Endpoints (unchanged)
- `POST /api/questions/sets` — Create set
- `PUT /api/questions/sets/{id}` — Update set
- `DELETE /api/questions/sets/{id}` — Archive set
- `POST /api/questions/recipients/{id}/remind` — Send reminder
- `POST /api/questions/recipients/{id}/deactivate` — Deactivate link

---

## UI/UX Requirements

### Card Design
- Cards use the existing Bootstrap card pattern with white background, subtle border
- Draft cards have a muted/dashed border to visually distinguish them
- Expandable cards use chevron toggle (reuse pattern from QuestionRequestCard)
- Status icons reuse existing iconography: ✓ green, ◔ orange, ○ gray, ✕ red

### Responsive
- Cards stack full-width on mobile
- Recipient action buttons collapse to icon-only on small screens (already the pattern)

### Progressive Disclosure
- Card headers show summary (name, counts, latest activity)
- Expanding reveals full recipient list with inline answers
- "View Full" navigates to memory detail for deep content

### Transitions
- After completing the Ask Questions flow, redirect to `/questions` with the new/updated card at the top
- Smooth expand/collapse animation on cards (v-show, same as current)

---

## Data Model

No new database entities required. The unified endpoint aggregates existing data:
- `QuestionSet` + `Question` (set template)
- `QuestionRequest` + `QuestionRequestRecipient` (sends)
- `QuestionResponse` (answer linkage to drops)

The new `GET /api/questions/sets/unified` endpoint joins these tables and computes aggregated counts server-side.

---

## Technical Considerations

### Performance
- The unified endpoint must be efficient since it replaces two separate calls. Use a single query with JOINs and GROUP BY to compute aggregated counts, plus a second query for the detailed recipient data (only for expanded cards, loaded on-demand)
- Consider: load card headers (aggregated counts) on page load, then lazy-load recipient details when a card is expanded

### Lazy Loading Expanded Details
- Option A: Return everything in one call (simpler, fine for <50 sets)
- Option B: Return headers only, fetch `GET /api/questions/sets/{id}/unified` on expand (better for scale)
- **Recommendation: Start with Option A.** Most users will have <10 sets. Optimize later if needed.

### Backwards Compatibility
- Old routes (`/questions/requests`, `/questions/dashboard`, `/questions/responses`) redirect to `/questions`
- MemoryCard and QuestionAnswerCard links updated to `/questions`
- The `GET /api/questions/requests/detailed` and `GET /api/questions/requests/sent` endpoints remain available (no breaking changes)

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Page Navigation Reduction | Avg pages visited per question workflow session | <2 (from current ~3) |
| Response Check Frequency | Times per week user checks for new responses | 3+ |
| Time to First Response Check | Time from sending questions to first visit to response view | <1 hour |
| Set Reuse Rate | % of sends that use an existing set vs. creating new | Track baseline first |

---

## Out of Scope (Future Considerations)

- Bottom nav badge for pending response count
- Quick send (create and send without saving as reusable set)
- Real-time push notifications for new responses
- Bulk actions (remind all pending recipients at once)
- Search/filter within the question sets list
- Archiving completed sets to reduce clutter

---

## Implementation Phases

### Phase 1: Backend — Unified Endpoint + Sending Changes
- Create `GET /api/questions/sets/unified` endpoint with aggregated response counts
- Create `GET /api/questions/recipients/previous` endpoint for recipient suggestions
- Update `POST /api/questions/requests` to require email, add duplicate detection
- Add service methods and tests for all three

### Phase 2: Unified Page View
- Create new `UnifiedQuestionsView.vue` replacing `QuestionSetListView`
- Build `QuestionSetCard.vue` component with draft/sent/complete states
- Expand existing `QuestionRequestCard` patterns for the aggregated view
- Wire up recipient actions (remind, copy link, deactivate)
- Update routing: `/questions` points to new view, old routes redirect

### Phase 3: Combined Ask Questions Flow + Recipient Improvements
- Create `AskQuestionsView.vue` as multi-step flow (pick/create → recipients → confirmation)
- Step 0: Choose "Create new" or select existing set
- Step 1: Set name + questions (from QuestionSetEditView)
- Step 2: Recipients with previous recipient suggestions, email required, optional message
- Step 3: Confirmation with all links (email + name + link + copy), redirect to unified page
- Update "Ask More People" action on cards to enter at Step 2
- Email required validation on frontend

### Phase 4: Cleanup & Polish
- Remove `QuestionSetListView.vue` and `QuestionRequestsView.vue`
- Remove legacy `QuestionDashboardView.vue` and `QuestionResponsesView.vue`
- Update all internal links (MemoryCard, QuestionAnswerCard, AppBottomNav)
- Update `QuestionSetEditView` cancel/save redirects
- Verify all redirects work correctly
- Empty state and loading state polish

---

*Document Version: 3.0*
*Created: 2026-02-07*
*Status: Draft*
