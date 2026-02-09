# Product Requirements Document: Terms of Service & Privacy Policy Pages

## Overview

Add public-facing Terms of Service and Privacy Policy pages to the Fyli web app. These pages are required by Google for apps that use Google OAuth and must be publicly accessible, linkable from the Google OAuth consent screen, and hosted on the same domain as the app. The Terms page should maintain Fyli's warm, casual tone established on the existing fyli.com/termsOfService/ page while covering the necessary legal ground.

## Problem Statement

Fyli recently added Google Sign-In as an authentication method. Google requires all apps using OAuth to have publicly accessible Terms of Service and Privacy Policy pages linked from their OAuth consent screen. Without these pages:

1. **Google will reject OAuth verification** — The app cannot pass brand verification or scope verification without published terms and privacy policy links on the same domain
2. **Users have no transparency** — There's no clear disclosure of what data Fyli collects, how it's used, or what Google data the app accesses
3. **Registration terms checkbox has no destination** — The register page has a "terms of service" checkbox but it doesn't link to an actual page

## Goals

1. Comply with Google's OAuth verification requirements so Fyli can move to production without the "unverified app" warning
2. Give users clear, honest, approachable information about their data and rights — in language that matches Fyli's family-first brand
3. Provide linkable URLs that can be configured in the Google Cloud Console OAuth consent screen

## User Stories

### Public Visitors
1. As a potential user evaluating Fyli, I want to read the terms of service so that I understand what I'm agreeing to before creating an account
2. As a potential user, I want to read the privacy policy so that I know how my data (including Google account data) will be used and protected

### Existing Users
3. As a registered user, I want to review the privacy policy at any time so that I feel confident my family's memories are handled responsibly
4. As a user who signed in with Google, I want to understand exactly what Google data Fyli accesses so that I can make an informed decision about linking my account

### Registration Flow
5. As a new user on the register page, I want the "Terms of Service" checkbox to link to the actual terms page so that I can read what I'm agreeing to before signing up

## Feature Requirements

### 1. Terms of Service Page

#### 1.1 Route & Access
- Public route: `/terms`
- No authentication required
- Uses the `PublicLayout` (same as login/register pages)
- Page title: "Terms of Service"

#### 1.2 Content Sections
The page should maintain Fyli's casual, family-friendly voice established on the existing terms page. Required sections:

**Welcome / Philosophy**
- Set the tone — Fyli is a place for families to share and preserve meaningful moments
- Reference the "choose kindness, embrace joy, let go" ethos from the existing page

**What Fyli Is**
- Brief description: a platform to create, share, and preserve family memories and moments
- Not a general social media platform — focused on meaningful family connections

**Your Agreement**
- By creating an account or using Fyli, you agree to these terms
- Must be at least 13 years of age
- Agree to act lawfully, not behave in a misleading or fraudulent way

**Acceptable Use / Rules of Engagement**
- Treat others with respect and kindness
- No hate speech, extremist content, or illegal material
- No adult content
- Family disputes belong elsewhere (maintain the casual tone from existing page)
- Fyli reserves the right to remove users who violate these rules
- Illegal content will be reported to authorities

**Your Content**
- You own your memories and content
- By posting, you grant Fyli a license to store, display, and serve your content to the people you share it with
- Fyli will not sell your content or use it for advertising
- When you use AI-powered features (e.g., content suggestions, writing assistance), Fyli may send relevant data to third-party AI platforms to process your request — this only happens when you initiate it

**Third-Party Authentication**
- If you sign in with Google, Fyli receives only your name, email, and Google account identifier
- Fyli does not access your Google Calendar, Gmail, Drive, or any other Google services beyond basic sign-in

**Data & Reliability**
- Fyli endeavors to protect your data with redundancies, but cannot guarantee against data loss
- Fyli is provided "as is" without warranties

**Dispute Resolution**
- Any dispute will be resolved by binding arbitration

**Changes to Terms**
- Fyli may update these terms; continued use constitutes acceptance
- Material changes will be communicated via the app

