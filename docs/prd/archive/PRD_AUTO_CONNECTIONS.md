# Product Requirements Document: Auto-Connections & Connections Page

## Overview

Today, connections are only created through explicit email invitations. But users already interact through sharing memories, asking questions, contributing to storylines, and viewing share links — all without becoming "connected." This feature automatically creates connections whenever two users interact through any sharing action, and adds a Connections page to the navigation so users can see and manage the people in their circle.

## Problem Statement

Busy parents share memories, ask questions, and invite family to storylines — but unless they went through the formal invite flow, those people aren't "connections." This means:

- A grandparent who received a share link and signed up can't see future "Everyone" posts
- A family member who answered a question isn't visible in the sharer's network
- Users have no way to see who they're connected with or manage those relationships
- The invite flow is the only path to connection, creating unnecessary friction

The result: meaningful family interactions happen but don't build lasting connections on the platform.

## Goals

1. **Zero-friction connections** — any sharing interaction between two logged-in users automatically connects them
2. **Visibility** — users can see all their connections from the main navigation
3. **Control** — users can easily disconnect from anyone, especially accidental share link viewers
4. **Simplicity** — no approval workflows, no connection tiers, no complexity

## User Stories

### Auto-Connection
1. As a user, I want people I share memories with to automatically become connections so that they can see my future posts without me re-inviting them
2. As a user, I want someone who views my share link (while logged in) to become a connection so that we can continue sharing naturally
3. As a user, I want people I ask questions to (or who ask me questions) to become connections so that our relationship is recognized
4. As a user, I want people I invite to a storyline (or who invite me) to become connections so that we can collaborate more easily

### Connections Page
5. As a user, I want to see a list of all my connections from the navigation so that I know who's in my circle
6. As a user, I want to quickly disconnect from someone so that I have full control over who sees my content
7. As a user, I want to rename a connection so that I see familiar names like "Grandma" instead of formal names
8. As a user, I want to invite new connections from the connections page so that the invite flow is easy to find

## Feature Requirements

### 1. Auto-Connection Triggers

Every sharing interaction between two logged-in users should create a bidirectional connection (UserUser records) if one doesn't already exist. The triggers are:

#### 1.1 Memory Share Link Viewed (NEW)
- When a logged-in user views a memory via a share link (`/s/{token}`), auto-connect the viewer with the memory creator
- Only triggers for authenticated users — anonymous viewers are not connected
- Backend: After resolving the share link token, check if a UserUser relationship exists; if not, create one

#### 1.2 Question Asked/Answered (ALREADY HAPPENS)
- When a user asks a connection a question via the invite flow, the ShareRequest confirmation already creates UserUser records
- **No backend change needed** — verify this path works correctly

#### 1.3 Storyline Invite Accepted (ALREADY HAPPENS)
- When a user accepts a storyline invitation, the ShareRequest confirmation already creates UserUser records
- **No backend change needed** — verify this path works correctly

#### 1.4 Connection Invite Accepted (ALREADY HAPPENS)
- The existing invite flow already creates UserUser records
- **No change needed**

#### 1.5 Memory Shared with Specific Person (VERIFY)
- When sharing a memory with "Specific people" in the creation wizard, verify that recipients are already connections
- If somehow a memory is shared with a non-connection (edge case), auto-connect them

### 2. Connections Page

#### 2.1 Navigation Entry
- Replace "Invite" nav item with "Connections" in the app drawer
- Icon: `mdi-account-group` (people group icon)
- Route: `/connections`

#### 2.2 Connections List
- Display all active connections sorted alphabetically by display name
- Each connection row shows:
  - Avatar placeholder (first letter of name, colored circle)
  - Display name (custom name if set, otherwise their profile name)
  - Email
  - "Disconnect" action (subtle, not prominent — available via swipe or icon button)
  - "Rename" action (edit icon to change display name)
- Empty state: "No connections yet. Invite someone to start sharing memories together." with invite button

#### 2.3 Invite Action
- "Invite" button at the top of the connections page (primary action)
- Opens the existing invite flow (email input + send)
- This replaces the standalone `/invite` page — the invite functionality moves into the connections context

#### 2.4 Disconnect Flow
- Tapping disconnect shows a confirmation: "Disconnect from {name}? They won't see your future memories shared with Everyone, and you won't see theirs."
- On confirm: removes UserUser records and TagViewer associations (existing `RemoveConnection` backend method)
- !IMPORTANT! Disconnect must be easy and fast — this is critical for the share-link auto-connection feature. Users need confidence that accidental connections can be removed instantly.
  - **Solution 1 (Recommended):** Each connection row has a visible icon button (e.g., `mdi-close-circle-outline`) that triggers the confirmation dialog. One tap to reveal, one tap to confirm.
  - **Solution 2:** Swipe-to-disconnect on mobile with a confirmation step. Desktop shows the icon on hover.

#### 2.5 Rename Flow
- Tapping the edit/rename icon opens an inline text field or small modal
- User types a custom display name and saves
- Uses existing `UpdateName` backend method on SharingService

!IMPORTANT! Connection needs to be bi-derectional.  Make sure that data is reflected that way.  The UserUser table requires two entries for every connection (owner and reader).

### 3. Auto-Connection Behavior

