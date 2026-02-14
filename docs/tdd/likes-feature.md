# TDD: Memory Likes (Heart) Feature

## Overview

Add a "like" feature to memories (drops) using the existing comment system's `Kind` field. Kind=1 (Thank) represents a like. Users click a heart icon to toggle their like, see a count, and hover to see who liked. Likes are excluded from comment counts and comment display.

## Design Decisions

- **Self-likes disabled** — users cannot like their own memories
- **Placement** — heart button appears on both MemoryCard (feed) and MemoryDetailView
- **Hover** — simple Bootstrap tooltip showing comma-separated names
- **Data approach** — frontend filters the existing `comments` array; no backend API contract changes

## Architecture

### Data Flow

```
User clicks heart → POST /api/comments/{dropId}/thanks → Backend toggles Kind 1↔2
                                                        → Returns CommentModel
Frontend updates local comments array → Re-computes like count and tooltip
```

### Existing Backend (No API Changes)

The backend already has a complete "thank" system:

- **Endpoint:** `POST /api/comments/{dropId}/thanks`
- **Toggle logic:** Creates Kind=1 (Thank) on first call, flips between Kind=1 and Kind=2 (UnThank) on subsequent calls
- **One per user per drop** — enforced by `SingleOrDefault(x => x.UserId == userId && x.Kind != 0)`

### Backend Change: Prevent Self-Likes

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs`

The `Thank` method currently allows the drop owner to like their own memory. Add a guard:

```csharp
public async Task<CommentModel> Thank(int userId, int dropId)
{
    if (CanView(userId, dropId))
    {
        var drop = await Context.Drops.Include(i => i.CreatedBy).Include(i => i.Comments).FirstOrDefaultAsync(x => x.DropId.Equals(dropId));

        // NEW: prevent self-likes
        if (drop.UserId == userId)
        {
            throw new NotAuthorizedException("You cannot like your own memory");
        }

        // ... rest of existing logic unchanged
    }
}
```

## Frontend Changes

### Component Diagram

```
MemoryCard.vue
├── LikeButton.vue          ← NEW shared component
├── CommentList.vue          ← Modified (filter out likes)
│   └── CommentForm.vue

MemoryDetailView.vue
├── LikeButton.vue          ← NEW shared component
├── CommentList.vue          ← Modified (filter out likes)
│   └── CommentForm.vue
```

### File Structure

```
fyli-fe-v2/src/
├── components/
│   └── ui/
│       └── LikeButton.vue              ← NEW
├── services/
│   └── commentApi.ts                   ← ADD thankDrop()
├── components/
│   ├── memory/
│   │   └── MemoryCard.vue              ← MODIFY (add LikeButton, filter comment count)
│   └── comment/
│       └── CommentList.vue             ← MODIFY (filter out likes from display + count)
├── views/
│   └── memory/
│       └── MemoryDetailView.vue        ← MODIFY (add LikeButton)
└── types/
    └── index.ts                        ← NO CHANGES (DropComment.kind already exists)
```

---

## Phase 1: Backend — Prevent Self-Likes ✅ COMPLETE

### 1.1 Modify `DropsService.Thank()`

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs` (line ~593)

Add a self-like guard after loading the drop:

```csharp
var drop = await Context.Drops.Include(i => i.CreatedBy).Include(i => i.Comments).FirstOrDefaultAsync(x => x.DropId.Equals(dropId));

// Prevent self-likes
if (drop.UserId == userId)
{
    throw new NotAuthorizedException("You cannot like your own memory");
}
```

No database changes. No migration needed.

### 1.2 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/DropsServiceTest.cs` (or new test file)

Add test cases:
- `Thank_OtherUserDrop_CreatesLike` — verify Kind=1 comment created
- `Thank_OwnDrop_ThrowsNotAuthorized` — verify self-like is blocked
- `Thank_Toggle_SwitchesBetweenThankAndUnthank` — verify toggle behavior

---

## Phase 2: Frontend — API Service + LikeButton Component ✅ COMPLETE

### 2.1 Add `thankDrop()` to Comment API

**File:** `fyli-fe-v2/src/services/commentApi.ts`