**Contact**
- How to reach Fyli with questions about the terms

#### 1.3 Footer
- "Last updated: [date]"
- Link to Privacy Policy

### 2. Privacy Policy Page

#### 2.1 Route & Access
- Public route: `/privacy`
- No authentication required
- Uses the `PublicLayout`
- Page title: "Privacy Policy"

#### 2.2 Content Sections (Google OAuth Compliance)
Per [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy) and [Google's verification requirements](https://support.google.com/cloud/answer/13464321), the privacy policy **must** disclose:

**What Data We Collect**
- Account information: name, email address
- Google account data (when using Google Sign-In): name, email, Google account identifier (subject ID)
- Content you create: memories, answers to questions, albums
- Usage data: how you interact with the app (pages visited, features used)

**How We Use Your Data**
- To provide and operate the Fyli service
- To authenticate your identity
- To display your content to you and the people you choose to share with
- To improve the app experience
- Limited use disclosure: Google user data is only used for providing and improving user-facing features within Fyli

**How We Store Your Data**
- Data is stored on secure servers
- Passwords are not stored (authentication is via magic links and Google Sign-In)
- Industry-standard security practices

**What We Share (and Don't)**
- **We do not sell your data** to advertisers, data brokers, or any third parties
- **We do not use your data for advertising**, retargeting, or interest-based profiling
- **We do not transfer Google user data** to advertising platforms or data brokers
- **When you use AI features**, we may send your data to third-party AI platforms (e.g., to generate content or provide suggestions) — this only happens when you initiate an AI-powered action, and only the data relevant to your request is shared
- Content you choose to share with other Fyli users is visible to those users — Fyli cannot control what others do with shared content
- We may disclose data if required by law

**Google User Data — Limited Use Disclosure**
This section is specifically required by Google's API Services User Data Policy:
- Fyli's use of Google user data (name, email, account ID received via Google Sign-In) is limited to providing and improving the Fyli service
- Fyli does not use Google user data for serving advertisements
- Fyli does not transfer Google user data to third parties except as necessary to provide the service, as explicitly requested by the user, or as required by law
- Fyli does not use Google user data for purposes unrelated to the Fyli service
- Fyli complies with the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements

**Third-Party Services**
- Google Sign-In (Google Identity Services) — for authentication only
- Third-party AI platforms — used to generate content and provide suggestions when you use AI-powered features; only data relevant to your request is sent, and only when you initiate the action

**Data Retention & Deletion**
- Your data is retained as long as your account is active
- You can request deletion of your account and associated data
- How to request deletion (contact information or in-app mechanism)

**Children's Privacy**
- Fyli is not directed at children under 13
- We do not knowingly collect data from children under 13

**Cookies & Local Storage**
- Authentication tokens stored in local storage
- Any cookies used (if applicable)

**Changes to This Policy**
- How users will be notified of changes
- Continued use constitutes acceptance

**Contact**
- How to reach Fyli with privacy questions

#### 2.3 Footer
- "Last updated: [date]"
- Link to Terms of Service

### 3. Registration Page Link

#### 3.1 Terms Checkbox Update
- The existing "I agree to the Terms of Service" checkbox text on the register page should link "Terms of Service" to `/terms` (opens in new tab)
- Add "and Privacy Policy" linking to `/privacy` (opens in new tab)
- Updated text: "I agree to the [Terms of Service](/terms) and [Privacy Policy](/privacy)"

### 4. Cross-Linking

#### 4.1 Navigation Between Pages
- Terms page links to Privacy Policy at the bottom
- Privacy page links to Terms of Service at the bottom

#### 4.2 Login/Register Pages
- Add a small footer link to Terms and Privacy on both login and register pages (muted text, below the form)

## UI/UX Requirements

### Page Layout
- Use `PublicLayout` (consistent with login/register pages)
- Max-width content container for readability (matching PublicLayout's centered container)
- Clean typography — section headers, readable paragraphs
- No sidebar or complex navigation needed

### Terms of Service Page
```
┌─────────────────────────────────────────────────┐
│              fyli                                │
│                                                  │
│  Terms of Service                                │
│                                                  │
│  [Warm intro paragraph matching Fyli's voice]    │
│                                                  │
│  What Fyli Is                                    │
│  [description]                                   │
│                                                  │
│  Your Agreement                                  │
│  [terms]                                         │
│                                                  │
│  Rules of Engagement                             │
│  [acceptable use]                                │
│                                                  │
│  Your Content                                    │
│  [content ownership]                             │
│                                                  │
│  [... more sections ...]                         │
│                                                  │
│  Last updated: February 2026                     │
│  Privacy Policy                                  │
└─────────────────────────────────────────────────┘
```

### Privacy Policy Page
```
┌─────────────────────────────────────────────────┐
│              fyli                                │
│                                                  │
│  Privacy Policy                                  │
│                                                  │
│  [Warm intro — "Your privacy matters to us"]     │
│                                                  │
│  What Data We Collect                            │
│  [list of data types]                            │
│                                                  │
│  How We Use Your Data                            │
│  [usage descriptions]                            │
│                                                  │
│  What We Share (and Don't)                       │
│  [no selling, no ads]                            │
│                                                  │
│  Google User Data                                │
│  [limited use disclosure]                        │
│                                                  │
│  [... more sections ...]                         │
│                                                  │
│  Last updated: February 2026                     │
│  Terms of Service                                │
└─────────────────────────────────────────────────┘
```

### Mobile Responsiveness
- Content should be fully readable on mobile devices
- No horizontal scrolling
- Adequate touch targets for links

## Technical Considerations

### Routing
- Two new routes in the Vue Router config (`/terms` and `/privacy`)
- Both use `meta: { layout: 'public' }` — no auth required
- Lazy-loaded components

### Google Cloud Console Configuration
- After deployment, the Terms URL (`https://app.fyli.com/terms`) and Privacy URL (`https://app.fyli.com/privacy`) must be entered in the Google Cloud Console:
  - OAuth consent screen → App information → Terms of service link
  - OAuth consent screen → App information → Privacy policy link
- Both URLs must be on the verified domain

### Static Content
- Content is hardcoded in the Vue components (no CMS or API needed)
- Future consideration: if legal content needs frequent updates, could move to markdown files loaded at build time

### SEO / Accessibility
- Proper heading hierarchy (h1 for page title, h2 for sections)
- Semantic HTML for screen readers
- Meta tags for page title

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Google OAuth verification | App passes Google's brand verification with terms + privacy links | Pass |
| Page accessibility | Both pages load without auth and are publicly crawlable | 100% |
| Registration link | Terms checkbox on register page links to live terms page | Functional |

## Out of Scope (Future Considerations)

- Cookie consent banner (not needed currently — no third-party tracking cookies)
- GDPR-specific compliance page (can be added if Fyli expands to EU)
- In-app account deletion flow (currently manual via contact — could be a future feature)
- Version history of terms/privacy changes
- Multi-language support for legal pages

## Implementation Phases

### Phase 1: Vue Components & Routing
- Create `TermsView.vue` and `PrivacyView.vue` components with full content
- Add `/terms` and `/privacy` routes to the router
- Both routes use `PublicLayout`, no auth required

### Phase 2: Registration Page Updates
- Update the register page terms checkbox to link to `/terms` and `/privacy`
- Add footer links to terms and privacy on login and register pages

### Phase 3: Google Console Configuration
- Deploy to production
- Update Google Cloud Console OAuth consent screen with terms and privacy URLs
- Submit for brand verification if not already done

## Open Questions

1. What email or contact method should be listed for terms/privacy inquiries? (e.g., privacy@fyli.com, or a general contact form?)
2. Does Fyli currently have an account deletion process, and if so, how should users initiate it? (This must be disclosed in the privacy policy)
3. What is the production domain — `app.fyli.com` or `fyli.com`? (Needed for Google Console configuration — terms and privacy must be on the verified domain)

---

*Document Version: 1.0*
*Created: 2026-02-09*
*Status: Draft*
