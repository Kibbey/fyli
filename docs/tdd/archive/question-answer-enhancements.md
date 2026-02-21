# Technical Design Document: Question Answer Page Enhancements

## Overview

Enhance the anonymous question answer page (`/q/{token}`) to:
1. Display completed answers inline with full content, date, and media thumbnails
2. Consolidate image/video upload into a single input using the `useFileUpload` composable

This TDD covers backend API changes to return answer data and frontend refactoring for unified media handling.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    QuestionAnswerView.vue                    │
│  (Orchestrates answer flow, displays completed answers)      │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────┐  ┌──────────────────────────────┐  │
│  │   AnswerPreview     │  │      AnswerForm              │  │
│  │   (New Component)   │  │   (Refactored w/ useFile)    │  │
│  │   - Question text   │  │   - Combined media input     │  │
│  │   - Answer content  │  │   - Unified preview grid     │  │
│  │   - Date display    │  │   - Video progress overlay   │  │
│  │   - Media thumbs    │  └──────────────────────────────┘  │
│  │   - Edit button     │                                    │
│  └─────────────────────┘                                    │
├─────────────────────────────────────────────────────────────┤
│                    useFileUpload (composable)                │
│            (Reused from core memory creation)                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    questionApi.ts                            │
│  getQuestionsForAnswer → QuestionRequestView (extended)      │
│  uploadAnswerImage / requestAnswerMovieUpload (existing)     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              QuestionController.cs (Backend)                 │
│  GET /api/questions/answer/{token} → Extended response       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              QuestionService.cs (Backend)                    │
│  GetQuestionRequestByToken → Joins Drop + Images + Movies    │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

### Backend Changes

```
cimplur-core/Memento/
├── Domain/
│   ├── Models/
│   │   └── QuestionModels.cs          # Extended QuestionViewModel
│   └── Repositories/
│       └── QuestionService.cs          # Modified GetQuestionRequestByToken
```

### Frontend Changes

```
fyli-fe-v2/src/
├── components/
│   └── question/
│       ├── AnswerForm.vue              # Refactored (unified upload)
│       └── AnswerPreview.vue           # New component
├── views/
│   └── question/
│       └── QuestionAnswerView.vue      # Updated to display answers
├── types/
│   └── question.ts                     # Extended QuestionView type
├── composables/
│   └── useFileUpload.ts                # Existing (no changes)
└── services/
    └── questionApi.ts                  # No changes to endpoints
```

---

## Phase 1: Backend API Enhancement

### 1.1 Extend QuestionViewModel

**File:** `cimplur-core/Memento/Domain/Models/QuestionModels.cs`

Add nested `AnswerViewModel` class and extend `QuestionViewModel`:

```csharp
public class QuestionViewModel
{
    public int QuestionId { get; set; }
    public string Text { get; set; }
    public int SortOrder { get; set; }
    public bool IsAnswered { get; set; }

    /// <summary>
    /// Answer data when IsAnswered is true; null otherwise.
    /// </summary>
    public AnswerViewModel Answer { get; set; }
}

/// <summary>
/// Represents an answer to a question, including content, date, and attached media.
/// </summary>
public class AnswerViewModel
{
    public int DropId { get; set; }
    public string Content { get; set; }
    public DateTime Date { get; set; }
    public DateTypes DateType { get; set; }

    /// <summary>
    /// True if the answer can be edited (registered users always, anonymous within 7 days).
    /// </summary>
    public bool CanEdit { get; set; }

    /// <summary>
    /// Images attached to this answer (excludes comment images).
    /// </summary>
    public List<AnswerImageModel> Images { get; set; } = new();

    /// <summary>
    /// Videos attached to this answer (excludes comment videos).
    /// </summary>
    public List<AnswerMovieModel> Movies { get; set; } = new();
}

/// <summary>
/// Image attached to an answer with pre-signed URL.
/// </summary>
public class AnswerImageModel
{
    public int ImageDropId { get; set; }
    public string Url { get; set; }
}

/// <summary>
/// Video attached to an answer with thumbnail URL.
/// </summary>
public class AnswerMovieModel
{
    public int MovieDropId { get; set; }

    /// <summary>
    /// Thumbnail URL. May be empty for newly uploaded videos (generated asynchronously).
    /// </summary>
    public string ThumbnailUrl { get; set; }
}
```

### 1.2 Modify GetQuestionRequestByToken

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

Update the method to load answer content with images and movies:

