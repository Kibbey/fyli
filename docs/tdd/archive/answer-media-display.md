# TDD: Answer Media Display Enhancements

## Overview

Enhance the anonymous question answer page (`/q/{token}`) to display uploaded media (images and videos) immediately after upload without requiring a page reload, and improve the media display to match the logged-in user experience with larger sizes, playable videos, and lightbox functionality.

## Problem Statement

Currently, after uploading images/videos to an answer:
1. **Media not visible until reload**: The `uploadAnswerImage` API returns `boolean`, not the image data with URL, so the frontend cannot display newly uploaded media without reloading
2. **Small thumbnails**: Media displays as 60x60px thumbnails in `AnswerPreview`, unlike the larger, more engaging display used in `MemoryCard`
3. **Videos not playable**: Videos show static thumbnails with play icons but aren't actually playable
4. **No lightbox**: Images cannot be clicked to view full-size, unlike memories for logged-in users

## Goals

1. **Immediate Media Visibility**: Return media URLs from upload endpoints so media can be displayed without reload
2. **Memory-like Display**: Use `PhotoGrid` and playable videos like `MemoryCard` does
3. **Lightbox Support**: Enable `ClickableImage` for full-size image viewing
4. **Consistent UX**: Anonymous answer experience matches logged-in user experience

## Breaking Changes

**API Response Change:** The `POST /api/questions/answer/{token}/images` endpoint will change from returning `boolean` to returning `AnswerImageUploadResult`. Frontend and backend are deployed together, so this is acceptable, but any external clients would need to update.

## Technical Design

### Phase 1: Backend - Return Image Data from Upload

Modify the image upload endpoint to return the uploaded image's ID and pre-signed URL.

#### 1.1 Create Response Model

**File:** `cimplur-core/Memento/Domain/Models/QuestionModels.cs`

Add a new response model:

```csharp
/// <summary>
/// Response from uploading an answer image.
/// </summary>
public class AnswerImageUploadResult
{
    public int ImageDropId { get; set; }
    public string Url { get; set; } = "";
}
```

#### 1.2 Refactor ImageService to Return Image ID

**File:** `cimplur-core/Memento/Domain/Repositories/ImageService.cs`

The current `Add` method returns `Task<bool>`. Refactor to avoid code duplication by extracting the upload logic:

```csharp
/// <summary>
/// Adds an image and returns the image ID. Returns null on failure.
/// </summary>
public async Task<int?> AddWithId(IFormFile file, int userId, int dropId, int? commentId)
{
    string imageId = this.DropImageId(dropId, userId, commentId);
    if (imageId == null)
    {
        return null;
    }

    var success = await UploadImageToS3Async(file, imageId, dropId, userId);
    return success ? int.Parse(imageId) : null;
}

/// <summary>
/// Legacy method - prefer AddWithId for new code.
/// </summary>
public async Task<bool> Add(IFormFile file, int userId, int dropId, int? commentId)
{
    return await AddWithId(file, userId, dropId, commentId) != null;
}

/// <summary>
/// Uploads image to S3 after resizing. Returns true on success.
/// </summary>
private async Task<bool> UploadImageToS3Async(IFormFile file, string imageId, int dropId, int userId)
{
    string name = GetName(dropId, imageId, userId);
    Stream stream;

    try
    {
        stream = await ReSizeImageAsync(file);
        using (IAmazonS3 s3Client = new AmazonS3Client(RegionEndpoint.USEast1))
        {
            PutObjectRequest request = new PutObjectRequest
            {
                BucketName = BucketName,
                Key = name,
                InputStream = stream,
                ContentType = "image/jpeg",
            };
            PutObjectResponse response = await s3Client.PutObjectAsync(request);
            if (response.HttpStatusCode != System.Net.HttpStatusCode.OK)
            {
                await RemoveImageId(imageId);
                return false;
            }
        }
    }
    catch (Exception)
    {
        await RemoveImageId(imageId);
        throw;
    }

    stream.Dispose();
    return true;
}
```

#### 1.3 Update Controller to Return Image Data

**File:** `cimplur-core/Memento/Memento/Controllers/QuestionController.cs`

