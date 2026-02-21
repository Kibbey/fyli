# TDD: Video Processing Placeholder with Refresh

## Overview

Address the timing issue with video uploads in the question answer flow. After a video is uploaded, AWS MediaConvert takes time to transcode it. Currently, if the user views the answer immediately, the video may fail to load because transcoding hasn't completed. This TDD implements:

1. A transcode delay after video upload (matching the memory creation pattern)
2. An enhanced "processing" placeholder UI with a refresh button
3. Per-video refresh capability without full page reload

## Problem Statement

When a user uploads a video as part of their answer:
1. The video is uploaded to S3
2. `completeAnswerMovieUpload` triggers AWS MediaConvert transcoding
3. The UI immediately shows the blob URL for local preview
4. When the page is reloaded or the answer is fetched from the server, the transcoded video URL may not be ready yet
5. The video fails to load, showing a broken experience

## Goals

1. **Add transcode delay**: After video upload completes, wait before transitioning to the "answered" state (2-8 seconds based on file size)
2. **Enhanced processing placeholder**: Show a user-friendly placeholder with an explanation and refresh button
3. **Per-video refresh**: Allow users to refresh individual videos without reloading the entire page
4. **Graceful degradation**: If the video still isn't ready after refresh, show the placeholder again with updated messaging

## Technical Design

### Phase 1: Add Transcode Delay to Answer Submission

Apply the same delay pattern used in memory creation after video uploads complete.

#### 1.1 Update QuestionAnswerView.vue

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

Import the existing `getTranscodeDelay` function and apply it after video uploads:

```typescript
import { getTranscodeDelay } from "@/composables/useFileUpload";

// Add state for showing processing feedback during delay
const processingVideoDelay = ref(false);

// In handleAnswerSubmit, after all uploads complete:
async function handleAnswerSubmit(payload: AnswerPayload) {
	// ... existing code ...

	try {
		const { data: drop } = await submitAnswer(token, { ... });

		// Upload media files and collect results
		const uploadedImages: AnswerImage[] = [];
		const uploadedVideos: AnswerMovie[] = [];

		for (const entry of files) {
			// ... existing upload logic ...
		}

		// Wait for transcoding to start processing
		const delay = getTranscodeDelay(files);
		if (delay > 0) {
			processingVideoDelay.value = true;
			await new Promise((resolve) => setTimeout(resolve, delay));
			processingVideoDelay.value = false;
		}

		// Build local answer view with uploaded media URLs
		const localAnswer: AnswerView = { ... };

		// ... rest of function ...
	}
}
```

Add template feedback for the delay:

```vue
<!-- Show processing indicator during transcode delay -->
<div v-if="processingVideoDelay" class="text-center py-3">
	<div class="spinner-border spinner-border-sm text-primary me-2" role="status">
		<span class="visually-hidden">Processing video...</span>
	</div>
	<span class="text-muted">Processing video...</span>
</div>
```

### Phase 2: Create VideoProcessingPlaceholder Component

Create a reusable component for the processing state with refresh capability.

#### 2.1 New Component

**File:** `fyli-fe-v2/src/components/question/VideoProcessingPlaceholder.vue`

