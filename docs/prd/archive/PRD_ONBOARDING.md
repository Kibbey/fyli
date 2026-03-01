# Product Requirements Document: Onboarding Experience

## Overview

New users sign up for Fyli and land on an empty stream with no guidance, no inspiration, and no understanding of what Fyli can do. This PRD defines a two-phase onboarding experience: a guided "First Moment" flow that demonstrates Fyli's core value (AI-assisted memory capture) in under 60 seconds, followed by three optional missions that introduce Storylines, Questions, and Sharing over time.

## Problem Statement

A busy parent hears about Fyli, signs up, and sees: "No memories yet. Create your first one!" They stare at a blank text box with date pickers, storyline selectors, and sharing controls they don't understand. They have 2 minutes before their kid needs a snack. They close the app and never come back.

The marketing site promises "Capture the moments that matter — before they slip away" but the product doesn't carry that feeling forward. There's no warmth, no guidance, and no demonstration of the AI writing assist that makes Fyli different from a notes app.

## Goals

1. **Eliminate the blank page** — Every new user leaves onboarding with at least one real memory in their stream
2. **Demonstrate core value immediately** — Show the AI writing assist as the very first feature interaction
3. **Introduce key features without forcing them** — Missions guide users to Storylines, Questions, and Sharing at their own pace
4. **Respect the user's time and autonomy** — Everything is completable in under 60 seconds, and missions are fully optional and dismissible

## Core Principle

**The user is in control.** Missions are suggestions, not gates. Users can dismiss them, do them out of order, or ignore them entirely. No feature is locked behind onboarding completion. The app is fully functional from the moment the first memory is saved.

## User Stories

### First Moment (Phase 1)
1. As a new user, I want to be guided through creating my first memory so that I don't face a blank page with no context
2. As a busy parent, I want to pick from relatable prompts so that I don't have to think about what to write
3. As a new user, I want to see my rough notes polished by AI so that I immediately understand what makes Fyli special
4. As a user who signed up via a share link, I want the same guided first moment so that I understand the product before exploring what was shared with me

### Missions (Phase 2)
5. As a new user, I want optional guidance on what to try next so that I can discover features at my own pace
6. As a user, I want to dismiss the mission card so that it doesn't distract me when I want to use the app freely
7. As a user who dismissed missions, I want to resume them later so that I can come back to them when I'm ready
8. As a user, I want my mission progress to persist across devices so that I don't repeat steps

## Feature Requirements

### 1. First Moment Flow (Phase 1)

This flow activates for every new user after sign-up (including share link sign-ups). It replaces the current empty stream landing.

