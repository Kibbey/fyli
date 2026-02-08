# Release Notes

## 2026-02-07: Unified Questions Page

### New Features

**Unified Questions Page**
- Combined `/questions` (set management) and `/questions/requests` (response tracking) into a single page
- Each question set displayed as a lifecycle card showing draft, sent, or complete status
- Expandable cards with inline answer previews, recipient status indicators, and action buttons
- "Load More" pagination for users with many question sets

**Ask Questions Wizard**
- Multi-step wizard combining set creation and recipient selection into one flow
- Previous recipients suggested for quick re-selection when sending new questions
- Email now required for all recipients (with validation)
- Support for `?setId=N` query parameter to skip directly to recipient selection

**Recipient Deduplication**
- When sending to the same email twice for the same question set, reuses existing token
- Avoids confusing recipients with multiple links

### Technical Details

- Two-phase query pattern: lightweight summary for sorting/pagination, full detail load only for visible results
- Old routes (`/questions/requests`, `/questions/dashboard`, `/questions/responses`) redirect to unified page
- New endpoints: `GET /questions/sets/unified`, `GET /questions/recipients/previous`
- 12 new backend tests, 43 new frontend tests

### Files Changed

**Backend:**
- `QuestionModels.cs` - 3 new models (UnifiedQuestionSetModel, UnifiedRequestModel, PreviousRecipientModel)
- `IQuestionService.cs` - 2 new interface methods
- `QuestionService.cs` - Updated CreateQuestionRequest, added GetUnifiedQuestionSets, GetPreviousRecipients
- `QuestionController.cs` - 2 new endpoints

**Frontend:**
- `UnifiedQuestionsView.vue` (new) - Main unified questions page
- `QuestionSetCard.vue` (new) - Lifecycle card component
- `AskQuestionsView.vue` (new) - Multi-step wizard
- `questionApi.ts` - 2 new API functions
- `question.ts` - 3 new TypeScript types
- `router/index.ts` - Updated routes with redirects
- Removed: QuestionSetListView, QuestionRequestsView, QuestionSendView, QuestionDashboardView, QuestionResponsesView

---

## 2026-02-07: Video Processing Placeholder with Refresh

### New Features

**Video Processing Placeholder**
- Added visual feedback when videos are still being transcoded after upload
- Users now see a "Video is being processed..." placeholder instead of a broken video element
- Added a "Check if ready" button to refresh individual video status without reloading the page
- Processing placeholder automatically updates messaging after refresh attempts

**Transcode Delay**
- Added intelligent delay after video uploads (2-8 seconds based on file size) to allow AWS MediaConvert time to process
- Visual "Processing video..." indicator shown during the delay period

### Technical Details

- New `VideoProcessingPlaceholder` component for consistent processing state UI
- New `GET /api/questions/answer/{token}/movies/{movieId}` endpoint for checking video status
- Video error handling - automatically shows placeholder if video fails to load
- Proper ARIA attributes for accessibility (`aria-live="polite"`, `aria-label`)

### Files Changed

**Frontend:**
- `src/components/question/VideoProcessingPlaceholder.vue` (new)
- `src/components/question/AnswerPreview.vue` (updated)
- `src/views/question/QuestionAnswerView.vue` (updated)
- `src/services/questionApi.ts` (updated)

**Backend:**
- `QuestionController.cs` - Added `GetAnswerMovieStatus` endpoint
- `QuestionService.cs` - Added `GetAnswerMovieStatus` implementation
- `IQuestionService.cs` - Added interface method