```csharp
public async Task<QuestionRequestViewModel> GetQuestionRequestByToken(Guid token)
{
    // Load recipient with all related data
    // Note: Images and Movies are loaded in full, then filtered in BuildAnswerViewModel
    // to avoid EF Core issues with filtered includes in nested ThenInclude chains
    var recipient = await Context.QuestionRequestRecipients
        .Include(r => r.QuestionRequest)
            .ThenInclude(qr => qr.QuestionSet)
                .ThenInclude(qs => qs.Questions.OrderBy(q => q.SortOrder))
        .Include(r => r.QuestionRequest)
            .ThenInclude(qr => qr.Creator)
        .Include(r => r.Responses)
            .ThenInclude(resp => resp.Drop)
                .ThenInclude(d => d.ContentDrop)
        .Include(r => r.Responses)
            .ThenInclude(resp => resp.Drop)
                .ThenInclude(d => d.Images)
        .Include(r => r.Responses)
            .ThenInclude(resp => resp.Drop)
                .ThenInclude(d => d.Movies)
        .SingleOrDefaultAsync(r => r.Token == token);

    if (recipient == null || !recipient.IsActive)
        throw new NotFoundException("This question link is no longer active.");

    // Build response-to-question lookup
    var responsesByQuestionId = recipient.Responses
        .ToDictionary(r => r.QuestionId, r => r);

    var now = DateTime.UtcNow;
    var hasAccount = recipient.RespondentUserId.HasValue;

    return new QuestionRequestViewModel
    {
        QuestionRequestRecipientId = recipient.QuestionRequestRecipientId,
        CreatorName = recipient.QuestionRequest.Creator.Name,
        Message = recipient.QuestionRequest.Message,
        QuestionSetName = recipient.QuestionRequest.QuestionSet.Name,
        Questions = recipient.QuestionRequest.QuestionSet.Questions
            .OrderBy(q => q.SortOrder)
            .Select(q => {
                var isAnswered = responsesByQuestionId.TryGetValue(q.QuestionId, out var response);

                return new QuestionViewModel
                {
                    QuestionId = q.QuestionId,
                    Text = q.Text,
                    SortOrder = q.SortOrder,
                    IsAnswered = isAnswered,
                    Answer = isAnswered ? BuildAnswerViewModel(
                        response,
                        hasAccount,
                        now,
                        recipient.QuestionRequest.CreatorUserId) : null
                };
            }).ToList()
    };
}

/// <summary>
/// Builds an AnswerViewModel from a QuestionResponse, filtering out comment media.
/// </summary>

private AnswerViewModel BuildAnswerViewModel(
    QuestionResponse response,
    bool hasAccount,
    DateTime now,
    int creatorUserId)
{
    var drop = response.Drop;

    // Calculate edit eligibility: registered users always, anonymous within 7 days
    var canEdit = hasAccount || (now - response.AnsweredAt).TotalDays <= 7;

    return new AnswerViewModel
    {
        DropId = drop.DropId,
        Content = drop.ContentDrop.Stuff,
        Date = drop.Date,
        DateType = drop.DateType,
        CanEdit = canEdit,
        Images = drop.Images
            .Where(i => !i.CommentId.HasValue)
            .Select(i => new AnswerImageModel
            {
                ImageDropId = i.ImageDropId,
                Url = imageService.GetLink(i.ImageDropId, creatorUserId, drop.DropId)
            }).ToList(),
        Movies = drop.Movies
            .Where(m => !m.CommentId.HasValue)
            .Select(m => new AnswerMovieModel
            {
                MovieDropId = m.MovieDropId,
                ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, creatorUserId, drop.DropId)
            }).ToList()
    };
}
```

### 1.3 Inject ImageService and MovieService

The `QuestionService` needs access to `ImageService` and `MovieService` for generating signed URLs. Add these to the constructor:

```csharp
private readonly ImageService imageService;
private readonly MovieService movieService;

public QuestionService(
    SharingService sharingService,
    GroupService groupService,
    UserService userService,
    DropsService dropsService,
    SendEmailService sendEmailService,
    ImageService imageService,
    MovieService movieService,
    ILogger<QuestionService> logger)
{
    // ... existing assignments ...
    this.imageService = imageService;
    this.movieService = movieService;
}
```

### 1.4 Update IQuestionService Interface

**File:** `cimplur-core/Memento/Domain/Repositories/IQuestionService.cs`

No changes needed — the return type `QuestionRequestViewModel` remains the same; only its structure is extended.

---

## Phase 2: Frontend Type Updates

### 2.1 Extend QuestionView Type

**File:** `fyli-fe-v2/src/types/question.ts`

```typescript
export interface QuestionView {
  questionId: number;
  text: string;
  sortOrder: number;
  isAnswered: boolean;
  // New: answer data when isAnswered is true
  answer?: AnswerView;
}

// New interface
export interface AnswerView {
  dropId: number;
  content: string;
  date: string;
  dateType: DateType;
  canEdit: boolean;
  images: AnswerImage[];
  movies: AnswerMovie[];
}

export interface AnswerImage {
  imageDropId: number;
  url: string;
}

export interface AnswerMovie {
  movieDropId: number;
  thumbnailUrl: string;
}
```

---

## Phase 3: AnswerPreview Component

### 3.1 Create AnswerPreview Component

**File:** `fyli-fe-v2/src/components/question/AnswerPreview.vue`

