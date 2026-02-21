# Release Notes

## 2026-02-21: Memory Date Precision

### Overview

Users can now assign flexible date precision when creating or editing memories. Instead of being forced to pick an exact date, users can choose Month & year, Year only, or Decade for older or approximate memories. All display surfaces now format dates based on the stored precision.

### What Changed

- **New utility** (`dateFormat.ts`): Shared `formatMemoryDate()` function with timezone-safe parsing, plus helpers for year/decade/month options
- **New component** (`DatePrecisionSelector.vue`): Inline dropdown that adapts the date input based on selected precision (date picker, month+year selects, year select, or decade select)
- **7 display surfaces updated**: MemoryCard, MemoryDetailView, SharedMemoryView, StorylineInviteView, AddExistingMemoryModal, QuestionAnswerCard, AnswerPreview now use `formatMemoryDate()` instead of raw `toLocaleDateString()`
- **3 forms updated**: CreateMemoryView, EditMemoryView, and AnswerForm now include the precision selector and send the user's chosen `dateType` to the API (previously hardcoded to 0)

### Display Formats

| Precision | Example |
|-----------|---------|
| Exact date | December 24, 2023 |
| Month & year | June 2019 |
| Year only | 2015 |
| Decade | 1950s |

### Tests

- 19 unit tests for dateFormat utility
- 11 component tests for DatePrecisionSelector
- All 686 frontend tests passing

### Notes

Frontend-only change. No backend or database modifications required — the `dateType` column already exists on the Drops table.

---

## 2026-02-20: Fix Question Suggestion Prompt Priority

### Bug Fix

**AI suggestions no longer influenced by old questions/answers**
Previously, the AI prompt included up to 50 previous questions and 20 recent Q&A pairs, causing generated suggestions to "riff off" unrelated past history instead of focusing on the user's current intent. The prompt now uses only the user's intent (primary) and optional storyline context (secondary) to generate questions, producing more relevant and focused suggestions. This also reduces token usage per request.

### Backend Changes

- **BuildUserPromptAsync**: Removed previous questions query and recent answers query from prompt assembly
- Removed "build on details from previous answers" and de-duplication instructions
- Simplified final prompt instructions to focus on intent + storyline only

### Tests Updated

- `WithPreviousQuestions_DoesNotIncludeThemInPrompt`: Verifies questions in DB are excluded from prompt
- `WithPreviousAnswers_DoesNotIncludeThemInPrompt`: Verifies answers in DB are excluded from prompt
- **18 QuestionSuggestionService tests passing**

---

## 2026-02-19: AI Question Suggestions (Phase 3 — Storyline Context)

### Enhancement

**Storyline-Aware AI Suggestions**
When a user creates questions from a storyline detail page, the AI prompt now includes the storyline's name, description, and up to 10 recent memories for deeper context. Access control ensures drop content is only included when the user has an active `TimelineUser` record.

### Backend Changes

- **BuildUserPromptAsync**: Extended with storyline context — queries `Timelines`, `TimelineUsers` (access check), and `TimelineDrops` (recent memory content, truncated to 200 chars)
- Additional prompt instructions for storyline narrative deepening

### Frontend Changes

- **StorylineDetailView**: New "Ask Questions" button (comment-question-outline icon) in the header action buttons, links to `/questions/new` with `storylineId` and `storylineName` query params

### Tests Added

- 3 backend: `WithStorylineId_IncludesStorylineContext`, `WithInvalidStorylineId_IgnoresStorylineContext`, `WithStorylineNoAccess_ExcludesDropContent`
- 2 frontend: `shows ask questions button`, `ask questions link includes question icon`
- **Total: 346 backend + 656 frontend = 1002 tests passing**

---

## 2026-02-19: AI Question Suggestions (Phase 2 — History-Enriched)

### Enhancement

**History-Enriched AI Suggestions**
The AI question suggestion prompt now includes the user's previous questions (up to 50) and recent answer content (up to 20), enabling smarter de-duplication and follow-up depth. The AI avoids repeating previously asked questions and builds on details from received answers.

### Backend Changes

- **BuildUserPromptAsync**: Extended to query `Questions` (via `QuestionSets`) and `QuestionResponses` (via `Drop.ContentDrop.Stuff`) for enriched prompt context
- Long answers are truncated to 300 characters to manage token usage
- History sections are omitted for new users with no question history

### Tests Added

- `GenerateSuggestions_WithPreviousQuestions_IncludesThemInPrompt`
- `GenerateSuggestions_WithPreviousAnswers_IncludesThemInPrompt`
- `GenerateSuggestions_WithNoPreviousHistory_StillGenerates`
- **Total: 343 backend + 654 frontend = 997 tests passing**

---

## 2026-02-19: AI Question Suggestions (Phase 1)

### New Feature

