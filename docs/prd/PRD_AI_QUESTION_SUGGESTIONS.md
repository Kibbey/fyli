# Product Requirements Document: AI Question Suggestions

## Overview

Help users ask better questions by suggesting AI-generated questions during the QuestionSet creation flow. The AI uses the user's stated intent (who they're asking and what they want to learn), their previous question and answer history, and optionally storyline context to generate thoughtful, specific questions that surface meaningful stories and memories.

## Problem Statement

Asking good questions is hard. Most people default to generic questions like "What was your childhood like?" when what they really want is something more specific that draws out a meaningful story. Users stare at blank question fields unsure what to ask, or they repeat questions they've already asked. The result is fewer questions sent, lower response rates, and missed opportunities to capture the stories that matter most.

Fyli's question feature is only as valuable as the quality of questions people ask. If we can help users craft questions that are specific, positive, and draw out untold stories, we unlock deeper family connection and richer memories.

## Goals

1. **Reduce friction in question creation** — Users should never feel stuck staring at a blank form
2. **Improve question quality** — Suggested questions should be specific, thoughtful, and designed to draw out stories, not just facts
3. **Avoid repetition** — Never suggest questions similar to ones the user has already asked
4. **Build on what's already known** — Use previous answers to go deeper, asking about details hinted at but not yet explored

## User Stories

### Intent Gathering
1. As a user, I want to optionally describe what I want to learn about so that the suggestions are relevant to my situation
2. As a new user with no history, I want to get great question suggestions right away so that I can start capturing meaningful stories from day one
3. As a user who already knows what to ask, I want the suggestion feature to stay out of my way so that my existing workflow is unaffected
4. As a user I want to be able to select a timeline as reference for creating questions.

### Suggestion Experience
1. As a user, I want to see AI-suggested questions as tappable chips below the question form so that I can quickly populate my question set without typing from scratch
2. As a user, I want to refresh suggestions to get new ideas so that I'm not limited to the first batch
3. As a user, I want to edit a suggested question after selecting it so that I can personalize it in my own voice
4. As a user, I want to be able to optionally select a timeline to help with question generation


### Context-Aware Suggestions
6. As a user, I want the AI to consider my previous questions and their answers so that it suggests follow-up questions that go deeper rather than retreading old ground
7. As a user creating questions for a storyline, I want the AI to use that storyline's context so that the suggestions are relevant to the story being told

## Feature Requirements

### 1. Inline Suggestion Panel (on Create Step)

The AI suggestion feature lives entirely within the existing Create step — no new steps are added to the flow. The flow remains: **Choose → Create → Send → Done**. Users who know what they want to ask experience zero added friction.

#### 1.1 "Need ideas?" Collapsible Panel
- Below the question input fields, a collapsible section is displayed: **"Need ideas? Get suggested questions"** with a lightbulb icon (`mdi-lightbulb-outline`)
- Collapsed by default — users who already know what to ask never see it expand
- When expanded, shows:
  1. An intent input field: **"What do you want to learn about?"** with placeholder examples (e.g., "grandma's childhood", "how my parents met", "dad's career journey")
  2. A "Suggest Questions" button that triggers the AI call
  3. Option to select timeline to reference.
  4. Suggestion chips appear below after the AI responds
- Maximum 200 characters for the intent field

#### 1.2 Flow Integration
- The existing flow is unchanged: Choose → Create → Send → Done
- No new steps, no changes to the step indicator
- The suggestion panel is purely additive — a collapsible helper on the Create step
- When creating questions from a storyline, the panel auto-expands with pre-filled context: "Questions about [Storyline Name]"

### 2. AI Suggestion Generation

#### 2.1 Backend Endpoint
- `POST /api/questions/suggestions`
- Authenticated (JWT required)
- Request body:
```json
{
  "intent": "grandma's childhood in Italy",
  "storylineId": null
}
```
- Response body:
```json
{
  "suggestions": [
    "What's a smell or sound from your childhood home in Italy that instantly takes you back?",
    "Who was your closest friend growing up, and what kind of trouble did you get into together?",
    "What's a family tradition from Italy that you wish we still kept today?",
    "Can you describe a typical Sunday in your family when you were about 10 years old?",
    "What's something your parents taught you that you didn't appreciate until much later?"
  ]
}
```
- Returns 5 suggestions per request
- Rate limited: max 10 requests per user per day (prevents abuse, manages cost)

