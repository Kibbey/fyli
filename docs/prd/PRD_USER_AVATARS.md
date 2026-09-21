# Product Requirements Document: User Avatars

## Overview

Let a person put a face on their Fyli account. A user can upload a photo of themselves, or — if they signed up with Google — accept the photo Google already has, after being asked. That photo appears wherever their name appears today: on the memories they post, on the comments they leave, in the connections list, in the app header, and on storyline and invite screens.

Avatars are optional. A user who never sets one keeps the initials circle Fyli already shows, and nothing about their experience degrades.

## Problem Statement

Fyli is where a family keeps the moments that matter. But a Fyli stream reads like a mailing list. A memory says "Sarah" and a comment says "Mike," and the parent scrolling on a phone at 9pm has to read each name to work out who is talking. Names are the same size, the same weight, the same color. Three comments from three people look like one block of text.

That is a small friction with a real cost. The reason a stretched parent opens Fyli is to feel connected to the people in it — to see grandma react to a photo of the kids, to notice that their partner added something. Faces do that work instantly and names do not. Every family app the user already uses (photos, messages, shared albums) puts a face next to a voice, so a stream of initials reads as unfinished and slightly impersonal.

There is also an onboarding cost. A new user who just signed in with Google has a perfectly good photo sitting one API field away. Asking them to go find a photo, crop it, and upload it is exactly the kind of chore that gets skipped — which is why most accounts today have no photo at all.

## Goals

1. **Make the stream feel like people, not records** — a parent can tell at a glance who posted a memory and who commented, without reading names
2. **Make setting a photo nearly free for Google users** — one tap during onboarding, with the photo shown first and nothing stored until they say yes
3. **Keep it entirely optional** — no nagging, no incomplete-profile badge, no degraded experience for a user who skips it
4. **Stay simple** — one square photo per person. No crop editor, no filters, no photo history, no group avatars
5. **Change nothing about memories or access** — avatars are display-only. No memory, comment, or sharing permission is affected

## Decisions (from stakeholder interview)

| Topic | Decision |
|-------|----------|
| Google photo import | **Ask during onboarding.** After Google signup, show the user their Google photo and ask. Nothing is written to Fyli storage until they accept |
| Visibility | **Anyone who can see the memory**, including anonymous visitors on public share links and invite pages |
| Placement (v1) | Memory posts, comments, connections list, app header / account menu, storyline members, and share / invite screens |
| Fallback | **The initials circle Fyli shows today** (`--fyli-primary-light` background, `--fyli-primary-dark` letter). Unchanged styling |
| Required? | **Optional, always.** No prompt after the one onboarding ask |

### A note on the visibility decision

Showing avatars to anonymous share-link and invite visitors means a real person's face is served to anyone holding a link. That is a deliberate product call and this PRD builds it as decided — but the implementation must not make it worse than the link itself already is. Specifically: **avatar URLs are keyed by an unguessable token, never by user id**, so possessing a link exposes exactly the faces on that page and nothing else. No one can walk `/api/avatars/1`, `/2`, `/3` and harvest the user base. See Technical Considerations, and Open Questions for the opt-out we deferred.

## User Stories

### Setting a photo

1. As a parent who just signed up with Google, I want to be shown the photo Google already has and asked whether to use it, so that my family recognizes me in Fyli without me hunting for a photo
2. As a user, I want to upload a photo from my phone or computer, so that I can choose how I show up to the people I share memories with
3. As a user, I want to change or remove my photo at any time from my account page — not just during signup — so that I stay in control of how my family sees me
4. As a user, I want to skip the photo entirely and never be asked again, so that setting up Fyli takes as little of my evening as possible

### Seeing other people

5. As a parent scrolling the stream, I want to see who posted each memory at a glance, so that I can find the people I care about without reading every name
6. As a user reading a thread, I want each comment to carry the commenter's face, so that a back-and-forth between grandma and my partner reads like a conversation instead of a transcript
7. As a user managing connections, I want faces in my connections list, so that I can find the right person quickly when I am deciding who to share with
8. As a user, I want to see my own photo in the header, so that I know which account I am in and where to go to change it

### Family members arriving from a link

9. As someone opening a shared memory link from my daughter, I want to see who wrote it and who commented, so that a link from a family member feels personal rather than anonymous

## Feature Requirements

### 1. Setting an avatar

#### 1.1 Upload

- Accept **JPEG, PNG, and HEIC** (HEIC support already exists in `ImageService`)
- Maximum upload size **10 MB**; larger files are rejected with a plain message ("That photo is too large — please pick one under 10 MB")
- The image is **rotated per EXIF orientation, center-cropped to a square, and resized to 256 × 256**, then re-encoded as JPEG. All original metadata (including GPS) is dropped in re-encoding
- A user has **at most one avatar**. Uploading a new one replaces the old one and the old stored object is deleted
- Upload is available from **Account settings** and from the **onboarding step** (1.2)

#### 1.2 Google photo, asked for