```vue
<template>
  <div class="answer-preview">
    <div class="card">
      <div class="card-body">
        <!-- Question prompt -->
        <div class="question-prompt mb-3 p-3 bg-light rounded border-start border-primary border-4">
          <p class="mb-0 fst-italic">"{{ question.text }}"</p>
        </div>

        <!-- Answer content -->
        <div class="answer-content ps-3 border-start border-2">
          <p class="mb-2">{{ question.answer.content }}</p>

          <!-- Date display -->
          <p class="text-muted small mb-3">
            <span class="mdi mdi-calendar-outline me-1" aria-hidden="true"></span>
            {{ formattedDate }}
          </p>

          <!-- Media thumbnails -->
          <div
            v-if="hasMedia"
            class="media-grid d-flex flex-wrap gap-2 mb-3"
            role="list"
            aria-label="Attached media"
          >
            <!-- Images -->
            <div
              v-for="img in question.answer.images"
              :key="`img-${img.imageDropId}`"
              class="media-thumb"
              role="listitem"
            >
              <img
                :src="img.url"
                class="rounded"
                alt="Photo attachment"
              />
            </div>

            <!-- Videos -->
            <div
              v-for="vid in question.answer.movies"
              :key="`vid-${vid.movieDropId}`"
              class="media-thumb position-relative"
              role="listitem"
            >
              <img
                v-if="vid.thumbnailUrl"
                :src="vid.thumbnailUrl"
                class="rounded"
                alt="Video attachment"
              />
              <div v-else class="video-placeholder rounded d-flex align-items-center justify-content-center bg-secondary">
                <span class="mdi mdi-video text-white" aria-hidden="true"></span>
              </div>
              <!-- Play icon overlay -->
              <div class="play-overlay position-absolute top-50 start-50 translate-middle">
                <span class="mdi mdi-play-circle text-white play-icon" aria-hidden="true"></span>
              </div>
            </div>
          </div>

          <!-- Edit button -->
          <button
            v-if="question.answer.canEdit"
            type="button"
            class="btn btn-sm btn-outline-secondary"
            @click="$emit('edit', question.questionId)"
          >
            <span class="mdi mdi-pencil me-1" aria-hidden="true"></span>
            Edit
          </button>
          <span v-else class="text-muted small">
            <span class="mdi mdi-lock-outline me-1" aria-hidden="true"></span>
            Edit window closed
          </span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue';
import type { QuestionView, AnswerView } from '@/types';

/**
 * Props interface requiring answer to be present.
 * This component should only be rendered when question.answer exists.
 */
interface AnsweredQuestion extends Omit<QuestionView, 'answer'> {
  answer: AnswerView;
}

const props = defineProps<{
  question: AnsweredQuestion;
}>();

defineEmits<{
  (e: 'edit', questionId: number): void;
}>();

const formattedDate = computed(() => {
  const date = new Date(props.question.answer.date);
  const dateType = props.question.answer.dateType;

  // DateType: 0=Exact, 1=Month, 2=Year, 3=Decade
  switch (dateType) {
    case 1: // Month
      return date.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
    case 2: // Year
      return date.getFullYear().toString();
    case 3: // Decade
      return `${Math.floor(date.getFullYear() / 10) * 10}s`;
    default: // Exact
      return date.toLocaleDateString('en-US', {
        month: 'long',
        day: 'numeric',
        year: 'numeric'
      });
  }
});

const hasMedia = computed(() => {
  return props.question.answer.images.length > 0 ||
         props.question.answer.movies.length > 0;
});
</script>

<style scoped>
.media-grid {
  max-width: 100%;
}

.media-thumb {
  width: 60px;
  height: 60px;
  flex-shrink: 0;
}

.media-thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.video-placeholder {
  width: 100%;
  height: 100%;
}

.play-overlay {
  pointer-events: none;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.5);
}

.play-icon {
  font-size: 1.5rem;
}
</style>
```

---

## Phase 4: Refactor AnswerForm with useFileUpload

### Design Decision: Token-Based Upload Handling

The `useFileUpload` composable is designed for authenticated uploads using the standard `mediaApi`. However, the anonymous question answer flow uses token-based endpoints (`uploadAnswerImage`, `requestAnswerMovieUpload`).

**Approach:** Use `useFileUpload` for file selection and preview management only. The actual upload logic remains in `QuestionAnswerView.vue` using the token-based endpoints. This provides:
- Consistent file selection UX across the app
- Proper memory management for object URLs
- Video size validation
- Upload progress tracking

The `uploadFiles` method from the composable is not used; instead, `QuestionAnswerView` iterates over `files` and calls token-based APIs directly.

### 4.1 Update AnswerForm Component

**File:** `fyli-fe-v2/src/components/question/AnswerForm.vue`

