# Product Requirements Document: Memory Sharing at Creation

## Overview

Add a sharing step to the memory creation flow that lets users choose who sees their memory before saving it. The default is to share with all connections, with the ability to select specific people or keep it private with a two-step creation wizard inspired by the question-sharing UX.

## Problem Statement

When a busy parent captures a meaningful moment — a child's first bike ride, a holiday dinner — they want specific people to see it immediately. Today, sharing happens after creation as a separate step, which adds friction and means memories often go unshared. Parents want to capture *and* share in one fluid motion, the same way they already do with questions.

## Goals

1. **Reduce sharing friction** — Share a memory with the right people in one creation flow, not as an afterthought
2. **Smart defaults** — Default to sharing with everyone so memories are shared by default, not hoarded
3. **Familiar UX** — Re-use the proven question-sharing pattern so users don't have to learn a new interaction
4. **No new concepts** — Users select everyone, individual people, or no one.  The data schema remains unchanged, this change is limited to frontend and possibly a new api endpoint but stores data the same way.  Use groups in this way - "everyone" is a single group. Each user is their own "group".  This preserves the current data architecture.

---

## User Stories

### Sharing During Creation

1. As a busy parent, I want to share a memory with all my connections by default so that the people I care about see my moments without extra steps.
2. As a user, I want to choose specific people to share a memory with so that I can control who sees sensitive or personal moments.
3. As a user, I want a "Select All" option so that I can quickly share with everyone after deselecting some people.
4. As a user, I want to keep a memory private ("Only me") so that I can capture personal reflections without sharing.

### Recipient List

5. As a user, I want to see all the people I've previously shared with (via invites, questions, or timelines) so that I have a complete list of people to choose from.
6. As a user, I want to see people's names (not email addresses) in the sharing list so that I can quickly identify who I'm sharing with.

---

## Feature Requirements

### 1. Two-Step Creation Flow

#### 1.1 Step 1: Create Memory (unchanged)
- Text input ("What happened?")
- Date picker (defaults to today)
- Photo & video upload
- Storyline selection (if storylines exist)
- "Next" button advances to Step 2

#### 1.2 Step 2: Choose Who to Share With
- Header: "Share this memory"
- Default state: "Everyone" is selected (all connections)
- Three sharing modes:
  - **Everyone** — Share with all connections (default, pre-selected)
  - **Specific people** — Pick individual recipients from a list
  - **Only me** — Keep private, no sharing
- "Save Memory" button creates the drop and shares accordingly
- "Back" button returns to Step 1 with all content preserved

### 2. Sharing Mode: Everyone

#### 2.1 Default Behavior
- When the user reaches Step 2, "Everyone" is pre-selected
- A summary label shows: "Sharing with all X connections"
- No further interaction needed — user can immediately tap "Save Memory"

### 3. Sharing Mode: Specific People

#### 3.1 People List
- When user selects "Specific people," a scrollable checkbox list appears
- List contains all people the user has previously shared with across:
  - Connection invites (accepted)
  - Question requests (sent to)
  - Timeline sharing
- Each row shows: checkbox + person's display name
- List is sorted alphabetically by display name

#### 3.2 Select All / Deselect All
- A "Select All" checkbox at the top of the list
- Checking it selects every person
- Unchecking it deselects everyone
- If all individuals are manually checked, "Select All" auto-checks
- If any individual is unchecked, "Select All" unchecks

#### 3.3 Validation
- If no one is selected, prompt user to either select people or switch to "Only me"

### 4. Sharing Mode: Only Me

#### 4.1 Private Memory
- No sharing occurs — drop is created with no group/tag associations
- Same as current behavior when no group is selected

### 5. Backend: Reuse Existing Infrastructure

#### 5.1 "Everyone" Shares via All Connections Group
- Uses the existing "All Connections" `UserTag` group (auto-created by `GroupService`)
- Drop is created with `tagIds: [allConnectionsGroupId]`
- Existing notification flow triggers automatically

#### 5.2 "Specific People" Sharing
- Creates a new group (`UserTag`) on backend on call for to get sharing recipients (i.e. 6.1 below) for each possible user to be shared with if one does not already exist.
- Drop is created with `tagIds: [user_1_user_tag, user_2_user_tag]`
- Group is not visible in any group management UI — it's a backend implementation detail
- Existing notification flow triggers for the selected users

#### 5.3 "Only Me"
- Drop is created with no `tagIds`
- No notifications sent

### 6. New API Endpoints

#### 6.1 Get Sharing Recipients
```
GET /api/connections/sharing-recipients
```
Returns all people the current user has shared with, deduplicated across invites, questions, and timelines.