#### 2.2 AI Prompt Engineering
The system prompt should instruct the AI to generate questions that:
- **Ask about specific details** hinted at but not yet discussed in previous answers
- **Are positive and warm in tone** — never confrontational, never about regrets or failures
- **Invite storytelling** — "Tell me about..." or "What was it like when..." rather than yes/no questions
- **Are specific enough to trigger a memory** — "What did your kitchen smell like on Sunday mornings?" not "What was your childhood like?"
- **Vary in scope** — mix of questions about people, places, moments, feelings, and lessons
- **Avoid repetition** — never suggest questions semantically similar to previously asked ones (provide previous questions as context)

#### 2.3 Context Assembly (Server-Side)
The backend assembles context before calling the AI:
1. **User intent** — the free-text topic from the intent step. Limit length of text input to reasonable size make prompt injection harder. 
2. **Previous questions** — all question texts from the user's QuestionSets (for de-duplication)
3. **Previous answers** — answer content from completed QuestionResponses (for follow-up depth). Limited to the most recent 20 answers to manage token costs
4. **Storyline context** (when `storylineId` is provided) — storyline name, description, and the text content of the most recent 10 drops in that storyline

### 3. Frontend Suggestion UI

#### 3.1 Suggestion Chips
- Displayed below the question input fields on the Create step
- Each suggestion is a tappable chip showing the full question text
- Tapping a chip populates the next empty question field with the suggestion text
- If all 5 fields are filled, tapping a chip does nothing (with a subtle visual hint)
- A "Refresh" button (icon: `mdi-refresh`) fetches a new batch of 5 suggestions
- Loading state: skeleton chips while the AI request is in flight

#### 3.2 States
- **Collapsed** (default): Panel shows "Need ideas? Get suggested questions" as a clickable header — nothing else visible
- **Expanded, awaiting input**: Intent field visible with placeholder text. "Suggest Questions" button ready
- **Loading**: Show 3 skeleton/placeholder chips with a subtle pulse animation below the intent field
- **Loaded**: Show up to 5 suggestion chips
- **Used**: When a chip is tapped, it visually dims (muted style) to indicate it's been used
- **Error**: If AI call fails, show a subtle inline message: "Couldn't load suggestions — try again or write your own." No blocking — the form remains fully functional

#### 3.3 No AI Dependency
- The suggestion feature is purely additive. The question creation flow must work identically if suggestions fail to load or the AI service is unavailable
- Users can always type their own questions regardless of suggestion state

### 4. Provider-Agnostic AI Abstraction

