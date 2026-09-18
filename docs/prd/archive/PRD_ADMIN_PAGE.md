# Product Requirements Document: Admin Page

## Overview

Give the Fyli owner a small, role-gated Admin page for operator work, and give every signed-in user a way to ask for help or file a bug without hunting for a support email.

Admin can: (1) see asks and bugs from users, (2) see how many people joined in the last 30 days with a simple detail list, and (3) change a user's login email when they request it. When any user submits an ask or bug, every admin is emailed.

This is mostly internal operator tooling. The ask/bug form is the one family-facing piece: a parent who is stuck can reach the owner from Account, stay in the product, and get back to capturing family memories.

There is no role system today. Admin is additive: users with no role keep working exactly as they do now. Only the Admin page, its frontend routes, and its backend APIs require the `admin` role. Creating an ask or bug does **not** require a role.

## Problem Statement

When a parent changes jobs, loses an old inbox, or typed the wrong email at signup, they cannot get a magic-link login. Their family memories are still in Fyli, but they cannot reach them. Today the owner has to look the user up in SQL, change the email by hand, and hope Google sign-in and magic-link still line up. That is slow, error-prone, and easy to get wrong (duplicate emails, stale Google login records).

Separately, the owner has no in-product view of whether people are joining. Answering "how many people signed up in the last 30 days, and who?" requires a database query.

And when something is broken or a parent has a question, there is no in-product way to tell Fyli. Pointing people at a support email puts the burden on them (find the address, leave the app, hope it is monitored). If we put a support address in an "your email changed" notice, we are training families to email us instead of asking inside Fyli — and that inbox is a single point of failure.

## Goals

1. **Let families reach us in-product** — A signed-in parent can ask a question or file a bug from Account, and every admin is notified, so they are not stuck hunting for an email address
2. **Restore access without SQL** — When a parent asks to change the email on their account, the owner can find them and update it in the product, so they can log in and keep capturing family memories
3. **See who is joining** — The owner can open Admin and immediately see a 30-day signup count plus a name/email/date list
4. **Keep existing access unchanged** — Users without a role continue to use every current page and API. Role checks exist only on Admin
5. **Stay small** — One Account form (type + message). One Admin page. No ticketing system, no support inbox address, no self-service email change

## Decisions (from stakeholder interview)

| Topic | Decision |
|-------|----------|
| Nav | Admin appears **only in the hamburger drawer**, as the **last item**, and only if the signed-in user has the `admin` role. Bottom nav stays Memories / Questions / Account for everyone |
| Find a user | Search by **email or name** (case-insensitive) |
| Email change timing | Change is **immediate**. Send a notice to **both the old and new email** |
| Duplicate email | **Block** the change and show an error. Do not merge accounts |
| "Joined" | `UserProfile.Created` in a **rolling last 30 days**. Detail rows: **name, email, join date** |
| First admin | SQL script grants `admin` to the existing user with email `kibbeyj@gmail.com` |
| Support contact | **No support email.** Any signed-in user creates an **Ask** or files a **Bug** from **Account**. Submitting **emails all admins** and lists the item on the Admin page |
| Ask vs bug | **One form** with a required type: Ask or Bug |
| Ask/bug fields | **Type + message** only. We already know who they are |
| Admin follow-up | **Email all admins + list on the Admin page** |
| List size | **No caps, no paging.** Show the full ask/bug list and the full 30-day join list. If volume ever becomes a problem, that is a success problem for later |
| Name search | Search **email, name, and username**. Do not narrow the match; a broader hit list is acceptable |

## User Stories

### Ask / file a bug
1. As a signed-in parent, I want to ask a question or file a bug from Account so that I can get help without leaving Fyli or finding a support email
2. As a parent, I want to choose Ask or Bug so that the owner can tell a question from something that is broken
3. As a parent who submitted an ask or bug, I want a clear "we got it" confirmation so that I am not left wondering whether anyone will see it
4. As the Fyli owner, I want an email when anyone submits an ask or bug so that I do not have to remember to open Admin
5. As the Fyli owner, I want to see recent asks and bugs on the Admin page so that I can act on them even if I missed the email
6. As a parent whose login email was changed without my asking, I want the notice at my old address to let me flag it from the email so that I am not locked out of the only way to ask for help

### Restore login access
7. As the Fyli owner, I want to search for a user by email or name so that I can find the parent who asked for help without opening the database
8. As the Fyli owner, I want to change that user's login email immediately so that they can get a magic link at the address they actually use and keep capturing family memories
9. As a parent whose email was changed, I want a notice at both my old and new address so that I know the change happened and can flag it if I did not request it
10. As the Fyli owner, I want the change rejected if the new email already belongs to another account so that I do not accidentally merge two families' memories

