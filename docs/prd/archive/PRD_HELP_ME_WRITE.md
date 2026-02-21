# Product Requirements Document: Help Me Write

## Overview

"Help me write" is an always-available writing assistant that transforms rough notes, bullet points, or messy drafts into polished, well-written memories. It appears on every writing surface in the app as a subtle but obvious option, letting users opt in when they want help without ever feeling pressured. The assistant learns the user's voice from their recent memories so polished output sounds like *them*, not a robot.

## Problem Statement

Capturing a meaningful memory shouldn't require being a good writer. Many users know *what* they want to say but struggle with *how* to say it — especially when answering someone else's question about a personal topic. They stare at a blank text area, type a few disjointed notes, and either give up or save something they're not proud of. The result: fewer memories captured, lower quality content, and less engagement with the people who asked.

This is especially true for question responses, where users feel social pressure to write something "good enough" for the person who asked. A working parent already short on time shouldn't also need to worry about writing quality when preserving a family story.

## Goals

1. Eliminate writing quality as a barrier to capturing memories so users save more moments, more often
2. Preserve each user's authentic voice — polished output should sound like them, not generic AI prose
3. Keep the feature completely optional and non-intrusive so it never feels like the app is judging what the user wrote

## User Stories

### Writing Assistance
1. As a user answering a question, I want help turning my rough notes into a well-written response so that I can share a meaningful memory without struggling over the writing
2. As a user creating a memory, I want to jot down quick bullet points and have them expanded into a full memory so that I capture the moment before I forget the details
3. As a user, I want the polished version to sound like me so that my memories feel authentic when my family reads them

### Control & Trust
4. As a user, I want to review the polished version before it replaces my draft so that I stay in control of what gets saved
5. As a user, I want to be able to ignore the feature entirely so that it never gets in the way of my normal writing flow
6. As a user, I want to edit the polished version further after accepting it so that I can fine-tune anything the assistant got wrong

### Contextual Awareness
7. As a user answering the question "What was your favorite family vacation?", I want the assistant to understand that context so the polished version actually answers the question


## Feature Requirements

### 1. "Help me write" Button

#### 1.1 Placement & Visibility
- A clearly labeled "Help me write" button appears near every text area in the app
- The button is always visible — not hidden behind menus or conditional on user behavior
- Position: directly below or adjacent to the text area, visually connected but not competing with the primary "Save" action
- The button should use a recognizable icon (e.g., sparkle/wand) alongside the text label

#### 1.2 States
- **Default**: Subtle but obvious — muted styling that doesn't distract from the text area
- **Disabled**: When the text area is empty — the button is visible but non-interactive, with a tooltip explaining "Type something first"
- **Loading**: After tapping, show a spinner/progress indicator on the button while the AI processes
- **Error**: If the request fails, show a brief inline error message with a "Try again" option

#### 1.3 Writing Surfaces
The button appears on every text input where users write memory content:
- **CreateMemoryView** — new memory creation
- **EditMemoryView** — editing an existing memory
- **AnswerForm** — answering a question from someone else
- Any future writing surfaces should include it by default

### 2. AI Polishing

#### 2.1 Input
The AI receives:
- **User's current text** — whatever is in the text area (bullets, fragments, rough prose, anything)
- **3 most recent saved memories** by this user — used **exclusively** to match the user's writing voice and tone. These memories must NOT be used as content source material, referenced, quoted, or incorporated into the polished output. They exist solely to help the AI mimic how this user naturally writes.
- **Contextual metadata** (when available):
  - The question text being answered (if responding to a question)
  - The storyline name (if writing within a storyline)

#### 2.2 Output
- A single polished version of the user's text
- The polished version should:
  - Preserve all facts and details from the user's original text
  - Not invent, add, or embellish details that weren't in the original
  - Improve grammar, flow, and readability
  - Expand terse bullet points into natural sentences
  - Match the user's voice based on their recent memories
  - Answer the question naturally if one was provided as context
  - Be roughly proportional in length to the input — don't turn 2 bullet points into 5 paragraphs

#### 2.3 AI Provider
- Use the existing `IAiCompletionService` abstraction (currently backed by xAI/Grok)
- System prompt must be carefully crafted to:
  - Emphasize voice matching over generic polish
  - Explicitly prohibit using voice-reference memories as content
  - Protect against prompt injection in user text
  - Produce warm, personal writing appropriate for family memories

### 3. Review & Accept Flow

#### 3.1 Presentation
- After the AI returns a result, show the polished version in a distinct review state
- The polished text replaces the content of the text area with clear visual indication that this is a suggestion (e.g., highlighted background, "Suggested version" label)
- Two clear action buttons:
  - **Accept** — keeps the polished version in the text area, returns to normal editing
  - **Undo** — reverts to the user's original text, returns to normal editing
- The user can also directly edit the polished text in the text area before accepting

#### 3.2 Behavior
- While in review state, the "Help me write" button is hidden (replaced by Accept/Undo)
- The user's original text is preserved in memory until they explicitly Accept or Undo
- If the user starts editing the polished text, that's treated as an implicit accept — the Undo option remains available but Accept is no longer needed
- Navigating away without accepting or undoing preserves whatever is currently in the text area
- If the user taps "Help me write" again (after editing the polished version or after undoing), it re-polishes whatever is currently in the text area — it always works on the current content, not the original draft

### 4. Voice Matching

