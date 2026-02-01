# TDD: Edit Memory

## Overview

There is no way to edit a memory after creation. This TDD adds an Edit Memory view that allows the user to edit text, change the date, add new images/videos, and remove existing images/videos. The backend already supports all of this via `PUT /api/drops/{id}` — the work is entirely frontend.

### Current State
- `MemoryDetailView.vue` has Share and Delete buttons but no Edit button
- `memoryApi.ts` has `updateDrop()` already defined but unused
- Backend `PUT /api/drops/{id}` accepts `images` and `movies` arrays (IDs to keep) and deletes anything not in the list
- No `/memory/:id/edit` route exists

### Target State
- Edit button on `MemoryDetailView.vue` (next to Share/Delete, visible when `memory.editable`)
- New route `/memory/:id/edit` → `EditMemoryView.vue`
- Edit view loads existing drop data, shows existing media with remove capability, allows adding new files
- On save: calls `updateDrop()` with text/date/IDs-to-keep, then uploads any new files, then navigates back to detail

---

## Phase 0: Extract `useFileUpload` Composable

**File:** `fyli-fe-v2/src/composables/useFileUpload.ts`

Extract the shared file upload logic from `CreateMemoryView.vue` into a reusable composable so both Create and Edit views can use it without duplication.

```typescript
import { ref, onBeforeUnmount } from "vue"
import {
	uploadImage,
	requestVideoUpload,
	completeVideoUpload,
	uploadFileToS3,
} from "@/services/mediaApi"

export interface FileEntry {
	id: string
	file: File
	previewUrl: string
	type: "image" | "video"
}

const MAX_VIDEO_SIZE = 5 * 1024 * 1024 * 1024 // 5GB

export function useFileUpload() {
	const fileEntries = ref<FileEntry[]>([])
	const videoProgress = ref<Record<string, number>>({})
	const fileError = ref("")

	let nextId = 0
	function generateFileId(): string {
		return `file-${nextId++}`
	}

	function isVideoFile(file: File): boolean {
		return file.type.startsWith("video/")
	}

	function isImageFile(file: File): boolean {
		return file.type.startsWith("image/")
	}

	function onFileChange(e: Event) {
		const input = e.target as HTMLInputElement
		if (!input.files) return
		const newFiles = Array.from(input.files)
		for (const f of newFiles) {
			if (!isImageFile(f) && !isVideoFile(f)) continue
			if (isVideoFile(f) && f.size > MAX_VIDEO_SIZE) {
				fileError.value = "Video files must be under 5GB."
				continue
			}
			const previewUrl = isVideoFile(f)
				? URL.createObjectURL(f) + "#t=0.1"
				: URL.createObjectURL(f)
			fileEntries.value.push({
				id: generateFileId(),
				file: f,
				previewUrl,
				type: isVideoFile(f) ? "video" : "image",
			})
		}
		input.value = ""
	}

	function removeFile(id: string) {
		const index = fileEntries.value.findIndex((e) => e.id === id)
		if (index === -1) return
		URL.revokeObjectURL(fileEntries.value[index]!.previewUrl.split("#")[0]!)
		fileEntries.value.splice(index, 1)
		delete videoProgress.value[id]
	}

	function getTranscodeDelay(entries: FileEntry[]): number {
		const videoEntries = entries.filter((e) => e.type === "video")
		if (videoEntries.length === 0) return 0
		const largestSize = Math.max(...videoEntries.map((e) => e.file.size))
		const MB_100 = 100 * 1024 * 1024
		if (largestSize > MB_100) return 8000
		return 2000
	}

	async function uploadVideo(entry: FileEntry, dropId: number) {
		const { data } = await requestVideoUpload(dropId, entry.file.type, entry.file.size)
		const { promise } = uploadFileToS3(data.presignedUrl, entry.file, (percent) => {
			videoProgress.value[entry.id] = percent
		})
		await promise
		await completeVideoUpload(data.movieId, dropId)
	}

	async function uploadFiles(entries: FileEntry[], dropId: number): Promise<number> {
		const results = await Promise.allSettled(
			entries.map((entry) => {
				if (entry.type === "image") {
					return uploadImage(entry.file, dropId)
				}
				return uploadVideo(entry, dropId)
			})
		)
		return results.filter((r) => r.status === "rejected").length
	}

	function cleanup() {
		fileEntries.value.forEach((e) =>
			URL.revokeObjectURL(e.previewUrl.split("#")[0]!)
		)
	}

	onBeforeUnmount(cleanup)

	return {
		fileEntries,
		videoProgress,
		fileError,
		onFileChange,
		removeFile,
		uploadFiles,
		getTranscodeDelay,
	}
}
```

After creating this composable, refactor `CreateMemoryView.vue` to import and use it instead of its inline copy of the same logic.

