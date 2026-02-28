# Product Requirements Document: Marketing Site Content Refresh

## Overview

The fyli marketing site (fyli-html) is significantly out of date. It markets features that have been renamed or removed (Albums, Timelines) and doesn't mention core capabilities that now define the product (Storylines, Questions, AI-powered writing assist, share links, date precision). This PRD defines a content refresh to align the marketing site with the current product, shift messaging toward the busy-parent persona, and remove the pricing section in favor of driving signups directly.

## Problem Statement

A busy parent discovers fyli through a recommendation or search. They land on fyli.com and see messaging about "Share, Discover, Preserve Stories" with screenshots of Albums and Timelines. When they sign up, they find a different product — one with Storylines, Questions, smart writing tools, and share links. This disconnect erodes trust and fails to communicate fyli's actual value: helping busy parents capture and share the moments that matter, even when time is short.

## Goals

1. **Accurate product representation** — Every feature and screenshot on the marketing site reflects the current product
2. **Parent-led, family-inclusive positioning** — Lead with the busy parent's pain (no time, guilt about missing moments) while making clear the whole family benefits
3. **Remove friction to signup** — Drop the pricing section; drive users to create a free account and experience the product
4. **Subtly communicate smart features** — Highlight capabilities like "we help you find the words" and "get the stories only your family knows" without using AI/ML jargon

## User Stories

### Visitor Experience
1. As a busy parent visiting fyli.com, I want to immediately understand that fyli helps me capture family memories even when I'm short on time, so that I feel this product was built for someone like me
2. As a visitor, I want to see the actual features I'll use (Storylines, Questions, share links) so that I know what to expect when I sign up
3. As a visitor, I want a clear, single call-to-action to get started for free so that I don't get bogged down comparing plans
4. As a grandparent or extended family member visiting fyli.com, I want to understand how I fit into the picture so that I feel welcomed, not excluded by parent-focused messaging

### Content Accuracy
5. As a returning visitor, I want the site to reflect the product I actually use so that I feel confident recommending fyli to friends
6. As a visitor evaluating fyli, I want to see social proof from real users so that I trust the product delivers on its promises

## Current State Analysis

### What the site says vs. what the product does

| Marketing Site (Current) | Actual Product | Gap |
|--------------------------|---------------|-----|
| "Discover, Share, Preserve Stories" | Memory capture, Storylines, Questions, Sharing | Messaging is generic; misses the "busy parent" angle |
| Albums (People, Places, Pets) | Storylines (flexible themed collections) | Feature renamed and redesigned |
| Timelines | Storylines | Feature renamed |
| "Intriguing Fyli questions" | Questions feature with custom question sets, recipient tracking, response collection | Undersells a major feature |
| Not mentioned | AI writing assist ("Help me write") | Missing entirely |
| Not mentioned | Share links (one-tap public sharing) | Missing entirely |
| Not mentioned | Date precision (exact, month, year, decade) | Missing entirely |
| Not mentioned | Comments & reactions | Missing entirely |
| Not mentioned | Google sign-in | Missing entirely |
| Individual & Family pricing plans | Free tier focus | Pricing section should be removed |
| Generic family photos | — | Need updated visuals showing actual product |

## Feature Requirements

### 1. Hero Section Update

#### 1.1 New Headline & Subheadline
- **Replace** animated "Share, Discover, Preserve Stories" with a single, clear headline that speaks to the busy parent
- Suggested direction: "Capture the moments that matter — before they slip away"
- Subheadline should acknowledge the tension: time is short, but these moments are worth protecting
- **Keep** the animated typing effect if desired, but cycle through parent-relevant phrases (e.g., "first steps", "bedtime stories", "Sunday mornings", "family dinners")

#### 1.2 Single CTA
- Replace dual "Sign In / Get Started" buttons with one prominent "Get Started Free" button
- Add a subtle "Already have an account? Sign in" text link below
- CTA links to `app.fyli.com/register`

#### 1.3 Hero Visual
- Update phone mockup to show the current product UI (memory stream or memory creation)
- Consider showing a memory being created in under 60 seconds to reinforce "even when you're busy"