```vue
<template>
	<div
		class="video-processing-placeholder rounded d-flex flex-column align-items-center justify-content-center bg-light border"
		aria-live="polite"
	>
		<div v-if="isRefreshing" class="text-center">
			<div class="spinner-border spinner-border-sm text-primary mb-2" role="status">
				<span class="visually-hidden">Checking video status...</span>
			</div>
			<p class="text-muted small mb-0">Checking video status...</p>
		</div>
		<div v-else class="text-center p-3">
			<span class="mdi mdi-video-processing text-secondary mb-2" style="font-size: 2rem;" aria-hidden="true"></span>
			<p class="text-muted small mb-2">
				{{ hasRefreshed ? "Video is still processing..." : "Video is being processed..." }}
			</p>
			<p class="text-muted small mb-3">
				This usually takes a few seconds. Click below to check if it's ready.
			</p>
			<button
				type="button"
				class="btn btn-sm btn-outline-primary"
				@click="handleRefresh"
				:disabled="isRefreshing"
				aria-label="Check if video is ready"
			>
				<span class="mdi mdi-refresh me-1" aria-hidden="true"></span>
				Check if ready
			</button>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref } from "vue";

defineProps<{
	movieDropId: number;
}>();

const emit = defineEmits<{
	(e: "refresh", movieDropId: number): void;
}>();

const isRefreshing = ref(false);
const hasRefreshed = ref(false);

function handleRefresh() {
	isRefreshing.value = true;
	hasRefreshed.value = true;
	emit("refresh", props.movieDropId);
}

/**
 * Called by parent when refresh completes.
 */
function onRefreshComplete() {
	isRefreshing.value = false;
}

defineExpose({ onRefreshComplete });
</script>

<style scoped>
.video-processing-placeholder {
	width: 100%;
	min-height: 200px;
}
</style>
```

### Phase 3: Add Video Status Refresh API

Create an API endpoint and frontend service to check a single video's status.

#### 3.1 Backend Endpoint

**File:** `cimplur-core/Memento/Memento/Controllers/QuestionController.cs`

Add a new endpoint to get a single video's current URLs:

```csharp
/// <summary>
/// Gets the current video URLs for a specific movie in an answer.
/// Used to refresh video status after transcoding.
/// </summary>
[EnableRateLimiting("public")]
[HttpGet]
[Route("answer/{token:guid}/movies/{movieId:int}")]
public async Task<IActionResult> GetAnswerMovieStatus(Guid token, int movieId)
{
    var result = await questionService.GetAnswerMovieStatus(token, movieId);
    if (result == null)
        return NotFound("Invalid token or movie.");

    return Ok(result);
}
```

#### 3.2 Backend Service Method

**File:** `cimplur-core/Memento/Domain/Repositories/IQuestionService.cs`

Add interface method:

```csharp
// Video Status
Task<AnswerMovieModel?> GetAnswerMovieStatus(Guid token, int movieId);
```

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

Implementation:

```csharp
/// <summary>
/// Gets the current video URLs for a specific movie.
/// Returns null if the token doesn't own the movie.
/// </summary>
public async Task<AnswerMovieModel?> GetAnswerMovieStatus(Guid token, int movieId)
{
    var movie = await Context.MovieDrops
        .Include(m => m.Drop)
            .ThenInclude(d => d.QuestionResponses)
                .ThenInclude(qr => qr.QuestionRequestRecipient)
                    .ThenInclude(r => r.QuestionRequest)
        .FirstOrDefaultAsync(m => m.MovieDropId == movieId);

    if (movie == null)
        return null;

    // Verify the token owns this movie via the question response chain
    var recipient = movie.Drop.QuestionResponses
        .Select(qr => qr.QuestionRequestRecipient)
        .FirstOrDefault(r => r.Token == token);

    if (recipient == null)
        return null;

    var creatorUserId = recipient.QuestionRequest?.CreatorUserId
        ?? recipient.RespondentUserId
        ?? 0;

    if (creatorUserId == 0)
        return null;

    return new AnswerMovieModel
    {
        MovieDropId = movie.MovieDropId,
        ThumbnailUrl = movieService.GetThumbLink(movie.MovieDropId, creatorUserId, movie.DropId, movie.IsTranscodeV2),
        VideoUrl = movieService.GetLink(movie.MovieDropId, creatorUserId, movie.DropId, movie.IsTranscodeV2)
    };
}
```

#### 3.3 Frontend API Service

**File:** `fyli-fe-v2/src/services/questionApi.ts`

Add the new API function:

```typescript
/**
 * Gets current video URLs for a specific movie.
 * Used to refresh video status after transcoding.
 */
export function getAnswerMovieStatus(token: string, movieId: number) {
	return api.get<{ movieDropId: number; thumbnailUrl: string; videoUrl: string }>(
		`/questions/answer/${token}/movies/${movieId}`
	);
}
```

