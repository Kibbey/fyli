# Product Requirements Document: Admin Usage Metrics

## Overview

Give the Fyli owner an in-product Usage section on the existing Admin page so they can see whether families are coming back, capturing memories, and commenting — without running SQL.

Three metrics: **visits** (authenticated app sessions), **comments**, and **memory creations**. Headline counts for today, last 7 days, and last 30 days. Tap a metric to see the individual events: who, when, and (for comments and creations) which memory as an id plus a short text snippet.

This is operator tooling. Regular family users never see it. Existing Admin work (asks/bugs, 30-day joins, email change) is unchanged.

## Problem Statement

Joining is not the same as using Fyli. The Admin page already answers "who signed up in the last 30 days." It does not answer the questions that actually tell the owner whether the product is helping families:

- Did anyone open Fyli today?
- Who came back this week?
- Did anyone capture a memory?
- Did anyone comment — is the family conversation happening?

Today those answers live in SQL. At hobby scale that is not a performance problem; it is a feedback-loop problem. The owner cannot tell whether stretched parents are capturing moments that matter, or whether they joined and disappeared, without leaving the product.

Views of a specific memory are not tracked today (share links only have a running counter). Comments and drops already exist as rows. What is missing is a visit log and a small Admin surface that turns those facts into a pulse the owner will actually look at.

## Goals

1. **See if families are showing up** — The owner can open Admin and immediately see today's, 7-day, and 30-day visit counts (and unique people), so they know whether anyone is coming back after signup
2. **See if the capture / comment loop is happening** — The owner can see memory creations and comments for the same windows, so they know whether people are preserving moments and talking to family — not just loading the app
3. **Drill to a person and a moment without SQL** — Tapping a number shows who, when, and (for comments and creations) which memory, so a spike or a silence is explainable
4. **Stay on one Admin page** — No analytics product, no sub-nav, no date picker. Three numbers, three windows, a list
5. **Do not change family-facing behavior** — Visit logging is silent. A failed visit write must never block opening Fyli. Drops, comments, sharing, and access rules are untouched

## Decisions (from stakeholder interview)

| Topic | Decision |
|-------|----------|
| What is a "view" | An **authenticated app visit (session)**, not a memory open and not a feed impression. Public share-link traffic and the marketing site do not count |
| Drill-down | **Event list**: who, when, and which memory (id + short snippet). Visits have no memory — they show who, when, and the path that started the session |
| Time windows | **Today + last 7 days + last 30 days.** No date picker. A compact last-7-days unique-visitor strip is always visible |
| Placement | **New Usage section on the same Admin page.** No `/admin/usage` route. No admin sub-nav |
| Content shown | **Who, when, memory id + ~80 character snippet.** No photos, no videos, no full memory body |
| Session length | **30 minutes.** If the same user already has a visit in the last 30 minutes, do not write another row |
| "Today" | **UTC calendar day** for bucketing (matches stored timestamps). Event times display in the admin's browser local timezone |
| Comments | **`Kind = Normal` only.** Thanks / un-thanks are not comments |
| Memory creations | A **Drop row's `Created`**. Include archived drops (they were still created). Include question-answer drops. Do not invent a separate "published" definition |
| History | Comments and creations are queryable for the full window. **Visits start at ship** — empty until logging is live |
| List size | **No caps, no paging** (same as asks and 30-day joins). ~100 DAU is the scale assumption |
| Owner's own visits | **Count them.** The owner will see their own name in the list; do not special-case admin traffic |
| Frontend target | **`fyli-fe-v2` only.** `fyli-fe` and `fyli-html` are out of scope |

## User Stories

### Pulse
1. As the Fyli owner, I want to see how many authenticated visits happened today, in the last 7 days, and in the last 30 days so that I know whether families are coming back without running SQL
2. As the Fyli owner, I want each visit count paired with how many unique people that is so that I can tell "one parent refreshed all morning" from "eight families showed up"
3. As the Fyli owner, I want to see comment and memory-creation counts for the same windows so that I know whether people are capturing moments that matter and talking to family, not only opening the app
4. As the Fyli owner, I want a last-7-days unique-visitor strip so that I can see the daily pulse (DAU) at a glance