Modify `UploadAnswerImage` to return the image ID and URL:

```csharp
[EnableRateLimiting("public")]
[HttpPost]
[Route("answer/{token:guid}/images")]
public async Task<IActionResult> UploadAnswerImage(Guid token)
{
    var file = HttpContext.Request.Form.Files.Count > 0
        ? HttpContext.Request.Form.Files[0] : null;
    var dropIdParam = HttpContext.Request.Form["dropId"];

    if (file == null)
        return BadRequest("No file provided.");

    if (!int.TryParse(dropIdParam, out var dropId))
        return BadRequest("dropId is required.");

    if (file.ContentType.Split('/')[0] != "image"
        && !file.FileName.ToLower().Contains(".heic"))
        return BadRequest("Only image files are supported.");

    var recipient = await questionService.ValidateTokenOwnsDropAsync(token, dropId);
    if (recipient == null)
        return NotFound("Invalid token or drop.");

    var userId = recipient.RespondentUserId
        ?? recipient.QuestionRequest.CreatorUserId;

    var imageId = await imageService.AddWithId(file, userId, dropId, null);
    if (imageId == null)
        return BadRequest("Failed to upload image.");

    // Get the image owner to generate correct URL
    var imageOwnerId = recipient.RespondentUserId ?? recipient.QuestionRequest.CreatorUserId;
    var url = imageService.GetLink(imageId.Value, imageOwnerId, dropId);

    return Ok(new AnswerImageUploadResult
    {
        ImageDropId = imageId.Value,
        Url = url
    });
}
```

### Phase 2: Backend - Add Video URL to Response

For videos loaded from the server (on page refresh), include the video URL, not just the thumbnail.

#### 2.1 Update AnswerMovieModel

**File:** `cimplur-core/Memento/Domain/Models/QuestionModels.cs`

```csharp
/// <summary>
/// Video attached to an answer with thumbnail and video URLs.
/// </summary>
public class AnswerMovieModel
{
    public int MovieDropId { get; set; }
    public string ThumbnailUrl { get; set; } = "";
    public string VideoUrl { get; set; } = "";
}
```

#### 2.2 Update QuestionService to Include Video URLs

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

In `BuildAnswerViewModel`, update the movie mapping to use the correct `MovieService` method signatures. Note that `MovieDrop` doesn't have `ThumbnailName` or `UserId` - use `MovieDropId` as the ID and `creatorUserId` (the question creator who owns the response) as the owner:

```csharp
Movies = drop.Movies.Where(m => !m.CommentId.HasValue)
    .Select(m => new AnswerMovieModel
    {
        MovieDropId = m.MovieDropId,
        ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, creatorUserId, drop.DropId, m.IsTranscodeV2),
        VideoUrl = movieService.GetLink(m.MovieDropId, creatorUserId, drop.DropId, m.IsTranscodeV2)
    }).ToList()
```

**Note:** The existing `MovieService` methods are:
- `GetThumbLink(int imageId, int imageOwnerUserId, int dropId, bool isTranscodeV2)` - returns pre-signed thumbnail URL
- `GetLink(int imageId, int imageOwnerUserId, int dropId, bool isTranscodeV2)` - returns pre-signed video URL

### Phase 3: Frontend - Update API Service and Types

#### 3.1 Update questionApi.ts

**File:** `fyli-fe-v2/src/services/questionApi.ts`

Update the return type of `uploadAnswerImage`:

```typescript
export interface AnswerImageUploadResult {
	imageDropId: number;
	url: string;
}

export function uploadAnswerImage(token: string, dropId: number, file: File) {
	const formData = new FormData();
	formData.append("file", file);
	formData.append("dropId", dropId.toString());
	return api.post<AnswerImageUploadResult>(`/questions/answer/${token}/images`, formData, {
		headers: { "Content-Type": "multipart/form-data" }
	});
}
```

#### 3.2 Update Frontend Types

**File:** `fyli-fe-v2/src/types/question.ts`

Update `AnswerMovie` to include `videoUrl`:

```typescript
/**
 * Video attached to an answer with thumbnail and video URLs.
 */
export interface AnswerMovie {
	movieDropId: number;
	/**
	 * Thumbnail URL. May be empty for newly uploaded videos (generated asynchronously).
	 */
	thumbnailUrl: string;
	/**
	 * Video URL for playback. Empty for local previews (use thumbnailUrl blob URL instead).
	 */
	videoUrl: string;
}
```

### Phase 4: Frontend - Update QuestionAnswerView Media Handling

#### 4.1 Track Uploaded Media in Local State

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

Add imports for the required types:

```typescript
import type { AnswerImage, AnswerMovie } from "@/types";
```

Modify `handleAnswerSubmit` to capture uploaded media URLs and include them in the local answer:

```typescript
async function handleAnswerSubmit(payload: AnswerPayload) {
	const { questionId, content, date, dateType, files } = payload;

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

		// Upload media files and collect results
		const uploadedImages: AnswerImage[] = [];
		const uploadedVideos: AnswerMovie[] = [];

		for (const entry of files) {
			try {
				if (entry.type === "image") {
					const { data: imageResult } = await uploadAnswerImage(token, drop.dropId, entry.file);
					uploadedImages.push({
						imageDropId: imageResult.imageDropId,
						url: imageResult.url
					});
				} else {
					const { data: uploadReq } = await requestAnswerMovieUpload(
						token,
						drop.dropId,
						entry.file.size,
						entry.file.type
					);
					const { promise } = uploadFileToS3(uploadReq.presignedUrl, entry.file);
					await promise;
					await completeAnswerMovieUpload(token, uploadReq.movieId, drop.dropId);
					// Use local preview URL until server thumbnail is generated
					// The blob URL works for both thumbnail and video playback
					uploadedVideos.push({
						movieDropId: uploadReq.movieId,
						thumbnailUrl: entry.previewUrl,
						videoUrl: entry.previewUrl // Local blob URL for playback
					});
				}
			} catch (mediaErr) {
				console.error(`${entry.type} upload failed:`, mediaErr);
				error.value = "Some media failed to upload. You can edit your answer to retry.";
			}
		}

		// Build local answer view with uploaded media URLs
		const localAnswer: AnswerView = {
			dropId: drop.dropId,
			content,
			date,
			dateType: dateType as 0 | 1 | 2 | 3,
			canEdit: true,
			images: uploadedImages,
			movies: uploadedVideos
		};

		pendingAnswers.value.delete(questionId);
		answeredDrops.value.set(questionId, localAnswer);

		if (answeredCount.value === 1 && !auth.isAuthenticated) {
			showRegister.value = true;
		}
	} catch (e: unknown) {
		pendingAnswers.value.delete(questionId);
		error.value = getErrorMessage(e, "Failed to submit answer");
	} finally {
		isSubmitting.value = false;
	}
}
```

#### 4.2 Clean Up Blob URLs on Unmount

Add cleanup for blob URLs to prevent memory leaks:

```typescript
import { onUnmounted } from "vue";

// Clean up blob URLs when component unmounts
onUnmounted(() => {
	answeredDrops.value.forEach((answer) => {
		answer.movies.forEach((m) => {
			if (m.videoUrl.startsWith("blob:")) {
				URL.revokeObjectURL(m.videoUrl);
			}
		});
	});
});
```

### Phase 5: Frontend - Enhance AnswerPreview Component

Replace the small thumbnail grid with memory-like media display using `PhotoGrid` and playable videos.

#### 5.1 Update AnswerPreview.vue

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

					<!-- Videos - playable -->
					<div v-for="vid in question.answer.movies" :key="`vid-${vid.movieDropId}`" class="mb-3">
						<video
							v-if="hasVideoSrc(vid)"
							:src="getVideoSrc(vid)"
							:poster="getVideoPoster(vid)"
							controls
							class="img-fluid rounded video-player"
							preload="metadata"
						></video>
						<div
							v-else
							class="video-placeholder rounded d-flex align-items-center justify-content-center bg-secondary"
						>
							<span class="mdi mdi-video-processing text-white" aria-hidden="true"></span>
							<span class="text-white ms-2 small">Processing...</span>
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
import { computed } from "vue";
import type { AnswerView, AnswerMovie } from "@/types";
import type { ImageLink } from "@/types";
import PhotoGrid from "@/components/memory/PhotoGrid.vue";