**AI-Powered Question Suggestions**
When creating a question set, users can now get AI-generated question suggestions to help them ask better, more meaningful questions. A collapsible "Need ideas?" panel lets users describe what they want to learn about and receive 5 suggested questions as tappable chips that auto-fill empty question fields.

### Backend Changes

- **AI Infrastructure**: Ports and adapters architecture with `IAiCompletionService` (port) and `XaiCompletionService` (adapter using xAI/Grok API)
- **QuestionSuggestionService**: Generates suggestions with intent-based prompts, database-backed rate limiting (10/day per user), and prompt injection defense
- **CacheEntry table**: New EF Core entity for distributed rate limiting with inline expired entry cleanup
- **Controller endpoint**: `POST /api/questions/suggestions` with JWT auth and IP rate limiting
- **Configuration**: `AiService` section in appsettings.json for provider/model/key/limits

### Frontend Changes

- **QuestionSuggestionPanel**: Collapsible panel with intent input, storyline picker, loading skeleton, and error handling
- **SuggestionChip**: Tappable chip component with used/disabled states
- **Session cache**: Avoids redundant AI calls for the same intent; Refresh button bypasses cache
- **AskQuestionsView integration**: Panel appears in Step 1 (Create), auto-fills empty question fields

### Tests Added

- **Backend**: 12 QuestionSuggestionService tests + 5 XaiCompletionService tests = 17 new tests
- **Frontend**: 5 SuggestionChip + 10 QuestionSuggestionPanel + 2 suggestionApi = 17 new tests
- **Total: 340 backend + 654 frontend = 994 tests passing**

---

## 2026-02-16: Email Link Fix

### Bug Fixes

**All Email Links Updated for New Frontend**
- Migrated all 17+ email templates from legacy AngularJS hash routing (`/#/`) to clean Vue 3 URLs
- Fixed actively broken `QuestionAnswerNotification` email where the link was malformed (`@Model.Link/questions/requests` instead of a proper URL)
- Fixed `ConnectionRequestQuestion` missing auto-login token (`?link=@Model.Link`)
- Fixed Login email to preserve `@Model.Route` return destination
- Fixed `/q/` public question links using wrong base URL (`BaseUrl` → `HostUrl`)

**Email Safe Link System Rewrite**
- Rewrote `EmailSafeLinkCreator` regex to match clean URLs instead of hash routes
- `GetPath` now preserves non-auth query parameters (e.g., `questionId`) that were previously stripped
- Public routes (`/q/`, `/Connection/`, `/api/`) correctly excluded from link conversion

**Security**
- Added open redirect protection in `LinksController` — validates decoded paths don't contain `://` or start with `//`

### Technical Details

**Backend Changes**
- `EmailTemplates.cs`: All 17 user-facing templates updated from `/#/` to clean URL paths
- `EmailSafeLinkCreator.cs`: Full rewrite of `FindAndReplaceLinks` regex and `GetPath` method
- `LinksController.cs`: Null-token redirect now preserves path for new-user invite flows + open redirect guard
- `QuestionService.cs`: Fixed 3 instances of `BaseUrl` → `HostUrl` for public `/q/` links; removed Link model override in QuestionAnswerNotification
- `QuestionReminderJob.cs`: Fixed `BaseUrl` → `HostUrl` for `/q/` links

**Frontend Changes**
- `MagicLinkView.vue`: Updated route handling for new path format (no leading `/` from `GetPath`)

**Tests Added**
- `EmailTemplateLinkTests.cs`: 24 tests — parameterized route validation for 19 email types, no-hash-route sweep, footer validation, Login/ForgotPassword/QuestionAnswerNotification dedicated tests
- `EmailSafeLinkCreatorTests.cs`: 13 tests — GetPath, RetrieveLink, ConvertLink round-trip, FindAndReplaceLinks with public route exclusions
- `emailRoutes.test.ts`: 13 frontend tests — 12 email destination paths resolve to real routes, no hash routes in router
- `MagicLinkView.test.ts`: Updated 5 tests for new route format

**Total: 323 backend + 637 frontend = 960 tests passing**

---

## 2026-02-16: Question Recipient Picker

### New Features

**Enhanced Recipient Selection for Questions**
- When choosing who to ask a question, users can now select from three sources:
  - **My Connections** — existing contacts from the connections list
  - **Previously Asked** — people they've sent questions to before
  - **Add Someone New** — manual email entry (existing behavior)
- Recipients are deduplicated by email (case-insensitive) so no person appears twice across sections
- Dynamic subtitle adapts based on whether contacts are available

### Technical Details

