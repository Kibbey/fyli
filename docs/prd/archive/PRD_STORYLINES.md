# Product Requirements Document: Storylines & Navigation Restructure

## Overview

Storylines let users assemble a chronological narrative of memories around a person or place — a child's milestones, a grandparent's life story, a family home's history. Users can create storylines, add existing memories to them, create new memories within a storyline, and invite connections to contribute.

This PRD also covers a prerequisite navigation restructure: replacing the bottom tab bar with a top nav + drawer pattern that scales as fyli adds more features.

## Problem Statement

Busy parents capture memories but lack a way to organize them into meaningful narratives. A stream of memories is useful for capture, but when you want to look back at your daughter's first year or your family's trips to the lake house, you need a curated thread. Without storylines, parents must scroll through their entire memory stream to piece together a story — and they can't invite family members to help fill in the gaps.

Additionally, the current bottom navigation bar (3 fixed items) doesn't scale. Every new feature requires rethinking the nav layout. A drawer-based navigation solves this permanently.

## Note
!IMPORTANT! this is an existing feature. We can extend it or even change it, but the underlying data need to still be avialable to the end user after the migration.  Any data changes must be backwards compatible (but the frontend / api does not have to be).

## Goals

1. Give users a simple way to curate memories into themed narratives about the people and places that matter most
2. Enable family collaboration — invite connections to contribute memories to a shared storyline
3. Establish a scalable navigation pattern that supports ongoing feature growth without layout changes

## User Stories

### Navigation
1. As a user, I want a clean, uncluttered interface so that I can focus on my memories without visual noise
2. As a user, I want to access all features from a single menu so that I always know where to find things
3. As a user, I want to create a new memory with one tap from any screen so that I can capture moments quickly

### Storyline Management
4. As a parent, I want to create a storyline for my child so that I can build a growing narrative of their life
5. As a user, I want to see all my storylines in one place so that I can browse the narratives I'm building
6. As a user, I want to edit a storyline's name and description so that I can refine it over time
7. As a user, I want to delete a storyline I no longer need so that my list stays organized but I don't want the memories to go away (they should still be on the main memory viewing page).

### Adding Memories to Storylines
8. As a user, I want to add an existing memory to a storyline so that I can curate from what I've already captured
9. As a user, I want to create a new memory directly within a storyline so that it's automatically associated
10. As a user, I want to see which storylines a memory belongs to so that I understand its context
11. As a user, I want to remove a memory from a storyline without deleting the memory itself

### Viewing a Storyline
12. As a parent, I want to view all memories in a storyline chronologically so that I can experience the narrative as a timeline of events
13. As a user, I want to scroll through a storyline's memories with the same card experience as the main stream

### Collaboration
14. As a grandparent, I want to be invited to contribute to my grandchild's storyline so that I can add my perspective without being forced to create an account
15. As a user, I want to invite connections to a storyline so that family members can help preserve memories together
16. As a user, I want to see which storylines I created vs. which were shared with me
17. As a user, I want the option to create an account to also have the memories I created based on requests from other users.

## Feature Requirements

### 1. Navigation Restructure

#### 1.1 Top Navigation Bar
- Display fyli logo on the left (links to home/memories)
- Hamburger menu icon on the left (opens drawer)
- Keep "Invite" action button on the right

#### 1.2 Navigation Drawer
- Opens from the left as a slide-over panel with backdrop
- Displays user's name or email at the top
- Navigation items with icons:
  - **Memories** (mdi-home-outline) — main memory stream
  - **Storylines** (mdi-book-outline) — storyline list
  - **Questions** (mdi-comment-question-outline) — questions
  - **Account** (mdi-account-outline) — settings/profile
- Active item highlighted with primary color
- Tapping an item navigates and closes the drawer
- Tapping the backdrop closes the drawer
- Adding future features = adding a line to the drawer item list

#### 1.3 Floating Action Button (FAB)
- Persistent "+" button in the bottom-right corner
- Always visible on authenticated screens
- Tapping opens the create memory flow
- Positioned above safe area inset on notched devices

#### 1.4 Remove Bottom Navigation
- Remove AppBottomNav component entirely
- All navigation moves to the drawer

### 2. Storyline List View

#### 2.1 Route: `/storylines`
- Accessible from the navigation drawer
- One section with two categories:
  - **Your Storylines** — storylines the user created
  - **Shared with You** — storylines others invited the user to