```vue
<template>
  <div class="answer-form">
    <div class="card">
      <div class="card-body">
        <div class="question-prompt mb-3 p-3 bg-light rounded border-start border-primary border-4">
          <p class="mb-0 fst-italic">"{{ question.text }}"</p>
        </div>

        <div class="mb-3">
          <label :for="`answer-${question.questionId}`" class="visually-hidden">Your answer</label>
          <textarea
            :id="`answer-${question.questionId}`"
            v-model="content"
            class="form-control"
            rows="4"
            placeholder="Share your memory..."
            maxlength="4000"
            :aria-describedby="`char-count-${question.questionId}`"
            :aria-invalid="content.length > 4000"
          ></textarea>
          <small :id="`char-count-${question.questionId}`" class="text-muted">{{ content.length }}/4000</small>
        </div>

        <div class="mb-3">
          <label :for="`date-${question.questionId}`" class="form-label">When did this happen?</label>
          <input :id="`date-${question.questionId}`" v-model="date" type="date" class="form-control" />
        </div>

        <!-- Combined Photos & Videos upload -->
        <div class="mb-3">
          <label :for="`media-${question.questionId}`" class="form-label">Photos & Videos</label>
          <input
            :id="`media-${question.questionId}`"
            type="file"
            class="form-control"
            accept="image/*,video/*"
            multiple
            :aria-describedby="`media-help-${question.questionId}`"
            @change="onFileChange"
          />
          <div :id="`media-help-${question.questionId}`" class="form-text">
            Supported: JPG, PNG, HEIC, MP4, MOV. Max video size: 5GB.
          </div>
          <div v-if="fileError" role="alert" class="text-danger mt-1">{{ fileError }}</div>

          <!-- Unified preview grid -->
          <div
            v-if="fileEntries.length"
            class="mt-2 d-flex gap-2 flex-wrap"
            role="list"
            aria-label="Selected media"
          >
            <div
              v-for="entry in fileEntries"
              :key="entry.id"
              class="position-relative media-preview"
              role="listitem"
            >
              <!-- Video preview -->
              <video
                v-if="entry.type === 'video'"
                :src="entry.previewUrl"
                class="rounded"
                muted
                preload="metadata"
              />
              <!-- Image preview -->
              <img
                v-else
                :src="entry.previewUrl"
                class="rounded"
                alt="Selected media"
              />

              <!-- Video upload progress overlay -->
              <div
                v-if="entry.type === 'video' && videoProgress[entry.id] != null"
                class="position-absolute top-0 start-0 w-100 h-100 d-flex align-items-center justify-content-center rounded"
                style="background: rgba(0, 0, 0, 0.5)"
              >
                <span class="text-white small">{{ videoProgress[entry.id] }}%</span>
              </div>

              <!-- Remove button -->
              <button
                type="button"
                class="btn btn-sm btn-danger position-absolute top-0 end-0"
                style="padding: 0.1rem 0.3rem; font-size: 0.7rem"
                :disabled="isSubmitting"
                @click="removeFile(entry.id)"
                :aria-label="`Remove ${entry.type}`"
              >
                <span class="mdi mdi-close" aria-hidden="true"></span>
              </button>
            </div>
          </div>
        </div>

        <div class="d-flex gap-2">
          <button
            type="button"
            class="btn btn-primary"
            :disabled="!content.trim() || isSubmitting"
            @click="handleSubmit"
          >
            {{ isSubmitting ? "Submitting..." : "Submit Answer" }}
          </button>
          <button
            type="button"
            class="btn btn-outline-secondary"
            :disabled="isSubmitting"
            @click="emit('cancel')"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import type { QuestionView } from "@/types";
import { useFileUpload, type FileEntry } from "@/composables/useFileUpload";

export interface AnswerPayload {
  questionId: number;
  content: string;
  date: string;
  dateType: number;
  files: FileEntry[];
}

const props = defineProps<{
  question: QuestionView;
  isSubmitting?: boolean;
}>();

const emit = defineEmits<{
  (e: "submit", payload: AnswerPayload): void;
  (e: "cancel"): void;
}>();

const content = ref("");
const date = ref(new Date().toISOString().split("T")[0]);

// Use the shared file upload composable
const {
  fileEntries,
  videoProgress,
  fileError,
  onFileChange,
  removeFile,
} = useFileUpload();

function handleSubmit() {
  if (!content.value.trim()) return;
  emit("submit", {
    questionId: props.question.questionId,
    content: content.value.trim(),
    date: date.value,
    dateType: 0, // DateTypes.Exact
    files: fileEntries.value
  });
}
</script>

<style scoped>
.media-preview {
  width: 80px;
  height: 80px;
}

.media-preview img,
.media-preview video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
</style>
```

---

## Phase 5: Update QuestionAnswerView

### 5.1 Integrate AnswerPreview and Handle New Payload

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

Key changes:
1. Import and use `AnswerPreview` component
2. Update question list to show `AnswerPreview` for answered questions
3. Update `handleAnswerSubmit` to work with `FileEntry[]` instead of separate arrays