**Side effect:** For each connection returned, the backend ensures a per-user `UserTag` exists (creates one if missing) with a single `TagViewer` for that user. This is idempotent.

**Response:**
```json
[
  {
    "userId": 42,
    "userTagId": 17,
    "displayName": "Mom",
    "email": "mom@email.com"
  }
]
```

The frontend passes `userTagId` values directly as `tagIds` when creating the drop.

#### 6.2 Get All Connections Group ID
The frontend needs to know the "All Connections" group ID to pass as `tagIds` when sharing with everyone. This can be returned from the existing `GET /api/groups` endpoint (which already returns all groups including "All Connections").

Update backend to only return "All Connections" and suppress legacy groups (but not delete them).

---

## UI/UX Requirements

### Step Indicator
- Visual step indicator at top: **Write** → **Share**
- Current step highlighted, matching the question wizard pattern

### Step 1: Memory Form
- Same fields as today (text, date, photos/videos, storylines)
- "Next" button replaces "Save Memory" button
- "Cancel" button still returns to previous page

### Step 2: Share Selection
- Clean card-based layout for the three sharing modes
- **Everyone** shown as a radio-style option with connection count
- **Specific people** shown as a radio-style option that expands to show the people list when selected
- **Only me** shown as a radio-style option
- People list uses checkboxes with "Select All" at top, consistent with storyline selection pattern
- "Save Memory" primary button at bottom
- "Back" secondary button to return to Step 1

### Mobile
- People list scrollable within a max-height container
- Touch-friendly checkbox targets (full row tappable)

---

## Technical Considerations

### Frontend
- Refactor `CreateMemoryView.vue` from a single form to a two-step wizard
- Remove the current conditional group dropdown (`v-if="groups.length"`)
- New composable or inline state for managing sharing selection
- Fetch sharing recipients on Step 2 mount (lazy load)
- Preserve Step 1 form state when navigating back from Step 2

### Backend
- New endpoint `GET /api/connections/sharing-recipients` in `ConnectionController`
  - Query `UserUser` table for accepted connections
  - Query `QuestionRequestRecipient` for question recipients who have accounts
  - Query `TimelineUser` for timeline sharing recipients
  - Deduplicate by `UserId`, return display names and `userTagId`
  - Side effect: ensure a per-user `UserTag` (with single `TagViewer`) exists for each connection returned
- `GET /api/groups` updated globally: only returns "All Connections" group. Legacy groups are suppressed (not deleted)
- Per-user groups are also suppressed from `GET /api/groups` — they are a backend implementation detail only
- No schema changes — reuse `UserTag`, `TagViewer`, `TagDrop`, `UserUser` tables

### Backwards Compatibility
- Existing memories are unaffected
- The `createDrop` API already accepts `tagIds` — no API contract changes needed
- Group-based sharing and notification infrastructure remains unchanged

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Sharing Rate | % of new memories shared with at least one person | > 70% |
| Default Acceptance | % of shares that use "Everyone" (no override) | > 50% |
| Specific People Usage | % of shares using individual selection | > 20% |

---

## Out of Scope (Future Considerations)

- Sharing with people not yet connected (email invites during creation)
- Named/saved sharing groups in the UI
- Sharing after creation (edit flow)
- Notification preferences per share
- Share with specific storyline followers

---

## Implementation Phases

### Phase 1: Two-Step Wizard + Everyone/Only Me
- Refactor `CreateMemoryView.vue` into two-step flow
- Step 2 with "Everyone" and "Only me" options
- Use "All Connections" group for "Everyone"
- Remove old group dropdown

### Phase 2: Specific People Selection
- New `GET /api/connections/sharing-recipients` endpoint
- People list with checkboxes and "Select All"
- Ad-hoc group creation for specific people sharing
- Full notification flow for selected recipients

---

## Resolved Decisions

1. **Display name fallback:** Show display name in the people list. If name is missing, show email instead.
2. **Zero connections:** Skip Step 2 entirely — memory is auto-private.
3. **Pre-selection:** No memory of previous selections. "Specific people" mode starts with no one selected.
4. **Sharing recipients response:** Includes `userTagId` per person. Frontend passes `userTagId` values directly as `tagIds` to `createDrop`.
5. **Groups API change:** `GET /api/groups` globally returns only "All Connections." Legacy groups and per-user groups are suppressed (not deleted). Old frontend is being replaced.
6. **Per-user group visibility:** Per-user groups are backend implementation details only — never exposed in any group management UI or API.

---

*Document Version: 1.0*
*Created: 2026-02-11*
*Status: Draft*
