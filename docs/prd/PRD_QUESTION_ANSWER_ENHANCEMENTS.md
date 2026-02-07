# Product Requirements Document: Question Answer Page Enhancements

## Overview

Enhance the anonymous question answer page to display completed answers inline, allowing respondents to see what they've created. Additionally, consolidate the image and video upload functionality to use the shared `useFileUpload` composable, providing a consistent experience with core memory creation.

## Problem Statement

When family members answer questions on the anonymous question page, they currently see only a green "Answered" badge with no preview of their response. This creates uncertainty — "Did my answer save correctly? What did I write? Did my photos upload?" Respondents can't appreciate the memories they've contributed without hunting for an Edit button or creating an account.

Additionally, the answer form has separate upload inputs for photos and videos, while core memory creation uses a single combined input. This inconsistency confuses users and creates maintenance overhead for two different upload patterns.

## Goals

1. **Build confidence** — Show respondents exactly what they submitted so they know their memory was captured correctly
2. **Create satisfaction** — Let users appreciate the memories they've shared without friction
3. **Simplify the upload experience** — Unify media upload to match core memory creation
4. **Reduce code duplication** — Reuse the `useFileUpload` composable in the answer form

---

## User Stories

### Viewing Completed Answers

1. As a respondent, I want to see my answer text displayed below each answered question so that I can confirm my memory was saved.
2. As a respondent, I want to see thumbnail previews of photos I uploaded so that I know my images were captured.
3. As a respondent, I want to see indicators for videos I uploaded so that I know my videos were included.
4. As a respondent, I want to see the date I set for my answer so that I can verify the memory context is correct.
5. As a respondent, I want my completed answers always visible (not collapsed) so that I can scan what I've shared without extra taps.

### Unified Media Upload

6. As a respondent, I want a single upload button for photos and videos so that I don't have to think about which type of media I'm adding.
7. As a respondent, I want to see previews of all my selected media (photos and videos) in a unified grid so that I know exactly what will be uploaded.
8. As a respondent, I want upload progress shown for large videos so that I know the upload is working.

---

## Feature Requirements

### 1. Completed Answer Display

#### 1.1 Answer Preview Card
- When a question is answered, display the answer content inline below the question
- Show full answer text (up to reasonable length, no truncation for typical answers)
- Display the answer date in a subtle format (e.g., "December 25, 2025")
- Include visual connection between question and answer (indented or nested styling)

#### 1.2 Media Thumbnails
- Display photo thumbnails in a grid below the answer text
- Wrap thumbnails to a second row (or third, etc) if there are more than 4 (i.e. max 4 per row)
- Thumbnail size: 60x60px with rounded corners, matching existing PhotoGrid styling
- For videos: show video thumbnail with play icon overlay, or video icon placeholder

#### 1.3 Edit Access
- Include an "Edit" button on each completed answer
- Edit button opens the existing AnswerForm pre-populated with saved data
- Editing respects the 7-day edit window (button disabled/hidden after window closes)

#### 1.4 Layout & Styling
- Question displayed in highlighted quote style (existing `bg-light border-start border-primary border-4`)
- Answer displayed below with subtle left indent or border to show hierarchy
- Smooth transition when an answer is newly submitted (fade in the answer card)

### 2. Unified Media Upload