/**
 * Props interface requiring answer to be present.
 */
interface AnsweredQuestion {
	questionId: number;
	text: string;
	sortOrder: number;
	isAnswered: boolean;
	answer: AnswerView;
}

const props = defineProps<{
	question: AnsweredQuestion;
}>();

defineEmits<{
	(e: "edit", questionId: number): void;
}>();

/**
 * Convert AnswerImage[] to ImageLink[] for PhotoGrid compatibility.
 */
const imageLinks = computed<ImageLink[]>(() =>
	props.question.answer.images.map((img) => ({
		id: img.imageDropId,
		link: img.url
	}))
);

/**
 * Check if video has a playable source.
 */
function hasVideoSrc(vid: AnswerMovie): boolean {
	return Boolean(vid.videoUrl) || vid.thumbnailUrl.startsWith("blob:");
}

/**
 * Get video source URL.
 */
function getVideoSrc(vid: AnswerMovie): string {
	// For locally uploaded videos, thumbnailUrl is a blob URL pointing to the video
	if (vid.thumbnailUrl.startsWith("blob:")) {
		return vid.thumbnailUrl;
	}
	// Use the server-provided video URL
	return vid.videoUrl;
}

/**
 * Get video poster (thumbnail) URL.
 */
function getVideoPoster(vid: AnswerMovie): string | undefined {
	// For blob URLs, the video element will auto-generate a poster frame
	if (vid.thumbnailUrl.startsWith("blob:")) {
		return undefined;
	}
	return vid.thumbnailUrl || undefined;
}

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

.video-placeholder {
	width: 100%;
	height: 150px;
}
</style>
```

### Phase 6: Testing

#### 6.1 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/ImageServiceTest.cs`

Add tests for `AddWithId`:

```csharp
[Fact]
public async Task AddWithId_ReturnsImageId_WhenSuccessful()
{
    // Arrange - mock file, userId, dropId
    // Act
    var result = await imageService.AddWithId(mockFile, userId, dropId, null);
    // Assert
    Assert.NotNull(result);
    Assert.True(result > 0);
}

[Fact]
public async Task AddWithId_ReturnsNull_WhenDropImageIdFails()
{
    // Arrange - setup to return null from DropImageId
    // Act
    var result = await imageService.AddWithId(mockFile, userId, invalidDropId, null);
    // Assert
    Assert.Null(result);
}

[Fact]
public async Task Add_ReturnsTrue_WhenAddWithIdSucceeds()
{
    // Arrange
    // Act
    var result = await imageService.Add(mockFile, userId, dropId, null);
    // Assert
    Assert.True(result);
}
```

#### 6.2 Frontend Tests

**File:** `fyli-fe-v2/src/components/question/AnswerPreview.test.ts`

Update tests for new media display:

```typescript
import PhotoGrid from "@/components/memory/PhotoGrid.vue";

describe("AnswerPreview", () => {
	// ... existing tests ...

	it("renders PhotoGrid for images", () => {
		const question = {
			...mockQuestion,
			answer: {
				...mockQuestion.answer,
				images: [
					{ imageDropId: 1, url: "https://example.com/img1.jpg" },
					{ imageDropId: 2, url: "https://example.com/img2.jpg" }
				]
			}
		};
		const wrapper = mount(AnswerPreview, {
			props: { question },
			global: { components: { PhotoGrid } }
		});
		expect(wrapper.findComponent(PhotoGrid).exists()).toBe(true);
	});

	it("renders playable video elements with server URL", () => {
		const question = {
			...mockQuestion,
			answer: {
				...mockQuestion.answer,
				images: [],
				movies: [{ movieDropId: 1, thumbnailUrl: "thumb.jpg", videoUrl: "video.mp4" }]
			}
		};
		const wrapper = mount(AnswerPreview, { props: { question } });
		const video = wrapper.find("video");
		expect(video.exists()).toBe(true);
		expect(video.attributes("controls")).toBeDefined();
		expect(video.attributes("src")).toBe("video.mp4");
		expect(video.attributes("poster")).toBe("thumb.jpg");
	});

	it("renders playable video elements with blob URL", () => {
		const question = {
			...mockQuestion,
			answer: {
				...mockQuestion.answer,
				images: [],
				movies: [{ movieDropId: 1, thumbnailUrl: "blob:http://localhost/abc", videoUrl: "blob:http://localhost/abc" }]
			}
		};
		const wrapper = mount(AnswerPreview, { props: { question } });
		const video = wrapper.find("video");
		expect(video.exists()).toBe(true);
		expect(video.attributes("src")).toBe("blob:http://localhost/abc");
	});

	it("shows processing placeholder for videos without thumbnail or URL", () => {
		const question = {
			...mockQuestion,
			answer: {
				...mockQuestion.answer,
				images: [],
				movies: [{ movieDropId: 1, thumbnailUrl: "", videoUrl: "" }]
			}
		};
		const wrapper = mount(AnswerPreview, { props: { question } });
		expect(wrapper.text()).toContain("Processing...");
	});

	it("does not render PhotoGrid when no images", () => {
		const question = {
			...mockQuestion,
			answer: {
				...mockQuestion.answer,
				images: [],
				movies: []
			}
		};
		const wrapper = mount(AnswerPreview, {
			props: { question },
			global: { components: { PhotoGrid } }
		});
		expect(wrapper.findComponent(PhotoGrid).exists()).toBe(false);
	});
});
```

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts`

Add tests for immediate media display and error handling:

```typescript
import { uploadAnswerImage } from "@/services/questionApi";

// Add to mock at top of file
vi.mock("@/services/questionApi", () => ({
	getQuestionsForAnswer: vi.fn(),
	submitAnswer: vi.fn(),
	registerViaQuestion: vi.fn(),
	uploadAnswerImage: vi.fn(),
	requestAnswerMovieUpload: vi.fn(),
	completeAnswerMovieUpload: vi.fn()
}));

