# Product Requirements Document: Inline Collapsible Comments

## Overview

Comments on memories currently require navigating to a separate detail page. This creates friction — users lose their place in the stream and must navigate back after commenting. Comments should expand inline below each memory card in the stream, with the ability to collapse them, and display media (images and videos) with the same visual treatment as the main memory.

## Problem Statement

When a parent sees a memory in their stream and wants to leave a comment or read others' reactions, they must click through to a new page. This breaks the browsing flow and discourages engagement. For families sharing memories, quick reactions and comments are how people stay connected — the current friction reduces those meaningful interactions.

## Goals

1. Let users comment without leaving the stream, keeping them present in the browsing experience
2. Give comments a polished visual treatment that matches the memory itself, so shared photos and videos in comments feel like part of the conversation
3. Let users collapse comments to keep the stream clean when they want to scroll

## User Stories

### Viewing Comments
1. As a user, I want to expand comments directly below a memory so that I can read reactions without losing my place in the stream
2. As a user, I want to collapse comments so that I can keep my stream view clean and focused
3. As a user, I want to see who commented and when so that conversations feel personal and timely

### Commenting
4. As a user, I want to post a comment inline so that sharing a quick thought feels effortless
5. As a user, I want to delete my own comments so that I can fix mistakes

### Media in Comments
6. As a user, I want images in comments to display in a grid with click-to-expand so that they look as good as the images in the memory itself
7. As a user, I want videos in comments to show with a thumbnail and play controls so that they match the memory's video treatment

## Feature Requirements

### 1. Collapsible Comment Section on MemoryCard

#### 1.1 Toggle Button
- The existing comment count button on MemoryCard becomes a toggle that expands/collapses comments inline
- Clicking it no longer navigates to `/memory/:id` — it expands below the card
- Show the comment count (e.g. "3" with a comment icon)
- Visual indicator of expanded/collapsed state (chevron or icon rotation)

#### 1.2 Collapse Behavior
- Comments start collapsed by default
- Only one memory's comments should be expanded at a time (optional — discuss with team; could allow multiple)
- Expanding comments fetches them if not already loaded (the `Drop` object already includes `comments` in the stream response, so no extra API call needed for initial load)
- Collapsing preserves any loaded comments in memory (no re-fetch on re-expand)

#### 1.3 Comment List Display
- Show below the card content, inside the same card container
- Each comment shows:
  - Commenter name (bold) and relative timestamp (e.g. "2 hours ago")
  - Comment text
  - Images displayed via `PhotoGrid` component (same as memory) for visual consistency
  - Videos displayed with poster thumbnail and controls (same as memory)
  - Delete button (trash icon) for own comments only (`!comment.foreign`)

#### 1.4 Comment Form
- Appears at the bottom of the expanded comment section
- Simple single-line input with a "Post" button (matches current `CommentForm` pattern)
- New comments appear immediately at the bottom of the list after posting

### 2. Visual Treatment of Comment Media

#### 2.1 Images in Comments
- Use the same `PhotoGrid` component used in the memory card
- Images should be the same max-height and styling as memory images
- Click-to-expand via `ClickableImage` (already in PhotoGrid)

#### 2.2 Videos in Comments
- Same `<video>` element with `:poster` thumbnail and `controls`
- Same `img-fluid rounded` classes as memory videos
- Same max-width behavior

### 3. Comment Styling

#### 3.1 Individual Comment
- Light background (`bg-light`) with rounded corners
- Small padding
- Subtle separation between comments (margin-bottom)
- Commenter name in bold, timestamp in muted small text
- Comment text at normal readable size

#### 3.2 Empty State
- When expanded with no comments: "No comments yet." in muted text
- Comment form still shows so user can be first to comment

### 4. Navigation Changes

#### 4.1 MemoryCard Comment Button
- Changes from `RouterLink` to a `<button>` that toggles expansion
- Still shows comment count with comment icon

#### 4.2 Memory Detail View
- Remains accessible (users may still navigate there from other entry points like share links or direct URLs)
- Comments on the detail view continue to work as they do today
- Consider adding a link from the card (e.g. the date or "View details") for users who want the full detail page

## UI/UX Requirements

### Comment Section Layout
```
┌─────────────────────────────────┐
│ Memory Card Content             │
│ (text, photos, videos)          │
│                                 │
│ [💬 3 ▾]                        │  ← Toggle button
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ Jane Smith · 2 hours ago  🗑│ │  ← Comment with delete
│ │ This is so sweet!           │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ John Doe · 1 hour ago      │ │
│ │ Love this memory!           │ │
│ │ ┌─────┐ ┌─────┐            │ │  ← PhotoGrid in comment
│ │ │ img │ │ img │            │ │
│ │ └─────┘ └─────┘            │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Add a comment...        ] [Post]│
└─────────────────────────────────┘
```

### Interactions
- Toggle is instant (no loading spinner for initial data since comments come with the stream response)
- Smooth expand/collapse transition (optional, CSS transition on max-height)
- After posting a comment, input clears and new comment appears at bottom
- Delete shows the ConfirmModal before removing

### Responsive
- Full width on mobile
- Comment media scales down on smaller screens (same as memory media)

## Technical Considerations

### Data
- Comments are already included in the `Drop` object returned by the stream API (`memory.comments`)
- No additional API calls needed to display comments on expand
- `createComment` and `deleteComment` APIs already exist
- Comment media URLs (`imageLinks`, `movieLinks`) are already populated by the backend

### Component Changes
- `MemoryCard.vue` — add collapsible section, import `CommentList`
- `CommentList.vue` — update styling to use `PhotoGrid` for images and match memory video treatment; add relative timestamps
- `CommentForm.vue` — no changes needed
- Remove `RouterLink` to detail page from comment button (add a separate subtle "View details" link if needed)

### State
- Expanded/collapsed state is local to each `MemoryCard` instance (no store needed)
- Comment list state is local (already managed by `CommentList` via ref)

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Comment Engagement | % of memory views that result in a comment | Increase over current |
| Comments Per Session | Average comments posted per user session | Track baseline then improve |

## Out of Scope (Future Considerations)

- File/media upload in comment form (currently comments are text-only in v2; media upload can be added later)
- Edit existing comments
- Thanks/reaction system (exists in old frontend, can be added separately)
- Real-time comment updates (WebSocket push)
- Comment pagination (unlikely needed — most memories have few comments)
- @mentions or notifications

## Implementation Phases

### Phase 1: Inline Collapsible Comments
- Convert comment button from RouterLink to toggle
- Add collapsible comment section to MemoryCard
- Update CommentList styling (PhotoGrid for images, matched video treatment, relative timestamps)
- Add a "View details" link for accessing the detail page

### Phase 2: Polish
- Delete confirmation via ConfirmModal
- Smooth expand/collapse CSS transition
- Visual review with designer skill

## Open Questions

1. Should multiple memories be expandable at once, or should expanding one collapse others? (Recommendation: allow multiple — simpler and less surprising)
2. Should there be a "View details" link on the card for accessing the full detail page? If so, where? (Recommendation: make the date a link to the detail page)

---

*Document Version: 1.0*
*Created: 2026-02-01*
*Status: Draft*
