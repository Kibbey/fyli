# Product Requirements Document: Automatic Account Creation

## Overview

When a fyli user invites someone (via questions, shared memories, or storyline invites), we automatically create an account for the recipient using their email. This eliminates the "anonymous user" state, fixes a class of image storage bugs, and streamlines the onboarding experience. The recipient's first real sign-in becomes a simple "What's your name?" step rather than a full registration flow.

## Problem Statement

Today, when someone receives a question link and answers it, their content (memories, photos, videos) is stored under a temporary "creator-owned" identity. When they later create an account, the system attempts to transfer ownership of that content — but the files in S3 don't move, causing broken images and videos. This is a poor experience for both the sender (who sees broken images in their dashboard) and the recipient (whose content disappears after registering).

Beyond the bug, the current signup flow creates unnecessary friction. Recipients who answer questions or view shared memories are asked to fill out a registration form with name, email, and terms checkbox — even though we already have their email from the invitation. This is redundant data entry that interrupts the emotional moment of sharing memories.

## Goals

1. Eliminate image/video breakage caused by user ID mismatches during account linking
2. Reduce signup friction for invited users — they should feel welcomed, not interrogated
3. Make the transition from "invited recipient" to "active user" feel seamless and natural

## User Stories

### Invitation Flow
1. As a user sending questions to a family member, I want their account to be ready when they answer so that their photos and videos are always stored correctly and never break
2. As a user sharing a memory with someone, I want them to have an account automatically so that when they sign in later, their shared content is already waiting for them

### First Sign-In
3. As someone who received a question link, I want to sign in without re-entering my email so that I can get to my memories faster
4. As a new user signing in for the first time, I want to just tell fyli my name and start using it so that I don't have to wade through a registration form

### Standard Registration
5. As someone visiting fyli for the first time (no invitation), I want to create an account quickly so that I can start capturing memories

## Feature Requirements

### 1. Automatic Account Creation on Invitation

#### 1.1 When a user sends a question request
- For each recipient email, look up existing `UserProfile` by email
- If no user exists, create one via `UserService.AddUser` with `acceptTerms = false`
- Set `QuestionRequestRecipient.RespondentUserId` to the new (or existing) user's ID
- Do NOT call `AddHelloWorldNetworks` or `AddHelloWorldDrop` — defer until first sign-in

#### 1.2 When a user shares a memory
- Same pattern: look up or create `UserProfile` by email
- Set the share link's target user ID immediately

#### 1.3 When a user invites someone to a storyline
- Same pattern: look up or create `UserProfile` by email