### Phase 4: Update AnswerPreview with Refresh Logic

Enhance AnswerPreview to handle video refresh and status updates.

#### 4.1 Update AnswerPreview.vue

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

					<!-- Images using PhotoGrid with lightbox -->
					<PhotoGrid v-if="imageLinks.length" :images="imageLinks" class="mb-3" />

					<!-- Videos - playable or processing placeholder -->
					<div v-for="vid in displayMovies" :key="`vid-${vid.movieDropId}`" class="mb-3">
						<video
							v-if="isVideoReady(vid)"
							:src="getVideoSrc(vid)"
							:poster="getVideoPoster(vid)"
							controls
							class="img-fluid rounded video-player"
							preload="metadata"
							@error="handleVideoError(vid)"
						></video>
						<VideoProcessingPlaceholder
							v-else
							:ref="(el) => setPlaceholderRef(vid.movieDropId, el)"
							:movie-drop-id="vid.movieDropId"
							@refresh="handleVideoRefresh"
						/>
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
import { ref, computed } from "vue";
import type { AnswerView, AnswerMovie, ImageLink } from "@/types";
import PhotoGrid from "@/components/memory/PhotoGrid.vue";
import VideoProcessingPlaceholder from "./VideoProcessingPlaceholder.vue";

interface AnsweredQuestion {
	questionId: number;
	text: string;
	sortOrder: number;
	isAnswered: boolean;
	answer: AnswerView;
}

const props = defineProps<{
	question: AnsweredQuestion;
	token: string; // Required for refresh API calls
}>();

const emit = defineEmits<{
	(e: "edit", questionId: number): void;
	(e: "videoRefresh", movieDropId: number): void;
}>();

// Track placeholder component refs for calling onRefreshComplete
const placeholderRefs = ref<Map<number, InstanceType<typeof VideoProcessingPlaceholder>>>(new Map());

// Track videos that have had load errors (need to show placeholder instead)
const videoErrors = ref<Set<number>>(new Set());

// Track updated video URLs from refresh
const refreshedVideos = ref<Map<number, { videoUrl: string; thumbnailUrl: string }>>(new Map());

function setPlaceholderRef(movieId: number, el: InstanceType<typeof VideoProcessingPlaceholder> | null) {
	if (el) {
		placeholderRefs.value.set(movieId, el);
	} else {
		placeholderRefs.value.delete(movieId);
	}
}

/**
 * Merge refreshed video data with original movies.
 */
const displayMovies = computed<AnswerMovie[]>(() => {
	return props.question.answer.movies.map((movie) => {
		const refreshed = refreshedVideos.value.get(movie.movieDropId);
		if (refreshed) {
			return {
				...movie,
				videoUrl: refreshed.videoUrl,
				thumbnailUrl: refreshed.thumbnailUrl
			};
		}
		return movie;
	});
});

const imageLinks = computed<ImageLink[]>(() =>
	props.question.answer.images.map((img) => ({
		id: img.imageDropId,
		link: img.url
	}))
);

/**
 * Check if video is ready to play.
 * A video is ready if it has a valid URL and hasn't errored.
 */
function isVideoReady(vid: AnswerMovie): boolean {
	if (videoErrors.value.has(vid.movieDropId)) {
		return false;
	}
	// Blob URLs (local previews) are always ready
	if (vid.videoUrl.startsWith("blob:") || vid.thumbnailUrl.startsWith("blob:")) {
		return true;
	}
	// Server URLs are ready if videoUrl is present
	return Boolean(vid.videoUrl);
}

function getVideoSrc(vid: AnswerMovie): string {
	if (vid.thumbnailUrl.startsWith("blob:")) {
		return vid.thumbnailUrl;
	}
	return vid.videoUrl;
}

