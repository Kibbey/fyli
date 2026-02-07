# Product Requirements Document: Question Answer UX Consistency

## Overview

Unify the user experience for viewing and interacting with question-generated memories across all views in the application. Currently, users encounter different UX patterns depending on where they view a memory created through the question flow — the anonymous answer page, the main memory feed, the Question Dashboard ("Sent Requests"), and the Question Responses view all present different information and interactions. This PRD proposes a consistent, intuitive experience with clear attribution, proper edit permissions, and simplified navigation.

## Problem Statement

When a user sends questions to family members and receives answers, those answers become memories that can appear in multiple locations:

1. **Anonymous Answer Page** — Where respondents answer (shows their answers inline)
2. **Memory Feed** — Where answers appear as regular memories with question context
3. **Question Dashboard** — "Sent Requests" shows request status and links to responses
4. **Question Responses View** — Dedicated view for seeing all responses to a question set

Each view currently presents information inconsistently:

- **Respondent identity** varies: Some views show alias → name → "Anonymous", others show alias → email → "Recipient"
- **Edit permissions** are unclear: Users may see edit buttons on others' answers
- **Navigation is fragmented**: "Sent Requests" and "View Responses" are separate concepts but overlap in purpose
- **Question context** presentation differs between views

This inconsistency creates confusion, reduces confidence, and makes the app feel unpolished.

## Goals

1. **Consistent respondent identity** — Display the same respondent name/identifier everywhere
2. **Clear edit permissions** — Never show edit options for another person's answer
3. **Unified navigation** — Combine "Sent Requests" and "View Responses" into one intuitive interface
4. **Predictable question context** — Show question-answer relationship the same way everywhere
5. **Role clarity** — Make it clear whether you're viewing as the asker or as a respondent

---

## User Stories

### Consistent Identity Display

1. As an asker, I want to see each respondent identified the same way everywhere so that I always know whose answer I'm viewing.
2. As a respondent, I want my identity shown consistently across the app so that I'm not confused about how I appear to others.
3. As a user, I want respondent names to fall back gracefully (alias → name → email → "Family Member") so that no one shows as blank or cryptic.

### Edit Permission Clarity

4. As an asker, I should NOT see an Edit button on someone else's answer so that I'm not confused about what I can modify.
5. As a respondent, I want the Edit button only on MY answers so that I understand what belongs to me.
6. As a respondent who hasn't created an account, I want to see my edit window countdown so I know how long I have to make changes.

### Unified Navigation

7. As an asker, I want to see my sent requests and their responses in one unified view so that I don't have to navigate between separate pages.
8. As an asker, I want to expand a request to see all responses inline so that I can quickly review what everyone wrote.
9. As an asker, when I expand the request, I want to see the entire response including images and video (not just text).
10. As an asker, I want to see at a glance which requests have responses and which are still pending so I can follow up if needed.

### Consistent Question Context

10. As a user viewing a question-answer memory, I want the question displayed the same way everywhere so the UI feels cohesive.
11. As a user, I want to understand immediately that an answer was created via a question request so I have full context.

---

## Feature Requirements

### 1. Unified Respondent Identity Display

#### 1.1 Identity Resolution Order

Establish a single identity resolution algorithm used everywhere:

```
1. Alias (from QuestionRequestRecipient) — "Grandma", "Uncle Bob"
2. User's full name (if respondent has account with name set)
3. User's email (if respondent has account, formatted nicely)
4. "Family Member" (fallback if nothing else available)
```