#### 1.1 Welcome Screen
- Full-screen, minimal layout — no app nav, no sidebar, no chrome
- Headline: "You're busy. We get it. Let's capture one moment in under 60 seconds."
- Single CTA button: "Let's go"
- Uses brand primary color (#56c596) for the CTA

#### 1.2 Prompt Selection
- Headline: "Pick a prompt, or write your own:"
- Four prompt cards displayed as tappable options:
  - "Something funny your kid said recently"
  - "A meal your family loved"
  - "A moment you want to remember from this week"
  - "Write your own"
- Selecting a prompt or "Write your own" advances to the next step
- The selected prompt becomes placeholder/helper text in the capture step

#### 1.3 Quick Capture
- Simple, focused text area — not the full memory creation form
- Placeholder text matches the selected prompt (e.g., "My daughter told me that...")
- If "Write your own" was selected, placeholder is "What moment do you want to remember?"
- Optional file attachment — single button that accepts photo or video (not the full media picker)
- No date picker, no storyline picker, no sharing controls, no visibility selector
- Date defaults to today
- CTA: "Next" (disabled until text is entered)
- Minimum text length: 10 characters

#### 1.4 AI Polish
- Split view: user's original text on top, AI-polished version below
- Label above original: "What you wrote"
- Label above polished: "Polished by Fyli"
- Three action buttons:
  - "Use polished version" (primary)
  - "Keep my original" (outline/secondary)
  - "Edit" (text link — opens the polished version in an editable text area)
- The AI polish uses the existing writing assist backend (same endpoint/logic as "Help me write")

#### 1.5 Save & Celebrate
- Memory is saved via the existing create memory API
- Brief, warm celebration: gentle animation + message "Your first moment is safe."
- CTA: "See my memories" — navigates to StreamView
- The stream now has their first memory visible — no more empty state

### 2. Getting Started Missions (Phase 2)

After Phase 1 completes, the user lands on StreamView with a mission card at the top.

#### 2.1 Mission Card Component
- Positioned at the top of the stream, above the memory list
- Shows the current suggested mission (lowest-numbered incomplete mission)
- Displays progress: "Getting Started — 0 of 3 complete"
- Each mission shows:
  - Icon (Material Design Icon relevant to the feature)
  - Title (e.g., "Start a Storyline")
  - Description (one line explaining the benefit)
  - CTA button linking to the relevant feature
- Dismissible with an "x" button — card hides immediately
- When dismissed, a subtle "Resume getting started" text link appears at the top of the stream
- Clicking "Resume getting started" shows the mission card again

#### 2.2 Mission Definitions

**Mission 1: Start a Storyline**
- Icon: `mdi-book-open-page-variant`
- Title: "Start a Storyline"
- Description: "Organize memories around a person, place, or theme"
- CTA: "Create Storyline" — navigates to storyline creation
- Completion trigger: User creates any storyline
- Completion message: "Now you can curate memories for the people who matter most."

**Mission 2: Ask a Question**
- Icon: `mdi-comment-question-outline`
- Title: "Ask a Question"
- Description: "Ask someone to share a story — they don't need an account"
- CTA: "Ask a Question" — navigates to question creation
- Completion trigger: User creates any question
- Completion message: "When they answer, their story becomes a memory in your collection."

**Mission 3: Share a Memory**
- Icon: `mdi-share-variant-outline`
- Title: "Share a Memory"
- Description: "Send a memory to someone with a private link"
- CTA: "Share a Memory" — navigates to the user's first memory with the share flow open
- Completion trigger: User generates any share link
- Completion message: "You're all set. Capture moments as they happen — we'll be here."

#### 2.3 Mission Behavior
- Missions are **not sequential** — the card suggests the next incomplete mission, but users can complete features in any order through normal app usage
- If a user creates a storyline through the nav (not via the mission CTA), the mission still completes
- Completion triggers are based on the action happening, not on how the user got there
- After all 3 missions are complete, the card shows a final message: "You're all set. Capture moments as they happen — we'll be here." The card auto-dismisses after 5 seconds or on tap.
- Missions auto-expire after 30 days — the card stops showing regardless of completion state
- The "Resume getting started" link also disappears after 30 days or full completion

#### 2.4 Mission State Tracking (Server-Side)
- Mission progress is persisted server-side so it syncs across devices
- State is returned as part of the user API response
- State includes: which missions are complete, whether missions were dismissed, and the user's account creation date (for 30-day expiry calculation)

## Data Model

### OnboardingState (new JSON field on UserProfile)

```
OnboardingState {
  firstMomentCompletedAt: DateTime?        // null if Phase 1 not complete
  missionsDismissed: boolean               // true if user dismissed the card
  completedMissions: string[]              // e.g., ["storyline", "question", "share"]
}
```

This is stored as a JSON string column on the `UserProfile` entity, similar to how `CurrentNotifications` works. This avoids creating a new table for simple state tracking.

### UserModel Extension

```
UserModel (existing, add field) {
  ...existing fields...
  onboardingState: OnboardingState?        // null for users created before this feature
}
```

For users created before this feature launches, `onboardingState` is null and no mission card is shown. Onboarding only applies to new sign-ups.

## UI/UX Requirements

### First Moment Flow
- Full-screen, distraction-free — no app navigation visible during the flow
- Clean white background, centered content, generous whitespace
- Progress indicator: subtle step dots (not numbered steps — reduces pressure)
- All text is warm and conversational, not instructional
- AI polish split view should visually highlight the difference (e.g., polished version in a card with slight elevation)
- Mobile-first layout — all steps must work on phone screens

### Mission Card
- Card style: Bootstrap card with left border accent in brand primary (#56c596)
- Progress text: muted/secondary color, small font
- CTA button: primary (brand green)
- Dismiss "x": top-right corner, muted color, no confirmation dialog
- Completion celebration: inline animation within the card AND a toast notification (both)
- "Resume getting started" link: muted text, positioned at the top of the stream where the card was

### Responsive Behavior
- First Moment flow: single column, max-width 600px, centered
- Mission card: full-width within the stream container (matches memory card width)

## Technical Considerations

### Backend
- Add `OnboardingState` JSON column to `UserProfile` entity
- Add `OnboardingState` to `UserModel` response
- New endpoint: `PUT /api/users/onboarding` to update mission state (dismiss, complete mission)
- Completion triggers (storyline created, question created, share link generated) should update onboarding state in their respective services
- The existing AI writing assist endpoint is reused for the polish step — no new AI integration needed

### Frontend
- Replace or extend existing onboarding views (`FirstMemoryView`, `FirstShareView`, `WelcomeView`)
- New component: `MissionCard.vue` for the stream overlay
- Onboarding state should be stored in the user Pinia store alongside the existing user model
- Router guard: if `onboardingState.firstMomentCompletedAt` is null, redirect to the First Moment flow

### Migration
- Existing users (created before feature launch): `OnboardingState` is null, no onboarding shown
- New users: `OnboardingState` initialized with empty state on account creation
- The existing "Hello World" drop creation (`AddHelloWorldDrop`) should be removed — the First Moment flow replaces it
- Keep the existing default group creation (`AddHelloWorldNetworks` — "Family", "Extended Family") — only the sample drop is removed

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| First Memory Completion | % of new users who complete the First Moment flow | >80% |
| AI Polish Acceptance | % of users who choose the polished version over their original | >50% |
| Mission 1 Completion | % of new users who create a storyline within 14 days | >40% |
| Mission 2 Completion | % of new users who send a question within 14 days | >30% |
| Mission 3 Completion | % of new users who share a memory within 14 days | >35% |
| Day-7 Retention | % of new users who return to the app within 7 days of signup | Improvement over baseline |
| Time to First Memory | Time from signup to first memory saved | <90 seconds |

## Out of Scope (Future Considerations)

- Personalized prompts based on user profile (e.g., number of kids, ages)
- Onboarding for specific entry points (e.g., invited to a storyline vs. organic signup)
- Re-engagement missions after initial 3 (e.g., "Try voice capture", "Add a photo to a memory")
- A/B testing different prompt options
- Onboarding analytics dashboard
- Custom welcome video or animation

## Implementation Phases

### Phase 1: First Moment Flow
- Backend: Add `OnboardingState` to `UserProfile`, migration script, update `UserModel`
- Backend: Router/guard logic for onboarding redirect
- Frontend: Welcome screen, prompt selection, quick capture, AI polish, save & celebrate
- Frontend: Router guard to redirect new users to onboarding
- Remove existing `AddHelloWorldDrop` in favor of the guided first memory

### Phase 2: Getting Started Missions
- Backend: `PUT /api/users/onboarding` endpoint for state updates
- Backend: Completion triggers in StorylineService, QuestionService, ShareLinkService
- Frontend: `MissionCard.vue` component
- Frontend: Mission state management in user store
- Frontend: "Resume getting started" link behavior

### Phase 3: Polish & Measurement
- Analytics events for each onboarding step
- Completion message animations
- 30-day auto-expiry logic
- Edge case handling (account deletion, re-registration)

## Resolved Questions

1. **Prompt copy** — Ship with current prompts and iterate based on usage data
2. **File in onboarding** — Include optional file attachment (photo or video) in the quick capture step
3. **Hello World removal** — Remove the sample drop but keep the default groups ("Family", "Extended Family")
4. **Mission completion toast** — Both: inline animation in the card AND a toast notification

---

*Document Version: 1.0*
*Created: 2026-02-28*
*Status: Draft*