- On Google signup, the verified `GoogleJsonWebSignature.Payload.Picture` URL is recorded on the user as a **pending suggestion only**. No image is fetched, copied, or stored in Fyli at this point
- On first entry into the app, a new user with a pending suggestion sees a single onboarding step:
  - The Google photo rendered in the same circle it will appear in
  - **"Use this photo"** — Fyli fetches the image server-side, processes it per 1.1, stores it, and clears the pending suggestion
  - **"Upload a different one"** — opens the same upload control as 1.1
  - **"Skip"** — clears the pending suggestion and moves on
- The step is shown **once**. Whatever the outcome — accept, upload, or skip — the user is never asked again
- If the Google photo URL fails to load or fetch, the step degrades to a plain "Add a photo?" upload prompt rather than erroring
- Users who did not sign up with Google never see this step; they set a photo from Account settings

#### 1.3 Changing and removing — always available

- The account page is the **permanent home** for the avatar. A user can add, replace, or remove their photo there **at any time, as many times as they like**, with no cooldown, no limit, and no dependence on onboarding state
- This is true for every user regardless of how they arrived: Google users who accepted the suggested photo, Google users who skipped the ask, users who signed up with email, and users created before this feature shipped
- **Change photo** replaces the stored image and regenerates `AvatarToken`; the change is visible on the account page immediately and everywhere else on next load
- **Remove photo** deletes the stored object, clears `AvatarUpdatedAt`, and returns the user to the initials fallback everywhere, immediately. Removing is not a dead end — the user can add a new photo right after

### 2. Display

#### 2.1 One shared component

All avatar rendering goes through a single `UserAvatar` component taking a name, an optional avatar URL, and a size. It renders the photo when a URL is present and the existing initials circle when it is not. No surface renders an avatar any other way.

#### 2.2 Sizes

| Context | Diameter |
|---------|----------|
| Memory post header | 40 px |
| Comment row | 32 px |
| Connections list | 46 px (matches today) |
| App header | 32 px |
| Storyline members, share / invite | 32 px |

A single stored 256 × 256 image serves every size, including on retina displays.

#### 2.3 Surfaces (v1)

- **Memory post header** — the author, next to the existing name and date
- **Comment rows** — the commenter, leading each comment; thanks / likes (`kind != 0`) are unchanged
- **Connections list** — replaces the initials-only circle currently in `ConnectionsView.vue`
- **App header / account menu** — the current user's own avatar, which also acts as the entry point to change it
- **Storyline member lists** and **share / invite screens**
- **Public shared-memory and invite pages** — same author and commenter avatars as the in-app view

#### 2.4 Fallback

The initials circle exactly as it renders today: first letter of the display name, uppercased, on `--fyli-primary-light` with `--fyli-primary-dark` text. Unchanged for users without a photo.

## Data Model

Additive only. No existing column, table, or payload field changes meaning.

```
UserProfile (existing table, new nullable columns)
  AvatarToken            Guid?      // unguessable key for the stored image; regenerated on every upload
  AvatarUpdatedAt        DateTime?  // null = no avatar set
  PendingAvatarSourceUrl varchar(1000)?  // Google-supplied URL awaiting the user's yes; cleared on accept or skip
```

```
OnboardingStateModel (existing JSON blob on UserProfile.OnboardingState)
  AvatarPromptedAt       DateTime?  // set when the avatar step is shown or dismissed; gates the one-time ask
```

Stored object: `avatars/{AvatarToken}.jpg` in the existing S3 bucket, separate from the drop-scoped image key space.

**Backwards compatibility:** every new column is nullable. Existing users have `AvatarUpdatedAt = null` and render exactly as they do today. No drop, comment, or access row is touched.

### Payload additions

All nullable and additive; existing clients ignore them.

| Model | New field |
|-------|-----------|
| `Drop` | `createdByAvatarUrl: string \| null` |
| `DropComment` | `ownerAvatarUrl: string \| null` |
| Connection model | `avatarUrl: string \| null` |
| `UserModel` | `avatarUrl: string \| null`, `pendingAvatarSourceUrl: string \| null` |
| Storyline member / invite models | `avatarUrl: string \| null` |

`Drop.createdById` and `DropComment.ownerId` are already on the wire, so no new joins or lookups are needed on the client.

## UI/UX Requirements

### Onboarding step

- One screen, one question, three options, no progress bar
- The Google photo is shown **as a circle at the size it will be used**, so the user is approving what they will actually see
- Copy is plain and non-committal: "Is this you?" / "Your family will see this next to your memories and comments." No persuasion, no benefit pitch
- Skip is a peer of the other options, not a greyed-out afterthought

### Account settings

- A permanent avatar row showing the current photo (or initials), with **Change photo** and, when one is set, **Remove photo**. This row is present on every visit, for every user, whether or not they have a photo — it is not hidden once a photo is set and not gated on onboarding
- Upload shows the processed result immediately on success; a failed upload leaves the previous photo intact and states what went wrong

### Stream and comments