### Drill-down
5. As the Fyli owner, I want to tap Visits, Comments, or Creations and see the individual events so that a number is never a dead end
6. As the Fyli owner, I want each comment and creation row to show who, when, memory id, and a short snippet so that I can tell which moment it was without opening other people's photos
7. As the Fyli owner, I want each visit row to show who, when, and the path they landed on so that I can tell whether they opened Memories, Questions, or something else
8. As the Fyli owner, I want to tap a day in the 7-day strip so that the event list and headline counts focus on that day

### Access and family impact
9. As the Fyli owner, I want Usage only on `/admin` so that regular family users never see operator metrics
10. As a parent using Fyli, I want opening the app to stay fast and unchanged so that silent visit logging never gets in the way of capturing a moment
11. As a parent, I want my photos and full memory text kept off the Admin usage list so that operator metrics do not become a backdoor into family content

## Feature Requirements

### 1. Visit logging (new; required for the Visits metric)

#### 1.1 What counts as a visit
- A **visit** is recorded when a **signed-in** user is in the authenticated `fyli-fe-v2` app chrome (`AppLayout` / `meta.auth` routes)
- Includes onboarding (they are using Fyli)
- Includes `/admin` (the owner's own use counts)
- Does **not** include:
  - Signed-out public pages (share links, invites, login, email-change notice)
  - `fyli-html` marketing site
  - Raw API traffic with no app load (scripts, health checks)
  - Old `fyli-fe`

#### 1.2 30-minute session window
- If this user already has an `AppVisit` with `Created >= UtcNow - 30 minutes`, **do not insert** a new row
- Return success anyway (idempotent no-op)
- Server is the source of truth. The client may also skip an obvious repeat; it must not be the only debounce
- Tab refresh, route changes, and API calls inside an open session do **not** each count as a new visit
- After 30 minutes of no new qualifying load, the next app load starts a new visit

#### 1.3 When the client records
- Fire-and-forget `POST` from `AppLayout` (or equivalent authenticated shell) on:
  - First mount of the authenticated shell
  - Document becoming visible again (`visibilitychange` → `visible`), still subject to the 30-minute server debounce
- Do **not** POST on every Vue route change
- Do **not** block rendering, navigation, or memory creation on this call
- Failures are silent in the UI. Log on the server. The parent must never see an error because a visit write failed

#### 1.4 What is stored
- `userId` of the signed-in user
- `created` UTC
- `path` — the Vue route path at the time of the call (e.g. `/`, `/questions`, `/memory/123`), max 200 characters, no query string, no hash, no share/invite tokens in the clear if they appear as path segments — store the path pattern the app already uses; do not add new token-stripping beyond "no query/hash"
- Do **not** store user agent, IP, referrer, or a full analytics payload

#### 1.5 API
- `POST /api/visits` (or equivalent)
- Authenticated, **no admin role**
- Body: `{ path: string }` (optional; default `/` if missing)
- Identity is `CurrentUserId`. Do **not** accept a `userId` in the body
- 200 on insert and on debounce no-op
- Do **not** put this under `/api/admin`

### 2. Metric definitions

All windows are rolling from `DateTime.UtcNow` except **Today**, which is the current UTC calendar date (`Created >= start of today UTC`).

| Metric | Count | Unique people | Source | History |
|--------|-------|---------------|--------|---------|
| **Visits** | `AppVisit` rows in the window | Distinct `userId` in those rows | New table | From ship only |
| **Comments** | `Comment` rows with `Kind = Normal` and `TimeStamp` in the window | Distinct `Comment.UserId` | Existing `Comment` | Full |
| **Creations** | `Drop` rows with `Created` in the window | Distinct `Drop.UserId` | Existing `Drop` | Full |

#### 2.1 Comments
- Include text comments, including those with photos/videos attached
- Exclude `Thank` and `UnThank`
- Do not require the parent drop to still be un-archived (the comment still happened)
- Snippet: first **80 characters** of `Comment.Content` after collapsing whitespace. Empty content → empty snippet (row still shows who / when / drop id)

#### 2.2 Memory creations
- Count by `Drop.Created` (when they captured it), not `Drop.Date` (the memory's family date)
- Include archived drops — archiving is not "this never happened"
- Include drops created from question answers
- Do not filter on `Assisted`, timeline, or sharing
- Snippet: first **80 characters** of `ContentDrop.Stuff` after collapsing whitespace. Missing content → empty snippet
- Headline number is **drops created**, not unique memories after edits (edits do not create a new drop)

#### 2.3 Unique vs total
- Each metric card shows **total events** as the big number and **N people** as the subtitle
- Example: `14` visits / `8 people` — one parent can account for several sessions

### 3. Admin Usage section

#### 3.1 Placement
- Same route: `/admin`
- Same drawer item, same role gate
- New card **after Asks & bugs, before Joined last 30 days**
- Page order becomes:
  1. Asks & bugs
  2. **Usage** (this feature)
  3. Joined last 30 days
  4. Change user email

#### 3.2 Window control
- Segmented control (or equivalent): **Today** | **7 days** | **30 days**
- Default: **Today**
- Changing the window updates the three headline counts and, if a drill-down is open, reloads that list for the new window
- No custom date picker in this release

#### 3.3 Headline cards
- Three equal cards/buttons in one row on desktop, stacked or 3-across wrapping on a phone (must remain tappable ≥ 44px)
- Labels: **Visits**, **Comments**, **Memories** (creations — use "Memories" in the UI; it is the family word)
- Each shows the total and the unique-people subtitle for the selected window
- The selected metric is visually indicated (existing primary / active styles, not a new palette)

#### 3.4 Last-7-days unique-visitor strip
- Always visible in the Usage card, independent of the window control
- Seven cells: last 6 UTC days + today
- Each cell: short weekday or date, and the **unique visitor** count for that UTC day (this is DAU)
- Tap a day: set the event list (and headline window conceptually) to that UTC day. Show which day is selected
- Days with zero: show `0`, not blank
- This strip is visits/DAU only — do not cram comment and creation counts into the cells

#### 3.5 Empty and loading
- First load of `/admin` fetches asks, signups, and usage summary in parallel (existing pattern)
- Usage summary failure: show the existing error pattern for that card with retry; do not fail the whole Admin page if asks/signups succeeded
- 403 on any admin usage endpoint: leave `/admin` (same as today)
- Visits empty after ship: "No visits yet in this window" — expected until logging has run
- Comments/creations empty: "No comments yet in this window" / "No memories created in this window"

### 4. Drill-down event list

#### 4.1 Opening
- Tap Visits, Comments, or Memories to open that metric's event list **on the same page**, below the headline cards (inside the Usage card or immediately under it)
- Tapping the already-selected metric may collapse the list (optional; either persist-open or toggle is fine, pick one and keep it consistent)
- Do not navigate to a new route

#### 4.2 Sort and size
- Newest first
- Full list for the selected window (or selected day). No cap, no pager, no virtual scroll
- At 100 DAU this is small. If a 30-day visit list ever feels long, that is a later problem

#### 4.3 Visit row
- Name (empty → email), email, user id, local datetime, path
- No memory snippet (a visit is not a memory)

#### 4.4 Comment row
- Name (empty → email), email, user id, local datetime
- `dropId`
- Snippet of the comment (80 chars)
- Do **not** show the commenter's photos/videos

#### 4.5 Creation row
- Name (empty → email), email, user id, local datetime
- `dropId`
- Snippet of the memory text (80 chars)
- Do **not** show the memory's photos/videos
- Do **not** link into the family memory detail in this release (Admin is not a memory browser)

#### 4.6 Loading events
- Fetch the event list when the admin selects a metric (or day), not necessarily on first page load
- In-flight: existing spinner
- Failure: existing error + retry for the list only

### 5. Admin APIs

All under `/api/admin`, existing `[AdminAuthorization]` (401 unauthenticated, 403 not admin).

Suggested shape (implementer may rename fields to match existing admin models, but the data must be present):

#### 5.1 Summary
`GET /api/admin/usage?window=today|7d|30d`

```
{
  window: "today" | "7d" | "30d",
  visits: { count, uniquePeople },
  comments: { count, uniquePeople },
  creations: { count, uniquePeople },
  dailyVisitors: [ { date: "YYYY-MM-DD", uniquePeople } ]  // last 7 UTC days, oldest first
}
```

`dailyVisitors` is always the last 7 UTC days, even when `window=30d` or `today`.

Do **not** accept an arbitrary from/to that could dump unbounded PII. Only the three windows (and the fixed 7-day strip).

#### 5.2 Events
`GET /api/admin/usage/events?metric=visits|comments|creations&window=today|7d|30d`

Optional `day=YYYY-MM-DD` (UTC). When `day` is set, ignore `window` and return that UTC day's events for the metric.

Response: array, newest first, unbounded.

```
// visits
{ userId, name, email, created, path }

// comments
{ userId, name, email, created, dropId, snippet, commentId }

// creations
{ userId, name, email, created, dropId, snippet }
```

Snippets are computed server-side (do not send full `Stuff` / `Content` to the client).

#### 5.3 Do not
- Do not add a generic "run this SQL" endpoint
- Do not return photos, video URLs, or full memory bodies
- Do not require the visit POST to go through the admin API

## Data Model

Existing `Comment` and `Drop` / `ContentDrop` are unchanged.

```
AppVisit {
  appVisitId: int (PK, identity)
  userId: int (FK → UserProfile, Restrict)
  path: string          // varchar, max 200
  created: datetime2 (UTC)
}

index (created)
index (userId, created)
```

No unique constraint on `(userId, created)` — debounce is application logic, not a uniqueness rule.

Do **not** add visit columns to `UserProfile`. Do **not** reuse `MemoryShareLink.ViewCount` (that is a share-link counter, not a session log, and it has no who/when).

EF Code-First + generated idempotent SQL in `docs/migrations/`, per `docs/DATABASE_GUIDE.md`.

## UI/UX Requirements

### Usage card
- Heading: **Usage**
- Window control directly under the heading
- Three metric buttons, then the 7-day unique-visitor strip, then the event list (if open)
- Mobile-first, inside existing `AppLayout` max-width 600px
- Bootstrap 5 + `var(--fyli-*)` only. No hardcoded hex. No chart library
- 7-day cells: simple buttons or tappable `div`s, selected state using existing primary/active styles
- Numbers use tabular/plain text; do not animate counters

### Event list
- Same stacked-row pattern as asks and 30-day joins (`border-bottom`, name, muted metadata line)
- Snippets wrap (`text-break`). Do not use a tooltip-only snippet — it must be readable on a phone
- Path shown as muted monospace or small muted text
- Empty name → email (same helper as the rest of Admin)

### Accessibility
- Metric controls are real buttons (not clickable non-buttons) with accessible names including the count ("Visits, 14")
- Window control is a radio group or tabs with a name ("Time window")
- Event list is a list; times have a human-readable string, not only `datetime` attributes

## Technical Considerations

### Backend
- New `AppVisit` entity, `DbSet`, indexes, Restrict FK to `UserProfile`
- Visit write in a small service used by a non-admin controller (`VisitController` or equivalent)
- Usage reads live in `AdminService` (or a dedicated method there) so PII stays behind `[AdminAuthorization]`
- Debounce query: latest `AppVisit` for `userId` where `Created >= UtcNow.AddMinutes(-30)`
- Concurrent double-POST can insert two visits inside the window. **Do not** add a serializable transaction for this. Operator-scale; same stance as the ask rate limit
- Comment query filters `Kind == Normal` (enum 0)
- Creation query is `Drops` by `Created`; join `ContentDrop` only for snippet
- Snippet helper: collapse whitespace, truncate to 80 characters, no ellipsis required (optional `…` is fine)
- Follow existing admin test patterns in `AdminServiceTest`

### Frontend
- `adminApi.ts`: `getUsage(window)`, `getUsageEvents(metric, window, day?)`
- New `visitApi.ts` (not admin): `recordVisit(path)` — fire-and-forget, catch and ignore
- Call `recordVisit` from the authenticated shell, not from `AdminView` only
- `AdminView` gains the Usage card; asks / signups / email change stay as they are
- Types for summary and event rows live next to the other admin types
- Tests: summary render, window switch, metric tap loads events, 403 redirect still works, visit client does not throw into the UI

### Backwards compatibility
- Additive table and additive endpoints
- Users with no role: unchanged. They simply generate visits when they use the app
- JWT shape unchanged
- Drops, comments, sharing, and drop access: **untouched**
- Existing `GET /api/admin/signups` stays; do not fold joins into Usage in this release

### Security and privacy
- Usage and event APIs are admin-only because they return other users' names, emails, and content snippets
- Visit POST is authenticated and bound to `CurrentUserId`
- Snippets are short on purpose. Do not "just send the full text and truncate in the client"
- Do not log visit payloads with PII to client-visible errors
- Paths must not include query strings (tokens live there on some public routes; those routes are not supposed to call this POST anyway)

### Scale
- Assumed max ~100 DAU
- 30-day visit list is on the order of thousands of rows at worst, not millions
- No Redis, no rollup tables, no background aggregation in this release
- Count and distinct on the source tables for the window is acceptable
- If this ever grows, add paging then — not now

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Pulse without SQL | Owner can read today / 7d / 30d visits, comments, and creations from `/admin` | 100% of those checks done in-product after ship |
| Drill-down completeness | Every headline number opens a list whose length matches that number for the same window | List count equals headline |
| Unique vs total | Visit card shows both session count and unique people | Visible on every window |
| Family path unblocked | Visit POST failure never surfaces in the family UI and never blocks navigation or save | Zero user-visible visit errors |
| Accidental exposure | Non-admin users who can load usage APIs or see Usage on Admin | Zero |
| Existing Admin | Asks, 30-day joins, and email change still work | No regression |

This feature does not have a family-outcome target of its own. It exists so the owner can *see* family outcomes (showing up, capturing, commenting).

## Out of Scope (Future Considerations)

- Memory-detail views or feed impressions
- Share-link `ViewCount` on this dashboard
- Signed-out / anonymous traffic
- Marketing-site analytics
- Date-range picker, all-time totals, or CSV export
- Charts / graph libraries
- Dedicated `/admin/usage` route or admin sub-nav
- By-person ranking as a first-class view (the event list is filterable by eye at this scale)
- Opening the full memory from Admin
- Thanks / likes as a fourth metric
- Funnel, retention, cohort, or "memories per active user" derived metrics
- Real-time refresh / websockets
- Excluding the owner's own visits
- Geo, device, or UTM data
- Rolling up visits into a daily table
- Instrumenting `fyli-fe` (old frontend)
- Google Analytics / third-party analytics

## Implementation Phases

### Phase 1: Record visits + Usage summary
- `AppVisit` entity, EF migration, generated SQL
- `POST /api/visits` with 30-minute debounce
- Authenticated shell fire-and-forget call
- `GET /api/admin/usage`
- Usage card on `/admin`: window control, three headline counts, 7-day unique-visitor strip
- Empty/error/403 behavior

### Phase 2: Event-list drill-down
- `GET /api/admin/usage/events`
- Tap metric → list (visit rows vs comment/creation rows)
- Tap a 7-day cell → that UTC day's events
- Server-side 80-character snippets, no media

## Open Questions

None. View definition, drill-down grain, windows, placement, and snippet policy are decided. Session length (30 minutes) and UTC bucketing are specified above so implementation is not blocked.

---

*Document Version: 1.0*
*Created: 2026-09-19*
*Status: Draft*