```vue
<template>
  <div class="container py-4" style="max-width: 600px">
    <div v-if="loading" class="text-center py-5" aria-busy="true" aria-live="polite">
      <LoadingSpinner />
    </div>

    <div v-else-if="fatalError" role="alert" class="alert alert-danger text-center">
      {{ fatalError }}
    </div>

    <div v-else-if="view">
      <!-- Header -->
      <header class="text-center mb-4">
        <h1 class="h4">{{ view.creatorName }} asked you some questions</h1>
        <p v-if="view.message" class="text-muted">{{ view.message }}</p>
        <div class="badge bg-secondary" aria-live="polite">{{ answeredCount }} of {{ totalCount }} answered</div>
      </header>

      <!-- Error banner -->
      <div v-if="error" role="alert" class="alert alert-danger mb-4">
        {{ error }}
        <button type="button" class="btn-close float-end" @click="error = ''" aria-label="Dismiss error"></button>
      </div>

      <!-- Active Answer Form -->
      <div v-if="activeQuestionId !== null">
        <AnswerForm
          :question="view.questions.find((q) => q.questionId === activeQuestionId)!"
          :is-submitting="isSubmitting"
          @submit="handleAnswerSubmit"
          @cancel="cancelAnswer"
        />
      </div>

      <!-- Question List -->
      <div v-else class="d-flex flex-column gap-3 mb-4" role="list" aria-label="Questions">
        <template v-for="q in view.questions" :key="q.questionId">
          <!-- Answered question: show preview -->
          <AnswerPreview
            v-if="q.isAnswered || answeredDrops.has(q.questionId)"
            :question="getQuestionWithLocalAnswer(q)"
            @edit="startAnswer"
          />

          <!-- Unanswered question: show prompt -->
          <div v-else class="card" role="listitem">
            <div class="card-body">
              <div class="d-flex justify-content-between align-items-start">
                <div>
                  <p class="mb-1">{{ q.text }}</p>
                  <span v-if="pendingAnswers.has(q.questionId)" class="badge bg-warning" aria-live="polite">
                    Submitting...
                  </span>
                </div>
                <button
                  v-if="!pendingAnswers.has(q.questionId)"
                  class="btn btn-sm btn-primary"
                  @click="startAnswer(q.questionId)"
                >
                  Answer
                </button>
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- Registration Prompt -->
      <div v-if="showRegister && !auth.isAuthenticated" class="card" role="region" aria-labelledby="register-title">
        <div class="card-body">
          <h5 id="register-title" class="card-title">Keep your memories safe</h5>
          <p class="card-text text-muted">
            Create an account to save your answers to your own feed and get notified when
            {{ view.creatorName }} shares with you.
          </p>

          <div class="mb-3">
            <label for="reg-email" class="visually-hidden">Email</label>
            <input id="reg-email" v-model="regEmail" type="email" class="form-control mb-2" placeholder="Email" />
            <label for="reg-name" class="visually-hidden">Your name</label>
            <input id="reg-name" v-model="regName" type="text" class="form-control mb-2" placeholder="Your name" />
            <div class="form-check">
              <input v-model="regAcceptTerms" type="checkbox" class="form-check-input" id="acceptTerms" />
              <label class="form-check-label" for="acceptTerms">
                I agree to the <a href="/terms" target="_blank">Terms of Service</a>
              </label>
            </div>
          </div>

          <div v-if="regError" role="alert" class="alert alert-danger py-2">{{ regError }}</div>

          <div class="d-flex gap-2">
            <button class="btn btn-primary" :disabled="regSubmitting" @click="handleRegister">
              {{ regSubmitting ? "Creating..." : "Create Account" }}
            </button>
            <button class="btn btn-link text-muted" @click="showRegister = false">Skip for now</button>
          </div>
        </div>
      </div>

      <!-- All Done Message -->
      <div v-if="answeredCount === totalCount && !showRegister" class="text-center py-4" role="status">
        <p class="text-success mb-2">All questions answered!</p>
        <p class="text-muted">{{ view.creatorName }} will be notified of your responses.</p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useRoute } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import {
  getQuestionsForAnswer,
  submitAnswer,
  registerViaQuestion,
  uploadAnswerImage,
  requestAnswerMovieUpload,
  completeAnswerMovieUpload
} from "@/services/questionApi";
import { uploadFileToS3 } from "@/services/mediaApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionRequestView, QuestionView, AnswerView } from "@/types";
import type { AnswerPayload } from "@/components/question/AnswerForm.vue";
import type { FileEntry } from "@/composables/useFileUpload";
import AnswerForm from "@/components/question/AnswerForm.vue";
import AnswerPreview from "@/components/question/AnswerPreview.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

// Type for questions with confirmed answers (used by AnswerPreview)
interface AnsweredQuestion extends Omit<QuestionView, 'answer'> {
  answer: AnswerView;
}

const route = useRoute();
const auth = useAuthStore();
const token = route.params.token as string;

const view = ref<QuestionRequestView | null>(null);
const loading = ref(true);
const fatalError = ref("");
const error = ref("");
const activeQuestionId = ref<number | null>(null);
const answeredDrops = ref<Map<number, AnswerView>>(new Map());
const pendingAnswers = ref<Set<number>>(new Set());
const isSubmitting = ref(false);

// Registration state
const showRegister = ref(false);
const regEmail = ref("");
const regName = ref("");
const regAcceptTerms = ref(false);
const regSubmitting = ref(false);
const regError = ref("");

const answeredCount = computed(() => {
  if (!view.value) return 0;
  return view.value.questions.filter(
    (q) => q.isAnswered || answeredDrops.value.has(q.questionId) || pendingAnswers.value.has(q.questionId)
  ).length;
});

const totalCount = computed(() => view.value?.questions.length ?? 0);

onMounted(async () => {
  await loadQuestions();
});

async function loadQuestions() {
  loading.value = true;
  fatalError.value = "";
  try {
    const { data } = await getQuestionsForAnswer(token);
    view.value = data;
  } catch (e: unknown) {
    fatalError.value = getErrorMessage(e, "This question link is no longer active.");
  } finally {
    loading.value = false;
  }
}

function startAnswer(questionId: number) {
  activeQuestionId.value = questionId;
}

function cancelAnswer() {
  activeQuestionId.value = null;
}

/**
 * Merges server answer data with local optimistic updates.
 * Returns AnsweredQuestion type for use with AnswerPreview component.
 * Should only be called when q.isAnswered or answeredDrops.has(q.questionId).
 */
function getQuestionWithLocalAnswer(q: QuestionView): AnsweredQuestion {
  const localAnswer = answeredDrops.value.get(q.questionId);
  if (localAnswer) {
    return { ...q, answer: localAnswer, isAnswered: true };
  }
  // q.answer is guaranteed to exist when isAnswered is true
  return q as AnsweredQuestion;
}

async function handleAnswerSubmit(payload: AnswerPayload) {
  const { questionId, content, date, dateType, files } = payload;

  // Optimistic update - show as pending immediately
  pendingAnswers.value.add(questionId);
  activeQuestionId.value = null;
  isSubmitting.value = true;
  error.value = "";

  try {
    const { data: drop } = await submitAnswer(token, {
      questionId,
      content,
      date,
      dateType: dateType as 0 | 1 | 2 | 3
    });

    // Upload media files using unified approach
    const uploadedImages: { imageDropId: number; url: string }[] = [];
    const uploadedVideos: { movieDropId: number; thumbnailUrl: string }[] = [];

    for (const entry of files) {
      try {
        if (entry.type === "image") {
          const { data: imgData } = await uploadAnswerImage(token, drop.dropId, entry.file);
          uploadedImages.push({
            imageDropId: imgData.imageDropId,
            url: imgData.url
          });
        } else {
          const { data: uploadReq } = await requestAnswerMovieUpload(
            token, drop.dropId, entry.file.size, entry.file.type
          );
          const { promise } = uploadFileToS3(uploadReq.presignedUrl, entry.file);
          await promise;
          await completeAnswerMovieUpload(token, uploadReq.movieId, drop.dropId);
          uploadedVideos.push({
            movieDropId: uploadReq.movieId,
            thumbnailUrl: "" // Thumbnail generated asynchronously
          });
        }
      } catch (mediaErr) {
        console.error(`${entry.type} upload failed:`, mediaErr);
        error.value = "Some media failed to upload. You can edit your answer to retry.";
      }
    }

    // Build local answer view for immediate display
    const localAnswer: AnswerView = {
      dropId: drop.dropId,
      content,
      date,
      dateType: dateType as 0 | 1 | 2 | 3,
      canEdit: true, // Just created, always editable
      images: uploadedImages,
      movies: uploadedVideos
    };

    // Success - move from pending to answered
    pendingAnswers.value.delete(questionId);
    answeredDrops.value.set(questionId, localAnswer);

    // Show registration prompt after first answer
    if (answeredCount.value === 1 && !auth.isAuthenticated) {
      showRegister.value = true;
    }
  } catch (e: unknown) {
    // Rollback optimistic update
    pendingAnswers.value.delete(questionId);
    error.value = getErrorMessage(e, "Failed to submit answer");
  } finally {
    isSubmitting.value = false;
  }
}

async function handleRegister() {
  if (!regEmail.value.trim() || !regName.value.trim()) {
    regError.value = "Email and name are required";
    return;
  }
  if (!regAcceptTerms.value) {
    regError.value = "You must accept the terms to create an account";
    return;
  }

  regSubmitting.value = true;
  regError.value = "";

  try {
    const { data: jwt } = await registerViaQuestion(token, regEmail.value.trim(), regName.value.trim(), regAcceptTerms.value);
    auth.setToken(jwt);
    await auth.fetchUser();
    showRegister.value = false;
  } catch (e: unknown) {
    regError.value = getErrorMessage(e, "Registration failed");
  } finally {
    regSubmitting.value = false;
  }
}
</script>
```