function getVideoPoster(vid: AnswerMovie): string | undefined {
	if (vid.thumbnailUrl.startsWith("blob:")) {
		return undefined;
	}
	return vid.thumbnailUrl || undefined;
}

/**
 * Handle video load error - show placeholder instead.
 */
function handleVideoError(vid: AnswerMovie) {
	videoErrors.value.add(vid.movieDropId);
}

/**
 * Handle refresh request from placeholder.
 * Simply emits to parent - parent will call updateVideoUrls or onRefreshFailed.
 */
function handleVideoRefresh(movieDropId: number) {
	emit("videoRefresh", movieDropId);
}

/**
 * Called by parent when video refresh completes successfully.
 */
function updateVideoUrls(movieDropId: number, videoUrl: string, thumbnailUrl: string) {
	// Clear error state since we have new URLs to try
	videoErrors.value.delete(movieDropId);

	// Store the refreshed URLs
	refreshedVideos.value.set(movieDropId, { videoUrl, thumbnailUrl });

	// Notify placeholder that refresh is complete
	const placeholder = placeholderRefs.value.get(movieDropId);
	placeholder?.onRefreshComplete();
}

/**
 * Called by parent when video refresh fails or video still not ready.
 */
function onRefreshFailed(movieDropId: number) {
	const placeholder = placeholderRefs.value.get(movieDropId);
	placeholder?.onRefreshComplete();
}

defineExpose({ updateVideoUrls, onRefreshFailed });

const formattedDate = computed(() => {
	const date = new Date(props.question.answer.date);
	const dateType = props.question.answer.dateType;

	switch (dateType) {
		case 1:
			return date.toLocaleDateString("en-US", { month: "long", year: "numeric" });
		case 2:
			return date.getFullYear().toString();
		case 3:
			return `${Math.floor(date.getFullYear() / 10) * 10}s`;
		default:
			return date.toLocaleDateString("en-US", {
				month: "long",
				day: "numeric",
				year: "numeric"
			});
	}
});
</script>

<style scoped>
.video-player {
	max-height: 400px;
	width: 100%;
	object-fit: contain;
}
</style>
```

### Phase 5: Update QuestionAnswerView to Handle Video Refresh

Wire up the refresh logic in the parent view.

#### 5.1 Update QuestionAnswerView.vue

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

Add the API import and handle the videoRefresh event:

```typescript
import { getAnswerMovieStatus } from "@/services/questionApi";
import { getTranscodeDelay } from "@/composables/useFileUpload";

// Add state for showing processing feedback during delay
const processingVideoDelay = ref(false);

// Add refs to track AnswerPreview components
const answerPreviewRefs = ref<Map<number, InstanceType<typeof AnswerPreview>>>(new Map());

// Template changes:
// Add ref and token to AnswerPreview, handle videoRefresh event
<AnswerPreview
	v-if="q.isAnswered || answeredDrops.has(q.questionId)"
	:ref="(el) => setAnswerPreviewRef(q.questionId, el)"
	:question="getQuestionWithLocalAnswer(q)"
	:token="token"
	@edit="startAnswer"
	@video-refresh="(movieId) => handleVideoRefresh(q.questionId, movieId)"
/>

// Add helper to track refs
function setAnswerPreviewRef(questionId: number, el: InstanceType<typeof AnswerPreview> | null) {
	if (el) {
		answerPreviewRefs.value.set(questionId, el);
	} else {
		answerPreviewRefs.value.delete(questionId);
	}
}

// Add handler for video refresh
async function handleVideoRefresh(questionId: number, movieDropId: number) {
	const previewRef = answerPreviewRefs.value.get(questionId);
	if (!previewRef) return;

	try {
		const { data } = await getAnswerMovieStatus(token, movieDropId);

		// Check if video is actually ready (videoUrl should be a valid S3 URL, not empty)
		if (data.videoUrl && !data.videoUrl.includes("undefined")) {
			previewRef.updateVideoUrls(movieDropId, data.videoUrl, data.thumbnailUrl);
		} else {
			previewRef.onRefreshFailed(movieDropId);
		}
	} catch (err) {
		console.error("Failed to refresh video status:", err);
		previewRef.onRefreshFailed(movieDropId);
	}
}

