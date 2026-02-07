# TDD: Comment File Upload

**PRD:** `docs/prd/PRD_INLINE_COMMENTS.md` (Out of Scope section — now in scope)

## Overview

Allow users to attach images and videos when posting a comment. The backend already supports this — `uploadImage` and `requestVideoUpload` in `mediaApi.ts` accept an optional `commentId`, and the backend `ImageController`/`MovieController` already store the `CommentId` FK on `ImageDrop`/`MovieDrop` records. The only changes are frontend.

### No database changes.
### No backend changes.
### No new API endpoints.

---

## Current Flow

1. User types text in `CommentForm`
2. `CommentForm` emits `submit` with text
3. `CommentList.addComment` calls `createComment(dropId, text, 0)` → gets back comment with `commentId`
4. Comment appears in list

## New Flow

1. User types text and/or selects files in `CommentForm`
2. `CommentForm` emits `submit` with text and file entries
3. `CommentList.addComment` calls `createComment(dropId, text, 0)` → gets back `commentId`
4. Comment appears in list immediately (optimistic — text only)
5. Files upload in background using `commentId`: images via `uploadImage(file, dropId, commentId)`, videos via `requestVideoUpload(dropId, contentType, fileSize, commentId)` → S3 → `completeVideoUpload`
6. After uploads complete, re-fetch the drop to get updated comment with media URLs
7. Replace the optimistic comment with the full one

---

## Phase 1: Update `useFileUpload` Composable

### File: `fyli-fe-v2/src/composables/useFileUpload.ts`

Add `commentId` support to `uploadVideo` and `uploadFiles`. Export `uploadCommentFiles` and `getTranscodeDelay` as standalone functions so `CommentList` can import them directly without instantiating the full composable.

Add these **exported standalone functions** after the `useFileUpload` function (outside it):

```typescript
async function uploadVideoFile(
	entry: FileEntry,
	dropId: number,
	commentId: number
): Promise<void> {
	const { data } = await requestVideoUpload(
		dropId, entry.file.type, entry.file.size, commentId
	)
	const { promise } = uploadFileToS3(data.presignedUrl, entry.file)
	await promise
	await completeVideoUpload(data.movieId, dropId)
}

export async function uploadCommentFiles(
	entries: FileEntry[],
	dropId: number,
	commentId: number
): Promise<number> {
	const results = await Promise.allSettled(
		entries.map((entry) => {
			if (entry.type === "image") {
				return uploadImage(entry.file, dropId, commentId)
			}
			return uploadVideoFile(entry, dropId, commentId)
		})
	)
	return results.filter((r) => r.status === "rejected").length
}

export function getTranscodeDelay(entries: FileEntry[]): number {
	const videoEntries = entries.filter((e) => e.type === "video")
	if (videoEntries.length === 0) return 0
	const largestSize = Math.max(...videoEntries.map((e) => e.file.size))
	const MB_100 = 100 * 1024 * 1024
	if (largestSize > MB_100) return 8000
	return 2000
}
```

Also update `uploadVideo` and `uploadFiles` inside the composable to accept optional `commentId`:

```typescript
async function uploadVideo(entry: FileEntry, dropId: number, commentId?: number) {
	const { data } = await requestVideoUpload(
		dropId, entry.file.type, entry.file.size, commentId
	)
	const { promise } = uploadFileToS3(data.presignedUrl, entry.file, (percent) => {
		videoProgress.value[entry.id] = percent
	})
	await promise
	await completeVideoUpload(data.movieId, dropId)
}

async function uploadFiles(
	entries: FileEntry[],
	dropId: number,
	commentId?: number
): Promise<number> {
	const results = await Promise.allSettled(
		entries.map((entry) => {
			if (entry.type === "image") {
				return uploadImage(entry.file, dropId, commentId)
			}
			return uploadVideo(entry, dropId, commentId)
		})
	)
	return results.filter((r) => r.status === "rejected").length
}
```