### 5.2 Update questionApi.ts Response Types

**File:** `fyli-fe-v2/src/services/questionApi.ts`

The API functions don't need changes — they already return `QuestionRequestView`. The type updates in `question.ts` (Phase 2) will ensure TypeScript recognizes the new `answer` field.

However, we need to ensure `uploadAnswerImage` returns the image data:

```typescript
// Existing function - verify it returns image data
export function uploadAnswerImage(token: string, dropId: number, file: File) {
  const formData = new FormData();
  formData.append("file", file);
  return api.post<{ imageDropId: number; url: string }>(
    `/questions/answer/${token}/images`,
    formData,
    { headers: { "Content-Type": "multipart/form-data" } }
  );
}
```

---

## Phase 6: Testing

### 6.1 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs`

Add tests for the enhanced `GetQuestionRequestByToken`:

```csharp
[Fact]
public async Task GetQuestionRequestByToken_WithAnsweredQuestion_ReturnsAnswerContent()
{
    // Arrange
    var token = Guid.NewGuid();
    var recipient = await CreateRecipientWithAnswer(token);

    // Act
    var result = await _questionService.GetQuestionRequestByToken(token);

    // Assert
    var answeredQuestion = result.Questions.Single(q => q.IsAnswered);
    Assert.NotNull(answeredQuestion.Answer);
    Assert.Equal("Test answer content", answeredQuestion.Answer.Content);
    Assert.True(answeredQuestion.Answer.CanEdit);
}

[Fact]
public async Task GetQuestionRequestByToken_AnonymousAfter7Days_CanEditIsFalse()
{
    // Arrange
    var token = Guid.NewGuid();
    var recipient = await CreateRecipientWithOldAnswer(token, daysAgo: 8);

    // Act
    var result = await _questionService.GetQuestionRequestByToken(token);

    // Assert
    var answeredQuestion = result.Questions.Single(q => q.IsAnswered);
    Assert.False(answeredQuestion.Answer.CanEdit);
}

[Fact]
public async Task GetQuestionRequestByToken_WithMedia_ReturnsImageAndMovieUrls()
{
    // Arrange
    var token = Guid.NewGuid();
    var recipient = await CreateRecipientWithAnswerAndMedia(token);

    // Act
    var result = await _questionService.GetQuestionRequestByToken(token);

    // Assert
    var answeredQuestion = result.Questions.Single(q => q.IsAnswered);
    Assert.Single(answeredQuestion.Answer.Images);
    Assert.NotEmpty(answeredQuestion.Answer.Images[0].Url);
    Assert.Single(answeredQuestion.Answer.Movies);
}
```

### 6.2 Frontend Component Tests

**File:** `fyli-fe-v2/src/components/question/AnswerPreview.test.ts`

