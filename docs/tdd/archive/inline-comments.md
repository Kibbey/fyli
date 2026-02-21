# TDD: Inline Collapsible Comments

**PRD:** `docs/prd/PRD_INLINE_COMMENTS.md`

## Overview

Move the comment experience from a separate detail page into an inline collapsible section on each `MemoryCard` in the stream. Update `CommentList` to use `PhotoGrid` for images and matched video styling. No backend changes — all data and APIs already exist.

### No database changes.
### No backend changes.
### No new API calls — comments already come in the `Drop` stream response.

---

## Phase 1: Update CommentList Styling

### File: `fyli-fe-v2/src/components/comment/CommentList.vue`

Upgrade the comment rendering to use `PhotoGrid` for images (matching memory card), full-width videos with poster/controls, relative timestamps, and `ConfirmModal` for delete.

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { createComment, deleteComment } from '@/services/commentApi'
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

async function addComment(text: string) {
	try {
		const { data } = await createComment(props.dropId, text, 0)
		comments.value.push(data)
		emit('countChange', comments.value.length)
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

<template>
	<div class="mt-3">
		<div v-if="comments.length === 0" class="text-muted small">
			No comments yet.
		</div>
		<div
			v-for="comment in comments"
			:key="comment.commentId"
			class="d-flex justify-content-between align-items-start mb-2 p-2 bg-light rounded"
		>
			<div class="flex-grow-1">
				<div class="d-flex align-items-baseline gap-2">
					<strong class="small">{{ comment.ownerName }}</strong>
					<small class="text-muted">{{ timeAgo(comment.date) }}</small>
				</div>
				<p v-if="comment.comment" class="mb-1">{{ comment.comment }}</p>
				<PhotoGrid :images="comment.imageLinks" />
				<div v-for="movie in comment.movieLinks" :key="movie.id" class="mb-2">
					<video
						:src="movie.link"
						:poster="movie.thumbLink"
						controls
						class="img-fluid rounded"
					></video>
				</div>
			</div>
			<button
				v-if="!comment.foreign"
				class="btn btn-sm btn-link text-danger flex-shrink-0"
				@click="deleteTarget = comment.commentId"
			>
				<span class="mdi mdi-delete-outline"></span>
			</button>
		</div>
		<CommentForm @submit="addComment" />
		<ConfirmModal
			v-if="deleteTarget !== null"
			title="Delete Comment"
			message="Are you sure you want to delete this comment?"
			@confirm="removeComment"
			@cancel="deleteTarget = null"
		/>
	</div>
</template>
```

**Changes from current:**
- Replaced `ClickableImage` loop with `PhotoGrid` (same component as memory card) for comment images
- Videos now use `img-fluid rounded` (same as memory card) instead of fixed `max-height: 120px`
- Added relative timestamps via `timeAgo()` helper
- Comment text changed from `small` to normal size for readability
- Added `ConfirmModal` for delete instead of immediate deletion
- Removed unused `useAuthStore` import
- Removed `<h6>Comments</h6>` header (the toggle button on the card serves as the label)
- Added error handling (try/catch) to `addComment` and `removeComment`
- Emits `countChange` event so parent can update displayed comment count

---

## Phase 2: Add Inline Collapsible Comments to MemoryCard

### File: `fyli-fe-v2/src/components/memory/MemoryCard.vue`

Replace the `RouterLink` comment button with a toggle button. Add a collapsible `CommentList` section inside the card. Make the date a link to the detail page.

**Changes to the `<script setup>`:**

Add imports and state:
```typescript
import CommentList from '@/components/comment/CommentList.vue'

const commentsOpen = ref(false)
const commentsEverOpened = ref(false)
const commentCount = ref(props.memory.comments?.length ?? 0)

function toggleComments() {
	commentsOpen.value = !commentsOpen.value
	if (commentsOpen.value) commentsEverOpened.value = true
}
```

**Changes to the `<template>`:**

1. Replace the `RouterLink` comment button with a toggle button:

```html
<!-- Replace this: -->
<RouterLink
	:to="`/memory/${memory.dropId}`"
	class="btn btn-sm btn-outline-primary"
>
	<span class="mdi mdi-comment-outline me-1"></span>
	{{ memory.comments?.length ?? 0 }}
</RouterLink>

<!-- With this: -->
<button
	class="btn btn-sm btn-outline-primary"
	@click="toggleComments"
>
	<span class="mdi mdi-comment-outline me-1"></span>
	{{ commentCount }}
	<span
		class="mdi ms-1"
		:class="commentsOpen ? 'mdi-chevron-up' : 'mdi-chevron-down'"
	></span>
</button>
```

2. Make the date a link to the detail page (replaces the removed RouterLink):

```html
<!-- Replace this: -->
<small class="text-muted ms-2">
	{{ new Date(memory.date).toLocaleDateString() }}
</small>

<!-- With this: -->
<RouterLink
	:to="`/memory/${memory.dropId}`"
	class="text-muted ms-2 small"
>
	{{ new Date(memory.date).toLocaleDateString() }}
</RouterLink>
```

3. Add the collapsible comment section inside the card-body, after the action bar:

```html
<CommentList
	v-if="commentsEverOpened"
	v-show="commentsOpen"
	:dropId="memory.dropId"
	:initialComments="memory.comments"
	@countChange="commentCount = $event"
/>
```

Use `v-if="commentsEverOpened"` for lazy mount (CommentList isn't created until first expand), combined with `v-show` to preserve state when collapsed. The `@countChange` event keeps the toggle button count in sync after add/delete. Multiple cards can be expanded simultaneously.

---

## Implementation Order

1. Update `CommentList.vue` — PhotoGrid for images, matched video styling, relative timestamps, ConfirmModal for delete
2. Update `MemoryCard.vue` — toggle button, collapsible section, date as detail link
3. Verify in browser:
   - Comments expand/collapse on toggle
   - Multiple cards can be open simultaneously
   - Comment images render via PhotoGrid with click-to-expand
   - Comment videos render full-width with poster and controls
   - Relative timestamps display correctly
   - Add comment works inline (appears at bottom, input clears)
   - Delete comment shows modal, removes on confirm
   - Date links to detail page
   - Detail page still works independently
4. Type-check and build
