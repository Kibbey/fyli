# Product Requirements Document: MVP Core — Capture & Share

## Overview

This is the first PRD in a series that rebuilds Fyli from scratch. It defines the minimum product that delivers on the core promise: **a parent can capture a meaningful moment and share it with the people who matter, in under 60 seconds.** Everything else — storylines, albums, questions, groups — comes later. This PRD ships the core loop and nothing more.

## Problem Statement

Busy parents experience countless meaningful moments — a child's first bike ride, a funny thing they said at dinner, a quiet Sunday morning. These moments disappear. Social media feels too public. Notes apps are disorganized graveyards. Photo libraries are unsearchable chaos. There is no simple, private place to capture a moment with context and share it only with the people who should see it.

## Goals

1. **Prove the core loop works** — capture a memory and share it privately in under 60 seconds
2. **Drive organic growth** — shareable links let recipients experience the product before signing up
3. **Validate retention** — do users come back to create a second, third, tenth memory?

## Scope

### In Scope

- Account creation & authentication
- Memory creation (text + photos + videos)
- Memory stream (browsing your own + shared memories)
- Comments on memories
- Shareable links (primary sharing mechanism)
- Email invitations (secondary)
- Minimal onboarding (sign up → first memory → first share)

### Explicitly Out of Scope

- Groups / per-group visibility (binary: private or shared with all connections)
- Reactions / hearts / thanks
- Storylines / timelines
- Albums
- Questions & prompts
- Notifications activity feed
- Filters (by person, date, year, look-back)
- Subscription / premium plans (free-only for now)
- Relationship selection during onboarding

---

## User Stories

### Account & Authentication

1. As a new user, I want to create an account with my email so that I can start capturing memories.
2. As a returning user, I want to log in with a magic link (passwordless) so that I don't need to remember a password.
3. As a user, I want to set my display name so that my connections see a familiar name.

### Memory Creation

4. As a busy parent, I want to create a memory with a description and date so that I can preserve a moment before it fades.
5. As a user, I want to attach one or more photos to a memory so that I can pair context with images.
6. As a user, I want to attach a video to a memory so that I can capture moments that photos can't.
7. As a user, I want to set a memory as private or shared so that I control who sees it.

### Memory Stream

8. As a user, I want to see all my memories in reverse chronological order so that recent moments are at the top.
9. As a user, I want to see memories shared with me by connections so that I stay connected with family.
10. As a user, I want to edit or delete a memory I created so that I can fix mistakes or remove content.

### Sharing via Links

11. As a parent, I want to generate a shareable link for a memory so that I can text it to grandma without her needing an account.
12. As a link recipient, I want to view a shared memory (text + photos + video) without creating an account so that I can see the moment immediately.
13. As a link recipient, I want to be prompted to create an account after viewing a shared memory so that I can see future memories and share my own.

### Sharing via Email Invitations

14. As a user, I want to invite a family member by email so that they can create an account and see my shared memories.
15. As an invited user, I want to click a link in the invitation email and land on a sign-up page so that joining is effortless.

### Comments

16. As a connection, I want to comment on a shared memory so that I can add context, ask questions, or share a reaction.
17. As a memory creator, I want to see comments on my memories so that I feel connected to my family.
18. As a commenter, I want to attach a photo to my comment so that I can share a related image (e.g., "Here's one from the same day").
19. As a user, I want to edit or delete my own comments so that I can fix mistakes.

### Onboarding

20. As a new user, I want a guided flow that gets me to create my first memory in under 2 minutes so that I immediately experience the product's value.
21. As a new user who just created my first memory, I want to be prompted to share it via link or email so that I complete the core loop.

---

## Feature Requirements

### 1. Account & Authentication

#### 1.1 Registration
- Email + display name only (no password)
- Send magic link to verify email and log in
- Backend: leverage existing `UserController.Register` and `UserController.Token` endpoints

#### 1.2 Login
- Passwordless magic link via email
- Token-based session (existing JWT infrastructure)
- Backend: `POST /api/users/token` → `POST /api/users/login`

#### 1.3 Profile
- Set/update display name
- Backend: `PUT /api/users`

### 2. Memory Creation & Management

#### 2.1 Create Memory
- Required: description text (rich text not required — plain text is fine for MVP)
- Required: date (default to today, allow backdating)
- Optional: one or more photos
- Optional: one video
- Privacy: toggle between "Private" (only me) and "Shared" (all connections)
- Backend: `POST /api/drops`

#### 2.2 Photo Upload
- Support JPEG, PNG
- Auto-orientation correction from EXIF data
- Thumbnail generation
- Backend: `POST /api/images`

#### 2.3 Video Upload
- Direct-to-S3 upload with pre-signed URL
- Transcoding pipeline (existing)
- Thumbnail generation
- Backend: `POST /api/movies/upload/request` → `POST /api/movies/upload/complete`

#### 2.4 Edit Memory
- Update description, date, privacy toggle, add/remove media
- Backend: `PUT /api/drops/{id}`

#### 2.5 Delete Memory
- Soft delete with confirmation dialog
- Backend: `DELETE /api/drops/{id}`