```typescript
import { describe, it, expect } from 'vitest';
import { mount } from '@vue/test-utils';
import AnswerPreview from './AnswerPreview.vue';
import type { AnswerView } from '@/types';

// AnsweredQuestion type matches the component's prop interface
interface AnsweredQuestion {
  questionId: number;
  text: string;
  sortOrder: number;
  isAnswered: boolean;
  answer: AnswerView;
}

const mockQuestion: AnsweredQuestion = {
  questionId: 1,
  text: 'What is your favorite memory?',
  sortOrder: 0,
  isAnswered: true,
  answer: {
    dropId: 100,
    content: 'Going to the beach with family.',
    date: '2025-07-04',
    dateType: 0,
    canEdit: true,
    images: [{ imageDropId: 1, url: 'https://example.com/img1.jpg' }],
    movies: []
  }
};

describe('AnswerPreview', () => {
  it('renders question text', () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    expect(wrapper.text()).toContain('What is your favorite memory?');
  });

  it('renders answer content', () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    expect(wrapper.text()).toContain('Going to the beach with family.');
  });

  it('formats exact date correctly', () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    expect(wrapper.text()).toContain('July 4, 2025');
  });

  it('formats month date correctly', () => {
    const question: AnsweredQuestion = {
      ...mockQuestion,
      answer: { ...mockQuestion.answer, dateType: 1 }
    };
    const wrapper = mount(AnswerPreview, { props: { question } });
    expect(wrapper.text()).toContain('July 2025');
  });

  it('shows Edit button when canEdit is true', () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    expect(wrapper.find('button').text()).toContain('Edit');
  });

  it('shows locked message when canEdit is false', () => {
    const question: AnsweredQuestion = {
      ...mockQuestion,
      answer: { ...mockQuestion.answer, canEdit: false }
    };
    const wrapper = mount(AnswerPreview, { props: { question } });
    expect(wrapper.text()).toContain('Edit window closed');
  });

  it('emits edit event when Edit button clicked', async () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    await wrapper.find('button').trigger('click');
    expect(wrapper.emitted('edit')).toEqual([[1]]);
  });

  it('renders image thumbnails', () => {
    const wrapper = mount(AnswerPreview, {
      props: { question: mockQuestion }
    });
    const imgs = wrapper.findAll('.media-thumb img');
    expect(imgs).toHaveLength(1);
    expect(imgs[0].attributes('src')).toBe('https://example.com/img1.jpg');
  });

  it('renders video thumbnails with play overlay', () => {
    const question: AnsweredQuestion = {
      ...mockQuestion,
      answer: {
        ...mockQuestion.answer,
        images: [],
        movies: [{ movieDropId: 1, thumbnailUrl: 'https://example.com/thumb.jpg' }]
      }
    };
    const wrapper = mount(AnswerPreview, { props: { question } });
    expect(wrapper.find('.play-overlay').exists()).toBe(true);
  });

  it('shows video placeholder when thumbnailUrl is empty', () => {
    const question: AnsweredQuestion = {
      ...mockQuestion,
      answer: {
        ...mockQuestion.answer,
        images: [],
        movies: [{ movieDropId: 1, thumbnailUrl: '' }]
      }
    };
    const wrapper = mount(AnswerPreview, { props: { question } });
    expect(wrapper.find('.video-placeholder').exists()).toBe(true);
  });
});
```