### Signup pulse
11. As the Fyli owner, I want to see how many people joined in the last 30 days, with name, email, and join date, so that I know whether families are finding Fyli without running SQL

### Access control
12. As the Fyli owner, I want Admin to appear in the drawer only when I have the `admin` role so that regular family users never see operator tools
13. As a regular user, I want every existing page and API to keep working with no role assigned so that adding Admin does not lock anyone out of their memories
14. As a regular user who types `/admin`, I want to be sent back to Memories so that operator tools stay hidden

## Feature Requirements

### 1. Admin role (additive, backwards compatible)

#### 1.1 Role storage
- New `UserRole` entity / table. A user may have zero or more roles
- Role name for this feature: `admin` (lowercase string)
- Users with **no rows** in `UserRole` are normal users. That is the current state of every existing account and must keep working
- Do **not** add a role column to `UserProfile`
- Do **not** require a role on existing endpoints, existing frontend routes, or JWT issuance
- JWT stays as it is today (`id` claim only). Role is looked up from the database when needed so a grant or revoke takes effect without forcing re-login

#### 1.2 Where a role is required
Role checks apply **only** to:
- Frontend route(s) for the Admin page
- Backend API routes under `/api/admin/*`

Everything else — including **creating an ask or bug** — must not check roles.

#### 1.3 Current user payload
- `GET` current user (existing `GetUser`) includes a `roles` array (e.g. `["admin"]` or `[]`)
- This endpoint itself does **not** require a role
- Frontend uses `roles` only to show the drawer item and to guard `/admin`

#### 1.4 Unauthorized Admin access
- Backend: authenticated but missing `admin` → **403**
- Backend: not authenticated → **401** (same as today)
- Frontend: signed-in non-admin navigating to `/admin` → redirect to `/` (Memories). Do not render an "Admin exists" error page
- Frontend: signed-out user navigating to `/admin` → existing auth redirect to login

### 2. Seed the first admin

#### 2.1 Data script
- Provide a **data** SQL script (not an EF schema migration) that grants `admin` to the user whose email is `kibbeyj@gmail.com`
- Location: `docs/migrations/` (e.g. `GrantAdminKibbeyj.sql`)
- Idempotent: safe to run more than once
- Case-insensitive email match
- If that user **does not exist**, the script must fail in a clear way (do not silently succeed). The account must already exist
- If the user already has `admin`, do nothing
- Schema for `UserRole` is created via the normal EF Code-First workflow; this script only inserts the role row

#### 2.2 No in-product role management
- Granting or revoking `admin` is SQL-only in this release
- No UI to add admins

### 3. Ask or file a bug (any signed-in user)

This is the replacement for a support email. It is **not** admin-gated.

#### 3.1 Where
- **Account page** only (`/account`)
- A Help section below plan, above Logout
- No extra drawer item, no dedicated `/help` route in this release
- Visible to every signed-in user (admin and non-admin)

#### 3.2 Form
- Required **type**: `Ask` or `Bug` (radio or equivalent; one must be selected)
- Required **message**: free text
  - Minimum 10 characters
  - Maximum 2000 characters