---

## Phase 1: Add Route

**File:** `fyli-fe-v2/src/router/index.ts`

Add before the `/memory/:id` route (more specific path first):

```typescript
{
	path: "/memory/:id/edit",
	name: "edit-memory",
	component: () => import("@/views/memory/EditMemoryView.vue"),
	meta: { auth: true, layout: "app" },
},
```

---

## Phase 2: Add Edit Button to MemoryDetailView

**File:** `fyli-fe-v2/src/views/memory/MemoryDetailView.vue`

Add an Edit button in the actions area, between Share and Delete:

```html
<router-link
	:to="{ name: 'edit-memory', params: { id: String(memory.dropId) } }"
	class="btn btn-sm btn-outline-secondary"
>
	<span class="mdi mdi-pencil-outline"></span>
</router-link>
```

---

## Phase 3: Create `EditMemoryView.vue`

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.vue`

### 3.1 Data Model

The view loads the existing drop and tracks:
- `text` — editable content (initialized from `drop.content.stuff`)
- `date` — editable date
- `existingImages` — current images with a `removed` flag for soft-delete UI
- `existingMovies` — current movies with a `removed` flag
- New files managed by `useFileUpload()` composable

```typescript
interface ExistingImage {
	id: number
	link: string
	removed: boolean
}

interface ExistingMovie {
	id: number
	link: string
	thumbLink: string
	removed: boolean
}
```

### 3.2 Load Existing Drop

On mount, fetch the drop via `getDrop(id)` and populate the form fields:

```typescript
const route = useRoute()
const router = useRouter()
const stream = useStreamStore()
const dropId = Number(route.params.id)

const {
	fileEntries: newFileEntries,
	videoProgress,
	fileError,
	onFileChange,
	removeFile: removeNewFile,
	uploadFiles,
	getTranscodeDelay,
} = useFileUpload()

const text = ref("")
const date = ref("")
const existingImages = ref<ExistingImage[]>([])
const existingMovies = ref<ExistingMovie[]>([])
const submitting = ref(false)
const loading = ref(true)
const error = ref("")

onMounted(async () => {
	try {
		const { data } = await getDrop(dropId)
		if (!data.editable) {
			router.replace({
				name: "memory-detail",
				params: { id: String(dropId) },
			})
			return
		}
		text.value = data.content.stuff
		date.value = data.date.slice(0, 10)
		existingImages.value = data.imageLinks.map((img) => ({
			id: img.id,
			link: img.link,
			removed: false,
		}))
		existingMovies.value = data.movieLinks.map((mov) => ({
			id: mov.id,
			link: mov.link,
			thumbLink: mov.thumbLink,
			removed: false,
		}))
	} catch {
		error.value = "Failed to load memory."
	} finally {
		loading.value = false
	}
})
```

### 3.3 Remove / Restore Existing Media

Soft-delete pattern matching the old frontend — toggle `removed` flag, show restore option:

```typescript
function toggleImageRemoval(id: number) {
	const img = existingImages.value.find((i) => i.id === id)
	if (img) img.removed = !img.removed
}