**File:** `fyli-fe-v2/src/components/question/AnswerForm.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import AnswerForm from './AnswerForm.vue';
import type { QuestionView } from '@/types';

// Mock useFileUpload composable
vi.mock('@/composables/useFileUpload', () => ({
  useFileUpload: () => ({
    fileEntries: { value: [] },
    videoProgress: { value: {} },
    fileError: { value: '' },
    onFileChange: vi.fn(),
    removeFile: vi.fn()
  })
}));

const mockQuestion: QuestionView = {
  questionId: 1,
  text: 'What is your favorite memory?',
  sortOrder: 0,
  isAnswered: false
};

describe('AnswerForm', () => {
  it('renders question text', () => {
    const wrapper = mount(AnswerForm, {
      props: { question: mockQuestion }
    });
    expect(wrapper.text()).toContain('What is your favorite memory?');
  });

  it('has combined media file input', () => {
    const wrapper = mount(AnswerForm, {
      props: { question: mockQuestion }
    });
    const input = wrapper.find('input[type="file"]');
    expect(input.attributes('accept')).toBe('image/*,video/*');
  });

  it('disables submit when content is empty', () => {
    const wrapper = mount(AnswerForm, {
      props: { question: mockQuestion }
    });
    const submitBtn = wrapper.find('button.btn-primary');
    expect(submitBtn.attributes('disabled')).toBeDefined();
  });

  it('emits submit with files array', async () => {
    const wrapper = mount(AnswerForm, {
      props: { question: mockQuestion }
    });

    await wrapper.find('textarea').setValue('My answer');
    await wrapper.find('button.btn-primary').trigger('click');

    expect(wrapper.emitted('submit')).toBeDefined();
    const payload = wrapper.emitted('submit')![0][0];
    expect(payload).toHaveProperty('files');
    expect(Array.isArray(payload.files)).toBe(true);
  });

  it('emits cancel when Cancel clicked', async () => {
    const wrapper = mount(AnswerForm, {
      props: { question: mockQuestion }
    });
    await wrapper.find('button.btn-outline-secondary').trigger('click');
    expect(wrapper.emitted('cancel')).toBeDefined();
  });
});
```

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts`

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createWebHistory } from 'vue-router';
import { createPinia, setActivePinia } from 'pinia';
import QuestionAnswerView from './QuestionAnswerView.vue';

// Mock API
vi.mock('@/services/questionApi', () => ({
  getQuestionsForAnswer: vi.fn(),
  submitAnswer: vi.fn(),
  registerViaQuestion: vi.fn(),
  uploadAnswerImage: vi.fn(),
  requestAnswerMovieUpload: vi.fn(),
  completeAnswerMovieUpload: vi.fn()
}));

vi.mock('@/services/mediaApi', () => ({
  uploadFileToS3: vi.fn(() => ({ promise: Promise.resolve() }))
}));

import * as questionApi from '@/services/questionApi';

const mockView = {
  questionRequestRecipientId: 1,
  creatorName: 'Test User',
  message: 'Please answer these questions',
  questionSetName: 'Family Memories',
  questions: [
    {
      questionId: 1,
      text: 'Question 1?',
      sortOrder: 0,
      isAnswered: true,
      answer: {
        dropId: 100,
        content: 'My answer',
        date: '2025-01-01',
        dateType: 0,
        canEdit: true,
        images: [],
        movies: []
      }
    },
    {
      questionId: 2,
      text: 'Question 2?',
      sortOrder: 1,
      isAnswered: false
    }
  ]
};

describe('QuestionAnswerView', () => {
  beforeEach(() => {
    setActivePinia(createPinia());
    vi.mocked(questionApi.getQuestionsForAnswer).mockResolvedValue({ data: mockView });
  });

  const createWrapper = async () => {
    const router = createRouter({
      history: createWebHistory(),
      routes: [{ path: '/q/:token', component: QuestionAnswerView }]
    });
    await router.push('/q/test-token');
    await router.isReady();

    const wrapper = mount(QuestionAnswerView, {
      global: { plugins: [router] }
    });
    await flushPromises();
    return wrapper;
  };

  it('displays answered question with AnswerPreview', async () => {
    const wrapper = await createWrapper();
    expect(wrapper.text()).toContain('My answer');
    expect(wrapper.text()).toContain('Question 1?');
  });

  it('displays unanswered question with Answer button', async () => {
    const wrapper = await createWrapper();
    expect(wrapper.text()).toContain('Question 2?');
    expect(wrapper.find('button').text()).toContain('Answer');
  });

  it('shows progress badge', async () => {
    const wrapper = await createWrapper();
    expect(wrapper.text()).toContain('1 of 2 answered');
  });

  it('shows all done message when all questions answered', async () => {
    const allAnsweredView = {
      ...mockView,
      questions: mockView.questions.map(q => ({
        ...q,
        isAnswered: true,
        answer: q.answer || {
          dropId: 101,
          content: 'Answer 2',
          date: '2025-01-02',
          dateType: 0,
          canEdit: true,
          images: [],
          movies: []
        }
      }))
    };
    vi.mocked(questionApi.getQuestionsForAnswer).mockResolvedValue({ data: allAnsweredView });

    const wrapper = await createWrapper();
    expect(wrapper.text()).toContain('All questions answered');
  });
});
```

---

## Implementation Order

1. **Phase 1: Backend API Enhancement**
   - Add `AnswerViewModel` and related models
   - Modify `GetQuestionRequestByToken` to include answer data
   - Add backend tests

2. **Phase 2: Frontend Type Updates**
   - Extend `QuestionView` interface with `answer` field
   - Add `AnswerView`, `AnswerImage`, `AnswerMovie` interfaces

3. **Phase 3: AnswerPreview Component**
   - Create new component with question/answer display
   - Add date formatting logic
   - Add media thumbnail grid
   - Add component tests

4. **Phase 4: Refactor AnswerForm**
   - Replace custom file handling with `useFileUpload`
   - Update template to single file input
   - Update payload type to include `FileEntry[]`
   - Add component tests

5. **Phase 5: Update QuestionAnswerView**
   - Integrate `AnswerPreview` component
   - Update `handleAnswerSubmit` for new payload
   - Add optimistic updates with `AnswerView`
   - Add view tests

6. **Phase 6: Integration Testing**
   - End-to-end test of answer flow
   - Verify media upload works with token auth
   - Test edit flow for answered questions

---

## Migration Notes

- No database migrations required
- API is backward compatible (adds fields, doesn't remove any)
- Frontend changes are additive; old clients will ignore new fields

---

## Review Feedback Addressed

The following issues from code review have been addressed in this TDD:

| Priority | Issue | Resolution |
|----------|-------|------------|
| Critical | EF Core filtered include in nested ThenInclude | Moved filtering to `BuildAnswerViewModel` mapping phase |
| High | Initialize model lists | Added `= new()` to `Images` and `Movies` properties |
| Medium | AnswerPreview null guard | Created `AnsweredQuestion` interface requiring `answer` |
| Low | Inline styles | Extracted `font-size` to `.play-icon` CSS class |
| Enhancement | XML doc comments | Added doc comments to all new model classes |
| Enhancement | Token upload clarification | Added design decision section explaining approach |

---

*Document Version: 1.1*
*Created: 2026-02-06*
*Updated: 2026-02-06 — Addressed code review feedback*
*Status: Draft*