#### 3.1 All Connections Group
- Auto-connections are added to the "All Connections" group, same as invited connections
- This means auto-connections see content shared with "Everyone"
- **Rationale:** If someone interacted with you through sharing, they should be a full connection. The disconnect option provides the escape hatch.

#### 3.2 Idempotency
- If a connection already exists, auto-connection triggers should be no-ops
- Use existing `EnsureConnectionAsync` method which handles this correctly

#### 3.3 No Notification for Auto-Connection
- Do NOT send email notifications when auto-connections are created
- The sharing action itself (viewing memory, receiving question) is the notification
- Connection creation is a quiet, behind-the-scenes enhancement

## Data Model

### No New Entities Required

The existing `UserUser` and `ShareRequest` tables handle all connection data. Auto-connections use the same `UserUser` records as invited connections.

### Existing Entities Used
```
UserUser {
  OwnerUserId: int        // The user who "owns" this view
  ReaderUserId: int       // The connected user
  ReaderName: string      // Custom display name
  SendNotificationEmail: bool
  Archive: bool           // Soft delete
}
```

## UI/UX Requirements

### Connections Page Layout
- Page title: "Connections"
- Invite button: top-right, primary style (`btn-primary`)
- Connection list: card-based or simple list, each row with avatar + name + actions
- Search/filter: not needed for V1 (most users will have <50 connections)
- Responsive: single column on mobile, same layout on desktop

### Disconnect Confirmation Modal
- Title: "Disconnect?"
- Body: "Disconnect from {name}? They won't see your future memories shared with Everyone, and you won't see theirs."
- Actions: "Cancel" (secondary) | "Disconnect" (danger/red)

### Rename Inline Edit
- Clicking rename replaces the name text with an input field
- Save on Enter or blur, cancel on Escape
- Placeholder: original profile name

### Empty State
- Friendly illustration or icon
- "No connections yet"
- "Invite family and friends to start sharing memories together"
- Primary "Invite" button

### Navigation Update
- Drawer item changes from "Invite" to "Connections"
- Icon changes from `mdi-account-plus` to `mdi-account-group`
- The `/invite` route should redirect to `/connections`
- The `/invite/:token` route (accepting invitations) remains unchanged

## Technical Considerations

### Share Link Auto-Connection
- The `MemoryShareLinkService` or the share link view endpoint needs to call `EnsureConnectionAsync` when the viewer is authenticated
- Must determine the memory creator's userId from the DropId associated with the share link token
- Should NOT block the share link viewing experience — auto-connect asynchronously or after rendering

### Backend API Endpoints

#### Existing (reuse)
- `GET /api/connections/sharing-recipients` — returns all connections (used for sharing UI, reuse for connections list)
- `DELETE /api/users/connections/{userId}` — remove connection (RemoveConnection)
- `PUT /api/users/connections/{userId}/name` — rename connection (UpdateName)
- `POST /api/users/shareRequest` — send invite

#### May Need (verify/create)
- `GET /api/connections` — dedicated endpoint returning connection list with display names, if `sharing-recipients` doesn't return enough data (e.g., missing custom names)

### Frontend Route Changes
- Add `/connections` route → `ConnectionsView.vue`
- Redirect `/invite` → `/connections`
- Keep `/invite/:token` as-is (public acceptance flow)

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Auto-connections created | Number of connections created via sharing (not invite) | Track growth |
| Connections page visits | Users viewing their connections list | Weekly active |
| Disconnect rate | % of auto-connections disconnected within 24 hours | <10% (validates auto-connect isn't annoying) |
| Invite conversion from connections page | Invites sent from connections page vs. old invite page | Equal or higher |

## Out of Scope (Future Considerations)

- Connection suggestions / "People you may know"
- Connection tiers or permission levels (trusted vs. casual)
- Mutual connection visibility ("You both know Alice")
- SMS-based invitations
- Blocking (vs. disconnecting)
- Email notification preferences per connection (exists in backend, not in V1 UI)
- Group management UI (creating named groups, assigning connections to groups)

## Implementation Phases

### Phase 1: Connections Page
- Create `ConnectionsView.vue` with connection list, disconnect, and rename
- Move invite functionality into connections page
- Update navigation drawer (Invite → Connections)
- Add redirect from `/invite` to `/connections`
- Backend: verify `GET /api/connections` endpoint returns needed data
- Tests: component tests, API service tests

### Phase 2: Auto-Connection on Share Link View
- Backend: add `EnsureConnectionAsync` call when authenticated user views a share link
- Frontend: no changes needed (connection happens server-side)
- Tests: backend integration test for auto-connection

### Phase 3: Verify All Sharing Paths
- Audit all sharing triggers (questions, storylines, memory sharing) to confirm connections are created
- Fix any gaps found
- Tests: end-to-end verification of each trigger

## Open Questions

1. Should the connections page show when the connection was created (e.g., "Connected since Jan 2026")?
  Answer: no
2. Should we show a subtle toast when an auto-connection is created (e.g., "You're now connected with Grandma") or keep it silent?
  Answer: yes
3. Should disconnecting also remove existing shared content access, or only prevent future sharing?
  Answer: remove content access

---

*Document Version: 1.0*
*Created: 2026-02-14*
*Status: Draft*
