# Product Requirements Document: Authentication Upgrade — Google Sign-In & Anonymous Flow Improvements

## Overview

Upgrade the authentication system to add Google Sign-In as a primary auth method alongside magic links, and improve the anonymous question-answering flow so users always have a non-intrusive option to sign in or create an account. When a user signs in during the question flow, their previously-submitted anonymous answers are automatically linked to their account.

## Problem Statement

When someone receives a question link from a family member, they answer anonymously at `/q/:token`. Today, the only opportunity to create an account is a registration prompt that appears after the first answer — and there is no way to sign in to an existing account at all. This means:

1. **Returning users can't sign in** — If Grandma already has a Fyli account from a previous question, she has no way to sign in while answering new questions. Her answers stay orphaned from her account.
2. **No quick sign-up option** — The registration prompt only appears after answering, and only offers email-based magic link registration. Users who would prefer Google Sign-In (one tap, no email check) have no option.
3. **Anonymous answers are lost** — Answers submitted before creating an account aren't linked to the new account, so the user's memory feed stays empty even after registering.

## Goals

1. Give anonymous question answerers a **subtle, always-visible option to sign in** so returning users can link their answers to their account
2. Add **Google Sign-In** as a primary authentication method across the app (login, register, and anonymous question flow) so users can authenticate in one click without checking email
3. **Auto-link anonymous answers** to the user's account when they sign in or register during the question flow, so no memories are lost
4. Keep the existing magic link auth as a fallback for users without Google accounts

## User Stories

### Anonymous Question Flow
1. As an anonymous question answerer, I want to see a small "Sign in" link at the top of the page so that I can log into my existing account without it interrupting my answering flow
2. As an anonymous question answerer who just created an account, I want my already-submitted answers to automatically appear in my memory feed so that nothing I shared is lost
3. As an anonymous question answerer, I want to sign in with Google so that I can create an account or log in with one click instead of waiting for a magic link email

### Registration Prompt (Post-First-Answer)
4. As an anonymous user who just answered a question, I want the registration prompt to offer "Sign in with Google" alongside email registration so that I can choose the fastest option
5. As a returning user who sees the registration prompt, I want an option to sign in to my existing account so that I don't accidentally create a duplicate

### Login & Register Pages
6. As a new user on the login page, I want to sign in with Google so that I don't have to wait for a magic link email
7. As a new user on the register page, I want to sign up with Google so that account creation is instant

## Feature Requirements

### 1. Subtle Sign-In Link on Question Answer Page

#### 1.1 Placement & Design
- Add a small text link in the page header area: **"Have an account? Sign in"**
- Use muted text styling (`text-muted`, small font size) — it should not compete with the question content
- Link should be visible at all times (not just after answering)
- Hide the link once the user is authenticated

#### 1.2 Sign-In Flow from Question Page
- Clicking "Sign in" opens an **inline sign-in section** (not a redirect) at the top of the page with:
  - "Sign in with Google" button
  - Email input + "Send magic link" button
  - "Cancel" link to collapse back to just the text link
- On successful sign-in:
  - User stays on the same `/q/:token` page (no redirect)
  - Auth state updates — header changes to show user is signed in
  - Previously submitted anonymous answers are auto-linked to the account (backend handles this)
  - The registration prompt (post-first-answer) no longer appears

### 2. Updated Registration Prompt (Post-First-Answer)

#### 2.1 Keep Existing Behavior
- Still appears after the user submits their first answer
- Still shows only if user is not authenticated
- "Skip for now" still dismisses it

#### 2.2 Add Google Sign-In Option
- Add a "Sign in with Google" button **above** the email registration form
- Add a visual divider ("or") between Google button and email form
- Add a small "Already have an account? Sign in" link below the form that scrolls up to / expands the header sign-in section

### 3. Google Sign-In Integration

