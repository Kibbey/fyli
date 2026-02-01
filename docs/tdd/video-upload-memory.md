# TDD: Video Upload for Memories

## Overview

Users can currently only attach images when creating a memory. This TDD adds video upload support alongside images in `CreateMemoryView.vue`. The backend already fully supports video uploads via a presigned URL flow (`POST /api/movies/upload/request` → S3 PUT → `POST /api/movies/upload/complete`), and the frontend already has API stubs in `mediaApi.ts`. The work is entirely frontend.

### Current State
- `CreateMemoryView.vue` file input: `accept="image/*"` — only images
- `mediaApi.ts` has `requestVideoUpload()` and `completeVideoUpload()` stubs but they are never called
- The `requestVideoUpload` stub uses `uploadUrl` but the backend `DirectUploadResponse` returns `presignedUrl` — this must be fixed
- Old frontend (`fyli-fe`) fully supports video upload with presigned URLs, progress tracking, and parallel image/video uploads

### Target State
- Single file input accepts both images and videos
- Images upload via existing `POST /api/images` multipart flow
- Videos upload via presigned URL: request → S3 PUT → complete
- Upload progress shown for videos (large files)
- Video previews displayed as thumbnails before upload
- Files separated by MIME type at upload time
- Client-side file size validation (5GB limit for videos)

---

## Phase 1: Fix `mediaApi.ts` Response Type

**File:** `fyli-fe-v2/src/services/mediaApi.ts`

The `requestVideoUpload` return type uses `uploadUrl` but the backend `DirectUploadResponse` has `presignedUrl`. Fix to match:

```typescript
export function requestVideoUpload(dropId: number, contentType: string, fileSize: number, commentId?: number) {
	return api.post<{ presignedUrl: string; movieId: number }>("/movies/upload/request", {
		dropId,
		contentType,
		fileSize,
		commentId,
	});
}
```

No changes needed to `completeVideoUpload`.

---

## Phase 2: Add S3 Direct Upload Helper

**File:** `fyli-fe-v2/src/services/mediaApi.ts`

Add a function to PUT the file directly to S3 using the presigned URL. Use `XMLHttpRequest` instead of axios for upload progress tracking (axios does not reliably support `onUploadProgress` in all environments).

```typescript
export function uploadFileToS3(
	presignedUrl: string,
	file: File,
	onProgress?: (percent: number) => void
): { promise: Promise<void>; abort: () => void } {
	const xhr = new XMLHttpRequest();

	const promise = new Promise<void>((resolve, reject) => {
		xhr.open("PUT", presignedUrl, true);
		xhr.setRequestHeader("Content-Type", file.type);

		if (onProgress) {
			xhr.upload.onprogress = (e) => {
				if (e.lengthComputable) {
					onProgress(Math.round((e.loaded / e.total) * 100));
				}
			};
		}

		xhr.onload = () => {
			if (xhr.status >= 200 && xhr.status < 300) {
				resolve();
			} else {
				reject(new Error(`S3 upload failed with status ${xhr.status}`));
			}
		};

		xhr.onerror = () => reject(new Error("S3 upload network error"));
		xhr.send(file);
	});

	return { promise, abort: () => xhr.abort() };
}
```

Returns both the promise and an `abort` function so callers can cancel in-flight uploads.

---

## Phase 3: Update `CreateMemoryView.vue`

**Note:** The existing component uses `<script setup>` before `<template>`. This TDD follows the same order to keep the diff minimal, but a follow-up should reorder to `<template>`, `<script setup>`, `<style scoped>` per project conventions.

### 3.1 File Entry Type & Stable IDs

Instead of parallel arrays (`files`, `previews`, `previewTypes`) keyed by index, use a single array of typed entries with stable IDs. This fixes v-for key stability and keeps progress tracking reliable.

```typescript
interface FileEntry {
	id: string;
	file: File;
	previewUrl: string;
	type: "image" | "video";
}

let nextId = 0;
function generateFileId(): string {
	return `file-${nextId++}`;
}

const fileEntries = ref<FileEntry[]>([]);
const videoProgress = ref<Record<string, number>>({});
const MAX_VIDEO_SIZE = 5 * 1024 * 1024 * 1024; // 5GB
```

Using `ref<Record<string, number>>({})` instead of `ref<Map>` so Vue reactivity triggers correctly on individual key changes in templates.

### 3.2 Accept Both Images and Videos

Change the file input `accept` attribute and label:

```html
<label class="form-label">Photos & Videos</label>
<input
	type="file"
	class="form-control"
	accept="image/*,video/*"
	multiple
	@change="onFileChange"
/>
```

### 3.3 File Selection with Validation

```typescript
function isVideoFile(file: File): boolean {
	return file.type.startsWith("video/");
}

function isImageFile(file: File): boolean {
	return file.type.startsWith("image/");
}

function onFileChange(e: Event) {
	const input = e.target as HTMLInputElement;
	if (!input.files) return;
	const newFiles = Array.from(input.files);
	for (const f of newFiles) {
		if (!isImageFile(f) && !isVideoFile(f)) continue;
		if (isVideoFile(f) && f.size > MAX_VIDEO_SIZE) {
			error.value = "Video files must be under 5GB.";
			continue;
		}
		const previewUrl = isVideoFile(f)
			? URL.createObjectURL(f) + "#t=0.1"
			: URL.createObjectURL(f);
		fileEntries.value.push({
			id: generateFileId(),
			file: f,
			previewUrl,
			type: isVideoFile(f) ? "video" : "image",
		});
	}
	input.value = "";
}

function removeFile(id: string) {
	const index = fileEntries.value.findIndex((e) => e.id === id);
	if (index === -1) return;
	URL.revokeObjectURL(fileEntries.value[index]!.previewUrl);
	fileEntries.value.splice(index, 1);
	delete videoProgress.value[id];
}
```