describe("QuestionAnswerView", () => {
	// ... existing tests ...

	it("displays uploaded images immediately after submit", async () => {
		vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: mockView } as never);
		vi.mocked(submitAnswer).mockResolvedValue({ data: { dropId: 100 } } as never);
		vi.mocked(uploadAnswerImage).mockResolvedValue({
			data: { imageDropId: 1, url: "https://example.com/uploaded.jpg" }
		} as never);

		const wrapper = mount(QuestionAnswerView, {
			global: {
				stubs: { LoadingSpinner: true },
				components: { AnswerForm, AnswerPreview, PhotoGrid }
			}
		});
		await flushPromises();

		// Open form and submit with file
		await wrapper.find("button.btn-primary").trigger("click");
		const form = wrapper.findComponent(AnswerForm);
		form.vm.$emit("submit", {
			questionId: 1,
			content: "Answer with image",
			date: "2025-01-01",
			dateType: 0,
			files: [{ id: "f1", file: new File([], "test.jpg"), previewUrl: "blob:...", type: "image" }]
		});
		await flushPromises();

		// Verify image is displayed
		expect(wrapper.findComponent(PhotoGrid).exists()).toBe(true);
	});

	it("shows error when image upload fails but answer still submits", async () => {
		vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: mockView } as never);
		vi.mocked(submitAnswer).mockResolvedValue({ data: { dropId: 100 } } as never);
		vi.mocked(uploadAnswerImage).mockRejectedValue(new Error("Upload failed"));

		const wrapper = mount(QuestionAnswerView, {
			global: {
				stubs: { LoadingSpinner: true, AnswerPreview: true },
				components: { AnswerForm }
			}
		});
		await flushPromises();

		await wrapper.find("button.btn-primary").trigger("click");
		const form = wrapper.findComponent(AnswerForm);
		form.vm.$emit("submit", {
			questionId: 1,
			content: "Answer",
			date: "2025-01-01",
			dateType: 0,
			files: [{ id: "f1", file: new File([], "test.jpg"), previewUrl: "blob:...", type: "image" }]
		});
		await flushPromises();

		// Answer should still be marked as submitted
		expect(wrapper.findComponent({ name: "AnswerPreview" }).exists()).toBe(true);
		// Error message should be shown
		expect(wrapper.text()).toContain("Some media failed to upload");
	});

	it("handles video upload with local preview URL", async () => {
		vi.mocked(getQuestionsForAnswer).mockResolvedValue({ data: mockView } as never);
		vi.mocked(submitAnswer).mockResolvedValue({ data: { dropId: 100 } } as never);
		vi.mocked(requestAnswerMovieUpload).mockResolvedValue({
			data: { movieId: 1, presignedUrl: "https://s3.example.com/upload" }
		} as never);
		vi.mocked(uploadFileToS3).mockReturnValue({ promise: Promise.resolve() });
		vi.mocked(completeAnswerMovieUpload).mockResolvedValue({} as never);

		const wrapper = mount(QuestionAnswerView, {
			global: {
				stubs: { LoadingSpinner: true },
				components: { AnswerForm, AnswerPreview }
			}
		});
		await flushPromises();

		await wrapper.find("button.btn-primary").trigger("click");
		const form = wrapper.findComponent(AnswerForm);
		form.vm.$emit("submit", {
			questionId: 1,
			content: "Answer with video",
			date: "2025-01-01",
			dateType: 0,
			files: [{ id: "v1", file: new File([], "test.mp4"), previewUrl: "blob:http://localhost/video", type: "video" }]
		});
		await flushPromises();

		// Verify answer preview is shown (video will use blob URL)
		expect(wrapper.findComponent(AnswerPreview).exists()).toBe(true);
	});
});
```

## File Changes Summary

### Backend
| File | Change |
|------|--------|
| `Domain/Models/QuestionModels.cs` | Add `AnswerImageUploadResult`, update `AnswerMovieModel` with `VideoUrl` |
| `Domain/Repositories/ImageService.cs` | Add `AddWithId()` method, refactor `Add()` to use shared upload logic |
| `Memento/Controllers/QuestionController.cs` | Update `UploadAnswerImage` to return image data |
| `Domain/Repositories/QuestionService.cs` | Include `VideoUrl` in movie mapping using `movieService.GetLink()` |

### Frontend
| File | Change |
|------|--------|
| `src/services/questionApi.ts` | Add `AnswerImageUploadResult` type, update return type |
| `src/types/question.ts` | Add `videoUrl` to `AnswerMovie` |
| `src/components/question/AnswerPreview.vue` | Use `PhotoGrid`, playable videos, lightbox support |
| `src/views/question/QuestionAnswerView.vue` | Capture uploaded media URLs, add blob URL cleanup |
| `src/components/question/AnswerPreview.test.ts` | Update tests for new display |
| `src/views/question/QuestionAnswerView.test.ts` | Add tests for immediate media display and error paths |

## Migration SQL

No database schema changes required. This enhancement only modifies API response structures and frontend display.

## Documentation Updates

After implementation, update:
- `/docs/release_note.md` - Add entry for "Answer Media Display Enhancements"

## Implementation Order

1. **Phase 1**: Backend - Return Image Data from Upload
2. **Phase 2**: Backend - Add Video URL to Response
3. **Phase 3**: Frontend - Update API Service and Types
4. **Phase 4**: Frontend - Update QuestionAnswerView Media Handling
5. **Phase 5**: Frontend - Enhance AnswerPreview Component
6. **Phase 6**: Testing

## Acceptance Criteria

1. After uploading an image, it appears immediately in the answer preview without page reload
2. After uploading a video, a local preview appears immediately (processing indicator if server thumbnail not ready)
3. Images display using PhotoGrid with the same layout as memories (1/2/3+ image grid)
4. Clicking an image opens a full-size lightbox overlay
5. Videos are playable with native HTML5 controls
6. Video max-height is 400px to prevent oversized display
7. All existing tests pass
8. New tests cover immediate media display functionality and error paths
9. Blob URLs are cleaned up on component unmount to prevent memory leaks
