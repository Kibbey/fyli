# Product Requirements Document: Universal Google OAuth Across All Touchpoints

## Overview

Establish a consistent, content-first authentication experience across every touchpoint where an anonymous user interacts with Fyli. Every page that allows unauthenticated access should offer the same non-intrusive sign-in/sign-up pattern: a clear call-to-action that expands to reveal Google Sign-In and magic link options. Anonymous users should never feel pressured to join, but should always have an obvious path to do so.

## Problem Statement

Family members interact with Fyli through multiple entry points — answering questions, viewing shared memories, accepting storyline invitations, and responding to connection requests. Today these flows have **inconsistent authentication experiences**:

- **Question answering** (`/q/:token`) has the best pattern: a subtle "Have an account? Sign in" link that expands to an inline form with Google + magic link. This is the gold standard.
- **Shared memory links** (`/s/:token`) show "Sign Up" and "Sign In" buttons that toggle between forms — but Google Sign-In is missing entirely, and the layout differs from the question flow.
- **Storyline invitations** have no public acceptance flow — unauthenticated users can't view or contribute to a storyline they've been invited to.
- **Connection invitations** require authentication before the user can accept — there's no inline auth option on the invitation page.

This inconsistency creates confusion. Grandma who signed up via Google on a question page expects the same option when viewing a shared memory. A parent invited to a child's storyline shouldn't hit a login wall. Every anonymous touchpoint should feel like the same app.

## Goals

1. **Content first** — Anonymous users can always view and interact with shared content without being forced to sign in or create an account
2. **Consistent auth everywhere** — Every anonymous touchpoint uses the same visual pattern and behavioral flow for sign-in/sign-up, including Google OAuth
3. **No pressure, clear path** — The auth CTA is visible but non-intrusive; users feel welcome whether they sign in or not
4. **Context preservation** — After signing in on any page, users stay on that page and their actions (answers, views, contributions) are linked to their account

## User Stories

### Universal Auth Pattern
1. As an anonymous user on any Fyli page, I want to see clear but non-obnoxious sign-in and sign-up options so that I can join or log in whenever I'm ready without feeling pressured
2. As a returning user visiting any shared link, I want to sign in with Google in one click so that I don't have to wait for a magic link email
3. As an anonymous user who decides to sign in, I want the auth form to appear inline on the same page so that I don't lose context or get redirected away from the content I'm viewing

### Shared Memory Flow (`/s/:token`)
4. As a family member viewing a shared memory, I want the option to sign in with Google so that I can save this memory to my account and comment on it instantly
5. As a family member viewing a shared memory, I want to see the memory content before being asked to sign in so that I don't feel like I'm being gated

### Storyline Invitation Flow (new)
6. As a grandparent invited to a storyline, I want to view the storyline preview without creating an account so that I can see what I'm being invited to before committing
7. As a grandparent invited to a storyline, I want to sign up with Google right on the invitation page so that I can start contributing immediately without hunting for a registration page

### Connection Invitation Flow
8. As a family member who received a connection invite, I want to see who invited me and why before being asked to create an account so that I can make an informed decision
9. As a family member accepting a connection invite, I want to sign in with Google inline so that I can accept the connection without navigating away

## Feature Requirements

### 1. Reusable Inline Auth Component

The question answering page (`/q/:token`) already implements the ideal pattern. This must be extracted into a **shared, reusable component** used by every anonymous touchpoint.

#### 1.1 Collapsed State (CTA)
- Two adjacent links: **"Sign in"** and **"Sign up"** (e.g., "Have an account? Sign in · New here? Sign up")
- Styled as muted, secondary text — visible but not dominant
- Positioned consistently within each page's content area (not in a header or footer)
- Each link expands the appropriate variant (sign-in or registration)
- Hidden once the user is authenticated