```typescript
export function thankDrop(dropId: number) {
  return api.post<DropComment>(`/comments/${dropId}/thanks`)
}
```

### 2.2 Create LikeButton Component

**File:** `fyli-fe-v2/src/components/ui/LikeButton.vue`

**Props:**
- `comments: DropComment[]` — all comments for the drop (component filters internally)
- `dropId: number` — for the API call
- `isOwner: boolean` — if true, button is hidden (can't like own post)

**Emits:**
- `liked(comment: DropComment)` — after successful like/unlike toggle, parent updates its comments array

**Behavior:**
- Filter `comments` where `kind === 1` → those are active likes. Kind=2 (UnThank) represents a removed like and is excluded from the count.
- Check if current user has a like via `!comment.foreign` (the backend sets `foreign=false` for the current user's own comments)
- Display: heart icon + count
  - Empty heart (`mdi-heart-outline`) when not liked by current user
  - Red filled heart (`mdi-heart`, colored `text-danger`) when liked
  - Count hidden when zero
- On click: optimistically toggle the heart state, call `thankDrop(dropId)`, emit result to parent. Revert on error.
- Tooltip on hover: comma-separated `ownerName` list of likers
- Hidden when `isOwner` is true

**Template:**

```vue
<template>
  <button
    v-if="!isOwner"
    class="btn btn-sm btn-outline-secondary border-0"
    :disabled="liking"
    :title="tooltipText"
    :aria-label="isLikedByMe ? 'Unlike this memory' : 'Like this memory'"
    @click="toggleLike"
  >
    <span
      class="mdi"
      :class="isLikedByMe ? 'mdi-heart text-danger' : 'mdi-heart-outline'"
    ></span>
    <span v-if="likeCount > 0" class="ms-1">{{ likeCount }}</span>
  </button>
</template>

<script setup lang="ts">
import { computed, ref } from 'vue'
import { thankDrop } from '@/services/commentApi'
import type { DropComment } from '@/types'

const props = defineProps<{
  comments: DropComment[]
  dropId: number
  isOwner: boolean
}>()

const emit = defineEmits<{
  (e: 'liked', comment: DropComment): void
}>()

const liking = ref(false)

// Kind=1 (Thank) = active like. Kind=2 (UnThank) = removed like, excluded.
const likes = computed(() =>
  props.comments.filter(c => c.kind === 1)
)

const likeCount = computed(() => likes.value.length)

// Use `foreign` field: false means this is the current user's comment
const isLikedByMe = computed(() =>
  likes.value.some(c => !c.foreign)
)

const tooltipText = computed(() =>
  likes.value.map(c => c.ownerName).join(', ')
)

async function toggleLike() {
  if (liking.value) return
  liking.value = true
  try {
    const { data } = await thankDrop(props.dropId)
    emit('liked', data)
  } catch {
    // silently fail
  } finally {
    liking.value = false
  }
}
</script>
```

**Tooltip initialization:** Use the native `title` attribute which provides a simple hover tooltip without any extra setup.

---

## Phase 3: Frontend — Integrate LikeButton + Filter Comments ✅ COMPLETE

### 3.1 Modify MemoryCard.vue

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.vue`

**Changes:**
1. Import `LikeButton` and `useAuthStore`
2. Compute `normalCommentCount` filtering out kind !== 0
3. Add `LikeButton` next to the comment button
4. Handle `liked` event to update local comments

```diff
 <script setup lang="ts">
-import { ref } from 'vue'
+import { ref, computed } from 'vue'
 import { useRouter } from 'vue-router'
-import type { Drop } from '@/types'
+import type { Drop, DropComment } from '@/types'
 import { createLink } from '@/services/shareLinkApi'
 import { deleteDrop } from '@/services/memoryApi'
 import { useStreamStore } from '@/stores/stream'
 import PhotoGrid from './PhotoGrid.vue'
 import ConfirmModal from '@/components/ui/ConfirmModal.vue'
 import CommentList from '@/components/comment/CommentList.vue'
 import StorylinePicker from '@/components/storyline/StorylinePicker.vue'
+import LikeButton from '@/components/ui/LikeButton.vue'

 // ... existing setup ...

+const localComments = ref<DropComment[]>(props.memory.comments ?? [])
+
+const normalCommentCount = computed(() =>
+  localComments.value.filter(c => c.kind === 0).length
+)
-const commentCount = ref(props.memory.comments?.length ?? 0)
+const commentCount = ref(normalCommentCount.value)

+// Match by commentId — the Thank endpoint always returns the correct CommentId.
+// For toggles it matches the existing record; for new likes it's a new id.
+function handleLiked(comment: DropComment) {
+  const idx = localComments.value.findIndex(
+    c => c.commentId === comment.commentId
+  )
+  if (idx !== -1) {
+    localComments.value[idx] = comment
+  } else {
+    localComments.value.push(comment)
+  }
+}
```

**Template change** (action bar area):

```html
<div class="d-flex justify-content-between align-items-center">
  <div class="d-flex gap-2 align-items-center">
    <LikeButton
      :comments="localComments"
      :dropId="memory.dropId"
      :isOwner="memory.editable"
      @liked="handleLiked"
    />
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
  </div>
  <small v-if="shareMessage" class="text-muted">{{ shareMessage }}</small>
</div>
```

Also update `CommentList` to receive `localComments` so both components share the same data source:

```html
<CommentList
  v-if="commentsEverOpened"
  v-show="commentsOpen"
  :dropId="memory.dropId"
  :initialComments="localComments"
  @countChange="commentCount = $event"
/>
```

**Note on `isOwner`:** We use `memory.editable` as a proxy for ownership. The backend confirms this: `Editable = s.CreatedBy.UserId == currentUserId` (`DropsService.cs:343`). This prevents the like button from showing on your own posts. The backend self-like guard provides defense-in-depth.

### 3.2 Modify MemoryDetailView.vue

**File:** `fyli-fe-v2/src/views/memory/MemoryDetailView.vue`

**Changes:**
1. Import `LikeButton`
2. Add `localComments` ref initialized from `memory.comments` after fetch
3. Add `handleLiked` function (same `commentId`-matching logic as MemoryCard)
4. Add `LikeButton` below the content area, above comments

```diff
+import LikeButton from '@/components/ui/LikeButton.vue'
+import type { DropComment } from '@/types'

+const localComments = ref<DropComment[]>([])

 onMounted(async () => {
   try {
     const { data } = await getDrop(dropId)
     memory.value = data
+    localComments.value = data.comments ?? []
   } catch { ... }
 })

+function handleLiked(comment: DropComment) {
+  const idx = localComments.value.findIndex(
+    c => c.commentId === comment.commentId
+  )
+  if (idx !== -1) {
+    localComments.value[idx] = comment
+  } else {
+    localComments.value.push(comment)
+  }
+}
```

Add the like button in the template between the content/media and the comments section:

```html
<!-- After media, before comments -->
<div class="d-flex align-items-center mb-3">
  <LikeButton
    :comments="localComments"
    :dropId="memory.dropId"
    :isOwner="memory.editable"
    @liked="handleLiked"
  />
</div>
<CommentList :dropId="memory.dropId" :initialComments="localComments" />
```

### 3.3 Modify CommentList.vue

**File:** `fyli-fe-v2/src/components/comment/CommentList.vue`

**Changes:**
1. Filter out non-normal comments from display
2. Update count emission to exclude likes

```diff
-const comments = ref<DropComment[]>(props.initialComments ?? [])
+const allComments = ref<DropComment[]>(props.initialComments ?? [])
+const comments = computed(() => allComments.value.filter(c => c.kind === 0))

 async function addComment(text: string, files: FileEntry[]) {
   try {
     const { data } = await createComment(props.dropId, text, 0)
-    comments.value.push(data)
-    emit('countChange', comments.value.length)
+    allComments.value.push(data)
+    emit('countChange', comments.value.length)  // computed auto-updates
```

Same changes for `removeComment` — operate on `allComments`, emit filtered count.

---

## Phase 4: Frontend Tests ✅ COMPLETE

### 4.1 LikeButton Component Tests

**File:** `fyli-fe-v2/src/components/ui/LikeButton.test.ts`

| Test | Description |
|------|-------------|
| renders empty heart when not liked | Mount with no likes, verify `mdi-heart-outline` class |
| renders filled red heart when liked by current user | Mount with kind=1 comment where `foreign=false`, verify `mdi-heart text-danger` |
| shows like count | Mount with 3 likes (kind=1), verify count text "3" |
| excludes Kind=2 (UnThank) from count | Mount with kind=1 and kind=2 comments, verify only kind=1 counted |
| hides when isOwner is true | Mount with isOwner=true, verify button not rendered |
| calls thankDrop on click | Click button, verify `thankDrop` API called with correct dropId |
| emits liked event on success | Click button with mocked API response, verify `liked` event emitted |
| shows tooltip with liker names | Mount with likes, verify title attribute contains comma-separated names |
| has correct aria-label | Mount, verify `aria-label` is "Like this memory" (or "Unlike" when liked) |
| does not show count when zero likes | Mount with no likes, verify no count text |

### 4.2 MemoryCard Integration Tests

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.test.ts` (existing or new)

| Test | Description |
|------|-------------|
| comment count excludes likes | Provide memory with 2 normal comments + 1 like, verify count shows "2" |
| LikeButton receives correct props | Verify LikeButton is rendered with correct comments and dropId |
| handleLiked updates existing like by commentId | Simulate liked event with existing commentId, verify state updated |
| handleLiked adds new like | Simulate liked event with new commentId, verify pushed to array |

### 4.3 CommentList Tests

**File:** `fyli-fe-v2/src/components/comment/CommentList.test.ts` (existing or new)

| Test | Description |
|------|-------------|
| filters out like comments from display | Provide comments with kind=0 and kind=1, verify only kind=0 rendered |
| empty state excludes likes | Provide only kind=1 comments, verify "No comments yet" shown |
| countChange only counts normal comments | Add a comment, verify emitted count excludes likes |

### 4.4 Comment API Service Tests

**File:** `fyli-fe-v2/src/services/commentApi.test.ts`

| Test | Description |
|------|-------------|
| thankDrop calls POST with correct URL | Mock axios, call thankDrop(42), verify POST to `/comments/42/thanks` |

---

## Phase 5: Backend Tests ✅ COMPLETE

### 5.1 DropsService Thank Tests

**File:** `cimplur-core/Memento/DomainTest/DropsServiceTest.cs` (or new test class)

| Test | Description |
|------|-------------|
| Thank_OtherUserDrop_CreatesThankComment | User thanks another user's drop → Comment with Kind=Thank created |
| Thank_OwnDrop_ThrowsNotAuthorized | User tries to thank own drop → NotAuthorizedException |
| Thank_Toggle_ThankToUnthank | User thanks then thanks again → Kind flips to UnThank |
| Thank_Toggle_UnthankToThank | User unthanks then thanks again → Kind flips back to Thank |

---

## Implementation Order

1. **Phase 1** — Backend self-like guard (small, no risk)
2. **Phase 2** — API service function + LikeButton component (independent, testable)
3. **Phase 3** — Integration into MemoryCard + MemoryDetailView + CommentList filtering
4. **Phase 4** — Frontend tests
5. **Phase 5** — Backend tests

## Summary of Changes

| Layer | File | Change |
|-------|------|--------|
| Backend | `DropsService.cs` | Add self-like guard in `Thank()` |
| Frontend | `commentApi.ts` | Add `thankDrop()` function |
| Frontend | `LikeButton.vue` | **NEW** — reusable heart button component |
| Frontend | `MemoryCard.vue` | Add LikeButton, filter comment count |
| Frontend | `MemoryDetailView.vue` | Add LikeButton |
| Frontend | `CommentList.vue` | Filter out kind!=0 from display and count |
| Tests | `LikeButton.test.ts` | **NEW** — 10 component tests |
| Tests | `MemoryCard.test.ts` | 4 integration tests |
| Tests | `CommentList.test.ts` | 3 tests |
| Tests | `commentApi.test.ts` | 1 API test |
| Tests | `DropsServiceTest.cs` | 4 backend tests |
