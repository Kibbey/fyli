# Feature Ideas — Q1 2026

## Current Product State

Fyli is a private, family-focused memory platform that helps busy parents capture, organize, and share meaningful moments. The core loop — **capture, share, engage** — is fully implemented and shipping:

- **Memories** with photos, videos, text, and per-person sharing controls
- **Storylines** for organizing memories into curated collections with collaboration
- **Questions** for prompting family members to share stories (with anonymous answering)
- **Share Links** for frictionless one-tap sharing outside the platform
- **Google OAuth** and magic link authentication with inline auth on all public pages
- **Two-step wizards** for memory creation and editing with sharing controls

The product is past MVP and entering a growth phase. The biggest opportunities are: (1) reducing blank-page friction so users capture more moments, (2) making the growing memory library more useful over time, and (3) creating lasting family artifacts that feel irreplaceable.

---

## Feature Idea 1: Voice-to-Memory

### Problem

A parent watches their kid say something hilarious at the dinner table. They're holding a spatula, not a phone keyboard. By the time they can sit down and type it out, the exact words are gone. The best memories happen when your hands are full.

Fyli's current creation flow requires typing a description, picking a date, and optionally uploading media. That's fine when you're sitting down, but most family moments happen in motion — at the park, in the car, during bedtime.

### Proposal

Add a **voice capture button** to memory creation. The user taps a microphone icon, speaks their memory ("Today at dinner, Liam looked at his broccoli and said 'this tree is not for me' and everyone lost it"), and AI transcribes it into a clean, formatted memory description.

### How It Works