- The avatar sits left of the existing name/date block; names, dates, and layout are otherwise unchanged
- Images are lazy-loaded and reserve their box, so avatars loading never reflows a stream the user is already reading
- A broken or failed avatar image falls back to the initials circle rather than a broken-image icon

### Accessibility

- Every avatar has `alt` text of the person's name
- The initials fallback is not the only carrier of identity — the name text remains visible beside it in every surface except the app header, where the avatar is labelled

## Technical Considerations

### Serving avatars to unauthenticated viewers

The chosen visibility (anyone who can see the memory, including public links) means avatars must be readable without a session. Two rules keep that from becoming an enumeration surface:

- The URL is **keyed by `AvatarToken` (a Guid), never by user id**: `GET /api/avatars/{token}.jpg`. Tokens are only ever emitted inside payloads the viewer was already entitled to receive
- The token is **regenerated on every upload**, which both invalidates the previous URL and makes the new one safely cacheable

Responses are served with long-lived immutable cache headers (the token changes when the image does), so repeated stream scrolling costs no repeat fetches. This differs deliberately from the existing 3-hour presigned drop-image links, which cannot be cached and are wrong for an image that appears dozens of times per screen.

### Reuse of existing infrastructure

- `ImageService` already does ImageSharp EXIF rotation, resize, and S3 upload — avatar processing should reuse those helpers rather than introduce a second imaging path
- Avatars must **not** be written into `ImageDrop` or the drop-scoped key space, and must not pass through `PermissionService.CanView`, which is drop-based and has no meaning here

### Fetching the Google photo

- The fetch happens **server-side on accept only**, never in the browser and never at signup — so Google is not told when a Fyli page is viewed, and Fyli never hotlinks a URL whose lifetime it does not control
- The fetch is bounded (timeout, max bytes) and its failure is non-fatal: the user is shown the upload option instead

### Performance

- A stream of 20 memories with comments can reference many distinct users; avatar URLs must be produced from data already loaded for the memory query — no per-row lookup or per-row presign. This is why the token lives on `UserProfile` and the URL is a pure function of it
- Given `docs/investigations/2026-09-09-gettimeline-sql-timeout.md`, the timeline and stream queries are already under load pressure. Avatar fields must ride along on existing joins and add no new ones

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Accounts with a photo | % of active users with `AvatarUpdatedAt` set | > 50% within 60 days of ship |
| Google ask conversion | % of users shown the onboarding step who accept the Google photo or upload one | > 60% |
| Set during first session | % of new Google users with a photo before their first memory | > 50% |
| Family recognizability | % of memories in a user's stream whose author shows a photo | > 40% within 90 days |
| No cost to the loop | Comment rate and memory-creation rate after ship | No decrease |
| Skip stays sticky | Users who skipped who report being re-prompted | 0 |
| Changing is easy | Users who successfully change or remove a photo after their first one | No support contact needed |

## Out of Scope (Future Considerations)

- Crop and reposition editor — v1 center-crops; a drag-to-position control can follow if photos come out badly framed
- Per-user "hide my photo on public links" opt-out (see Open Questions)
- Avatars for storylines, groups, or connections a user has renamed
- Gravatar or other third-party avatar lookup
- Animated avatars, multiple photos, or photo history
- Photo moderation or reporting
- Importing a photo from a provider other than Google
- Showing avatars in notification emails

## Implementation Phases

### Phase 1: Storage and self-service
- `UserProfile` columns and migration
- Avatar upload, process, store, replace, and delete
- Public token-keyed serve endpoint with cache headers
- Account settings avatar row (upload / change / remove)
- `UserAvatar` component with the existing initials fallback
- Avatar in the app header

### Phase 2: Display everywhere
- `avatarUrl` on drop, comment, connection, storyline-member, and invite payloads
- Avatars on memory posts and comments, in-app and on public shared-memory and invite pages
- Avatars in the connections list, storyline members, and share / invite screens

### Phase 3: Google import
- Capture `payload.Picture` as a pending suggestion at Google signup
- One-time onboarding step with Use / Upload / Skip, gated by `AvatarPromptedAt`
- Server-side fetch-on-accept with bounded failure

## Open Questions

1. **Public-link opt-out.** We decided avatars show to anonymous link visitors. Do we want a "hide my photo outside Fyli" toggle in account settings as a fast follow, for the user who is happy showing their face to family but not to a forwarded link?
2. **Account deletion.** What removes the stored avatar object when an account is closed — and does the existing deletion path cover S3 objects at all today?
3. **Existing Google users.** Users who already signed up with Google never got the ask. Do we show them the onboarding step once on next login, or leave them to Account settings?
4. **Display name vs. photo.** Connections can be renamed locally. When a user has renamed a connection, does the fallback show initials of the name *they* gave, or of the person's own name? (Assumed: the local name, matching what is displayed today.)
5. **Storage cost.** One 256 × 256 JPEG per user is trivial at current scale — is there any reason to store a second smaller size, or is one enough?

---

*Document Version: 1.0*
*Created: 2026-09-19*
*Status: Draft*