#### 4.1 Recent Memories Retrieval
- When the user taps "Help me write", fetch the 3 most recent memories by that user
- If the user has fewer than 3 saved memories, use however many exist (including zero)
- Only include memories with non-empty text content
- These are passed to the AI as voice reference samples only

#### 4.2 Privacy & Boundaries
- Voice reference memories are sent to the AI provider in the same request (they are the user's own data)
- The system prompt must explicitly instruct the AI: "The following memories are provided ONLY to help you match this user's writing style. Do NOT reference, quote, or incorporate any content from these memories into your response."
- If the user has zero saved memories, the AI still works — it just produces a generically well-written version without voice matching

## Data Model

### Drop Entity Update

Add a boolean flag to track whether a memory was created with writing assist:

```
Drop {
  ...existing fields...
  assisted: boolean (default: false)
}
```

- Default `false` for full backwards compatibility with all existing drops
- Set to `true` on the frontend when the user saves a memory after accepting an AI-polished version
- Used for analytics only — no behavioral differences based on this flag

### API Endpoint

```
POST /api/drops/assist
```

**Request:**
```json
{
  "text": "string (required) — user's rough draft",
  "questionText": "string (optional) — the question being answered",
  "storylineName": "string (optional) — the storyline context"
}
```

**Response:**
```json
{
  "polishedText": "string — the AI-polished version"
}
```

The backend retrieves the user's 3 most recent memories server-side (not sent from the client) to avoid exposing them in network requests and to ensure consistency.

### Rate Limiting
- Use the existing `CacheEntry`-based rate limiting pattern (same as AI Question Suggestions)
- Limit: 20 requests per user per day
- When limit is reached, the button shows a tooltip: "You've used all your writing assists for today. Try again tomorrow."

## UI/UX Requirements

### Button Design
- Icon: sparkle or magic wand (from Material Design Icons)
- Label: "Help me write"
- Default state: muted text color, no background — present but not competing for attention
- Hover/focus: subtle background highlight
- Disabled (empty text): reduced opacity, cursor not-allowed
- Loading: spinner replaces icon, label changes to "Writing..."

### Review State
- Text area background changes to a soft highlight (e.g., light brand-color tint)
- Small label above or inside the text area: "Suggested version"
- Accept button: primary styled (brand green)
- Undo button: text/outline styled, positioned secondary to Accept
- Both buttons positioned directly below the text area, replacing the "Help me write" button

### Responsive Behavior
- Button and review state must work on mobile viewports
- Accept/Undo buttons should be full-width on mobile for easy tapping

## Technical Considerations

### Backend
- New endpoint: `POST /api/drops/assist` on existing `DropsController`
- Service method on `DropsService` (or new `WritingAssistService`) that:
  1. Validates the request (non-empty text)
  2. Fetches user's 3 most recent drops with non-empty text
  3. Builds the AI prompt with user text, voice samples, and optional context
  4. Calls `IAiCompletionService`
  5. Returns the polished text
- Rate limiting via `CacheEntry` table

### Frontend
- New composable: `useWritingAssist` — encapsulates the API call, loading state, original text preservation, and review state management
- The composable is consumed by any writing surface component
- No new routes or views required

### AI Prompt Engineering
- The system prompt is critical and should be iterated on. Initial version should:
  - Set the role as a writing assistant for personal family memories
  - Explain the voice matching requirement with explicit content prohibition
  - Include examples of good input→output transformations
  - Guard against prompt injection
  - Instruct proportional output length

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Assist Adoption | % of memories where "Help me write" was used | >20% after 60 days |
| Accept Rate | % of polished suggestions that users accept | >70% |
| Memory Completion Rate | % of started memories that get saved (with vs. without assist) | Measurable improvement over baseline |
| Repeat Usage | % of users who use the feature more than once per week | >40% of adopters |

## Out of Scope (Future Considerations)

- Voice-to-text input (speak instead of type) — separate feature, complementary
- Multiple style/tone options (e.g., "storytelling" vs. "casual") — could layer on later
- Assist for non-memory text (storyline descriptions, profile bios) — possible expansion
- Collaborative editing or suggestions from other users
- Saving assist history or showing before/after comparisons
- Proactive "you could add more detail about..." suggestions

## Implementation Phases

### Phase 1: Backend Endpoint & AI Prompt
- Create `POST /api/drops/assist` endpoint
- Implement voice sample retrieval (3 most recent memories)
- Craft and test the AI system prompt
- Add rate limiting (20/day)
- **Result:** API is callable and returns polished text

### Phase 2: Frontend — Core Component & Memory Creation
- Build `useWritingAssist` composable
- Add "Help me write" button to CreateMemoryView
- Implement review state (Accept/Undo) in CreateMemoryView
- **Result:** Users can get writing help when creating new memories

### Phase 3: Frontend — All Writing Surfaces
- Add "Help me write" to EditMemoryView
- Add "Help me write" to AnswerForm (question responses)
- Ensure consistent behavior and styling across all surfaces
- **Result:** Writing assist available everywhere users write

## Resolved Questions

1. **AI personalization with user's name?** — No. Keep the prompt generic; voice matching from recent memories is sufficient.
2. **Re-polish edited vs. original?** — Always re-polish whatever is currently in the text area. The feature works on current content, not the original draft.
3. **Track assist usage?** — Yes. Add `assisted` boolean (default `false`) to the Drop entity for analytics. See Data Model section.

---

*Document Version: 1.0*
*Created: 2026-02-21*
*Status: Accepted*