**Frontend Changes (AskQuestionsView.vue)**
- Added `getSharingRecipients()` call alongside `getPreviousRecipients()` using `Promise.allSettled` for resilient parallel loading
- Idempotency guard prevents re-fetching when navigating between steps
- `filteredPreviousRecipients` computed property deduplicates previous recipients against connections
- `handleSend` merges all three sources with case-insensitive email deduplication (connections > previous > manual priority)
- Connection `displayName` is used as the alias when sending (user's preferred label)
- No new CSS — reuses existing `.recipient-list` / `.recipient-option` styles

**Tests**
- 11 new tests added to `AskQuestionsView.test.ts` (18 total, all passing)
- Covers: connections rendering, deduplication, cross-source merge, case-insensitive dedup, API failure graceful degradation, dynamic subtitle

**No backend changes** — leverages existing `GET /connections/sharing-recipients` and `GET /questions/recipients/previous` APIs.

---

## 2026-02-14: Auto-Connections

### New Features

**Automatic Connections via Share Links**
- When a user claims a shared memory link, a bidirectional connection is automatically created between the sharer and recipient
- Toast notification shows "You're now connected with [Name]" when a new connection is formed
- Existing connections are not duplicated (idempotent behavior)

**Connections Page**
- New "Connections" page accessible from the navigation drawer (replaces "Invite")
- View all connections with name, email, and avatar initial
- Inline rename: click the pencil icon, edit name, press Enter to save or Escape to cancel
- Disconnect: click the X icon, confirm via modal, connection is removed from the list
- Invite form: send connection invitations by email directly from the connections page
- Empty state with call-to-action when no connections exist

### Technical Details

**Backend Changes**
- `ConnectionModel.cs`: Added `Email` property to expose connection email addresses
- `ClaimResult.cs` (new): Return model with `NewConnection` (bool) and `ConnectionName` (string)
- `SharingService.EnsureConnectionAsync`: Changed return type from `Task` to `Task<bool>` — returns true when a new connection is created
- `MemoryShareLinkService.ClaimDropAccessAsync` / `GrantDropAccessAsync`: Now return `ClaimResult` instead of `Task`
- `ShareLinkController.ClaimAccess`: Returns `{ success, newConnection, connectionName }` in response

**Frontend Changes**
- `ConnectionsView.vue` (new): Full connections management page with list, rename, disconnect, and invite
- `useToast.ts` (new): Composable for auto-dismissing toast notifications
- `SharedMemoryView.vue`: Shows toast when share link creates a new connection
- `connectionApi.ts`: Added `email` to Connection, `deleteConnection`, `renameConnection`
- `shareLinkApi.ts`: Added `ClaimResult` type, typed `claimAccess` return
- `AppDrawer.vue`: Changed nav item from "Invite" to "Connections"
- `router/index.ts`: Added `/connections` route, `/invite` redirects to `/connections`

**Tests Added**
- Backend: 5 new tests (EnsureConnectionAsync bidirectional, ConfirmationSharingRequest bidirectional, GetConnections email field, RemoveConnection bidirectional+TagViewers, ClaimDropAccess bidirectional+PopulateEveryone)
- Frontend: 27 new tests across 6 files (ConnectionsView, useToast, SharedMemoryView, AppDrawer, connectionApi, InviteView)

## 2026-02-13: Likes Feature

### New Features

**Like Memories**
- Users can like shared memories by clicking a heart icon
- Heart toggles between empty outline and filled red when liked
- Like count displayed next to the heart
- Hover over the heart to see who liked the memory via tooltip
- Likes are available on both the feed card and memory detail view
- Owners cannot like their own memories (button hidden)

**Like Filtering**
- Likes (Kind=1) are excluded from comment counts and comment list display
- Comment count badge only reflects normal comments (Kind=0)
- "No comments yet" empty state correctly ignores like-only entries

### Technical Details

**Backend Changes**
- `DropsService.Thank()`: Added self-like guard — throws `NotAuthorizedException` when a user attempts to like their own memory
- No schema changes — reuses existing Comment entity with `Kind` enum (Normal=0, Thank=1, UnThank=2)

**Frontend Changes**
- `LikeButton.vue` (new): Reusable component with heart toggle, like count, tooltip, aria-labels, and loading state
- `MemoryCard.vue`: Added `localComments` ref for like state management, LikeButton integration, comment count filtered to Kind=0
- `MemoryDetailView.vue`: Added LikeButton integration with `localComments` ref; converted file from 2-space to tab indentation
- `CommentList.vue`: Changed internal state to `allComments` ref + `comments` computed (filtered to Kind=0)
- `commentApi.ts`: Added `thankDrop()` function

**Tests Added**
- 10 LikeButton component tests (rendering, interactions, edge cases, accessibility)
- 3 MemoryCard tests (like count exclusion, LikeButton props, owner hiding)
- 3 CommentList tests (like filtering, empty state with likes, countChange exclusion)
- 1 commentApi service test (thankDrop)
- 4 backend DropsService tests (self-like guard, create thank, toggle, re-toggle)

**No Schema Changes, No New API Endpoints** — reuses existing `POST /api/comments/{dropId}/thanks`

## 2026-02-12: Edit Memory — Sharing & Storyline Editing

### New Features

**Two-Step Edit Memory Wizard**
- Step 1: Edit memory (text, date, photos/videos, storylines) — same fields as before
- Step 2: Choose sharing — Everyone, Specific People, or Only Me
- Sharing mode pre-populates from the memory's current tags
- Zero connections auto-saves directly (skips Step 2)
- "Back" button preserves all Step 1 state

**Sharing Editing**
- Users can now change who sees a memory after creation
- Pre-populates current sharing state: Everyone (All Connections tag), Specific People (matched per-user tags), or Only Me (no tags)
- Reuses the same `tagIds` field in `PUT /api/drops/{id}` — backend already supported this via `DropsService.Edit()`

**Storyline Editing Fix**
- Fixed broken storyline editing — backend `DropController.UpdateDrop()` ignores `timelineIds` in the PUT body
- Now uses individual `POST/DELETE /api/timelines/drops/{dropId}/timelines/{timelineId}` API calls (diff-based: only adds/removes changed storylines)
- Collapsible storyline selector with icon, badge count, and max-height (matches Create Memory pattern)
- Auto-expands when memory already belongs to storylines

### Technical Details

**Frontend Changes (no backend changes needed)**
- `EditMemoryView.vue`: Rewritten as two-step wizard with sharing UI and fixed storyline editing
- New imports: `getGroups`, `getSharingRecipients`, `addDropToStoryline`, `removeDropFromStoryline`
- `determineCurrentShareMode()`: Pure function that reverse-engineers sharing state from drop tags
- Added `aria-label` attributes on all icon-only buttons for accessibility

**Tests Added**
- 28 frontend component tests covering:
  - Step 1: form loading, step indicator, Next button, loading spinner, non-editable redirect, error state, image removal, empty text guard
  - Step 2: sharing options rendering, pre-population (Everyone/Specific/Only Me), Back button, disabled Save validation, displayName fallback
  - Storyline editing: add, remove, no-change, no timelineIds in PUT body
  - Save flow: Everyone tagIds, Specific tagIds, Only Me tagIds, image removal, navigation, error handling
  - Skip Step 2: no connections auto-save
  - Cancel: navigation

**No Backend Changes, No Schema Changes, No New API Endpoints**

## 2026-02-11: Memory Sharing at Creation

### New Features

**Two-Step Memory Creation Wizard**
- Step 1: Write memory (text, date, photos/videos, storylines) — unchanged
- Step 2: Choose sharing — Everyone (default), Specific People, or Only Me
- Zero connections auto-saves as private (skips Step 2)
- "Back" button preserves all Step 1 state

**Per-Person Sharing**
- New `GET /api/connections/sharing-recipients` endpoint returns all connections with per-user group IDs
- Each connection gets a `__person:{userId}` UserTag with a single TagViewer for granular sharing
- Timeline invitees without a UserUser connection are also included
- Select All / deselect all toggle for bulk selection

### Technical Details

**Backend Changes**
- `SharingRecipientModel.cs`: New DTO with `UserId`, `UserTagId`, `DisplayName`, `Email`
- `GroupService.EnsurePerUserGroup`: Creates `__person:{targetUserId}` UserTag atomically with race condition handling (DbUpdateException + ChangeTracker.Clear)
- `GroupService.GetSharingRecipients`: Queries UserUser + TimelineUser, bulk-fetches existing `__person:*` groups, creates missing ones, returns sorted deduplicated list
- `ConnectionController.SharingRecipients`: New `GET /api/connections/sharing-recipients` endpoint

**Frontend Changes**
- `CreateMemoryView.vue`: Rewritten as two-step wizard with v-show for DOM preservation
- `types/index.ts`: Fixed `Group` interface (`tagId` instead of `id`), added `GroupsResponse` and `SharingRecipient` types
- `groupApi.ts`: Fixed return type to match `GroupsResponse` wrapper
- `connectionApi.ts`: Added `getSharingRecipients()` function

**Tests Added**
- 7 backend integration tests (EnsurePerUserGroup, GetSharingRecipients scenarios)
- 13 frontend component tests (all sharing modes, loading states, error paths)
- 1 API service test (getSharingRecipients)

**No Schema Changes** — reuses existing UserTag, TagViewer, TagDrop, UserUser tables

## 2026-02-10: Automatic Account Creation & S3 Image Fix

### Bug Fixes

**S3 Image/Video Retrieval**
- Fixed three QuestionService methods (`BuildAnswerViewModel`, `BuildRecipientAnswerModel`, `GetAnswerMovieStatus`) that used the wrong userId when generating presigned URLs, causing broken images and videos
- Removed `Drop.UserId` reassignment in `LinkAnswersToUserAsync` that broke S3 key paths without moving objects

### New Features

**Pre-Created User Accounts**
- When sending questions, recipients now get a `UserProfile` created automatically via `UserService.FindOrCreateByEmailAsync`
- `RespondentUserId` is set on `QuestionRequestRecipient` at send time, giving a stable userId for all answer uploads
- Pre-created users have `AcceptedTerms=null` and `Name=null` until they complete their profile

**Simplified Registration Flow**
- Replaced terms checkbox with passive "Terms of Service" and "Privacy Policy" disclaimer text on all registration forms
- New `TermsDisclaimer.vue` component used across `RegisterView`, `InlineAuth`, and `InlineAuthPrompt`
- Submit button is always enabled (no checkbox gating)

**Profile Completion Flow**
- New `/complete-profile` API endpoint for pre-created users to set their name and accept terms
- `WelcomeView.vue` — first sign-in screen prompting for name with "Get Started" button
- Router guard redirects users with `needsProfileCompletion=true` to the welcome page
- Google OAuth auto-completes profile (no name prompt needed since Google provides the name)
- Hello world content (groups + sample drop) only added if user has no existing drops

### Technical Details

**Backend Changes**
- `UserService`: Added `FindOrCreateByEmailAsync`, `CompleteProfileAsync`, `TryCompletePreCreatedUserAsync` methods; added `GroupService` dependency
- `UserModel`: Added `NeedsProfileCompletion` property (true when `AcceptedTerms` is null)
- `UserController.Register`: Detects pre-created users via `TryCompletePreCreatedUserAsync`; removed terms validation
- `UserController.CompleteProfile`: New `[CustomAuthorization]` endpoint
- `GoogleAuthService.FindOrCreateUserAsync`: Detects pre-created users and calls `CompleteProfileAsync`
- `QuestionService.CreateQuestionRequest`: Calls `FindOrCreateByEmailAsync` for all recipients
- `QuestionService.LinkAnswersToUserAsync`: Simplified — no longer reassigns `Drop.UserId` or includes drop navigation
- `QuestionService.RegisterAndLinkAnswers`: Simplified — handles pre-created users with backwards-compatible fallback
- `AccountModels`: Added `CompleteProfileModel`

**Frontend Changes**
- `TermsDisclaimer.vue`: New reusable component
- `RegisterView.vue`: Removed terms checkbox, added disclaimer
- `InlineAuth.vue`: Removed terms checkbox, validation, and useId; added disclaimer
- `InlineAuthPrompt.vue`: Same changes as InlineAuth
- `auth.ts` store: Added `needsProfileCompletion` computed and `completeProfile` action
- `authApi.ts`: Added `completeProfile` function
- `types/index.ts`: Added `needsProfileCompletion` to User interface
- `WelcomeView.vue`: New profile completion page
- `router/index.ts`: Profile completion redirect guard
- `App.vue`: Added `onMounted` user fetch for authenticated sessions

**Tests Updated**
- Backend: 236 passing (removed obsolete terms validation test, updated drop ownership assertions to reflect no-transfer behavior)
- Frontend: 530 passing (updated RegisterView, InlineAuth, InlineAuthPrompt tests to remove checkbox interactions, add disclaimer tests)

---

## 2026-02-10: Universal Google OAuth & Invitation Flows

### New Features

**Reusable Inline Auth Components**
- Extracted auth UI (Google Sign-In, magic link, registration) from `QuestionAnswerView` into reusable `InlineAuth` and `InlineAuthPrompt` components
- Collapsed CTA with "Have an account? Sign in" / "New here? Sign up" toggle
- Sign-in form: Google button + magic link email
- Registration form: Google button + email/name/terms with custom `registerFn` callback support
- "Signed in as [name]" badge when authenticated
- `InlineAuthPrompt` variant with "Skip for now" button for post-action registration prompts

**Storyline Invitation Links**
- New `TimelineShareLink` entity for shareable storyline invitation links
- Public storyline preview page at `/st/:token` with storyline name, description, creator, memory count, and memory previews
- Context-specific registration and sign-in endpoints for storylines (`/storylines/:token/register`, `/storylines/:token/signin`)
- Authenticated users auto-accept invite on page load
- Google OAuth extended to accept `inviteToken` for atomic join on sign-in

**Connection Invitation Flow**
- New public connection invite page at `/invite/:token` with inviter name preview
- Safe `/preview` endpoint that avoids the `LogOffUser()` side-effect of the original endpoint
- Generic InlineAuth flow (no context-specific registration needed)
- Authenticated users auto-confirm connection on page load

**Shared Memory Link Improvements**
- `SharedMemoryView` refactored to use `InlineAuth` with context-specific `registerFn` and `magicLinkFn`
- Google OAuth extended to accept `shareToken` for atomic access claim on sign-in

### Technical Details

- New `TimelineShareLinks` table with `Token` (unique GUID index), `TimelineId`, `CreatorUserId`, `IsActive`, `ExpiresAt`, `ViewCount`
- `GoogleAuthService.AuthenticateAsync` extended with `shareToken` and `inviteToken` params
- `GoogleAuthModel` extended with `ShareToken` and `InviteToken` properties
- `TimelineShareLinkService` with `CreateLink`, `GetPreview`, `RegisterAndJoin`, `AcceptInvite`, `DeactivateLink`
- `TimelineShareLinkController` with 6 endpoints under `/api/storylines`
- Rate limiting on public endpoints (`"public"` and `"registration"` policies)
- EF Core migration `AddTimelineShareLinks` generated
- 61 new frontend tests (InlineAuth 12, InlineAuthPrompt 8, StorylineInvite 10, ConnectionInvite 7, SharedMemory 2, API services 22)
- 20 new backend tests (TimelineShareLinkService 17, GoogleAuthService +3 for share/invite tokens)
- EF Core migration `AddTimelineShareLinks` generated with production SQL

### Files Changed

**Backend (new):**
- `Domain/Entities/TimelineShareLink.cs` - Share link entity
- `Domain/Models/TimelinePreviewModel.cs` - Preview response model
- `Domain/Repositories/TimelineShareLinkService.cs` - Full service
- `Memento/Controllers/TimelineShareLinkController.cs` - 6 endpoints
- `Domain/Migrations/*_AddTimelineShareLinks.cs` - EF Core migration
- `docs/migrations/AddTimelineShareLinks.sql` - Production SQL

**Backend (modified):**
- `Domain/Entities/StreamContext.cs` - Added `TimelineShareLinks` DbSet
- `Domain/Repositories/GoogleAuthService.cs` - Extended with share/invite tokens
- `Memento/Models/GoogleAuthModel.cs` - Added `ShareToken`, `InviteToken`
- `Memento/Controllers/UserController.cs` - New `/preview` endpoint, updated GoogleAuth
- `Memento/Startup.cs` - DI registration for `TimelineShareLinkService`
- `DomainTest/Repositories/TestServiceFactory.cs` - New factory methods
- `DomainTest/Repositories/GoogleAuthServiceTest.cs` - Extended with share/invite token tests
- `DomainTest/Repositories/TimelineShareLinkServiceTest.cs` (new) - 17 service tests

**Frontend (new):**
- `src/components/auth/InlineAuth.vue` - Reusable auth component
- `src/components/auth/InlineAuthPrompt.vue` - Post-action registration prompt
- `src/services/timelineShareApi.ts` - 6 storyline share API functions
- `src/services/connectionInviteApi.ts` - 2 connection invite API functions
- `src/views/storyline/StorylineInviteView.vue` - Public storyline invite page
- `src/views/invite/ConnectionInviteView.vue` - Public connection invite page

**Frontend (tests):**
- `src/components/auth/InlineAuth.test.ts` (new) - 12 tests
- `src/components/auth/InlineAuthPrompt.test.ts` (new) - 8 tests
- `src/views/storyline/StorylineInviteView.test.ts` (new) - 10 tests
- `src/views/invite/ConnectionInviteView.test.ts` (new) - 7 tests
- `src/views/share/SharedMemoryView.test.ts` (new) - 2 tests
- `src/services/timelineShareApi.test.ts` (new) - 7 tests
- `src/services/connectionInviteApi.test.ts` (new) - 2 tests
- `src/services/authApi.test.ts` (updated) - 13 tests total

**Frontend (modified):**
- `src/composables/useGoogleSignIn.ts` - Added `shareToken`, `inviteToken` options
- `src/services/authApi.ts` - Extended `googleAuth` with new params
- `src/views/question/QuestionAnswerView.vue` - Refactored to use InlineAuth/InlineAuthPrompt
- `src/views/share/SharedMemoryView.vue` - Refactored to use InlineAuth
- `src/types/index.ts` - Added `TimelinePreview` interface
- `src/router/index.ts` - Added `/st/:token` and `/invite/:token` routes

---

## 2026-02-09: Storylines & Navigation Restructure

### New Features

**Navigation Restructure**
- Replaced bottom tab bar with a hamburger drawer navigation pattern
- New `AppDrawer` slide-out menu with links to Memories, Storylines, Questions, and Account
- Added persistent floating action button (FAB) for creating new memories from any page
- Swipe-to-close and escape key support on the drawer
- Drawer auto-closes on route navigation

**Storylines**
- New Storylines section for organizing memories into curated collections
- Storyline list view with "Your Storylines" and "Shared with You" sections
- Create and edit storylines with name and optional description
- Storyline detail view with paginated memory list and sort toggle (ascending/descending)
- Add existing memories to a storyline from the detail view
- Add/remove memories to storylines via checkbox picker from MemoryCard dropdown menu
- Storyline selection during memory create and edit flows
- Storyline badges displayed on memory detail view

**Collaboration**
- Invite connections to storylines with multi-select
- Already-invited users shown as disabled in the invite list
- Creator-only invite button on storyline detail view

### Technical Details

- New `timelineApi.ts` service with 11 API functions for all storyline operations
- New `storyline` Pinia store for paginated memory fetching with sort support
- `StorylinePicker` modal component with optimistic toggle and revert-on-failure
- `AddExistingMemoryModal` for browsing and adding memories to a storyline
- `connectionApi.ts` updated with `getConnections` function and `Connection` interface
- 5 new routes added to router (list, create, edit, invite, detail)
- `Drop.timeline` type changed from `unknown | null` to `Storyline | null`
- 105+ new tests across 16 test files, 476 total tests passing
- Also fixed 5 pre-existing test failures (Teleport stubs, clipboard mocks, route mocks)

### Files Changed

**New Files:**
- `src/components/ui/AppDrawer.vue` - Slide-out navigation drawer
- `src/components/ui/FloatingActionButton.vue` - Persistent "+" button
- `src/services/timelineApi.ts` - All storyline API functions
- `src/stores/storyline.ts` - Storyline detail store
- `src/components/storyline/StorylineCard.vue` - Card component
- `src/components/storyline/StorylinePicker.vue` - Add/remove drop modal
- `src/components/storyline/AddExistingMemoryModal.vue` - Browse memories modal
- `src/views/storyline/StorylineListView.vue` - List page
- `src/views/storyline/StorylineDetailView.vue` - Detail page
- `src/views/storyline/CreateStorylineView.vue` - Create form
- `src/views/storyline/EditStorylineView.vue` - Edit form with delete
- `src/views/storyline/InviteToStorylineView.vue` - Invite connections

**Modified Files:**
- `src/types/index.ts` - Added `Storyline` interface, updated `Drop.timeline` type
- `src/components/ui/AppNav.vue` - Added hamburger menu button
- `src/layouts/AppLayout.vue` - Replaced bottom nav with drawer + FAB
- `src/views/stream/StreamView.vue` - Removed inline FAB
- `src/components/memory/MemoryCard.vue` - Added storyline picker integration
- `src/views/memory/CreateMemoryView.vue` - Added storyline selection
- `src/views/memory/EditMemoryView.vue` - Added storyline selection
- `src/views/memory/MemoryDetailView.vue` - Added storyline badges
- `src/services/connectionApi.ts` - Added `getConnections` and `Connection` type
- `src/router/index.ts` - Added 5 storyline routes
- `src/test/fixtures.ts` - Added `createStoryline` fixture

---

## 2026-02-09: Terms of Service & Privacy Policy Pages

### New Features

**Legal Pages**
- Public `/terms` and `/privacy` pages accessible without authentication
- Casual, family-friendly tone matching the Fyli brand voice
- Full Google API Services User Data Policy Limited Use disclosure
- AI third-party provider disclosure (Grok/xAI, OpenAI, Google)
- Cross-links between Terms and Privacy pages
- Last updated date footer on each page

**Auth Page Footer Links**
- Terms and Privacy footer links on both login and registration pages (always visible, even after form submission)
- Registration terms checkbox links to Terms of Service and Privacy Policy in new tabs

### Technical Details

- `PublicLayout` dynamic width via `$route.meta.wide` route meta flag (680px for legal pages, 480px for auth)
- `scrollBehavior` added to router for scroll-to-top on navigation
- Lazy-loaded routes for `/terms` and `/privacy`
- 8 TermsView tests, 12 PrivacyView tests, 3 new RegisterView tests, 1 new LoginView test

## 2026-02-08: Google Sign-In & Question Flow Sign-In

### New Features

**Google Sign-In**
- Google Sign-In button on login and registration pages as a primary authentication method
- One-tap sign-in using Google Identity Services (GIS)
- Automatic account linking when Google email matches an existing Fyli account
- New `ExternalLogins` table tracks Google (and future provider) account links

**Question Answer Page Sign-In**
- Non-intrusive "Have an account? Sign in" link appears on question answer pages
- Inline sign-in section with Google button and magic link option
- Registration prompt includes Google sign-up button and "Already have an account?" toggle
- Anonymous answers auto-link to user's account upon sign-in (reuses existing linking logic)
- "Signed in as [name]" badge replaces sign-in link after authentication
- Magic link `returnTo` support redirects back to the question page after email sign-in

### Technical Details

- New `GoogleAuthService` verifies Google ID tokens and creates/links user accounts
- `LinkAnswersToUserAsync` extracted from `RegisterAndLinkAnswers` for shared answer-linking logic
- `IGoogleTokenVerifier` interface enables testable token verification
- `ExternalLogin` entity with unique index on `(Provider, ProviderUserId)`
- Login email template URL updated from old AngularJS hash routing to new frontend format
- 7 backend GoogleAuthService tests, 5 QuestionService LinkAnswers tests
- 7 composable tests, 2 AuthDivider tests, 9 authApi tests, 7+7 view tests, 22 QuestionAnswerView tests

### Files Changed

**Backend:**
- `Domain/Entities/ExternalLogin.cs` (new) - External login provider entity
- `Domain/Entities/StreamContext.cs` - Added ExternalLogins DbSet and configuration
- `Domain/Repositories/GoogleAuthService.cs` (new) - Google authentication service
- `Domain/Repositories/IGoogleTokenVerifier.cs` (new) - Token verifier interface
- `Domain/Repositories/GoogleTokenVerifier.cs` (new) - Production token verifier
- `Domain/Repositories/QuestionService.cs` - Extracted LinkAnswersToUserAsync
- `Domain/Repositories/IQuestionService.cs` - Added LinkAnswersToUserAsync
- `Domain/Emails/EmailTemplates.cs` - Updated login template URL format
- `Memento/Controllers/UserController.cs` - Added GoogleAuth endpoint
- `Memento/Models/GoogleAuthModel.cs` (new) - Request model
- `Memento/Startup.cs` - DI registration for GoogleAuthService

**Frontend:**
- `src/composables/useGoogleSignIn.ts` (new) - Google Sign-In composable
- `src/components/ui/AuthDivider.vue` (new) - "or" divider component
- `src/services/authApi.ts` - Added googleAuth, updated requestMagicLink with returnTo
- `src/views/auth/LoginView.vue` - Added Google button + AuthDivider
- `src/views/auth/RegisterView.vue` - Added Google button + AuthDivider
- `src/views/question/QuestionAnswerView.vue` - Added sign-in flow, Google buttons, magic link

---

## 2026-02-07: Unified Questions Page

### New Features

**Unified Questions Page**
- Combined `/questions` (set management) and `/questions/requests` (response tracking) into a single page
- Each question set displayed as a lifecycle card showing draft, sent, or complete status
- Expandable cards with inline answer previews, recipient status indicators, and action buttons
- "Load More" pagination for users with many question sets

**Ask Questions Wizard**
- Multi-step wizard combining set creation and recipient selection into one flow
- Previous recipients suggested for quick re-selection when sending new questions
- Email now required for all recipients (with validation)
- Support for `?setId=N` query parameter to skip directly to recipient selection

**Recipient Deduplication**
- When sending to the same email twice for the same question set, reuses existing token
- Avoids confusing recipients with multiple links

### Technical Details

- Two-phase query pattern: lightweight summary for sorting/pagination, full detail load only for visible results
- Old routes (`/questions/requests`, `/questions/dashboard`, `/questions/responses`) redirect to unified page
- New endpoints: `GET /questions/sets/unified`, `GET /questions/recipients/previous`
- 12 new backend tests, 43 new frontend tests

### Files Changed

**Backend:**
- `QuestionModels.cs` - 3 new models (UnifiedQuestionSetModel, UnifiedRequestModel, PreviousRecipientModel)
- `IQuestionService.cs` - 2 new interface methods
- `QuestionService.cs` - Updated CreateQuestionRequest, added GetUnifiedQuestionSets, GetPreviousRecipients
- `QuestionController.cs` - 2 new endpoints

**Frontend:**
- `UnifiedQuestionsView.vue` (new) - Main unified questions page
- `QuestionSetCard.vue` (new) - Lifecycle card component
- `AskQuestionsView.vue` (new) - Multi-step wizard
- `questionApi.ts` - 2 new API functions
- `question.ts` - 3 new TypeScript types
- `router/index.ts` - Updated routes with redirects
- Removed: QuestionSetListView, QuestionRequestsView, QuestionSendView, QuestionDashboardView, QuestionResponsesView

---

## 2026-02-07: Video Processing Placeholder with Refresh

### New Features

**Video Processing Placeholder**
- Added visual feedback when videos are still being transcoded after upload
- Users now see a "Video is being processed..." placeholder instead of a broken video element
- Added a "Check if ready" button to refresh individual video status without reloading the page
- Processing placeholder automatically updates messaging after refresh attempts

**Transcode Delay**
- Added intelligent delay after video uploads (2-8 seconds based on file size) to allow AWS MediaConvert time to process
- Visual "Processing video..." indicator shown during the delay period

### Technical Details

- New `VideoProcessingPlaceholder` component for consistent processing state UI
- New `GET /api/questions/answer/{token}/movies/{movieId}` endpoint for checking video status
- Video error handling - automatically shows placeholder if video fails to load
- Proper ARIA attributes for accessibility (`aria-live="polite"`, `aria-label`)

### Files Changed

**Frontend:**
- `src/components/question/VideoProcessingPlaceholder.vue` (new)
- `src/components/question/AnswerPreview.vue` (updated)
- `src/views/question/QuestionAnswerView.vue` (updated)
- `src/services/questionApi.ts` (updated)

**Backend:**
- `QuestionController.cs` - Added `GetAnswerMovieStatus` endpoint
- `QuestionService.cs` - Added `GetAnswerMovieStatus` implementation
- `IQuestionService.cs` - Added interface method