Key details:
- Video object URLs use `#t=0.1` fragment so the `<video>` element seeks to 0.1s, producing a visible thumbnail frame instead of a black rectangle.
- Files exceeding 5GB are rejected client-side with an error message before upload.
- `input.value = ""` resets the file input so re-selecting the same file triggers `change`.

### 3.4 Preview Template

Uses stable `entry.id` as `v-for` key. Shows `<video>` for video files, `<img>` for images. Progress overlay for videos during upload.

```html
<div v-if="fileEntries.length" class="d-flex gap-2 mt-2 flex-wrap">
	<div v-for="entry in fileEntries" :key="entry.id" class="position-relative">
		<video
			v-if="entry.type === 'video'"
			:src="entry.previewUrl"
			class="rounded"
			style="width: 80px; height: 80px; object-fit: cover"
			muted
			preload="metadata"
		/>
		<img
			v-else
			:src="entry.previewUrl"
			class="rounded"
			style="width: 80px; height: 80px; object-fit: cover"
		/>
		<div
			v-if="entry.type === 'video' && videoProgress[entry.id] != null"
			class="position-absolute top-0 start-0 w-100 h-100 d-flex align-items-center justify-content-center rounded"
			style="background: rgba(0, 0, 0, 0.5)"
		>
			<span class="text-white small">{{ videoProgress[entry.id] }}%</span>
		</div>
		<button
			type="button"
			class="btn btn-sm btn-danger position-absolute top-0 end-0"
			:disabled="submitting"
			@click="removeFile(entry.id)"
		>&times;</button>
	</div>
</div>
```

### 3.5 Upload Logic

Extract file uploading into a dedicated function. Handle partial failures gracefully — if some uploads fail after the drop is created, navigate to the memory detail so the user can see what succeeded and retry.

```typescript
async function uploadVideo(entry: FileEntry, dropId: number) {
	const { data } = await requestVideoUpload(dropId, entry.file.type, entry.file.size);
	const { promise } = uploadFileToS3(data.presignedUrl, entry.file, (percent) => {
		videoProgress.value[entry.id] = percent;
	});
	await promise;
	await completeVideoUpload(data.movieId, dropId);
}

async function uploadFiles(entries: FileEntry[], dropId: number): Promise<number> {
	const results = await Promise.allSettled(
		entries.map((entry) => {
			if (entry.type === "image") {
				return uploadImage(entry.file, dropId);
			}
			return uploadVideo(entry, dropId);
		})
	);
	const failedCount = results.filter((r) => r.status === "rejected").length;
	return failedCount;
}

async function handleSubmit() {
	if (submitting.value || !text.value.trim()) return;
	submitting.value = true;
	error.value = "";
	videoProgress.value = {};
	let dropId: number | null = null;

	try {
		const { data: created } = await createDrop({
			information: text.value.trim(),
			date: date.value,
			dateType: 0,
			tagIds: groupId.value ? [groupId.value] : undefined,
		});
		dropId = created.dropId;

		if (fileEntries.value.length > 0) {
			const failedCount = await uploadFiles(fileEntries.value, dropId);
			if (failedCount > 0) {
				error.value = `${failedCount} file(s) failed to upload. You can add them from the memory detail.`;
			}
		}
	} catch (e: any) {
		error.value = getErrorMessage(e, "Failed to create memory.");
	}

	if (dropId) {
		try {
			const { data: drop } = await getDrop(dropId);
			stream.prependMemory(drop);
		} catch {
			// Drop was created but fetch failed; stream will show it on next refresh
		}
		router.push("/");
	}

	submitting.value = false;
}
```

Key details:
- `uploadFiles` is extracted as a separate function to keep `handleSubmit` focused on create-then-navigate.
- Uses `Promise.allSettled` instead of `Promise.all` so partial failures don't throw — all uploads get a chance to complete.
- Failed count is reported to the user. The drop is still navigated to so users can see what succeeded.

---

## Phase 4: Update Imports

**File:** `fyli-fe-v2/src/views/memory/CreateMemoryView.vue`

Update the import from `mediaApi`:

```typescript
import {
	uploadImage,
	requestVideoUpload,
	completeVideoUpload,
	uploadFileToS3,
} from "@/services/mediaApi";
```

Remove the old `files` and `previews` refs — replaced by `fileEntries`.

---

## Summary of Changes

**Files Modified:**
- `fyli-fe-v2/src/services/mediaApi.ts` — Fix `requestVideoUpload` response type (`uploadUrl` → `presignedUrl`), add `uploadFileToS3` helper with abort support
- `fyli-fe-v2/src/views/memory/CreateMemoryView.vue` — Accept video files, `FileEntry` type with stable IDs, video preview with `#t=0.1` seek, progress overlay, presigned URL upload flow, client-side 5GB validation, partial failure handling

**No Backend Changes Required.** All backend endpoints already exist and are functional:
- `POST /api/movies/upload/request` — Returns presigned S3 URL + movieId
- `POST /api/movies/upload/complete` — Triggers MediaConvert transcoding
- Video size limit: up to 5GB
- Content type must start with `video/`

## Implementation Order

1. Phase 1: Fix `mediaApi.ts` response type mismatch
2. Phase 2: Add `uploadFileToS3` helper with abort support
3. Phase 3: Update `CreateMemoryView.vue` (FileEntry type, file input, previews, upload logic)
4. Phase 4: Verify end-to-end with a test video upload