### 3. Memory Stream

#### 3.1 Feed
- Reverse chronological (newest first)
- Own memories + memories shared by connections
- Infinite scroll / pagination
- Backend: `GET /api/drops` (strip down filtering params — just basic pagination)

#### 3.2 Memory Card Display
- Creator name + avatar/initials
- Date
- Description text
- Photo thumbnails (expandable to full size)
- Video player (inline)
- Comment count
- Share button

### 4. Shareable Links

#### 4.1 Generate Link
- One-tap "Share" button on any memory
- Generates a token-based URL that gives access for that mememory only to anyone clicking connecting with that token
- Backend: Net new functionality - !IMPORTANT! - this is the ONLY part of the backend that should be updated.  

#### 4.2 Public View (No Account Required)
- Landing page that renders the memory: text, photos, video
- Creator name visible
- Comments visible (read-only for unauthenticated viewers)
- Clear CTA: "Sign up to share your own moments" or "Create an account to comment"
- Backend: Net new functionality - !IMPORTANT! - this is the ONLY part of the backend that should be updated. 

#### 4.3 Conversion Flow
- If viewer wants to comment, require a very light registration
- After registering, automatically connect the users (they should now be connections)
- Backend: Net new functionality - !IMPORTANT! - this is the ONLY part of the backend that should be updated. 

### 5. Email Invitations - Deprioritized for this PRD

#### 5.1 Send Invitation
- Enter email address of person to invite
- System sends email with personal link
- Backend: `POST /api/connections`

#### 5.2 Accept Invitation
- Click link in email → land on registration (or login if existing user)
- Automatically establish connection
- Backend: existing connection confirmation flow

### 6. Comments

!IMPORTANT! commentors must be logged in - offer login / create account option

#### 6.1 Add Comment
- Text comment on any memory visible to you
- Optional: attach one photo
- Backend: `POST /api/comments`

#### 6.2 Edit / Delete Comment
- Only your own comments
- Backend: `PUT /api/comments/{id}`, `DELETE /api/comments/{id}`

#### 6.3 Display
- Chronological under each memory
- Show commenter name + timestamp
- Backend: `GET /api/comments/{dropId}`

### 7. Onboarding

!IMPORTANT! only do this for users NOT comming in from share link
For those coming in from share link take them back to the memory to make a comment.

#### 7.1 Flow: Sign Up → First Memory → First Share
- Step 1: Register (email + name)
- Step 2: "Capture your first moment" — guided memory creation with helper text
- Step 3: "Share it with someone" — prompt to generate a link or enter an email
- Step 4: "You're all set" — land on the memory stream

#### 7.2 Design Principles
- No more than 3 steps after registration
- Every step has a skip option (but skip is visually de-emphasized)
- Progress indicator visible throughout

---

## Technical Considerations

### Backend Reuse
The existing C#/.NET backend supports every feature in this PRD. No new endpoints are required — only a new frontend that consumes a subset of existing APIs:

| Feature | Existing Endpoints |
|---------|--------------------|
| Auth | `/api/users/register`, `/api/users/token`, `/api/users/login` |
| Memories | `/api/drops` (CRUD), `/api/images`, `/api/movies` |
| Stream | `GET /api/drops` |
| Comments | `/api/comments` (CRUD) |
| Share links | `/api/users/shareRequest/{token}` |
| Invitations | `/api/connections` |

### Frontend
- New frontend build (technology TBD — separate TDD)
- Mobile-first responsive design
- Progressive Web App recommended for "add to home screen" on phones

### What to Ignore in the Backend
The backend has endpoints for albums, timelines, prompts, groups, notifications, plans, and stream filters. The new frontend simply does not call these endpoints. They remain available for future PRDs.

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Time to First Memory | Median time from registration to first memory created | < 2 minutes |
| Share Rate | % of users who share at least one memory in first session | > 40% |
| Link-to-Signup Conversion | % of share link viewers who create an account | > 15% |
| Week 1 Retention | % of users who create 2+ memories in first 7 days | > 30% |
| Memories per Active User | Average memories created per weekly active user | > 2 |

---

## Out of Scope (Future PRDs)

These features are intentionally deferred. Each will get its own PRD:

1. **PRD 2: Questions & Prompts** — guided memory creation to reduce blank-page friction
2. **PRD 3: Groups & Visibility** — per-group sharing controls
3. **PRD 4: Notifications & Activity Feed** — stay connected without checking the app
4. **PRD 5: Storylines** — curated timelines about people you love
5. **PRD 6: Albums & Organization** — themed memory collections
6. **PRD 7: Reactions & Engagement** — hearts, thanks, lightweight engagement
7. **PRD 8: Subscription & Plans** — premium features and monetization

---

## Answered Questions

1. **Frontend technology** — Vue 3
2. **Push notifications** — Defer
3. **Email delivery** — Yes 
4. **Video limits** — 500 mb
5. **Anonymous commenting** — No - create an account to comment but make it SUPER easy to do

---

*Document Version: 1.0*
*Created: 2026-01-31*
*Status: Draft*
