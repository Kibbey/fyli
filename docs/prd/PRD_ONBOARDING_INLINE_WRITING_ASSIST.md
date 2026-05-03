# Product Requirements Document: Onboarding Inline Writing Assist

## Overview

Move AI writing assistance into the onboarding Quick Capture step so new users discover "Help me write" while they're actively writing their first memory — not after they've already finished and clicked Next. This eliminates the separate forced AI Polish step and teaches users the same inline writing assist pattern they'll use throughout the app.

## Problem Statement

A new user picks a prompt, lands on the Quick Capture step, and stares at a text area with no indication that AI can help them write. If they're struggling to articulate a memory — common for busy parents typing on a phone — they have no idea help exists. They either push through with something they're not proud of or give up. Only after clicking "Next" do they discover AI can polish their text, but by then they've already done the hard work alone.

This is backwards. The moment a user needs help is *while they're writing*, not after they've finished. The current flow buries Fyli's most differentiating feature behind a step the user has to complete unaided first.

## Goals

1. **Surface AI help at the moment of need** — Users see "Help me write" while they're in the text area, exactly when struggling would occur
2. **Teach the real pattern** — The onboarding experience uses the same inline writing assist UX as CreateMemoryView, so users learn how it works everywhere
3. **Simplify the flow** — Remove the separate AI Polish step, reducing the onboarding from 5 steps to 4 (Welcome → Prompt → Capture → Celebrate)

## User Stories

### Writing Assistance During Onboarding
1. As a new user creating my first memory, I want to see that AI writing help is available while I'm typing so that I can ask for help if I'm struggling to find the right words
2. As a new user, I want the AI writing help in onboarding to work the same way it does everywhere else in the app so that I don't have to learn a different pattern later
3. As a new user who writes well on my own, I want to skip AI help entirely and just save my memory so that the flow doesn't force me through an unnecessary step

## Feature Requirements

### 1. Add "Help me write" to Quick Capture Step

#### 1.1 Button Placement
- Add the existing `WritingAssistButton` component below the text area in the Quick Capture step (step 2)
- Position it the same way as in `CreateMemoryView` — directly below the textarea, above the file attachment option
- Button is disabled when the text area is empty, with the same "Type something first" tooltip behavior

#### 1.2 Inline Polish Behavior
- Uses the existing `useWritingAssist` composable — same API call, same state management
- When the user taps "Help me write":
  - The text area content is replaced with the polished version
  - The text area gets the review highlight background (`review-highlight` class)
  - Accept/Undo buttons replace the "Help me write" button
  - "Suggested version" label appears
- Accept: keeps the polished text, returns to normal editing state
- Undo: reverts to the original text, returns to normal editing state
- The user can also directly edit the polished text in the textarea (implicit accept)

#### 1.3 "Next" Button Behavior Change
- "Next" now saves the memory directly (no longer triggers forced AI polish)
- After clicking Next: create the drop → upload files → mark onboarding complete → show Celebrate step
- The `assisted` flag on the created drop is set based on whether the user accepted a polished version

### 2. Remove the Forced AI Polish Step (Step 3)

#### 2.1 Step Removal
- Remove the entire AI Polish step (previously step 3) from `FirstMomentView`
- The Celebrate step (previously step 4) becomes step 3
- Step dots update: 4 total steps becomes 3 (Prompt → Capture → Celebrate), or remove step dots entirely since the flow is so short

#### 2.2 Flow Summary

**Before (current):**
```
Step 0: Welcome → Step 1: Prompt → Step 2: Capture → Step 3: AI Polish → Step 4: Celebrate
```

**After:**
```
Step 0: Welcome → Step 1: Prompt → Step 2: Capture (with Help me write) → Step 3: Celebrate
```

### 3. Preserve All Other Behavior

- File attachment (photo/video) remains in the capture step
- Selected prompt still sets the placeholder text
- Minimum 10 character requirement remains
- Onboarding state updates (`completeFirstMoment`) remain unchanged
- Memory is prepended to stream on save
- All backend endpoints and services remain unchanged

## UI/UX Requirements

### Quick Capture Step Layout (top to bottom)
1. Heading: "Capture your moment"
2. Textarea with prompt-based placeholder
3. **WritingAssistButton** (new — "Help me write" / Accept+Undo)
4. Polish error alert (if any)
5. File attachment button + thumbnails
6. Error alert (if any)
7. Back / Next buttons

### Review State
- Textarea background changes to `var(--fyli-primary-light)` with `var(--fyli-primary)` border (matching `review-highlight` class from CreateMemoryView)
- WritingAssistButton shows Accept/Undo in place of "Help me write"
- "Suggested version" label visible
- The "Next" button remains functional during review mode — user can save without explicitly accepting

### Step Dots
- Update from 4 dots to 3 (steps 1-3 visible: Prompt, Capture, Celebrate)
- Step 0 (Welcome) still has no dots, as before

## Technical Considerations

### Frontend Only
- This is a frontend-only change to `FirstMomentView.vue`
- No backend changes required — all APIs (writing assist, create drop, onboarding state) already exist
- Reuses existing `useWritingAssist` composable and `WritingAssistButton` component

### Changes Needed
- **`FirstMomentView.vue`**: Import and wire up `useWritingAssist` composable and `WritingAssistButton` component; remove step 3 (AI Polish); update step numbering; update `saveMemory` to be called from step 2's "Next" button

### No Changes Needed
- `useWritingAssist.ts` — reused as-is
- `WritingAssistButton.vue` — reused as-is
- `writingAssistApi.ts` — reused as-is
- `onboardingApi.ts` — reused as-is
- All backend services and endpoints

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Writing Assist Discovery | % of onboarding users who see and recognize the "Help me write" button | >90% (it's visible on the page) |
| Assist Usage in Onboarding | % of new users who tap "Help me write" during their first memory | >30% |
| First Memory Completion | % of new users who complete the First Moment flow | >80% (maintain current target) |
| Time to First Memory | Time from signup to first memory saved | <60 seconds (improved from <90s) |

## Out of Scope (Future Considerations)

- Animated tooltip or callout pointing to the "Help me write" button on first view
- Different prompt for onboarding vs. regular writing assist (e.g., more encouraging tone)
- Showing a brief explainer of what "Help me write" does before the user taps it
- Voice-to-text as an alternative capture method during onboarding

## Implementation Phases

### Phase 1: Single Phase (Frontend Only)
- Import `useWritingAssist` and `WritingAssistButton` into `FirstMomentView.vue`
- Add `WritingAssistButton` to step 2 (Quick Capture) below the textarea
- Wire up polish/accept/undo handlers (same pattern as `CreateMemoryView`)
- Move save logic from step 3 into the step 2 "Next" button
- Remove step 3 (AI Polish step) template and script code
- Update step numbering (Celebrate becomes step 3)
- Update step dots from 4 to 3
- Add `review-highlight` CSS class for textarea review state
- Update tests for `FirstMomentView` to reflect the new flow

## Open Questions

None — this is a straightforward frontend restructuring using existing components.

---

*Document Version: 1.0*
*Created: 2026-03-09*
*Status: Draft*