#### 1.2 Expanded State — Sign-In Variant
When "Sign in" is clicked, it expands inline to reveal:
- **Heading** — Contextual message (e.g., "Sign in to save this memory", "Sign in to join this storyline")
- **Google Sign-In button** — Primary action, always first
- **"or" divider** — Using the existing `AuthDivider` component
- **Magic link form** — Email input + "Send magic link" button
- **"Don't have an account? Sign up"** — Switches to the registration variant inline
- **Cancel** — Collapses back to the CTA text

#### 1.3 Expanded State — Registration Variant
When "Sign up" is clicked (from the CTA or from the sign-in variant's toggle link):
- **Heading** — Value-focused message (e.g., "Keep your memories safe", "Create an account to contribute")
- **Google Sign-Up button** — Primary action, always first
- **"or" divider**
- **Manual registration form** — Email, name, terms checkbox, "Create Account" button
- **"Already have an account? Sign in"** — Switches to the sign-in variant inline
- **Cancel** — Collapses back to the CTA text

#### 1.4 Post-Action Registration Prompt
For prompts that appear after an anonymous action (e.g., after answering a question, after viewing a shared memory):
- Same layout as Section 1.3 but triggered automatically, not by CTA click
- **"Skip for now"** — Dismisses the prompt (does not appear in the CTA-triggered variant)
- Must still include the **"Already have an account? Sign in"** toggle

#### 1.4 Behavior After Authentication
- User stays on the same page (no redirect)
- Page state updates to reflect authenticated status (e.g., "Signed in as [name]" badge)
- Any anonymous actions are linked to the user's account (answers, views, etc.)
- The auth component hides or transitions to the "Signed in as" state

### 2. Shared Memory Link Updates (`/s/:token`)

Currently missing Google auth and using an inconsistent layout.

#### 2.1 Replace Current Auth Section
- Remove the separate "Sign Up" / "Sign In" toggle buttons
- Replace with the universal inline auth component (Section 1)
- CTA text: **"Have an account? Sign in · New here? Sign up"**
- Registration prompt heading: **"Save this memory to your account"**

#### 2.2 Add Google Auth Support
- Add Google Sign-In button to both sign-in and registration flows
- On Google auth success: call the existing `claimAccess` endpoint to link the memory to the user's account
- Pass the share token to the backend so the claim happens as part of the auth flow

#### 2.3 Content Remains Accessible
- Memory content (text, photos, videos) always visible without auth
- Comments visible in read-only mode without auth
- Auth prompt appears below the memory content — never blocks it

### 3. Storyline Invitation Flow (New Public Route)

A new public route for storyline invitations that follows the universal auth pattern.

#### 3.1 New Route: `/st/:token`
- Public route (no auth guard)
- Displays storyline preview: title, description, creator name, number of memories, cover image if available
- Shows the invitation context: "[Creator] invited you to contribute to this storyline"

#### 3.2 Auth Integration
- Universal inline auth component below the preview
- CTA text: **"Have an account? Sign in · New here? Sign up"**
- Registration prompt heading: **"Join to add your memories to this storyline"**
- On auth success: accept the invitation, navigate to the full storyline view (see TDD for implementation details)

#### 3.3 Backend Support
- New endpoint: `GET /api/timelines/invite/:token` — returns storyline preview data (no auth required)
- New endpoint: `POST /api/timelines/invite/:token/accept` — accepts invitation (requires auth)
- New endpoint: `POST /api/timelines/invite/:token/register` — registers and accepts in one step
- Token generation: when inviting a user to a storyline, generate a unique invitation token and include it in the email/link

### 4. Connection Invitation Flow Updates

#### 4.1 Public Invitation Page
- The existing `GET /api/users/shareRequest/:token` endpoint already returns invitation metadata without auth
- Create a frontend view at `/invite/:token` that displays: inviter name, optional message, and the universal inline auth component
- CTA text: **"Have an account? Sign in · New here? Sign up"**
- Registration prompt heading: **"Create an account to connect with [name]"**

#### 4.2 Inline Auth + Accept
- On auth success: automatically accept the connection invitation
- User stays on the page, sees a confirmation state ("You're now connected with [name]")

### 5. Question Answering Flow Alignment (`/q/:token`)

The question flow already has the correct pattern. Minor alignment work:

#### 5.1 Extract to Shared Component
- Refactor the existing inline auth code in `QuestionAnswerView.vue` to use the new shared component
- Ensure the visual layout matches the universal spec exactly
- No functional changes — this is a refactor for consistency

### 6. Future Touchpoint Standard

#### 6.1 Pattern for New Anonymous Flows
Any future feature that introduces a public/anonymous page **must** use the universal inline auth component. This includes but is not limited to:
- Album sharing links
- Family event invitations
- Any content shared via URL

## UI/UX Requirements

### Universal Inline Auth — Collapsed State
```
┌─────────────────────────────────────────────────┐
│  [Page content — memory, storyline, etc.]       │
│                                                 │
│  Have an account? Sign in · New here? Sign up   │
└─────────────────────────────────────────────────┘
```

### Universal Inline Auth — Expanded (Sign-In)
```
┌─────────────────────────────────────────────────┐
│  [Contextual heading]                           │
│                                                 │
│  [G] Sign in with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email input         ] [Send magic link]       │
│                                                 │
│  Don't have an account? Sign up                 │
│  Cancel                                         │
└─────────────────────────────────────────────────┘
```

### Universal Inline Auth — Expanded (Registration)
```
┌─────────────────────────────────────────────────┐
│  [Value-focused heading]                        │
│  [Brief description of benefit]                 │
│                                                 │
│  [G] Sign up with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email                      ]                  │
│  [Your name                  ]                  │
│  [ ] I agree to the Terms of Service            │
│                                                 │
│  [Create Account]                               │
│                                                 │
│  Already have an account? Sign in               │
│  Cancel                                         │
└─────────────────────────────────────────────────┘
```

### Post-Action Registration Prompt (e.g., after first answer)
```
┌─────────────────────────────────────────────────┐
│  [Value-focused heading]                        │
│  [Brief description of benefit]                 │
│                                                 │
│  [G] Sign up with Google                        │
│                                                 │
│  ── or ──                                       │
│                                                 │
│  [Email                      ]                  │
│  [Your name                  ]                  │
│  [ ] I agree to the Terms of Service            │
│                                                 │
│  [Create Account]   Skip for now                │
│                                                 │
│  Already have an account? Sign in               │
└─────────────────────────────────────────────────┘
```

### Signed-In State (Replaces CTA)
```
┌─────────────────────────────────────────────────┐
│  ✓ Signed in as [Name]                          │
└─────────────────────────────────────────────────┘
```

### Visual Consistency Rules
- Google button always appears **first** (above the divider)
- "or" divider always uses the `AuthDivider` component
- CTA text always uses `text-muted` / small font — never bold or primary colored
- Expanded form appears inline — never a modal, popup, or redirect
- Cancel always collapses back to the CTA (no page reload)
- "Signed in as" badge uses the same style across all pages

## Technical Considerations

### Shared Component Architecture
- Create `InlineAuth.vue` — the universal auth component with props for:
  - `signinHeading`: heading text for the sign-in variant
  - `registerHeading`: heading text for the registration variant
  - `registerDescription`: optional subheading for registration variant
  - `onSuccess`: callback fired after successful auth (page-specific behavior)
  - `questionToken`: optional — for question answer linking
  - `shareToken`: optional — for shared memory claiming
  - `inviteToken`: optional — for storyline/connection invitation acceptance
- The collapsed CTA always shows both "Sign in" and "Sign up" links
- Each link opens the corresponding expanded variant
- Both variants include a toggle link to switch to the other (e.g., "Already have an account? Sign in" / "Don't have an account? Sign up")
- The component internally uses `useGoogleSignIn` composable and existing `authApi` methods

### Backend: Google Auth Endpoint Enhancement
- The existing `POST /api/users/google-auth` endpoint accepts `questionToken` for answer linking
- Extend to also accept `shareToken` and `inviteToken` so that claiming/accepting happens atomically with auth
- This prevents a race condition where auth succeeds but the claim/accept call fails

### Backend: New Storyline Invitation Endpoints
- Generate invitation tokens when users are invited to storylines (similar to question tokens)
- Store tokens in a new `TimelineInvitation` entity or extend `TimelineUser` with a token field
- Public GET endpoint returns limited preview data (no full memory content — just metadata)

### Security
- All public endpoints must be rate-limited (existing `"public"` and `"registration"` rate limit policies)
- Invitation tokens should be single-use or time-limited where appropriate
- Share link tokens remain reusable (existing behavior)
- Google token verification unchanged (backend validates audience + signature)

### Backwards Compatibility
- Existing magic link flows continue to work unchanged
- Existing share links (`/s/:token`) continue to work — the UI is enhanced, not replaced
- Question flow (`/q/:token`) continues to work — internal refactor only
- No database columns removed — only additive changes

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Google auth adoption on share pages | % of share link visitors who auth via Google | >40% of those who sign in |
| Auth conversion on share pages | % of anonymous share link visitors who sign in or register | >25% (up from ~15%) |
| Storyline invite acceptance rate | % of storyline invitation links that result in a user joining | >50% |
| Connection invite acceptance rate | % of connection invitations accepted via the new inline flow | >60% |
| Cross-touchpoint consistency | All anonymous pages pass visual/behavioral audit | 100% |
| Auth drop-off rate | % of users who expand the auth form but abandon | <20% |

## Out of Scope (Future Considerations)

- Google One Tap popup for returning visitors
- Apple Sign-In (same pattern, different provider — add when ready)
- Account linking page in settings (link/unlink Google from existing account)
- Social login on native mobile apps
- Password-based authentication
- Album sharing links (follow this pattern when albums get sharing)

## Implementation Phases

### Phase 1: Shared Inline Auth Component
- Extract auth pattern from `QuestionAnswerView.vue` into reusable `InlineAuth.vue` component
- Include both sign-in and registration variants
- Props for contextual headings, tokens, and success callbacks
- Refactor `QuestionAnswerView.vue` to use the new component (no functional change)

### Phase 2: Shared Memory Link (`/s/:token`)
- Replace current auth section in `SharedMemoryView.vue` with `InlineAuth` component
- Add Google auth support (pass share token through to `google-auth` endpoint)
- Update backend `google-auth` endpoint to accept `shareToken` and call `claimAccess` atomically
- Read-only comments visible to anonymous users

### Phase 3: Storyline Invitation Flow
- Backend: add invitation token generation and public preview endpoint
- Backend: add public accept + register-and-accept endpoints
- Frontend: new `/st/:token` route with storyline preview + `InlineAuth` component
- Update backend `google-auth` to accept `inviteToken` for atomic accept

### Phase 4: Connection Invitation Flow
- Frontend: new `/invite/:token` route with invitation details + `InlineAuth` component
- On auth success: auto-accept the connection
- Confirmation state after acceptance

### Phase 5: Visual Audit & Polish
- Audit all anonymous touchpoints for visual consistency
- Ensure identical spacing, typography, and animation across all pages
- Verify "Signed in as [name]" badge is consistent everywhere
- Cross-browser and mobile responsive testing

## Open Questions

1. Should the storyline invitation preview show a sample of memories in the storyline, or just metadata (title, description, count)? Showing memories might motivate joining but raises privacy considerations.
2. For connection invitations, should the inviter be able to include a personal message that appears on the invitation page?
3. Should we implement a "remember this device" flow so returning anonymous users are recognized across multiple share/question links?

---

*Document Version: 1.0*
*Created: 2026-02-10*
*Status: Draft*
*Supersedes: PRD_AUTH_GOOGLE_SIGNIN.md (Phase 1 — completed)*