### 2. Value Proposition Section (Replace "About")

#### 2.1 Lead with the Problem
- Open with empathy: busy parents know these moments matter but struggle to capture them
- Position fyli as the solution: private, simple, built for real life

#### 2.2 Three Pillars (Updated)
Replace "Discover, Share, Preserve" with pillars that match the actual product:

**Pillar 1: Capture**
- Create a memory in under 60 seconds
- Add photos, videos, and flexible dates (even "sometime in the '90s" works)
- Smart writing tools help you find the words when you're short on time
- Direction: "You don't need to be a writer. Jot down a few words and we'll help you tell the story."

**Pillar 2: Connect**
- Ask your family the questions that spark real stories
- Send prompts to parents, grandparents, siblings — collect responses in one place
- Share individual memories with a link — no account required for the recipient
- Direction: "Get the stories only your family knows — before they're lost."

**Pillar 3: Preserve**
- Group memories into Storylines — "Dad's childhood", "Our first year", "Family recipes"
- Invite family members to contribute to shared Storylines
- Comments and reactions keep the conversation going
- Direction: "Your family's story, organized the way you want."

### 3. How It Works Section (Update)

#### 3.1 Simplified Steps
Update the 3-step flow to reflect actual onboarding:

1. **Sign up in seconds** — Create a free account with email or Google
2. **Capture your first memory** — Write it, snap a photo, or just jot a few words — we'll help you polish it
3. **Invite your family** — Share a memory or send a question to get the stories flowing

### 4. Features Section (New Content)

#### 4.1 Key Features to Highlight
Present 4-6 feature cards with icons and short descriptions:

- **Memories** — Write, photograph, or video meaningful moments. Add dates as precise or fuzzy as you want.
- **Questions** — Prompt family members to share their stories. Track who's responded and send gentle reminders.
- **Storylines** — Curate themed collections. Invite others to contribute. Build your family's narrative together.
- **Share Links** — Share any memory with a single link. Recipients don't need an account.
- **Smart Writing** — Stuck on how to say it? We'll help you find the words while keeping your voice. (Subtle AI reference)
- **Private by Design** — You control exactly who sees what. This isn't social media — it's your family's private space.

#### 4.2 Visual Treatment
- Each feature card should include an icon (use Material Design Icons to match the product)
- Consider showing small product screenshots or illustrations for the top 3 features

### 5. Social Proof Section (Update Testimonials)

#### 5.1 Updated Testimonials
- Keep the testimonial slider format
- Update quotes to reflect current product experience (Storylines, Questions, writing assist)
- If real updated testimonials aren't available, remove placeholder quotes and add them when available

#### 5.2 Optional: Stats or Trust Signals
- Consider adding simple stats if available (e.g., "X memories captured", "X families connected")
- Only include if real data is available — no fabricated numbers

### 6. Security Section (Refresh)

#### 6.1 Privacy Messaging
- Keep the privacy/security section but refresh copy to emphasize:
  - Private by default — not a social network
  - You own your data
  - Fine-grained sharing controls (share with everyone, specific people, or keep private)
  - No ads, no data selling

### 7. Final CTA Section (Update)

#### 7.1 Closing CTA
- Strong closing message reinforcing the parent angle
- Suggested direction: "Your family's stories are worth keeping. Start preserving them today."
- Single "Get Started Free" button
- No pricing, no plan comparison

### 8. Remove Pricing Section

#### 8.1 Complete Removal
- Remove the entire subscription/pricing section
- Remove any references to "Individual Plan" or "Family Plan" from the site
- Users discover plans in-app after signing up

### 9. Navigation & Footer Updates

#### 9.1 Header Navigation
- Simplify navigation links to match available sections
- Keep: Features, How It Works, (link to app for Sign In)
- Remove: any pricing/plans links

#### 9.2 Footer
- Update copyright year
- Keep links to Terms of Service and Privacy Policy
- Update social media links if needed
- Remove any stale links

### 10. Research Citations (Keep/Update)

