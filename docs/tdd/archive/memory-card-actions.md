# TDD: Memory Card Inline Actions

## Problem

The only way to share, edit, or delete a memory is to click the comments icon on `MemoryCard`, navigate to `MemoryDetailView`, and use the action buttons there. Owners should be able to share and edit directly from the card in the stream.

## Solution

Add a three-dot overflow menu (kebab menu) to `MemoryCard` for owner actions (Share, Edit, Delete). This is frontend-only — no backend changes needed. The APIs already exist.

---

## Phase 1: Add Action Menu to MemoryCard

### File: `fyli-fe-v2/src/components/memory/MemoryCard.vue`

Add a kebab menu icon in the card header (top-right, next to the date). Only render it when `memory.editable` is true. The menu shows three actions: Share Link, Edit, and Delete.

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import type { Drop } from '@/types'
import { createLink } from '@/services/shareLinkApi'
import { deleteDrop } from '@/services/memoryApi'
import { useStreamStore } from '@/stores/stream'
import PhotoGrid from './PhotoGrid.vue'

const props = defineProps<{
  memory: Drop
}>()

const router = useRouter()
const stream = useStreamStore()
const menuOpen = ref(false)
const sharing = ref(false)
const shareMessage = ref('')

function toggleMenu() {
  menuOpen.value = !menuOpen.value
}

function closeMenu() {
  menuOpen.value = false
}

async function handleShare() {
  sharing.value = true
  shareMessage.value = ''
  try {
    const { data } = await createLink(props.memory.dropId)
    const url = `${window.location.origin}/s/${data.token}`
    await navigator.clipboard.writeText(url)
    shareMessage.value = 'Link copied!'
  } catch {
    shareMessage.value = 'Failed to copy link'
  } finally {
    sharing.value = false
    menuOpen.value = false
    setTimeout(() => { shareMessage.value = '' }, 2000)
  }
}

function handleEdit() {
  menuOpen.value = false
  router.push(`/memory/${props.memory.dropId}/edit`)
}

async function handleDelete() {
  menuOpen.value = false
  if (!confirm('Delete this memory?')) return
  await deleteDrop(props.memory.dropId)
  stream.removeMemory(props.memory.dropId)
}
</script>

<template>
  <div class="card mb-3">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-start mb-2">
        <div>
          <strong>{{ memory.createdBy }}</strong>
          <small class="text-muted ms-2">
            {{ new Date(memory.date).toLocaleDateString() }}
          </small>
        </div>
        <div v-if="memory.editable" class="position-relative">
          <button
            class="btn btn-sm btn-link text-muted p-0"
            @click.stop="toggleMenu"
            @blur="closeMenu"
          >
            <span class="mdi mdi-dots-vertical" style="font-size: 1.25rem;"></span>
          </button>
          <div
            v-if="menuOpen"
            class="dropdown-menu show position-absolute end-0"
            style="min-width: 140px;"
            @mousedown.prevent
          >
            <button class="dropdown-item" @click="handleShare" :disabled="sharing">
              <span class="mdi mdi-share-variant me-2"></span>Share Link
            </button>
            <button class="dropdown-item" @click="handleEdit">
              <span class="mdi mdi-pencil-outline me-2"></span>Edit
            </button>
            <button class="dropdown-item text-danger" @click="handleDelete">
              <span class="mdi mdi-delete-outline me-2"></span>Delete
            </button>
          </div>
        </div>
      </div>
      <p class="card-text">{{ memory.content?.stuff }}</p>
      <PhotoGrid :images="memory.imageLinks" />
      <div v-for="movie in memory.movieLinks" :key="movie.id" class="mb-2">
        <video
          :src="movie.link"
          :poster="movie.thumbLink"
          controls
          class="img-fluid rounded"
        ></video>
      </div>
      <div class="d-flex justify-content-between align-items-center">
        <RouterLink
          :to="`/memory/${memory.dropId}`"
          class="btn btn-sm btn-outline-primary"
        >
          <span class="mdi mdi-comment-outline me-1"></span>
          {{ memory.comments?.length ?? 0 }}
        </RouterLink>
        <small v-if="shareMessage" class="text-muted">{{ shareMessage }}</small>
      </div>
    </div>
  </div>
</template>
```

### Key design decisions:

1. **Kebab menu (three dots)** — standard mobile/web pattern for overflow actions. Uses Bootstrap `dropdown-menu` for consistent styling.
2. **`@blur` on button + `@mousedown.prevent` on menu** — closes the menu when clicking outside without interfering with menu item clicks.
3. **Share feedback** — brief "Link copied!" toast text below the card actions, auto-clears after 2 seconds. No modal or separate component needed.
4. **Delete** — uses `confirm()` dialog (same as MemoryDetailView) and removes from stream store immediately.
5. **Only shows for owners** — guarded by `v-if="memory.editable"`.

### No changes to MemoryDetailView

The detail view keeps its existing share/edit/delete buttons. Both entry points use the same APIs and store methods.

### No backend changes

All APIs already exist: `createLink`, `deleteDrop`, edit route.

### No new components, stores, or services

Everything needed is already available.

---

## Implementation Order

1. Update `MemoryCard.vue` with the action menu
2. Verify in browser: stream cards show kebab menu for owned memories, not for others' memories
3. Test Share: copies link to clipboard, shows feedback
4. Test Edit: navigates to edit page, returns to stream after save
5. Test Delete: confirms, removes card from stream