- No title, no screenshot, no email field (use the signed-in user's identity)
- Submit button disabled while in flight and while invalid

#### 3.3 On submit
- Persist the ask/bug (see Data Model)
- Email **every user who currently has the `admin` role** and has a non-empty email
- Show a success state: "We got it. We'll take a look."
- Clear the message; leave type as-is or reset to unset — either is fine as long as a duplicate tap does not silently resubmit the same text
- If persist succeeds but one or more admin emails fail: still show success to the user (we have the record). Log the send failure
- If persist fails: show an error, do not claim we got it
- If there are **zero admins**, still persist. Do not fail the user. Log that nobody could be notified

#### 3.4 Rate limit
- Cap submissions per user (e.g. 5 per rolling 24 hours)
- Over the cap: show a clear message ("Please wait before sending another") and do not persist

#### 3.5 API
- Authenticated, **no role required**
- Suggested: `POST /api/asks` with `{ type: "ask" | "bug", message: string }`
- Do **not** put this under `/api/admin`

#### 3.6 Do not build a ticket system
- No status, assignee, replies, or "my asks" history in this release
- The user is not given a ticket number

### 4. Admin page

#### 4.1 Route and placement
- Route: `/admin`
- Authenticated app layout (same chrome as other signed-in pages)
- **Drawer only**, last item, label **Admin**, shown only when `roles` contains `admin`
- Bottom nav is unchanged
- One page. No admin sub-nav in this release

#### 4.2 Page sections (top to bottom)
1. **Asks & bugs** — incoming list (actionable)
2. **Joined last 30 days** — count + detail list
3. **Change user email** — search, then change form

### 5. Asks & bugs on Admin

#### 5.1 List
- Newest first
- Each row: **type** (Ask / Bug), **message**, **name**, **email**, **user id**, **time**
- If name is empty, show email so the row is identifiable
- Show the **full** list. No cap, no paging
- Empty state: "No asks or bugs yet"

#### 5.2 Email to all admins
- Sent after a successful persist
- One email per admin (not a single BCC that hides who was notified — either To each admin individually or BCC all; individual send is simpler and matches the existing pipeline)
- Subject distinguishes Ask vs Bug (e.g. "Fyli Ask from {name}" / "Fyli Bug from {name}")
- Body includes: type, message, name, email, user id, time
- Link to `/admin` so the owner can open the list
- No "reply to support@" CTA. The email **is** the notification
- Skip admins with a missing/invalid email; do not fail the whole batch

### 6. Joined last 30 days

#### 6.1 Definition
- Cohort: `UserProfile` rows where `Created >= UtcNow - 30 days`
- Rolling window, not calendar month
- Window length is fixed at 30 days in this release (no date picker)

#### 6.2 Display
- A count: "N people joined in the last 30 days"
- A list of those users, newest first
- Each row: **name**, **email**, **join date** (user-local, human-readable)
- If name is empty, show the email (or username) so the row is still identifiable
- Empty state: count is 0 and a short "No one joined in the last 30 days" message. Do not show a blank table
- This list is PII. It is only returned by admin APIs and only rendered on `/admin`

### 7. Change user email

#### 7.1 Search
- Single search field: email or name
- Case-insensitive
- Require at least 2 characters before searching
- Match against `UserProfile.Email`, `UserProfile.Name`, and `UserName`
- Partial match (contains)
- Return all matches. No result cap
- Do not return a list of all users on an empty query
- Each result shows: name, email, user id, join date — enough to confirm the right person before changing anything

#### 7.2 Apply the change
- Owner selects a search result, enters the new email, confirms
- New email is trimmed, lowercased for comparison, and must be a valid email
- If new email equals current email (case-insensitive) → validation error, no write
- If any other `UserProfile` already has that email (case-insensitive) → **block**, show a clear error ("That email is already used by another account"), do not merge
- On success:
  - Update `UserProfile.Email` immediately
  - Magic-link login uses the new email from that moment
  - Google sign-in for an already-linked Google account continues to work via `ExternalLogin.ProviderUserId` (not email). Update `ExternalLogin.Email` on that user's Google row so it does not go stale. Do **not** relink to a different Google account
  - Leave `UserEmail` (alternate emails) unchanged
- Do not invalidate existing JWTs. The token is user-id based; the user stays signed in

#### 7.3 Notify old and new email (no support address)
- After a successful change, send two emails. **Do not include a support@ / personal inbox address.**
- **New address:** your Fyli login email is now {new}. Use this address for magic-link login. If you did not ask for this, sign in and file an Ask from Account.
- **Old address:** your Fyli login email was changed to {new}. If you asked for this, you can ignore this message.
- **Old address — "I didn't request this":** the old-email notice must include a **signed one-tap link** that files a **Bug** on that user's behalf **without requiring login at the new address**. That is the only signed-out create path in this release. It exists because the Account form is unreachable if the owner just took away the old login.
  - The link creates a Bug with a fixed message (e.g. "I did not request my login email to be changed from {old} to {new}.")
  - Same persist + email-all-admins path as a normal submit
  - Link is single-use and expires (e.g. 7 days), consistent with other Fyli email tokens
  - After tap: a simple public confirmation page ("We got it. We'll take a look.") — not the Admin page
- Include the user's name when we have it
- Failure to send either notice does not roll back the email change. Surface a warning to the admin if a send fails ("Email was changed, but we could not notify {address}")
- Use the existing email pipeline (`SendEmailService` / email jobs) and new template types, not a one-off send

#### 7.4 Confirmation in the UI
- Require an explicit confirm (modal or equivalent) that shows old email → new email before saving
- After success, show the updated email on the selected user and a success message
- Search results that still show the old email should refresh

### 8. Audit of email changes

Email change is a privileged write. Record each successful change:
- Admin `UserId`
- Target `UserId`
- Old email
- New email
- Timestamp (UTC)

Store this in a small `AdminAudit` table (or equivalent). No UI to browse the audit log in this release; it exists so we can answer "who changed this?" later.

## Data Model

```
UserRole {
  userRoleId: int (PK, identity)
  userId: int (FK → UserProfile, Restrict)
  role: string   // "admin"
  created: datetime2 (UTC)
}

unique (userId, role)
index (role)

Ask {
  askId: int (PK, identity)
  userId: int (FK → UserProfile, Restrict)
  type: string          // "ask" | "bug"
  message: string       // nvarchar, max 2000
  created: datetime2 (UTC)
  source: string        // "account" | "email_change_notice"
}

index (created)
index (userId)

AdminAudit {
  adminAuditId: int (PK, identity)
  adminUserId: int (FK → UserProfile, Restrict)
  targetUserId: int (FK → UserProfile, Restrict)
  action: string          // "email_change"
  oldValue: string        // previous email
  newValue: string        // new email
  created: datetime2 (UTC)
}

index (targetUserId)
index (created)
```

No change to `UserProfile` columns. `UserProfile.Created` is the join timestamp used for metrics.

`UserProfile.Email` is **not** unique at the database level today. This release enforces uniqueness in the application when changing email. Do not add a unique index here — existing data may already contain duplicates, and a constraint would be a separate cleanup project.

The existing `POST /api/contacts` marketing contact form and `giveFeedback` welcome-email flow are **unchanged**. This feature does not replace them in the backend; it replaces "email the owner" as the productized help path in the new frontend.

## UI/UX Requirements

### Drawer
- Insert **Admin** as the last item in `AppDrawer`, after Account
- Visible only when the signed-in user has role `admin`
- Icon: something operator-like and already in MDI (e.g. `mdi-shield-account-outline` / `mdi-shield-account`)
- Active state when the route starts with `/admin`
- Non-admin users: drawer markup and items are identical to today (Help lives on Account, not in the drawer)

### Account page (all signed-in users)
- New **Help** card/section
- Heading: Help (or "Ask or report a problem")
- Short prompt: e.g. "Ask a question or tell us something is broken."
- Type control: Ask / Bug
- Message textarea
- Submit
- Success and error use existing alert / `role="alert"` patterns
- Bootstrap 5 + Fyli tokens only (no hardcoded hex)

### Admin page layout
- Page title: **Admin**
- Three cards/sections, stacked, mobile-first
- Asks & bugs first (actionable)
- Metrics second
- Email-change third

### Asks & bugs section
- Visual distinction between Ask and Bug (badge or label, using existing semantic colors — not a new palette)
- Message can wrap; long messages must remain readable on a phone
- Do not require clicking into a detail page in this release; the list is the view

### Metrics section
- Headline count is the primary number
- Detail list in a simple table or stacked list that works on a phone
- Join dates as relative or short dates consistent with the rest of the app

### Email-change section
- Search input + results list
- Selecting a result reveals current email + new-email field + Change button
- Confirm modal before the write
- Inline error for duplicate email, invalid email, user not found, and send-failure warning
- Disable the Change button while the request is in flight

### Empty / error states
- Asks: "No asks or bugs yet"
- Metrics: zero-join empty state (not an error)
- Search: "No users match" empty state
- API 403 on admin endpoints: treat as "you don't have access" and leave `/admin`
- API failures: existing error-state pattern (`ErrorState` / alert)

## Technical Considerations

### Backend
- New `AdminController` (or equivalent) under `/api/admin`, all actions authenticated **and** admin-gated
- Suggested admin endpoints:
  - `GET /api/admin/asks` → newest asks/bugs
  - `GET /api/admin/signups?days=30` → `{ count, users: [{ userId, name, email, created }] }`
  - `GET /api/admin/users?q=` → search results
  - `PUT /api/admin/users/{userId}/email` → `{ email }`
- Suggested non-admin endpoint:
  - `POST /api/asks` → authenticated, no role
  - Public token endpoint for the old-email "I didn't request this" link (no JWT; signed token in the query/path, same family as magic links)
- Resolving "all admins": `UserRole` where `role = 'admin'`, join `UserProfile` for email
- Admin gate: look up `UserRole` for `CurrentUserId` + `admin`. Reuse one filter/attribute so it cannot be forgotten on a new admin action
- Do **not** add that filter to existing controllers or to `POST /api/asks`
- Email uniqueness check is case-insensitive and must exclude the target user
- Normalize emails (trim, lowercase) on write, matching Google auth and magic-link lookup
- Follow `docs/DATABASE_GUIDE.md`: EF Code-First for `UserRole`, `Ask`, and `AdminAudit`; generate idempotent SQL from the migration for schema; the grant script is a separate data script

### Frontend
- New view `AdminView` at `/admin` with `meta: { auth: true, role: 'admin', layout: 'app' }`
- Router guard: if `to.meta.role === 'admin'` and the user does not have that role, redirect to `/`
- Only `/admin` uses `meta.role`. Do not add `role` to Account or the ask API client
- `User` type and auth store expose `roles: string[]`
- New `adminApi.ts` for admin endpoints; ask create lives in a non-admin service (e.g. `askApi.ts`) matching swagger
- Drawer reads `auth.user.roles`; bottom nav does not
- AccountView gains the Help form

### Email / login side effects
- Magic link (`CreateLinkToken`) looks up `UserProfile.Email` — changing email is sufficient for magic-link login at the new address
- Google auth matches `ExternalLogin` by `Provider` + `ProviderUserId` first, then falls back to `UserProfile.Email`. Keep the Google sub link; update the stored Google email string
- Old email should no longer receive magic links for this account once the row is updated (unless another account has that address, which we block)

### Backwards compatibility
- Existing users have no `UserRole` rows → no behavior change
- Existing JWT shape unchanged
- Existing `GetUser` fields unchanged; `roles` is additive (`[]` when none)
- Drops, sharing, and access rules are untouched
- Existing contact/feedback endpoints remain; the new frontend does not send people to a support inbox

### Security
- Admin APIs must not be callable by a forged frontend; the server is the source of truth
- `POST /api/asks` is authenticated and rate-limited; do not accept an arbitrary `userId` in the body
- The email-change "I didn't request this" token must be unguessable, single-use, and bound to that email-change event
- Do not log full email-change payloads to client-visible errors
- Search, signup list, and ask list are admin-only because they return other users' content and emails

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| In-product help | Signed-in users can submit an Ask or Bug from Account without a support email | 100% of help in v2 goes through Ask/Bug |
| Admin notification | Each new ask/bug produces an email to every current admin and appears on `/admin` | Zero silent drops when at least one admin exists |
| Email-change time | Time from a parent's request to a successful in-product email change | Minutes, not a SQL session |
| Signup pulse without SQL | Owner can read last-30-day join count and details from `/admin` | 100% of checks done in-product after ship |
| Accidental exposure | Non-admin users who can see Admin in the drawer or call `/api/admin/*` successfully | Zero |
| Existing access | Users with no role can still use every pre-existing route and API | No regression |

## Out of Scope (Future Considerations)

- Self-service email change on the Account page
- In-product grant/revoke of `admin` (or any other role)
- Additional roles (`support`, etc.)
- Admin item in bottom nav
- Help item in the drawer or a dedicated `/help` page
- Title, screenshots, or attachments on asks/bugs
- Ask/bug status, assignment, replies, or "my asks" history
- Public/signed-out help form (except the email-change "I didn't request this" link)
- Date-range picker, DAU, memory counts, last-activity, or other analytics
- Account merge when two emails collide
- Relinking a different Google account
- Editing `UserEmail` alternate-email rows
- Admin UI for the audit log
- Forcing logout / invalidating JWTs on email change
- Unique database index on `UserProfile.Email` (needs a duplicate cleanup first)
- Removing or rewriting the old `POST /api/contacts` / `giveFeedback` flows

## Implementation Phases

### Phase 1: Role + seed + Admin shell + signup metrics
- `UserRole` entity, EF migration, generated schema SQL
- Data script `GrantAdminKibbeyj.sql` for `kibbeyj@gmail.com`
- `GetUser` returns `roles`
- Admin-only API gate
- `GET /api/admin/signups`
- `/admin` route, drawer item (last, admin-only), page with the 30-day count and detail list
- Router guard and 403 behavior

### Phase 2: Ask / file a bug
- `Ask` entity
- `POST /api/asks` (auth, no role) + rate limit
- Account page Help form (type + message)
- Email all current admins on submit
- `GET /api/admin/asks` and Asks & bugs section on Admin (first section)

### Phase 3: Search, email change, notices, audit
- `GET /api/admin/users?q=`
- `PUT /api/admin/users/{userId}/email` with duplicate-email block
- Confirm UI, success/error/warning states
- Notify old and new email via existing email pipeline — **no support address**; point people at Account Help
- Old-email signed "I didn't request this" link → files a Bug, emails admins
- `AdminAudit` row on success
- `ExternalLogin.Email` kept in sync for the user's Google row

## Open Questions

None. Support contact, list size, and name-search scope are decided.

---

*Document Version: 1.2*
*Created: 2026-09-17*
*Updated: 2026-09-17*
*Status: Draft*