- Each storyline card displays:
  - Storyline name
  - Description (truncated if long)
  - Creator indicator (badge or subtle label on shared storylines)
- Tapping a storyline card navigates to its detail view (with list of memories in cronological order)
- Empty state: friendly message encouraging user to create their first storyline with a CTA button

#### 2.2 Create Storyline
- "Create Storyline" button at the top of the list view
- Opens route `/storylines/new` with a simple form:
  - Name (required, text input)
  - Description (optional, textarea)
  - Save button → creates storyline and navigates to its detail view

### 3. Storyline Detail View

#### 3.1 Route: `/storylines/:id`
- Header shows storyline name and description
- Edit icon (pencil) if user is the creator — navigates to `/storylines/:id/edit`
- Chronological feed of memories in the storyline (reuses existing memory card component)
- Pagination via scroll (same pattern as main memory stream)
- Sort toggle: oldest-first (default, since it's a timeline) or newest-first
- Empty state: "This storyline has no memories yet" with CTA to add one

#### 3.2 Edit Storyline
- Route: `/storylines/:id/edit`
- Pre-populated form with name and description
- Save updates and navigates back to detail view
- Delete option (soft-delete — removes from user's list, not from other followers)

### 4. Adding Memories to Storylines

#### 4.1 From Memory Detail / Memory Card
- Action menu on a memory includes "Add to Storyline" option
- Opens a picker showing all user's active storylines with checkboxes
- Checked = memory is already in that storyline
- Toggle on/off to add or remove
- Saves immediately on toggle (no separate save button)

#### 4.2 From Storyline Detail View
- "Add Memory" button within the storyline detail view
- Two options:
  - **Create New Memory** — opens create memory flow with storyline pre-selected
  - **Add Existing Memory** — opens a searchable/scrollable list of the user's memories to pick from

#### 4.3 From Create Memory Flow
- When creating a new memory, add an optional "Storyline" field
- Shows a dropdown/picker of the user's active storylines
- If navigated from a storyline detail view, pre-selects that storyline
- Supports selecting multiple storylines for a single memory

### 5. Storyline Collaboration

#### 5.1 Invite to Storyline
- On the storyline detail view (creator only), show an "Invite" button
- Opens a view showing the user's connections with checkboxes
- Select one or more connections to invite
- Invited users receive a notification
- Invited users see the storyline in their "Shared with You" section

#### 5.2 Shared Storyline Behavior
- Invited users can view all memories in the storyline
- Invited users can add their own memories to the storyline
- Invited users can only remove memories they personally added
- Invited users can customize the storyline name/description for their own view (backend supports this via TimelineUser)

#### 5.3 Unfollow
- Invited users can unfollow a storyline (soft-delete their access)
- Removes it from their list; does not affect other followers or the storyline itself

## Data Model

The backend entities already exist. Summary for frontend reference:

### Timeline (backend entity name)
```
Timeline {
  TimelineId: int (PK)
  Name: string (max 200)
  Description: string (max 4000)
  UserId: int (FK - creator)
  CreatedAt: DateTime
  UpdatedAt: DateTime
}
```

### TimelineUser (follower/access record)
```
TimelineUser {
  TimelineUserId: int (PK)
  TimelineId: int (FK)
  UserId: int (FK)
  Name: string (max 200, user's custom name)
  Description: string (max 4000, user's custom description)
  Active: bool (soft delete flag)
  CreatedAt: DateTime
  UpdatedAt: DateTime
}
```

### TimelineDrop (memory-storyline association)
```
TimelineDrop {
  TimelineId: int (PK part 1)
  DropId: int (PK part 2)
  UserId: int (FK - who added it)
  CreatedAt: DateTime
}
```

### API Response: TimelineModel
```
TimelineModel {
  Id: int
  Name: string
  Description: string
  Active: bool
  Following: bool
  Creator: bool
  Selected: bool (context-dependent: is a specific drop in this storyline)
}
```

## API Endpoints (Backend — Already Implemented)

| Method | Route | Purpose |
|--------|-------|---------|
| GET | `/api/timelines` | List all storylines user has access to |
| GET | `/api/timelines/{id}` | Get single storyline |
| POST | `/api/timelines` | Create storyline (body: `{ name, description }`) |
| PUT | `/api/timelines/{id}` | Update storyline (body: `{ name, description }`) |
| DELETE | `/api/timelines/{id}` | Soft-delete (unfollow) storyline |
| POST | `/api/timelines/{id}/invite` | Invite users (body: `{ ids: int[] }`) |
| GET | `/api/timelines/{id}/invited` | Get invited users |
| GET | `/api/timelines/drops/{dropId}` | Get storylines for a memory (with Selected flag) |
| POST | `/api/timelines/drops/{dropId}/timelines/{timelineId}` | Add memory to storyline |
| DELETE | `/api/timelines/drops/{dropId}/timelines/{timelineId}` | Remove memory from storyline |
| GET | `/api/drops/timelines/{timelineId}` | Get memories in storyline (query: `skip`, `ascending`) |

## UI/UX Requirements

### Visual Design
- Follow existing fyli style guide (Bootstrap 5, `--fyli-primary: #56c596`, MDI icons)
- Storyline cards should feel consistent with memory cards in spacing and typography
- Drawer should use a semi-transparent backdrop overlay
- FAB should use the primary color with a white "+" icon

### Navigation Drawer
- Slide in from the left, 280px wide (or 80% of screen, whichever is smaller)
- Transition: 200-300ms ease-in-out
- Backdrop: semi-transparent dark overlay
- Close on backdrop tap, item tap, or swipe left
- Items stacked vertically with icon + label

### Storyline List
- Section headers ("Your Storylines", "Shared with You") in muted text
- Cards with name prominent, description secondary
- Shared storylines show contributor name subtly

### Storyline Detail
- Name as page title
- Description below title in muted text
- Memory cards in same layout as main stream
- Default sort: oldest first (chronological storytelling)

### Floating Action Button
- 56px diameter circle
- Primary color background, white `mdi-plus` icon
- Bottom-right corner, 16px margin from edges
- Elevated with subtle shadow
- z-index above content but below drawer overlay

## Technical Considerations

### Frontend
- Create `src/services/timelineApi.ts` mirroring backend endpoints
- Storyline detail view should reuse the existing `MemoryCard` component
- Drawer state can be managed with a simple reactive ref (no need for Pinia store)
- FAB component should be part of `AppLayout.vue`
- Pagination for storyline memories uses the same skip-based pattern as the main stream

### Backend
- All endpoints are already implemented and tested (9 test cases in TimelineServiceTest)
- No backend changes required for this PRD
- Authorization is handled: users only see storylines they created or were invited to

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Storyline Adoption | % of active users who create at least one storyline | 30% within 60 days |
| Memories per Storyline | Average number of memories added to a storyline | 5+ |
| Collaboration Rate | % of storylines with at least one invited contributor | 20% |
| Contributor Additions | % of storyline memories added by someone other than creator | 15% |

## Out of Scope (Future Considerations)

- Timeline-specific question prompts (backend supports this, UI deferred)
- Cover photo or avatar for storylines
- Storyline templates (e.g., "Baby's First Year" with pre-set prompts)
- Public/shareable storyline links (like memory share links)
- Storyline search or filtering
- Reordering memories within a storyline (currently chronological only)
- Desktop-optimized persistent sidebar (drawer works for now; sidebar can come later)

## Implementation Phases

### Phase 1: Navigation Restructure
- Replace bottom nav with top nav bar (hamburger + logo + invite)
- Build navigation drawer component with current items (Memories, Questions, Account)
- Add floating action button for memory creation
- Remove AppBottomNav component

### Phase 2: Storyline Foundation
- Create `timelineApi.ts` service
- Storyline list view (`/storylines`) with create button
- Create storyline form (`/storylines/new`)
- Edit storyline form (`/storylines/:id/edit`)
- Add "Storylines" to navigation drawer
- Delete/unfollow storyline

### Phase 3: Storyline Detail & Memory Association
- Storyline detail view (`/storylines/:id`) with memory feed
- "Add to Storyline" picker on memory cards/detail
- "Add Memory" from storyline detail (new + existing)
- Storyline field in create/edit memory flow

### Phase 4: Collaboration
- Invite connections to storyline
- "Shared with You" section in storyline list
- Notification for storyline invitations
- Unfollow storyline

## Open Questions

1. Should the FAB have additional actions beyond "Create Memory" in the future (e.g., quick-add to storyline, ask a question)? If so, it could expand into a speed-dial menu later.
2. When adding an existing memory to a storyline, should the picker show all memories or only recent ones with a search?
3. Should storyline invitations go through the existing notification system, or should we also send email notifications?

---

*Document Version: 1.0*
*Created: 2025-02-09*
*Status: Draft*
