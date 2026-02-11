# Release Notes

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