#### 1.4 Pre-created user state
- `AcceptedTerms = null` (indicates hasn't completed first sign-in yet)
- `Name = null` or empty (will be collected at first sign-in)
- `PremiumExpiration = null` (set at first sign-in)
- No hello world content created yet

### 2. Terms of Service — Disclaimer Approach

#### 2.1 Remove the terms checkbox from all registration forms
- Remove from `RegisterView.vue`
- Remove from `InlineAuth.vue`
- Remove from `InlineAuthPrompt.vue`
- Backend: `acceptTerms` parameter always treated as `true` (or removed)

#### 2.2 Add footer disclaimer to all public pages
- Text: "By using fyli, you agree to our [Terms of Service](/terms) and [Privacy Policy](/privacy)."
- Displayed as small muted text in the page footer
- Visible on: `/register`, `/login`, `/q/:token`, `/s/:token`, `/st/:token`, `/invite/:token`

#### 2.3 Backend changes
- `UserService.AddUser`: always set `AcceptedTerms = DateTime.UtcNow` (remove the conditional)
- Remove `acceptTerms` parameter validation from `RegisterAndLinkAnswers`, `QuestionController`, etc.
- OR: keep the parameter but ignore it (always treat as true) for backwards compatibility with older clients

### 3. First Sign-In Experience

When a pre-created user signs in for the first time (via magic link or Google), they need to complete their profile.

#### 3.1 Detection
- After auth succeeds, backend returns user profile
- Frontend checks if user `name` is empty/null → triggers first-sign-in flow
- No separate "terms acceptance" step needed (disclaimer covers it)

#### 3.2 First sign-in screen
- Simple card: "Welcome to fyli!"
- Single field: "The name others will see when you share your memories?" (name input)
- Button: "Get Started"
- On submit:
  - Backend: set `Name`, trigger if the user does not currently have any memories `AddHelloWorldNetworks` and `AddHelloWorldDrop`, if they have a memory skip the `AddHelloWorldNetworks` and `AddHelloWorldDrop`
  - Backend: set `PremiumExpiration = DateTime.UtcNow.AddYears(10)`
  - Frontend: redirect to onboarding or home

#### 3.3 What changes in existing auth flows

**Magic link login (`/users/token` → `/users/login`):**
- Already works — finds pre-created user by email, generates magic link
- After sign-in, frontend detects missing name → shows first-sign-in screen

**Google OAuth (`/users/google-auth`):**
- `FindOrCreateUserAsync` already looks up by email → finds pre-created user
- Google provides the user's name → backend can set `Name` automatically
- If Google provides name, skip the name prompt; go straight to onboarding/home

**Standard registration (`/users/register`):**
- User enters email → backend finds existing pre-created account
- Instead of "An account already exists" error, backend should recognize this as a first-sign-in for a pre-created user
- Set the name from the registration form, complete the account setup
- Return JWT as normal

**Question answer registration (`/questions/answer/{token}/register`):**
- User already has an account (pre-created when question was sent)
- `RegisterAndLinkAnswers` finds existing user by email → sets name, completes setup
- No drop ownership transfer needed (drops already belong to recipient)

### 4. Registration Form Simplification

#### 4.1 Inline registration (InlineAuth component)
- Remove terms checkbox
- Keep: email, name, Google button
- Add disclaimer text below the form

#### 4.2 Standard registration page
- Remove terms checkbox
- Keep: email, name, Google button
- Add disclaimer text below the form

#### 4.3 When pre-created user tries to register
- Backend finds existing user by email
- If `Name` is null (pre-created, never signed in): set name, complete setup, return JWT
- If `Name` is set (already active user): return "An account already exists. Please sign in."

### 5. Cleanup of `LinkAnswersToUserAsync`

#### 5.1 Current behavior (to be simplified)
Currently transfers `Drop.UserId` from question creator to respondent. This breaks S3 image paths.

#### 5.2 New behavior
- `RespondentUserId` is always set at question send time → drops are already owned by the respondent
- `LinkAnswersToUserAsync` only needs to:
  - Create connection between asker and respondent (`EnsureConnectionAsync`)
  - Populate "Everyone" groups
  - No more `Drop.UserId` reassignment

## UI/UX Requirements

### First Sign-In Screen
- Clean, centered card layout
- Heading: "Welcome to fyli!"
- Subheading: "You're here because [Creator Name] shared something special with you."
- Single input: name field with placeholder "What should we call you?"
- Primary button: "Get Started"
- Footer disclaimer: "By using fyli, you agree to our Terms of Service and Privacy Policy."

### Registration Form (simplified)
- Remove terms checkbox everywhere
- Add small disclaimer text: "By using fyli, you agree to our [Terms of Service] and [Privacy Policy]."
- Position: below the "Create Account" button, as muted small text

### Error Handling
- When pre-created user tries standard registration: "Welcome back! We already have an account for you. Check your email for a sign-in link." (send magic link automatically)

## Technical Considerations

### Backwards Compatibility
- Existing users with `AcceptedTerms` set: no change needed
- Existing anonymous recipients (no pre-created user): continue to work with current flow until backfill
- Frontend can keep sending `acceptTerms` parameter; backend ignores it

### Data Migration
- One-time script to pre-create users for existing `QuestionRequestRecipient` records where `RespondentUserId` is null
- One-time S3 fix for already-broken images (move objects from old path to correct path)

### Ghost User Cleanup
- Pre-created users who never sign in accumulate as lightweight rows
- Consider a cleanup job after 12+ months of inactivity (no sign-in, no content)
- Low priority — these are small records with no associated content

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Image breakage | % of presigned image URLs that return 403/404 | 0% (down from current bug rate) |
| Signup completion | % of invited users who complete first sign-in | Track as baseline, then improve |
| Time to first memory | Time from first visit to creating/viewing a memory | Reduce by removing form friction |

## Out of Scope (Future Considerations)

- Email verification for pre-created accounts (not needed — email was provided by a trusted sender)
- Account merging (if someone has two pre-created accounts from different senders)
- Notification preferences for pre-created users
- Push notifications before first sign-in

## Implementation Phases

### Phase 1: Bug Fix (immediate)
- Fix three QuestionService retrieval methods to use `drop.UserId`
- No product changes, pure backend fix

### Phase 2: Auto-Create Users
- Modify `CreateQuestionRequest` to pre-create users
- Update `SubmitAnswer` and upload controllers to use `RespondentUserId` (always set)
- Simplify `LinkAnswersToUserAsync`

### Phase 3: Terms Disclaimer
- Remove terms checkbox from all frontend forms
- Add disclaimer text to public pages and registration forms
- Backend: always set `AcceptedTerms`

### Phase 4: First Sign-In Flow
- Add "What's your name?" screen for pre-created users
- Update standard registration to handle pre-created users gracefully
- Defer `AddHelloWorldNetworks`/`AddHelloWorldDrop` to first sign-in

### Phase 5: Data Backfill
- Pre-create users for existing anonymous recipients
- Fix existing broken S3 image paths

## Open Questions

1. Should we send the pre-created user a welcome email when the question is sent, or wait until they click the question link? (Recommendation: don't send — let the question email be their first touchpoint) - 
  Answer: no
2. For Google OAuth where we get the name automatically, should we skip the name prompt entirely? (Recommendation: yes — Google provides name, go straight to app)
  Answer: yes
3. Should the "first sign-in" screen show a subset of onboarding (create first memory, share link)? Or just collect the name and go to home? (Recommendation: just name → home, keep it minimal)
   Answer: go with recommendation (name -> home)

---

*Document Version: 1.0*
*Created: 2026-02-10*
*Status: Draft*