function toggleMovieRemoval(id: number) {
	const mov = existingMovies.value.find((m) => m.id === id)
	if (mov) mov.removed = !mov.removed
}
```

### 3.4 Save Logic

```typescript
async function handleSubmit() {
	if (submitting.value || !text.value.trim()) return
	submitting.value = true
	error.value = ""
	videoProgress.value = {}

	try {
		const imageIdsToKeep = existingImages.value
			.filter((i) => !i.removed)
			.map((i) => i.id)
		const movieIdsToKeep = existingMovies.value
			.filter((m) => !m.removed)
			.map((m) => m.id)

		await updateDrop(dropId, {
			information: text.value.trim(),
			date: date.value,
			dateType: 0,
			images: imageIdsToKeep,
			movies: movieIdsToKeep,
		})

		if (newFileEntries.value.length > 0) {
			const failedCount = await uploadFiles(newFileEntries.value, dropId)
			if (failedCount > 0) {
				error.value = `${failedCount} file(s) failed to upload.`
			}
			const delay = getTranscodeDelay(newFileEntries.value)
			if (delay > 0) {
				await new Promise((r) => setTimeout(r, delay))
			}
		}
	} catch (e: any) {
		error.value = getErrorMessage(e, "Failed to update memory.")
		submitting.value = false
		return
	}

	try {
		const { data: drop } = await getDrop(dropId)
		stream.updateMemory(drop)
	} catch {
		// Updated but fetch failed; stream will show it on next refresh
	}
	router.push({ name: "memory-detail", params: { id: String(dropId) } })
	submitting.value = false
}
```

### 3.5 Template

```html
<template>
	<div>
		<LoadingSpinner v-if="loading" />
		<template v-else>
			<h4 class="mb-3">Edit Memory</h4>
			<form @submit.prevent="handleSubmit">
				<div v-if="error" class="alert alert-danger">{{ error }}</div>
				<div v-if="fileError" class="alert alert-warning">{{ fileError }}</div>
				<div class="mb-3">
					<textarea v-model="text" class="form-control" rows="4"
						placeholder="What happened?" required></textarea>
				</div>
				<div class="mb-3">
					<label class="form-label">Date</label>
					<input v-model="date" type="date" class="form-control" required />
				</div>

				<!-- Existing images -->
				<div v-if="existingImages.length" class="mb-3">
					<label class="form-label">Current Photos</label>
					<div class="d-flex gap-2 flex-wrap">
						<div v-for="img in existingImages" :key="img.id"
							class="position-relative">
							<img :src="img.link" class="rounded"
								:style="{
									width: '80px', height: '80px', objectFit: 'cover',
									opacity: img.removed ? 0.3 : 1
								}" />
							<button type="button"
								class="btn btn-sm position-absolute top-0 end-0"
								:class="img.removed ? 'btn-success' : 'btn-danger'"
								:disabled="submitting"
								@click="toggleImageRemoval(img.id)">
								{{ img.removed ? '&#x21a9;' : '&times;' }}
							</button>
						</div>
					</div>
				</div>

				<!-- Existing videos -->
				<div v-if="existingMovies.length" class="mb-3">
					<label class="form-label">Current Videos</label>
					<div class="d-flex gap-2 flex-wrap">
						<div v-for="mov in existingMovies" :key="mov.id"
							class="position-relative">
							<img :src="mov.thumbLink" class="rounded"
								:style="{
									width: '80px', height: '80px', objectFit: 'cover',
									opacity: mov.removed ? 0.3 : 1
								}" />
							<button type="button"
								class="btn btn-sm position-absolute top-0 end-0"
								:class="mov.removed ? 'btn-success' : 'btn-danger'"
								:disabled="submitting"
								@click="toggleMovieRemoval(mov.id)">
								{{ mov.removed ? '&#x21a9;' : '&times;' }}
							</button>
						</div>
					</div>
				</div>

				<!-- Add new files -->
				<div class="mb-3">
					<label class="form-label">Add Photos & Videos</label>
					<input type="file" class="form-control"
						accept="image/*,video/*" multiple @change="onFileChange" />
					<div v-if="newFileEntries.length" class="d-flex gap-2 mt-2 flex-wrap">
						<div v-for="entry in newFileEntries" :key="entry.id"
							class="position-relative">
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
								@click="removeNewFile(entry.id)"
							>&times;</button>
						</div>
					</div>
				</div>

				<div class="d-flex gap-2">
					<button type="submit" class="btn btn-primary" :disabled="submitting">
						{{ submitting ? "Saving..." : "Save Changes" }}
					</button>
					<button type="button" class="btn btn-outline-secondary"
						@click="router.back()">Cancel</button>
				</div>
			</form>
		</template>
	</div>
</template>
```

---

## Phase 4: Add `updateMemory` to Stream Store

**File:** `fyli-fe-v2/src/stores/stream.ts`

Add a method to update a memory in the stream list after editing:

```typescript
function updateMemory(drop: Drop) {
	const index = memories.value.findIndex((m) => m.dropId === drop.dropId)
	if (index !== -1) {
		memories.value[index] = drop
	}
}
```

---

## Summary of Changes

**Files Created:**
- `fyli-fe-v2/src/composables/useFileUpload.ts` — Shared composable for file selection, validation, preview, upload, and cleanup
- `fyli-fe-v2/src/views/memory/EditMemoryView.vue` — Edit memory form with existing media removal, new file uploads, and save logic

**Files Modified:**
- `fyli-fe-v2/src/router/index.ts` — Add `/memory/:id/edit` route
- `fyli-fe-v2/src/views/memory/MemoryDetailView.vue` — Add Edit button
- `fyli-fe-v2/src/views/memory/CreateMemoryView.vue` — Refactor to use `useFileUpload()` composable
- `fyli-fe-v2/src/stores/stream.ts` — Add `updateMemory()` method

**No Backend Changes Required.** `PUT /api/drops/{id}` already handles everything:
- Text and date updates
- Image removal (send IDs to keep, backend deletes the rest from DB + S3)
- Movie removal (same pattern)
- New file uploads use existing `POST /api/images` and presigned URL flow

## Implementation Order

1. Phase 0: Extract `useFileUpload` composable, refactor `CreateMemoryView`
2. Phase 4: Add `updateMemory` to stream store (dependency for save)
3. Phase 1: Add route
4. Phase 2: Add Edit button to detail view
5. Phase 3: Create `EditMemoryView.vue`