#### 10.1 Research Backing
- Keep the research-backed claims about family storytelling benefits (Emory University, NIH)
- These are strong differentiators — validate that links still work
- Integrate research references naturally into the value proposition section rather than as a standalone callout

## Content Guidelines

### Tone & Voice
- **Warm but not saccharine** — Acknowledge the real tension of being a busy parent without being preachy
- **Confident but not boastful** — Let the product speak for itself
- **Inclusive** — "Family" means whatever it means to the user (nuclear, extended, chosen)
- **Action-oriented** — Every section should move the visitor toward signing up

### Language Rules
- **DO:** "capture moments", "your family's stories", "the people who matter", "in under 60 seconds"
- **DO:** "we help you find the words", "smart tools", "works the way your memory works"
- **DON'T:** "AI-powered", "machine learning", "algorithm", "powered by"
- **DON'T:** "social media", "feed", "followers", "likes" (use "reactions" or "thanks" instead)
- **DON'T:** "free trial" (it's just free to start)

## UI/UX Requirements

### Visual Updates
- Update all product screenshots/mockups to show current fyli-fe-v2 UI
- Maintain existing color scheme (primary green #56c596, dark blue #192038)
- Keep responsive, mobile-first design
- Refresh imagery to show diverse families in everyday moments (not posed studio shots)

### Interaction Updates
- All CTAs should link to `app.fyli.com/register` (or appropriate route)
- "Sign In" link should go to `app.fyli.com/login`
- Ensure all external research links still work
- Remove any dead links to deprecated features

## Technical Considerations

### Existing Tech Stack (No Changes)
- Gulp 4 build system
- Sass for styling
- HTML templates with `gulp-file-include`
- jQuery + Swiper.js + Typer.js
- No framework migration needed — this is a content refresh

### Template Changes
- Update content in existing template files under `src/templates/`
- Update Sass variables only if color palette changes (not expected)
- Replace image assets in `src/images/` as needed
- No new JavaScript functionality required

### SEO Considerations
- Update `<title>` and `<meta description>` tags to reflect new messaging
- Ensure Open Graph tags are updated for social sharing
- Keep or improve existing URL structure (no URL changes needed for a single-page site)

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Signup conversion rate | % of unique visitors who click "Get Started Free" | >5% (baseline TBD) |
| Bounce rate | % of visitors who leave without scrolling | <50% |
| Time on page | Average time spent on marketing site | >45 seconds |
| Feature comprehension | Post-signup survey: "Did the website accurately describe the product?" | >80% "Yes" |

## Out of Scope (Future Considerations)

- Blog or content marketing section
- Video demo or product walkthrough
- Multi-page site (About Us, Blog, Help Center)
- Localization / multi-language support
- Integration with analytics tools (separate effort)
- A/B testing infrastructure
- New visual design / complete redesign (Phase 2 if needed)

## Implementation Phases

### Phase 1: Content Updates
- Update hero headline, subheadline, and CTA
- Rewrite value proposition section (Capture, Connect, Organize pillars)
- Update How It Works steps
- Rewrite feature descriptions to match current product
- Remove pricing section entirely
- Update navigation and footer

### Phase 2: Visual Updates
- Replace product mockup screenshots with current UI
- Update feature section imagery
- Refresh hero image/mockup
- Update testimonials with current product references

### Phase 3: Polish & Launch
- SEO meta tag updates
- Verify all links work (research citations, app links, social media)
- Cross-browser and mobile testing
- Deploy updated site

## Open Questions

1. Do we have updated product screenshots ready, or do we need to create them?
  Answer: create them
2. Are there real, recent testimonials we can use, or should we remove the testimonial section until we collect new ones?
  Answer: update existing to be inline with current product - they are from friends and family and we can get permission
3. What is the current URL for the production app — is it still `app.fyli.com`?
  Answer: yes
4. Are there analytics currently on the site (Google Analytics, etc.) that we need to preserve?
  Answer: no
5. Should we add a "For Families" or "For Grandparents" sub-page in a future phase?
  Answer: no

---

*Document Version: 1.0*
*Created: 2026-02-24*
*Status: Draft*