#### 2.1 Combined File Input
- Replace separate "Photos" and "Videos" inputs with single "Photos & Videos" input
- Accept both image/* and video/* in the same file input
- Match the exact pattern from `CreateMemoryView.vue`

#### 2.2 Reuse `useFileUpload` Composable
- Import and use `useFileUpload` from `@/composables/useFileUpload`
- Remove custom image/video handling logic from `AnswerForm.vue`
- Leverage existing `FileEntry` type with `type: "image" | "video"`

#### 2.3 Preview Grid
- Display all selected files in a unified preview grid
- Images: show image thumbnail (80x80px, object-fit: cover)
- Videos: show video thumbnail with timestamp preview (using `#t=0.1` trick)
- Each preview has remove button (X) in top-right corner
- Video upload progress overlay (percentage display over thumbnail)

#### 2.4 Error Handling
- Show file error message for oversized videos (5GB limit)
- Invalid file types silently ignored (matches existing behavior)
- Upload failures show non-blocking error message

### 3. Data Requirements

#### 3.1 Answer Data for Display
The existing `QuestionView` interface needs to include answer data when answered:

```typescript
interface QuestionView {
  questionId: number
  text: string
  isAnswered: boolean
  // New fields for displaying completed answers:
  answer?: {
    content: string
    date: string
    dateType: number
    images: { url: string }[]
    videos: { thumbnailUrl?: string }[]
    dropId: number
    canEdit: boolean  // true if within 7-day edit window
  }
}
```

#### 3.2 API Update
- `GET /questions/answer/{token}` response should include answer content when `isAnswered: true`
- Backend query joins `QuestionResponse` → `Drop` → images/movies for answered questions

---

## UI/UX Requirements

### Completed Answer Display

```
┌─────────────────────────────────────────────┐
│ ┌─────────────────────────────────────────┐ │
│ │ "What's your favorite family tradition?" │ │  ← Question (quoted style)
│ └─────────────────────────────────────────┘ │
│                                             │
│   Every Christmas Eve we make tamales       │  ← Answer text
│   together. My grandmother taught my mom,   │
│   and now we're teaching the kids...        │
│                                             │
│   December 24, 2025                         │  ← Answer date (subtle)
│                                             │
│   ┌────┐ ┌────┐ ┌────┐                      │  ← Media thumbnails
│   │ 📷 │ │ 📷 │ │ 🎥 │                      │
│   └────┘ └────┘ └────┘                      │
│                                             │
│                              [Edit]         │  ← Edit button (if within window)
└─────────────────────────────────────────────┘
```

### Combined Media Upload (in AnswerForm)

```
┌─────────────────────────────────────────────┐
│ Photos & Videos                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Choose Files...                         │ │  ← Single file input
│ └─────────────────────────────────────────┘ │
│ Supported: JPG, PNG, HEIC, MP4, MOV        │
│ Max video size: 5GB                         │
│                                             │
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐                │
│ │ 📷 │ │ 📷 │ │🎥  │ │ 📷 │                │  ← Unified preview grid
│ │  ✕ │ │  ✕ │ │45% │ │  ✕ │                │
│ └────┘ └────┘ └────┘ └────┘                │
└─────────────────────────────────────────────┘
```

### Visual Hierarchy

- Question: Primary prominence, quoted style with left border accent
- Answer text: Secondary, clear and readable
- Date: Tertiary, subtle text-muted styling
- Media: Supporting, compact thumbnails
- Edit button: Minimal, right-aligned, outline style

---

## Technical Considerations

### Frontend Changes

1. **AnswerForm.vue**
   - Replace custom file handling with `useFileUpload` composable
   - Update template to single file input with unified preview grid
   - Emit `FileEntry[]` instead of separate `images: File[]` and `videos: File[]`

2. **QuestionAnswerView.vue**
   - Update question list to render completed answer cards
   - Add media thumbnail display for answered questions
   - Pass answer data from API response to display component

3. **New Component: AnswerPreview.vue** (optional)
   - Encapsulate answer display with question context
   - Reusable for both anonymous page and potential future use
   - Props: question, answer, canEdit, onEdit

### Backend Changes

1. **QuestionController - GetQuestionsForAnswer**
   - Join `QuestionResponse` → `Drop` for answered questions
   - Include `Drop.Stuff` (answer content), date, images, movies in response
   - Calculate `canEdit` based on 7-day window from `answeredAt`

2. **Response DTO Update**
   - Extend `QuestionView` DTO to include answer data when present

### Token-Based Upload Integration

The `useFileUpload` composable is designed for authenticated uploads. For the anonymous answer flow:
- Continue using token-based upload endpoints (`uploadAnswerImage`, `requestAnswerMovieUpload`)
- Create a wrapper function in `QuestionAnswerView.vue` that maps from `useFileUpload.uploadFiles` pattern to token-based APIs
- Alternative: Create `useTokenFileUpload` composable variant (more work, cleaner separation)

**Recommended approach:** Adapt `AnswerForm` to use `useFileUpload` for file selection and preview, but custom upload logic for token-based submission.

---

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Answer Review Rate | % of respondents who view their completed answers (page scroll/visibility) | Track baseline |
| Edit Rate | % of respondents who click Edit after seeing their answer | 5-10% (indicates engagement) |
| Media Upload Success | % of media uploads that complete successfully | > 95% |
| Time to Complete All | Average time to answer all questions in a set | Reduce by 10% (simpler upload) |

---

## Out of Scope (Future Considerations)

- Lightbox/modal for full-size media viewing on answer preview
- Answer sharing (copy link to specific answer)
- Download own answers as PDF
- Rich text formatting in answers
- Voice memo answers

---

## Implementation Phases

### Phase 1: Completed Answer Display
- Update backend API to return answer content for answered questions
- Add answer preview display in QuestionAnswerView
- Include text, date, and Edit button
- No media thumbnails yet (simpler first iteration)

### Phase 2: Media Thumbnails
- Extend backend to return image/video references for answers
- Display media thumbnails in answer preview
- Handle video thumbnail generation or placeholders

### Phase 3: Unified Upload
- Refactor AnswerForm to use `useFileUpload` composable for file handling
- Update to single combined file input
- Add unified preview grid with video progress
- Update parent component to handle new FileEntry format

---

## Open Questions

None — all clarifications received.

---

*Document Version: 1.0*
*Created: 2026-02-06*
*Status: Draft*