Remove `getTranscodeDelay` from inside the composable (it's now the standalone export). Update the composable's return to remove `getTranscodeDelay` — existing callers (`CreateMemoryView`) should import the standalone version.

**Changes:**
- `uploadVideo` accepts optional `commentId`, passes to `requestVideoUpload`
- `uploadFiles` accepts optional `commentId`, passes to `uploadImage` and `uploadVideo`
- New standalone `uploadCommentFiles(entries, dropId, commentId)` — no progress tracking, no composable state needed
- `getTranscodeDelay` moved to standalone export (removed from composable return)
- Existing callers without `commentId` still work

---

## Phase 2: Update `CommentForm`

### File: `fyli-fe-v2/src/components/comment/CommentForm.vue`

Add file selection UI and emit file entries with the submit event.

```vue
<script setup lang="ts">
import { ref, computed } from 'vue'
import { useFileUpload, type FileEntry } from '@/composables/useFileUpload'

const emit = defineEmits<{
	submit: [text: string, files: FileEntry[]]
}>()

const {
	fileEntries,
	fileError,
	onFileChange,
	removeFile,
} = useFileUpload()

const text = ref('')
const submitting = ref(false)

const canSubmit = computed(() => {
	return (text.value.trim() || fileEntries.value.length > 0) && !submitting.value
})

async function handleSubmit() {
	if (!canSubmit.value) return
	submitting.value = true
	const files = [...fileEntries.value]
	const commentText = text.value.trim()
	text.value = ''
	fileEntries.value = []
	emit('submit', commentText, files)
	submitting.value = false
}
</script>

<template>
	<div class="mt-3">
		<div v-if="fileError" class="text-warning small mb-1">{{ fileError }}</div>
		<div v-if="fileEntries.length" class="d-flex gap-2 mb-2 flex-wrap">
			<div v-for="entry in fileEntries" :key="entry.id" class="position-relative">
				<video
					v-if="entry.type === 'video'"
					:src="entry.previewUrl"
					class="rounded"
					style="width: 60px; height: 60px; object-fit: cover"
					muted
					preload="metadata"
				/>
				<img
					v-else
					:src="entry.previewUrl"
					class="rounded"
					style="width: 60px; height: 60px; object-fit: cover"
				/>
				<button
					type="button"
					class="btn btn-sm btn-danger position-absolute top-0 end-0 p-0 lh-1"
					style="width: 18px; height: 18px; font-size: 0.65rem;"
					@click="removeFile(entry.id)"
				>&times;</button>
			</div>
		</div>
		<form @submit.prevent="handleSubmit" class="d-flex gap-2 align-items-center">
			<input
				v-model="text"
				type="text"
				class="form-control"
				placeholder="Add a comment..."
			/>
			<label class="btn btn-sm btn-outline-secondary mb-0 flex-shrink-0">
				<span class="mdi mdi-paperclip"></span>
				<input
					type="file"
					class="d-none"
					accept="image/*,video/*"
					multiple
					@change="onFileChange"
				/>
			</label>
			<button
				type="submit"
				class="btn btn-primary flex-shrink-0"
				:disabled="!canSubmit"
			>Post</button>
		</form>
	</div>
</template>
```

**Changes from current:**
- Added `useFileUpload` composable for file selection and preview
- File previews render above the input row (60×60 thumbnails, smaller than memory creation's 80×80)
- Paperclip button opens file picker (hidden `<input type="file">` inside a `<label>`)
- Submit is allowed with text-only, files-only, or both
- Emit signature changed: `submit: [text: string, files: FileEntry[]]`
- Files are cleared from the form on submit (entries passed to parent)
- No video progress in form — uploads happen in `CommentList` after form clears

---

## Phase 3: Update `CommentList` to Handle File Uploads

### File: `fyli-fe-v2/src/components/comment/CommentList.vue`

Update `addComment` to accept files, upload them after comment creation, and refresh the comment.

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { createComment, deleteComment } from '@/services/commentApi'
import { getDrop } from '@/services/memoryApi'
import {
	uploadCommentFiles,
	getTranscodeDelay,
	type FileEntry,
} from '@/composables/useFileUpload'
import CommentForm from './CommentForm.vue'
import PhotoGrid from '@/components/memory/PhotoGrid.vue'
import ConfirmModal from '@/components/ui/ConfirmModal.vue'
import type { DropComment } from '@/types'

const props = defineProps<{
	dropId: number
	initialComments?: DropComment[]
}>()

const emit = defineEmits<{
	(e: 'countChange', count: number): void
}>()

const comments = ref<DropComment[]>(props.initialComments ?? [])
const deleteTarget = ref<number | null>(null)
const uploadingCommentId = ref<number | null>(null)

async function addComment(text: string, files: FileEntry[]) {
	try {
		const { data } = await createComment(props.dropId, text, 0)
		comments.value.push(data)
		emit('countChange', comments.value.length)

		if (files.length > 0) {
			uploadingCommentId.value = data.commentId
			try {
				await uploadCommentFiles(files, props.dropId, data.commentId)
				const delay = getTranscodeDelay(files)
				if (delay > 0) {
					await new Promise((r) => setTimeout(r, delay))
				}
				const { data: drop } = await getDrop(props.dropId)
				const updated = drop.comments.find(
					(c) => c.commentId === data.commentId
				)
				if (updated) {
					const idx = comments.value.findIndex(
						(c) => c.commentId === data.commentId
					)
					if (idx !== -1) comments.value[idx] = updated
				}
			} catch {
				// Comment was created, media uploaded — URLs will appear on next load
			} finally {
				uploadingCommentId.value = null
			}
		}
	} catch {
		// silently fail — user can retry
	}
}

async function removeComment() {
	if (deleteTarget.value === null) return
	const id = deleteTarget.value
	deleteTarget.value = null
	try {
		await deleteComment(id)
		comments.value = comments.value.filter((c) => c.commentId !== id)
		emit('countChange', comments.value.length)
	} catch {
		// silently fail — user can retry
	}
}

function timeAgo(dateStr: string): string {
	const now = Date.now()
	const then = new Date(dateStr).getTime()
	const seconds = Math.floor((now - then) / 1000)
	if (seconds < 60) return 'just now'
	const minutes = Math.floor(seconds / 60)
	if (minutes < 60) return `${minutes}m ago`
	const hours = Math.floor(minutes / 60)
	if (hours < 24) return `${hours}h ago`
	const days = Math.floor(hours / 24)
	if (days < 30) return `${days}d ago`
	return new Date(dateStr).toLocaleDateString()
}
</script>
```

**Template change:** Add an uploading indicator to each comment entry. After the media section (videos), before the closing `</div>` of `flex-grow-1`:

```html
<div
	v-if="uploadingCommentId === comment.commentId"
	class="text-muted small mt-1"
>
	<span class="spinner-border spinner-border-sm me-1"></span>
	Uploading files…
</div>
```

**Changes from current:**
- `addComment` now accepts `files: FileEntry[]` parameter
- After comment creation, uploads files with `commentId` via standalone `uploadCommentFiles`
- After uploads finish (with transcode delay for videos), re-fetches the drop to get media URLs
- Replaces the optimistic comment entry with the server version that has `imageLinks`/`movieLinks`
- `uploadingCommentId` ref tracks which comment is uploading — shows spinner on that comment
- Imports standalone `uploadCommentFiles` and `getTranscodeDelay` (no composable instantiation)

---

## Implementation Order

1. Update `useFileUpload.ts` — add optional `commentId` to `uploadVideo` and `uploadFiles`
2. Update `CommentForm.vue` — file picker UI, updated emit signature
3. Update `CommentList.vue` — handle files in `addComment`, upload after creation, refresh comment
4. Verify in browser:
   - Can select images and videos in comment form
   - Previews appear above input
   - Can remove selected files before posting
   - Comment posts with text immediately, files upload after
   - After upload, comment refreshes with media
   - Uploading spinner shows on comment while files upload
   - Spinner disappears and media appears after upload completes
   - Works in both inline (MemoryCard) and detail (MemoryDetailView) contexts
5. Type-check and build