1. User taps the mic icon on the Create Memory screen (or on the FAB long-press)
2. Audio is recorded on-device and sent to an AI transcription service (e.g., OpenAI Whisper or Google Speech-to-Text)
3. AI transcribes the audio and lightly cleans it up (removes "um"s, fixes grammar, preserves the user's voice)
4. The transcription populates the description field — user can review and edit before saving
5. Date defaults to today, sharing defaults to their preference

### Why This Matters

- **Reduces capture time from 60 seconds to 15 seconds** — speak faster than you type
- **Captures moments in context** — you record while the feeling is fresh
- **Accessibility** — parents with limited typing ability can participate fully
- **Aligns with "be more present"** — you stay in the moment instead of staring at a keyboard

### Technical Considerations

- Browser `MediaRecorder` API for audio capture (works on mobile Safari and Chrome)
- AI dependency: transcription API (Whisper, Google STT, or Deepgram)
- Audio files stored temporarily in S3 for processing, then deleted
- Estimated backend: new `/api/drops/transcribe` endpoint that accepts audio blob
- Privacy: audio is transcribed and discarded, never stored permanently

### Success Metrics

| Metric | Target |
|--------|--------|
| % of memories created via voice | >15% after 30 days |
| Memories per active user (weekly) | +25% increase |
| Voice-created memory completion rate | >80% (user saves after transcription) |

---

## Feature Idea 2: AI Memory Prompts

### Problem

The biggest barrier to capturing memories isn't the UI — it's remembering to do it. Parents live in a blur of school pickups, meetings, and bedtime routines. Even when something beautiful happens, they think "I should write that down" and then forget.

The Questions feature solves this for *asking others* to share. But there's nothing that proactively nudges *you* to capture your own moments. The blank page is the enemy.

### Proposal

An **AI prompt engine** that sends personalized, contextual nudges to capture memories. Not generic "what are you grateful for?" prompts — specific, timely ones based on what the system knows about your life.

### How It Works

**Prompt Sources:**

1. **Calendar-aware** (if Google Calendar is connected): "Emma has her last soccer game of the season tomorrow. Capture a memory about this season?" or "It's picture day at school — don't forget to take one!"
2. **Seasonal/temporal**: "It's the first snow of the year. What did the kids think?" or "School starts next week — capture a back-to-school moment?"
3. **Gap-based**: "You haven't captured a memory in 12 days. What's been happening?" or "You have 8 memories about Liam but only 2 about Sophie this month."
4. **Memory anniversary**: "1 year ago today, you captured this moment: [preview]. What's changed since then?"
5. **Relationship-based**: "You sent Grandma a question last month and she answered. Want to capture your own memory about the same topic?"

**Delivery:**

- Push notification or email (user preference)
- 2-3 prompts per week maximum (not overwhelming)
- One-tap "Capture this" button that opens Create Memory with the prompt pre-filled as context
- "Not now" and "Stop these" controls for each prompt type
- AI generates prompts using an LLM (GPT-4 or Claude) with context about the user's memory history, family members, and calendar

### Why This Matters

- **Solves the #1 retention problem** — users who capture 3+ memories in their first week retain at 3x the rate
- **Turns passive users into active ones** — the system does the remembering for you
- **Builds habit** — regular prompts create a memory capture routine
- **Deeply personal** — these aren't generic; they feel like a thoughtful friend reminding you

### Technical Considerations

- AI dependency: LLM API for generating contextual prompts (Claude or GPT-4)
- New `PromptEngine` service that runs daily/weekly, generates personalized prompts per user
- Stores generated prompts in a `UserPromptQueue` table with delivery status
- Needs user preference settings: frequency, delivery method, prompt types enabled
- Calendar integration already exists (Google Calendar sync) — can read event titles
- Must respect privacy: LLM sees only metadata (event titles, memory dates, connection names), never full memory content

### Success Metrics

| Metric | Target |
|--------|--------|
| Prompt-to-memory conversion rate | >20% |
| Weekly active users (prompted vs. unprompted) | +40% increase in prompted cohort |
| User retention at 30 days (prompted cohort) | >50% |
| Prompt opt-out rate | <15% |

---

## Feature Idea 3: Memory Search & "On This Day"

### Problem

As families use Fyli over months and years, their memory library grows. A family with two parents and four grandparents contributing could have hundreds of memories within a year. Finding "that time we went to the lake" or "what Liam said about the moon" becomes increasingly difficult with only a reverse-chronological stream.

The product vision already lists filtering (by person, date, year, Look Back) as a P2 feature. This proposal expands that with AI-powered semantic search to make the library genuinely useful at scale.

### Proposal

Two features that make the memory library a living, searchable family archive:

**1. Semantic Search**
A search bar on the memory stream that understands natural language. "Beach trip last summer" finds memories from July-August with beach-related descriptions or photos, even if the word "beach" wasn't used. "Funny things Liam said" finds memories tagged to Liam with humorous content.

**2. On This Day**
A daily or weekly digest surfacing memories from the same date in previous years. "2 years ago today..." with a preview card and quick re-share button. This is the single highest-engagement feature on every photo platform (Facebook, Google Photos, Apple Photos) and Fyli doesn't have it yet.

### How It Works

**Semantic Search:**
1. When a memory is created, generate an embedding (vector representation) of its text + AI-described photo content
2. Store embeddings in a vector index (pgvector extension for PostgreSQL, or a dedicated service)
3. When the user searches, convert their query to an embedding and find the nearest matches
4. Display results ranked by relevance with highlighted matching context

**On This Day:**
1. Daily job checks each user's memory history for memories from the same date in prior years
2. If matches exist, surface them as a card at the top of the memory stream or via notification
3. One-tap "Share again" to re-share with current connections
4. "Add to Storyline" quick action

### Why This Matters

- **Search makes the library useful at scale** — without it, older memories are effectively lost
- **On This Day drives daily engagement** — it gives users a reason to open the app even when they have nothing new to capture
- **Emotional impact** — rediscovering a forgotten moment is one of the most powerful features a memory app can offer
- **Aligns with "live an intentional life"** — reflection on past moments creates gratitude and perspective

### Technical Considerations

- AI dependency: embedding model (OpenAI `text-embedding-3-small` or similar) for semantic search
- Optional AI dependency: vision model for photo description (to make photos searchable by content)
- PostgreSQL `pgvector` extension for vector storage and similarity search, or a managed service like Pinecone
- New `SearchController` with `GET /api/search?q=` endpoint
- On This Day: scheduled job (daily) + new notification type
- Embedding generation can be async (background job after memory creation)

### Success Metrics

| Metric | Target |
|--------|--------|
| Search usage (% of weekly active users) | >30% |
| On This Day engagement (tap-through rate) | >40% |
| Re-share rate from On This Day | >10% |
| Daily active users (after On This Day launch) | +20% increase |

---

## Feature Idea 4: Family Story Builder

### Problem

Fyli is great at capturing individual moments. But the real treasure is the *story* — the narrative that connects moments into something meaningful. A grandparent's 15 question answers about their childhood are powerful individually, but stitched together they become a family history chapter.

Today, the only way to create narrative is manually through Storylines (ordered collections). But most users won't take the time to curate and organize memories into a coherent story. The raw materials are there — the assembly is the bottleneck.

### Proposal

An **AI-powered story generator** that takes a collection of memories and/or question answers and weaves them into a readable narrative. The user selects the source material, the AI drafts a story, and the user can edit, save, and share it.

### How It Works

1. User navigates to a Storyline, album, or filtered set of memories
2. Taps "Create Story" button
3. AI analyzes all selected memories: text descriptions, dates, people mentioned, chronological order
4. Generates a narrative draft in the user's voice (calibrated from their writing style in memories)
5. User reviews, edits, and saves the story as a new type of content ("Story")
6. Stories can be shared like memories, exported as PDF, or printed

**Example Output:**

> *"Grandma's Kitchen" — assembled from 12 question answers and 6 memories*
>
> *Mom always said the kitchen was where the family happened. Not the living room, not the backyard — the kitchen. When we asked her about her earliest memory, she didn't hesitate: "Standing on a chair next to my mother, stirring something I wasn't allowed to taste yet." She was four...*

### Why This Matters

- **Transforms raw data into family heirlooms** — a generated story feels like something you'd print and frame
- **Unlocks the value of Questions** — answers become chapters, not just isolated responses
- **Creates shareable artifacts** — a story about Grandma is something the whole family wants to read
- **Differentiator** — no competitor does this; it positions Fyli as a family *storytelling* platform, not just a memory *storage* platform
- **Premium feature potential** — story generation is a natural premium tier feature

### Technical Considerations

- AI dependency: LLM (Claude or GPT-4) for narrative generation
- Input: collection of memory descriptions + question answers + metadata (dates, people, relationships)
- Output: markdown-formatted narrative with optional section headers
- New `Story` entity linked to source memories/answers
- PDF export: server-side rendering or client-side library (e.g., jsPDF, Puppeteer)
- Privacy: all content stays within the user's account; LLM processes only the selected memories
- Rate limiting: story generation is expensive; limit to N per month on free tier

### Success Metrics

| Metric | Target |
|--------|--------|
| Stories generated per month (per active user) | >1 |
| Story share rate | >50% (stories are inherently shareable) |
| Question-to-story pipeline (users who send questions AND generate stories) | >25% of question senders |
| Premium conversion (if gated) | >5% of free users who try it |

---

## Feature Idea 5: Weekly Family Digest

### Problem

Fyli's engagement model currently requires users to open the app. But the people sharing memories aren't always the same people who need to see them. Grandma shared a story about her childhood, but her daughter might not check Fyli for a week. A parent captured a photo of their kid's first bike ride, but the other parent was at work and hasn't opened the app.

Email notifications exist per-connection, but they're transactional ("Josh shared a memory with you") rather than curated. There's no "here's what happened in your family this week" summary that makes you *want* to open the app.

### Proposal

A **weekly AI-curated email digest** summarizing all family activity — new memories, question answers, comments, and milestones — in a warm, personal format.

### How It Works

**Content:**
- New memories shared with you this week (with thumbnail previews)
- Question answers received
- Comments on your memories
- On This Day highlights (if Feature 3 is built)
- A gentle prompt: "You haven't captured a memory this week. Here's an idea: [AI-generated prompt]"

**Format:**
- Clean, mobile-friendly HTML email
- Warm, personal tone (not transactional)
- "View Memory" buttons linking directly to each item
- Unsubscribe and frequency controls

**AI Enhancement:**
- AI selects the "highlight of the week" — the memory with the most engagement or emotional resonance
- AI writes a one-line personalized intro: "Big week for the family — Grandma shared 3 new stories and Liam had his first soccer goal."
- AI groups related items (e.g., multiple memories from the same event)

### Why This Matters

- **Brings less-active family members back** — grandparents, aunts, uncles who won't check an app daily
- **Creates a weekly family ritual** — "let's read the digest together on Sunday"
- **Drives engagement without requiring the app** — the email IS the experience for some users
- **Reduces notification fatigue** — one curated email replaces multiple transactional ones
- **Growth lever** — digest previews can include memories shared via link, driving link recipients to sign up

### Technical Considerations

- AI dependency: LLM for personalized intro + highlight selection (lightweight — could use a smaller model)
- Email rendering: HTML template with dynamic content (extend existing SendGrid integration)
- Scheduled job: weekly (configurable day), per-user timezone-aware
- New user preference: digest frequency (weekly/off), delivery day
- Must handle zero-activity weeks gracefully ("Quiet week — here's a prompt to get things started")
- Existing email notification infrastructure can be extended

### Success Metrics

| Metric | Target |
|--------|--------|
| Digest open rate | >45% |
| Click-through rate (digest to app) | >25% |
| Reactivation rate (inactive users who return via digest) | >15% |
| Digest-prompted memory creation | >10% of recipients create a memory within 24hrs |

---

## Summary & Prioritization Recommendation

| # | Feature | AI Required | Effort | Impact | Recommendation |
|---|---------|-------------|--------|--------|----------------|
| 1 | Voice-to-Memory | Yes (transcription) | Medium | High | **Build first** — lowest-effort AI feature, immediately reduces capture friction |
| 2 | AI Memory Prompts | Yes (LLM) | High | Very High | **Build second** — biggest retention impact, but needs prompt tuning |
| 3 | Memory Search & On This Day | Yes (embeddings) | High | High | **Build third** — becomes critical as library grows; On This Day is quick win |
| 4 | Family Story Builder | Yes (LLM) | High | Very High | **Build fourth** — strongest differentiator and premium feature candidate |
| 5 | Weekly Family Digest | Light (LLM optional) | Medium | Medium-High | **Build anytime** — independent of other features, steady engagement lift |

### Recommended Sequencing

**Phase 1 (Quick Wins):** Voice-to-Memory + On This Day (from Feature 3)
- Fast to ship, immediate user value, establishes AI infrastructure

**Phase 2 (Retention):** AI Memory Prompts + Weekly Family Digest
- Drives habitual usage and re-engagement

**Phase 3 (Differentiation):** Semantic Search + Family Story Builder
- Positions Fyli as the premium family storytelling platform

---

*Document Version: 1.0*
*Created: 2026-02-12*
*Status: Draft — Pending Review*