// Update handleAnswerSubmit to include delay with feedback
async function handleAnswerSubmit(payload: AnswerPayload) {
	// ... existing code up to uploads ...

	// Wait for transcoding to start processing
	const delay = getTranscodeDelay(files);
	if (delay > 0) {
		processingVideoDelay.value = true;
		await new Promise((resolve) => setTimeout(resolve, delay));
		processingVideoDelay.value = false;
	}

	// ... rest of function ...
}
```

Add template for delay feedback (add after the pending answers section):

```vue
<!-- Video processing delay indicator -->
<div v-if="processingVideoDelay" class="text-center py-3" role="status" aria-live="polite">
	<div class="spinner-border spinner-border-sm text-primary me-2" role="status">
		<span class="visually-hidden">Processing video...</span>
	</div>
	<span class="text-muted">Processing video...</span>
</div>
```

### Phase 6: Testing

#### 6.1 VideoProcessingPlaceholder Tests

**File:** `fyli-fe-v2/src/components/question/VideoProcessingPlaceholder.test.ts`

```typescript
import { describe, it, expect, vi } from "vitest";
import { mount } from "@vue/test-utils";
import VideoProcessingPlaceholder from "./VideoProcessingPlaceholder.vue";

describe("VideoProcessingPlaceholder", () => {
	it("renders processing message", () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});
		expect(wrapper.text()).toContain("Video is being processed");
		expect(wrapper.text()).toContain("Check if ready");
	});

	it("has aria-live attribute for accessibility", () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});
		expect(wrapper.find('[aria-live="polite"]').exists()).toBe(true);
	});

	it("emits refresh event when button clicked", async () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 42 }
		});

		await wrapper.find("button").trigger("click");

		expect(wrapper.emitted("refresh")).toEqual([[42]]);
	});

	it("shows refreshing state after button click", async () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});

		await wrapper.find("button").trigger("click");

		expect(wrapper.text()).toContain("Checking video status");
		expect(wrapper.find("button").attributes("disabled")).toBeDefined();
	});

	it("shows updated message after refresh", async () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});

		await wrapper.find("button").trigger("click");
		wrapper.vm.onRefreshComplete();
		await wrapper.vm.$nextTick();

		expect(wrapper.text()).toContain("still processing");
	});

	it("disables button during refresh", async () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});

		await wrapper.find("button").trigger("click");

		expect(wrapper.find("button").attributes("disabled")).toBeDefined();
	});

	it("re-enables button after onRefreshComplete", async () => {
		const wrapper = mount(VideoProcessingPlaceholder, {
			props: { movieDropId: 1 }
		});

		await wrapper.find("button").trigger("click");
		expect(wrapper.find("button").attributes("disabled")).toBeDefined();

		wrapper.vm.onRefreshComplete();
		await wrapper.vm.$nextTick();

		expect(wrapper.find("button").attributes("disabled")).toBeUndefined();
	});
});
```

#### 6.2 AnswerPreview Video Tests

**File:** `fyli-fe-v2/src/components/question/AnswerPreview.test.ts`

Add tests for video refresh functionality:

```typescript
import VideoProcessingPlaceholder from "./VideoProcessingPlaceholder.vue";

// Add to existing tests:

it("shows VideoProcessingPlaceholder for videos without URL", () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 1, thumbnailUrl: "", videoUrl: "" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	expect(wrapper.findComponent(VideoProcessingPlaceholder).exists()).toBe(true);
});

it("shows video player when videoUrl is present", () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 1, thumbnailUrl: "thumb.jpg", videoUrl: "video.mp4" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	expect(wrapper.find("video").exists()).toBe(true);
	expect(wrapper.findComponent(VideoProcessingPlaceholder).exists()).toBe(false);
});