Never show:
- "Anonymous" (confusing — they're not truly anonymous)
- "Recipient" (internal terminology)
- Raw tokens or IDs
- Blank/empty names

#### 1.2 Implementation Locations

Apply this identity resolution in:
- Question Dashboard (Sent Requests)
- Question Responses View
- Memory Feed (for question-answer memories)
- Answer Preview component
- Any notification or email referencing a respondent

#### 1.3 Identity Display Component

Create a reusable `RespondentName` component:
- Props: `recipient: QuestionRequestRecipient` (or relevant data)
- Returns the resolved display name
- Optional: tooltip showing relationship (e.g., "Alias: Grandma")

### 2. Edit Permission Enforcement

#### 2.1 Edit Button Visibility Rules

The Edit button for an answer should ONLY be visible when:
- Viewing user is the respondent who created the answer
- Answer is within the 7-day edit window
- (For anonymous page) The current token matches the answer's token

#### 2.2 Backend Enforcement

API endpoints must verify edit permissions:
- `PUT /questions/answer/{token}` — verify token matches the answer's original token
- Any edit endpoint — verify `userId` matches the answer's creator
- !IMPORTANT! /architect - this may be hard because an anonymous user won't have a `userId`.  Think of alternatives here. Maybe we can create a user, if email isn't associated with a user, and then simply have the create user flow claim this user (by matching the email).
This should allow for re-use of existing memory ownership code.

#### 2.3 Frontend Guard

Add permission check to all edit buttons:
```typescript
// Only show edit if this is the user's own answer
const canShowEdit = computed(() => {
  if (!answer.value?.canEdit) return false;
  // Check if this answer belongs to current user
  return answer.value.isOwnAnswer === true;
});
```

#### 2.4 Clear Messaging

When edit window is closed, show helpful text:
- "Edit window closed" (for own answers past 7 days)
- Never show for others' answers (no edit button, no message)

### 3. Unified Question Management View

#### 3.1 Combined "Question Requests" View

Replace separate "Sent Requests" and "View Responses" with a single unified view:

**View Name:** "Question Requests" (or "Questions I've Asked")

**Layout:**
```
┌─────────────────────────────────────────────────────────────┐
│ Question Requests                                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Christmas Memories 2025                    ▼ Expand     │ │
│ │ Sent Dec 20, 2025 • 4 recipients • 3 responses          │ │
│ ├─────────────────────────────────────────────────────────┤ │
│ │                                                         │ │
│ │ ┌─ Grandma ────────────────────────────────────────┐    │ │
│ │ │ "What's your favorite Christmas tradition?"      │    │ │
│ │ │ → "We always made tamales together..."           │    │ │
│ │ │   📷 📷 🎥                           [View Full]  │    │ │
│ │ └──────────────────────────────────────────────────┘    │ │
│ │                                                         │ │
│ │ ┌─ Uncle Bob ──────────────────────────────────────┐    │ │
│ │ │ "What's your favorite Christmas tradition?"      │    │ │
│ │ │ → "Opening presents at midnight..."              │    │ │
│ │ │   📷                                 [View Full] │    │ │
│ │ └──────────────────────────────────────────────────┘    │ │
│ │                                                         │ │
│ │ ┌─ mom@email.com ──────────────────────────────────┐    │ │
│ │ │ Waiting for response...                          │    │ │
│ │ │                                 [Send Reminder]  │    │ │
│ │ └──────────────────────────────────────────────────┘    │ │
│ │                                                         │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Family Stories Collection                  ▶ Collapsed  │ │
│ │ Sent Jan 5, 2026 • 2 recipients • 0 responses           │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 3.2 Request Card States

**Collapsed (default):**
- Question set name
- Date sent
- Recipient count
- Response count (with visual indicator: badge, progress bar)
- Expand arrow

**Expanded:**
- All questions with their answers from each recipient
- Recipients grouped (one section per recipient)
- Pending recipients shown with "Waiting for response..." and reminder option
- Each answer shows: truncated content, media thumbnails, "View Full" link

#### 3.3 Recipient Status Indicators

Visual indicators for each recipient:
- ✓ Green check — Has responded to all questions
- ⏳ Yellow — Has responded to some questions (partial)
- ○ Gray — No responses yet
- ✕ Deactivated — Link was revoked

#### 3.4 Actions Per Request

- **Expand/Collapse** — Toggle detailed view
- **Copy Link** — Copy a specific recipient's answer link
- **Send Reminder** — For pending recipients
- **Deactivate Link** — Revoke a recipient's access
- **View Full Response** — Navigate to full answer in memory view

### 4. Consistent Question-Answer Display

#### 4.1 Standard Question-Answer Card

Create a unified `QuestionAnswerCard` component used everywhere:

```
┌────────────────────────────────────────────────┐
│ 💬 Grandma answered a question                 │  ← Header with respondent
├────────────────────────────────────────────────┤
│ ┌────────────────────────────────────────────┐ │
│ │ "What's your favorite Christmas memory?"   │ │  ← Question (quoted style)
│ └────────────────────────────────────────────┘ │
│                                                │
│ We always made tamales together on Christmas  │  ← Answer content
│ Eve. My grandmother taught my mom, and now    │
│ we're teaching the kids. The kitchen gets     │
│ so crowded but that's part of the fun...      │
│                                                │
│ December 24, 2025                              │  ← Date
│                                                │
│ ┌────┐ ┌────┐ ┌────┐                          │  ← Media
│ │ 📷 │ │ 📷 │ │ 🎥 │                          │
│ └────┘ └────┘ └────┘                          │
│                                                │
│ ────────────────────────────────              │
│ From: Christmas Memories 2025    [View Set]   │  ← Optional: link to full set
└────────────────────────────────────────────────┘
```

#### 4.2 Usage Locations

Use `QuestionAnswerCard` in:
- Memory Feed (for question-answer memories)
- Question Requests expanded view (simplified version)
- Individual answer detail view
- Respondent's own feed (if they have an account)

#### 4.3 Context Variants

Different contexts may show different elements:
- **Feed:** Full card with "View Set" link
- **Request Expansion:** Compact card with truncated content
- **Answer Detail:** Full card with no "View Set" (already in context)

### 5. Navigation Simplification

#### 5.1 Sidebar/Menu Update

Replace current navigation:

**Before:**
- Sent Requests
- View Responses

**After:**
- Question Requests (unified view)

Or hierarchical:
- Questions
  - Ask Questions (create/send)
  - My Requests (view sent requests + responses)

#### 5.2 Entry Points

Clear paths to the unified view:
1. Main navigation menu
2. "View Responses" link on question-answer memories in feed
3. Notification links ("Grandma answered your question")

#### 5.3 Memory Feed Integration

In the memory feed, question-answer memories should:
- Show the question context prominently
- Link to "View all responses" if part of a multi-recipient request
- Navigate to the unified Question Requests view when clicked

---

## UI/UX Requirements

### Visual Hierarchy

1. **Respondent Name** — Prominent, consistent styling (semi-bold)
2. **Question** — Quoted style, left border accent (brand primary)
3. **Answer** — Normal text, clear and readable
4. **Media** — Compact thumbnails, consistent sizing
5. **Actions** — Subtle, right-aligned, don't compete with content

### Responsive Design

- Mobile: Cards stack vertically, full-width
- Desktop: Optional side-by-side comparison view for multiple responses

### Animation & Feedback

- Smooth expand/collapse for request cards
- Loading states when fetching responses
- Confirmation toasts for actions (reminder sent, link copied)

---

## Technical Considerations

### Frontend Changes

1. **New Components:**
   - `RespondentName.vue` — Unified identity display
   - `QuestionAnswerCard.vue` — Consistent question-answer display
   - `QuestionRequestCard.vue` — Expandable request card for unified view
   - `RecipientStatus.vue` — Status indicator for each recipient

2. **View Updates:**
   - `QuestionDashboardView.vue` — Transform to unified view (or create new)
   - `QuestionResponsesView.vue` — May be removed/merged
   - Memory feed components — Use `QuestionAnswerCard`

3. **Store Updates:**
   - Add computed for `canShowEditButton` with ownership check
   - Normalize respondent identity resolution in store/composable

### Backend Changes

1. **API Updates:**
   - `GET /questions/requests` — Return responses inline with recipients
   - Add `isOwnAnswer` flag to answer responses based on current user
   - Ensure identity resolution fields are always populated

2. **Permission Checks:**
   - Audit all edit endpoints for proper authorization
   - Add explicit ownership check to answer edit endpoints

### Migration Considerations

- Route redirects from old URLs to new unified view
- Preserve any bookmarked links
- Update email notification links to point to unified view

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Edit Error Rate | % of edit attempts on others' answers (should be blocked) | 0% |
| Navigation Efficiency | Clicks to view a specific response from dashboard | ≤ 2 clicks |
| Support Tickets | Confusion-related tickets about question responses | Reduce by 50% |
| Time on Unified View | Engagement with new Question Requests view | Increase from baseline |

---

## Out of Scope (Future Considerations)

- Side-by-side comparison view for multiple responses
- Bulk actions on question requests (remind all, archive all)
- Question request templates/library
- Response reactions or comments
- Export responses as document

---

## Implementation Phases

### Phase 1: Edit Permission Enforcement
- Add `isOwnAnswer` flag to API responses
- Update frontend to hide edit button for others' answers
- Add backend authorization checks
- **No UI changes, just permission fixes**

### Phase 2: Unified Identity Resolution
- Create `RespondentName` component
- Implement identity resolution algorithm
- Update all views to use new component
- **Consistency improvement**

### Phase 3: Unified Question Management View
- Create expandable `QuestionRequestCard` component
- Build new unified "Question Requests" view
- Add inline response display with recipient sections
- **Major navigation simplification**

### Phase 4: Consistent Question-Answer Cards
- Create `QuestionAnswerCard` component
- Update memory feed to use new component
- Ensure consistent styling across all views
- **Visual consistency**

### Phase 5: Navigation Cleanup
- Update sidebar/menu navigation
- Add route redirects
- Update email notification links
- Remove deprecated views
- **Finalization**

---

## Open Questions

1. **Naming:** Is "Question Requests" the best name for the unified view, or should it be "Questions I've Asked", "My Question Sets", or something else?

2. **Default State:** Should request cards be collapsed or expanded by default? Collapsed saves space but requires an extra click.

3. **Full Response View:** When clicking "View Full" on a response, should it open in a modal, navigate to the memory detail page, or expand inline?

4. **Email Display:** If showing email as fallback identity, should it be truncated/masked for privacy (e.g., "m***@email.com")?

---

*Document Version: 1.0*
*Created: 2026-02-07*
*Status: Draft*