#### 4.1 Backend Abstraction Layer
- Interface: `IAiCompletionService` with a method like `GenerateCompletionAsync(string systemPrompt, string userPrompt) → string`
- Initial implementation: one concrete provider (Claude or OpenAI — implementer's choice)
- Provider selection via configuration (`appsettings.json`), not code changes
- API keys stored in environment variables / secrets, never in source code

#### 4.2 Configuration
```json
{
  "AiService": {
    "Provider": "xai",
    "Model": "grok-4-1-fast-non-reasoning",
    "ApiKey": "{{from-secrets}}",
    "MaxTokensPerRequest": 2000,
    "DailyRequestLimitPerUser": 10
  }
}
```

### 5. Storyline Context Integration

#### 5.1 Entry Point
- When creating questions from within a storyline detail page (e.g., an "Ask questions about this storyline" action), the storylineId is passed through to the suggestion endpoint
- The suggestion panel auto-expands with pre-filled intent: "Questions about [Storyline Name]"

#### 5.2 Context Usage
- Storyline name and description are included in the AI prompt
- Recent drop content from the storyline is included as context for the AI to reference
- The AI is instructed to suggest questions that deepen the storyline's narrative

## Data Model

### No New Entities Required
This feature does not persist suggestions — they are generated on-the-fly and ephemeral. The only new data is:

### Configuration
```
AiService settings in appsettings.json (provider, model, rate limits)
```

### Rate Limiting
Track suggestion request counts per user per day. This can use an in-memory cache or a simple database counter — implementation detail left to TDD.

## UI/UX Requirements

### Suggestion Panel Display
- Sits below the question input fields within the existing Create step card
- Separated from the question fields by a subtle divider
- Collapsed state: single line with lightbulb icon and "Need ideas? Get suggested questions" text — inviting but unobtrusive
- Expanded state: intent input field with "Suggest Questions" button, then suggestion chips below
- The panel should feel like a helpful bonus, not a required part of the flow

### Suggestion Chips Display
- Appear in a section below the question fields labeled "Suggested Questions"
- Chips use a soft background (`--fyli-primary-light`) with primary text
- Subtle left border accent on each chip for visual hierarchy
- Compact but readable — full question text, not truncated
- Refresh button aligned right of the section header

### Responsive Behavior
- Chips stack vertically on mobile (full width)
- On desktop, chips can wrap in a natural flow layout

## Technical Considerations

### Token Cost Management
- Limit context sent to AI: max 20 previous answers, max 10 storyline drops
- Use a compact prompt format — send question text and answer summaries, not full drop metadata
- Cache suggestions for the same intent within a session (if user navigates back and forth, don't re-call AI)
- Daily per-user rate limit prevents runaway costs

### Latency
- AI calls typically take 1-3 seconds. The UI must feel responsive:
  - Show skeleton chips immediately
  - Question form is fully functional while suggestions load
  - No blocking — user can start typing before suggestions arrive

### Privacy
- Previous questions and answers are sent to the AI provider as context. This is user-owned data being processed on their behalf
- No user data is stored by the AI provider (use API, not training endpoints)
- Storyline content is only sent when the user explicitly creates questions from a storyline context

### Security
- AI endpoint requires authentication
- Rate limiting prevents abuse
- Input sanitization on intent field (standard XSS prevention)
- API keys stored in secrets management, never committed to source

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Suggestion Adoption Rate | % of question sets created where at least one AI suggestion was used | >40% |
| Questions Per Set | Average number of questions in sets created with suggestions vs. without | +1 question per set |
| Suggestion Refresh Rate | Average refreshes per session (indicates engagement) | 1-2 per session |
| Question Request Completion | % of users who start the flow and complete sending (with suggestions vs. without) | +15% improvement |
| Response Rate | % of recipients who answer at least one question (suggested vs. manual) | +10% improvement |

## Out of Scope (Future Considerations)

- **Per-recipient personalization** — Tailoring suggestions based on the specific person being asked (their previous answers, relationship type). Could be a Phase 4 enhancement
- **Proactive suggestion nudges** — Push notifications or email suggesting "Here are some great questions to ask your mom this week"
- **Inline autocomplete** — Suggesting completions as users type in question fields
- **Suggestion feedback loop** — Thumbs up/down on suggestions to improve quality over time
- **Multi-language support** — Generating suggestions in languages other than English
- **Old Prompt system integration** — This feature is separate from the legacy Prompt system, which serves a different purpose (self-reflection prompts)

## Implementation Phases

### Phase 1: AI Infrastructure + Intent-Based Suggestions
- Provider-agnostic `IAiCompletionService` abstraction
- Initial provider implementation
- `POST /api/questions/suggestions` endpoint with intent-only context
- AI prompt engineering for quality question generation
- Rate limiting
- Frontend: collapsible "Need ideas?" panel on the Create step
- Intent input field + "Suggest Questions" button
- Suggestion chips UI with loading, error, and used states

**What this unlocks:** Users can describe what they want to learn and get 5 great suggested questions immediately — works for brand new users with zero history. Users who know what to ask are completely unaffected.

### Phase 2: History-Enriched Suggestions
- Backend assembles previous questions for de-duplication context
- Backend assembles recent answer content for follow-up depth
- Updated AI prompt that references previous Q&A to suggest deeper questions
- Frontend: no changes needed (same panel and chips UI, richer suggestions from backend)

**What this unlocks:** Suggestions improve over time as the user asks more questions and receives more answers. The AI starts suggesting follow-up questions like "You mentioned grandma worked at a bakery — what was her favorite thing to bake?"

### Phase 3: Storyline Context Integration
- Backend includes storyline name, description, and recent drops in AI context
- Frontend: "Ask questions about this storyline" entry point from StorylineDetailView
- Suggestion panel auto-expands with pre-filled storyline context
- AI prompt enriched with storyline narrative

**What this unlocks:** Users exploring a family storyline (e.g., "Grandpa's Military Service") can generate questions that reference specific memories already captured in that storyline.

## Open Questions

1. **Cost monitoring** — How do we monitor and alert on AI API costs? Should we set a monthly budget cap?
2. **Prompt iteration** — How do we iterate on the AI system prompt over time? Should prompt templates be stored in the database for easy updates, or in code?
3. **Analytics** — Do we want to track which suggestions are selected vs. ignored to improve the prompt over time?

---

*Document Version: 1.1*
*Created: 2026-02-19*
*Status: Draft*