it("emits videoRefresh when placeholder refresh is clicked", async () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 42, thumbnailUrl: "", videoUrl: "" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	const placeholder = wrapper.findComponent(VideoProcessingPlaceholder);
	await placeholder.find("button").trigger("click");

	expect(wrapper.emitted("videoRefresh")).toEqual([[42]]);
});

it("updates video after successful refresh via updateVideoUrls", async () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 1, thumbnailUrl: "", videoUrl: "" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	// Initially shows placeholder
	expect(wrapper.findComponent(VideoProcessingPlaceholder).exists()).toBe(true);

	// Simulate parent calling updateVideoUrls
	wrapper.vm.updateVideoUrls(1, "https://example.com/video.mp4", "https://example.com/thumb.jpg");
	await wrapper.vm.$nextTick();

	// Now shows video
	expect(wrapper.find("video").exists()).toBe(true);
	expect(wrapper.find("video").attributes("src")).toBe("https://example.com/video.mp4");
});

it("shows placeholder again after video error", async () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 1, thumbnailUrl: "thumb.jpg", videoUrl: "invalid.mp4" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	// Initially shows video
	expect(wrapper.find("video").exists()).toBe(true);

	// Trigger error event
	await wrapper.find("video").trigger("error");

	// Now shows placeholder
	expect(wrapper.findComponent(VideoProcessingPlaceholder).exists()).toBe(true);
});

it("clears error state after updateVideoUrls", async () => {
	const question = {
		...mockQuestion,
		answer: {
			...mockQuestion.answer,
			images: [],
			movies: [{ movieDropId: 1, thumbnailUrl: "thumb.jpg", videoUrl: "invalid.mp4" }]
		}
	};
	const wrapper = mount(AnswerPreview, {
		props: { question, token: "test-token" },
		global: { stubs: { PhotoGrid: true } }
	});

	// Trigger error
	await wrapper.find("video").trigger("error");
	expect(wrapper.findComponent(VideoProcessingPlaceholder).exists()).toBe(true);

	// Update with new URLs
	wrapper.vm.updateVideoUrls(1, "https://example.com/video.mp4", "https://example.com/thumb.jpg");
	await wrapper.vm.$nextTick();

	// Now shows video again
	expect(wrapper.find("video").exists()).toBe(true);
});
```

#### 6.3 QuestionAnswerView Integration Tests

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts`

Add test for transcode delay:

```typescript
import { getAnswerMovieStatus } from "@/services/questionApi";

// Add to mock
vi.mock("@/services/questionApi", () => ({
	// ... existing mocks ...
	getAnswerMovieStatus: vi.fn()
}));

it("applies transcode delay after video upload", async () => {
	const unansweredView = {
		...mockView,
		questions: [{ questionId: 1, text: "Q1?", sortOrder: 0, isAnswered: false }]
	};
	vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: unansweredView } as never);
	vi.mocked(submitAnswer).mockResolvedValue({ data: { dropId: 100 } } as never);
	vi.mocked(requestAnswerMovieUpload).mockResolvedValue({
		data: { movieId: 1, presignedUrl: "https://s3.example.com/upload" }
	} as never);
	vi.mocked(uploadFileToS3).mockReturnValue({ promise: Promise.resolve() } as never);
	vi.mocked(completeAnswerMovieUpload).mockResolvedValue({} as never);

	const startTime = Date.now();

	const wrapper = mount(QuestionAnswerView, {
		global: {
			stubs: { LoadingSpinner: true, AnswerPreview: true },
			components: { AnswerForm }
		}
	});
	await flushPromises();

	await wrapper.find("button.btn-primary").trigger("click");
	const form = wrapper.findComponent(AnswerForm);

	// Create a 50MB video file to trigger 2s delay
	const videoFile = new File([new ArrayBuffer(50 * 1024 * 1024)], "test.mp4", { type: "video/mp4" });

	form.vm.$emit("submit", {
		questionId: 1,
		content: "Answer with video",
		date: "2025-01-01",
		dateType: 0,
		files: [{ id: "v1", file: videoFile, previewUrl: "blob:http://localhost/video", type: "video" }]
	});
	await flushPromises();

	const elapsed = Date.now() - startTime;
	// Should have waited at least 2 seconds (with some tolerance)
	expect(elapsed).toBeGreaterThanOrEqual(1900);
});

it("shows processing indicator during transcode delay", async () => {
	const unansweredView = {
		...mockView,
		questions: [{ questionId: 1, text: "Q1?", sortOrder: 0, isAnswered: false }]
	};
	vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: unansweredView } as never);
	vi.mocked(submitAnswer).mockResolvedValue({ data: { dropId: 100 } } as never);
	vi.mocked(requestAnswerMovieUpload).mockResolvedValue({
		data: { movieId: 1, presignedUrl: "https://s3.example.com/upload" }
	} as never);
	vi.mocked(uploadFileToS3).mockReturnValue({ promise: Promise.resolve() } as never);
	vi.mocked(completeAnswerMovieUpload).mockResolvedValue({} as never);

	const wrapper = mount(QuestionAnswerView, {
		global: {
			stubs: { LoadingSpinner: true, AnswerPreview: true },
			components: { AnswerForm }
		}
	});
	await flushPromises();

	await wrapper.find("button.btn-primary").trigger("click");
	const form = wrapper.findComponent(AnswerForm);

	const videoFile = new File([new ArrayBuffer(50 * 1024 * 1024)], "test.mp4", { type: "video/mp4" });

	// Start submission but don't await
	const submitPromise = form.vm.$emit("submit", {
		questionId: 1,
		content: "Answer with video",
		date: "2025-01-01",
		dateType: 0,
		files: [{ id: "v1", file: videoFile, previewUrl: "blob:http://localhost/video", type: "video" }]
	});

	// Wait a tick for the delay to start
	await new Promise((r) => setTimeout(r, 100));

	// Should show processing message during delay
	expect(wrapper.text()).toContain("Processing video");
});

it("handles video refresh API call", async () => {
	vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: mockView } as never);
	vi.mocked(getAnswerMovieStatus).mockResolvedValue({
		data: { movieDropId: 1, videoUrl: "https://example.com/video.mp4", thumbnailUrl: "https://example.com/thumb.jpg" }
	} as never);

	const wrapper = mount(QuestionAnswerView, {
		global: {
			stubs: { LoadingSpinner: true, AnswerForm: true },
			components: { AnswerPreview }
		}
	});
	await flushPromises();

	// Trigger video refresh
	await wrapper.vm.handleVideoRefresh(2, 1);

	expect(getAnswerMovieStatus).toHaveBeenCalledWith("test-token-123", 1);
});

it("handles video refresh failure gracefully", async () => {
	vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: mockView } as never);
	vi.mocked(getAnswerMovieStatus).mockRejectedValue(new Error("Network error"));

	const wrapper = mount(QuestionAnswerView, {
		global: {
			stubs: { LoadingSpinner: true, AnswerForm: true },
			components: { AnswerPreview }
		}
	});
	await flushPromises();

	// Should not throw
	await expect(wrapper.vm.handleVideoRefresh(2, 1)).resolves.not.toThrow();
});
```

#### 6.4 Backend Unit Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs`

Add tests for `GetAnswerMovieStatus`:

```csharp
[Fact]
public async Task GetAnswerMovieStatus_ReturnsNull_WhenMovieDoesNotExist()
{
    // Arrange
    var token = Guid.NewGuid();
    var movieId = 999; // Non-existent

    // Act
    var result = await questionService.GetAnswerMovieStatus(token, movieId);

    // Assert
    Assert.Null(result);
}

[Fact]
public async Task GetAnswerMovieStatus_ReturnsNull_WhenTokenDoesNotOwnMovie()
{
    // Arrange
    var wrongToken = Guid.NewGuid();

    // Create a question request with a different token
    var recipient = await CreateQuestionRequestRecipient();
    var drop = await CreateDropWithMovie(recipient);

    // Act
    var result = await questionService.GetAnswerMovieStatus(wrongToken, drop.Movies.First().MovieDropId);

    // Assert
    Assert.Null(result);
}

[Fact]
public async Task GetAnswerMovieStatus_ReturnsUrls_WhenTokenOwnsMovie()
{
    // Arrange
    var recipient = await CreateQuestionRequestRecipient();
    var drop = await CreateDropWithMovie(recipient);
    var movieId = drop.Movies.First().MovieDropId;

    // Act
    var result = await questionService.GetAnswerMovieStatus(recipient.Token, movieId);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(movieId, result.MovieDropId);
    Assert.NotEmpty(result.VideoUrl);
    Assert.NotEmpty(result.ThumbnailUrl);
}

[Fact]
public async Task GetAnswerMovieStatus_ReturnsCorrectUrls_ForTranscodeV2()
{
    // Arrange
    var recipient = await CreateQuestionRequestRecipient();
    var drop = await CreateDropWithMovie(recipient, isTranscodeV2: true);
    var movieId = drop.Movies.First().MovieDropId;

    // Act
    var result = await questionService.GetAnswerMovieStatus(recipient.Token, movieId);

    // Assert
    Assert.NotNull(result);
    // Verify URLs are generated with V2 transcode paths
    Assert.Contains("transcoded", result.VideoUrl.ToLower());
}
```

## File Changes Summary

### New Files
| File | Description |
|------|-------------|
| `fyli-fe-v2/src/components/question/VideoProcessingPlaceholder.vue` | Processing placeholder with refresh button |
| `fyli-fe-v2/src/components/question/VideoProcessingPlaceholder.test.ts` | Tests for placeholder component |

### Modified Files - Backend
| File | Change |
|------|--------|
| `cimplur-core/Memento/Memento/Controllers/QuestionController.cs` | Add `GetAnswerMovieStatus` endpoint |
| `cimplur-core/Memento/Domain/Repositories/IQuestionService.cs` | Add `GetAnswerMovieStatus` method signature |
| `cimplur-core/Memento/Domain/Repositories/QuestionService.cs` | Implement `GetAnswerMovieStatus` |
| `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs` | Add tests for `GetAnswerMovieStatus` |

### Modified Files - Frontend
| File | Change |
|------|--------|
| `fyli-fe-v2/src/services/questionApi.ts` | Add `getAnswerMovieStatus` function |
| `fyli-fe-v2/src/components/question/AnswerPreview.vue` | Add video error handling, refresh logic, placeholder integration, make token required |
| `fyli-fe-v2/src/components/question/AnswerPreview.test.ts` | Add video refresh tests |
| `fyli-fe-v2/src/views/question/QuestionAnswerView.vue` | Add transcode delay with feedback, handle video refresh |
| `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts` | Add transcode delay, processing indicator, and refresh tests |

## Migration SQL

No database changes required.

## Implementation Order

1. **Phase 1**: Add transcode delay to QuestionAnswerView (with processing feedback)
2. **Phase 2**: Create VideoProcessingPlaceholder component
3. **Phase 3**: Add backend video status endpoint
4. **Phase 4**: Update AnswerPreview with refresh logic
5. **Phase 5**: Wire up refresh in QuestionAnswerView
6. **Phase 6**: Write and run tests

## Acceptance Criteria

1. After video upload, the UI shows "Processing video..." and waits 2-8 seconds (based on file size) before showing the answer
2. If a video fails to load, a placeholder is shown with "Video is being processed" message
3. The placeholder has a "Check if ready" button
4. Clicking the button calls the API to get fresh video URLs
5. If the video is ready, it displays; if not, the placeholder shows "Video is still processing"
6. The refresh happens without full page reload
7. Placeholder has proper ARIA attributes for accessibility
8. All existing tests pass
9. New tests cover the placeholder, refresh functionality, and delay indicator