#### 3.1 Frontend — Google Identity Services
- Use [Google Identity Services (GIS)](https://developers.google.com/identity/gsi/web) library
- Render a standard "Sign in with Google" button (not One Tap popup)
- On success, receive a Google **ID token** (JWT) containing user's email, name, and Google subject ID
- Send this ID token to the backend for verification

#### 3.2 Backend — Google Token Verification
- New endpoint: `POST /api/users/google-auth`
  - Accepts: `{ idToken: string, questionToken?: string }`
  - Verifies the Google ID token with Google's public keys
  - Extracts: email, name, Google subject ID (`sub`)
  - **If user exists** (matched by Google subject ID or email): log them in, return JWT
  - **If user is new**: create account automatically (name + email from Google, terms accepted implicitly via Google ToS), return JWT
  - **If `questionToken` provided**: auto-link anonymous answers to the user (same as existing `registerViaQuestion` behavior)
  - Returns: `{ token: string }` (Fyli JWT)

#### 3.3 Backend — External Login Tracking
- New entity: `ExternalLogin`
  - `ExternalLoginId` (int, PK)
  - `UserId` (int, FK to UserProfile)
  - `Provider` (string) — "Google"
  - `ProviderUserId` (string) — Google's `sub` claim
  - `Email` (string) — email from Google profile
  - `LinkedAt` (DateTime2)
- One user can have multiple external logins (future: Apple, Facebook)
- One Google account maps to exactly one Fyli user

#### 3.4 Configuration
- `GoogleClientId` added to AppSettings (public, used by both frontend and backend)
- Google Cloud Console project configured with:
  - OAuth 2.0 Client ID (Web application type)
  - Authorized JavaScript origins: `https://app.fyli.com`, `https://localhost:5173`
  - No redirect URIs needed (using ID token flow, not authorization code flow)

### 4. Login Page Updates

#### 4.1 Add Google Sign-In
- Add "Sign in with Google" button **above** the magic link form
- Visual "or" divider between Google and magic link sections
- On success: redirect to home (`/`) or the `redirect` query param

### 5. Register Page Updates

#### 5.1 Add Google Sign-Up
- Add "Sign up with Google" button **above** the manual registration form
- Visual "or" divider
- Google sign-up auto-accepts terms (Google ToS covers this)
- On success: redirect to onboarding or home

### 6. Auto-Link Anonymous Answers

#### 6.1 Backend Behavior
- When `questionToken` is passed to any auth endpoint (Google auth, magic link login, or registration):
  - Find all anonymous answers submitted for that question token
  - Associate those Drop records with the authenticated user's account
  - Update the question request recipient record to link to the user
- This works for both new registrations and existing user sign-ins

!IMPORTANT! The auto-link of anonymous answers to a user's account is critical. Without this, the user loses their memories. The backend must handle the case where a user signs in with Google and their email matches an existing account — answers must link to that existing account, not create a duplicate.

## Data Model

### ExternalLogin (New Entity)
```
ExternalLogin {
  ExternalLoginId: int (PK, identity)
  UserId: int (FK → UserProfile)
  Provider: string (e.g., "Google")
  ProviderUserId: string (Google sub ID)
  Email: string
  LinkedAt: DateTime2
}
```

## UI/UX Requirements

### Question Answer Page Header
```
┌─────────────────────────────────────────────────┐
│  [Creator] asked you some questions             │
│  [message if any]                               │
│  [X of Y answered]                              │
│                                                 │
│  Have an account? Sign in  ← small muted link   │
└─────────────────────────────────────────────────┘
```

When "Sign in" is clicked, it expands:
```
┌─────────────────────────────────────────────────┐
│  Sign in to save your answers                   │
│                                                 │
│  [G] Sign in with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email input     ] [Send magic link]           │
│                                                 │
│  Cancel                                         │
└─────────────────────────────────────────────────┘
```

### Registration Prompt (After First Answer)
```
┌─────────────────────────────────────────────────┐
│  Keep your memories safe                        │
│  Create an account to save your answers...      │
│                                                 │
│  [G] Sign in with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email         ]                               │
│  [Your name     ]                               │
│  [ ] I agree to the Terms of Service            │
│                                                 │
│  [Create Account]   Skip for now                │
│                                                 │
│  Already have an account? Sign in               │
└─────────────────────────────────────────────────┘
```

### Login Page
```
┌─────────────────────────────────────────────────┐
│              fyli                                │
│                                                 │
│  [G] Sign in with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email input                ]                  │
│  [Send magic link           ]                   │
│                                                 │
│  Don't have an account? Register                │
└─────────────────────────────────────────────────┘
```

### Register Page
```
┌─────────────────────────────────────────────────┐
│              fyli                                │
│                                                 │
│  [G] Sign up with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Name                       ]                  │
│  [Email                      ]                  │
│  [ ] I agree to the Terms of Service            │
│  [Create Account             ]                  │
│                                                 │
│  Already have an account? Sign in               │
└─────────────────────────────────────────────────┘
```

## Technical Considerations

### Google Identity Services Library
- Load the GIS script (`https://accounts.google.com/gsi/client`) asynchronously
- Initialize with the Google Client ID
- Use the `google.accounts.id.renderButton()` API to render the standard button
- The callback receives an ID token (JWT) — send this to the backend, do NOT trust it on the frontend

### Backend Token Verification
- Use Google's `.well-known/openid-configuration` to get the JWKS URL
- Verify the ID token signature, audience (must match our Client ID), and expiry
- Use the `Google.Apis.Auth` NuGet package (`GoogleJsonWebSignature.ValidateAsync`) for simplicity

### Security
- Never trust the Google ID token on the frontend — always verify on the backend
- The backend must verify `aud` matches our Google Client ID
- Rate-limit the `google-auth` endpoint to prevent abuse
- CSRF protection: the GIS library handles this via its nonce mechanism

### Backwards Compatibility
- Magic link auth continues to work unchanged
- Existing users without Google linked can still use magic links
- No database migration removes or modifies existing columns

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Sign-in adoption | % of anonymous answerers who sign in or register | >30% (up from ~10%) |
| Google auth usage | % of all sign-ins/registrations using Google | >50% |
| Answer linking | % of sign-ins during question flow that successfully link answers | 100% |
| Drop-off rate | % of users who start sign-in but abandon | <20% |

## Out of Scope (Future Considerations)

- Apple Sign-In (follow same pattern as Google when ready)
- Account linking page in settings (link/unlink Google from existing account)
- Google One Tap popup for returning users
- Social login on mobile apps (native SDKs)
- Password-based authentication

## Implementation Phases

### Phase 1: Backend — Google Auth + Answer Linking
- Create `ExternalLogin` entity and migration
- Add `POST /api/users/google-auth` endpoint
- Add Google ID token verification via `Google.Apis.Auth`
- Implement answer auto-linking logic for all auth endpoints
- Add `GoogleClientId` to AppSettings

### Phase 2: Frontend — Login & Register Pages
- Add Google Sign-In button to LoginView
- Add Google Sign-In button to RegisterView
- Load GIS library, wire up token callback
- Update authApi.ts with new endpoint

### Phase 3: Frontend — Question Answer Page
- Add subtle "Have an account? Sign in" link in header
- Build inline sign-in section (Google + magic link)
- Add Google button + "Sign in" link to registration prompt
- Handle post-auth state update (stay on page, refresh question data)

### Phase 4: Testing
- Backend: Unit tests for Google token verification, user creation/linking, answer linking
- Frontend: Component tests for new auth UI in all three locations
- Integration: End-to-end flow from anonymous answer → Google sign-in → answers linked

## Open Questions

1. Should the magic link flow during question answering also keep the user on the page? (Currently magic links redirect to `/auth/verify` then home — would need a `returnTo` param) - answer: yes
2. Do we need to handle the case where a Google account email matches an existing Fyli account that was created with a different email? (e.g., user registered with work email, Google login uses personal email) answer: yes
3. Should we show a "Signed in as [name]" badge on the question page after successful auth? answer: yes


---

*Document Version: 1.0*
*Created: 2026-02-08*
*Status: Draft*
