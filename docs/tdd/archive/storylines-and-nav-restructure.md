# TDD: Storylines & Navigation Restructure

**PRD:** `docs/prd/PRD_STORYLINES.md`
**Status:** Draft
**Created:** 2026-02-09

## Overview

Frontend-only implementation adding Storylines to fyli-fe-v2 and restructuring navigation from a bottom tab bar to a top nav + drawer pattern. The backend API is fully implemented and tested — no backend changes required.

### !IMPORTANT! — Backwards Compatibility

The PRD flags this as an existing feature with data that must remain available. Two approaches:

**Approach A (Recommended): Pure frontend build, zero backend changes.** All existing Timeline/TimelineUser/TimelineDrop data remains untouched. The new frontend consumes the same API endpoints (`/api/timelines`, `/api/drops/timelines/{id}`) that already exist. Users who have existing storylines will see them immediately in the new UI. No migration needed.

**Approach B: Extend backend for public storyline sharing.** User stories 14 and 17 describe non-users contributing to storylines without creating an account. This would require new backend entities (e.g., `StorylineShareLink`) similar to the existing `MemoryShareLink` pattern. **Deferred to a future phase** — the current question-answer flow (`/q/:token`) already handles non-user contributions and can serve as the model when this is built.

**Decision: Approach A.** No data model changes, no migrations, full backwards compatibility by definition.

### Backend Prerequisite: Fix `GetInvited` Response

The `GET /api/timelines/{id}/invited` endpoint currently returns `Asked.Id` mapped to `ShareRequest.RequestId` (the share request's own ID), not the invited user's ID. The frontend needs user IDs to match against the connections list and show already-invited users as disabled.

**File:** `cimplur-core/Memento/Memento/Controllers/TimelineController.cs` — `GetByIdAsked` method

**Current (broken for our use case):**
```csharp
asked = invitations.Select(s => new Asked
{
    Connection = false,
    Name = s.ContactName,
    DropId = 0,
    Id = s.RequestId  // ← ShareRequest.ShareRequestId
}).ToList();
```

**Fix:** Map `Id` to the actual user ID instead of the request ID. The `OutstandingConnectionRequests` model needs to include the target user ID, or the query needs to join through to get it. This is a backwards-compatible change (no data model changes, only response mapping).

**Note:** This is the only backend change needed for the entire feature. It does not affect data models, migrations, or existing functionality — it only changes which ID value is returned in one API response.

### Backend Note: Drop Removal Permission

PRD 5.2 requires "Invited users can only remove memories they personally added." The backend **already enforces this** in `TimelineService.RemoveDropFromTimeline()` — it checks `x.UserId == currentUserId` and throws `NotAuthorizedException` if the current user didn't add the drop. No frontend enforcement needed; the API will reject unauthorized removals.

---

## Component Diagram

```
AppLayout.vue
├── AppNav.vue (modified: + hamburger icon)
├── AppDrawer.vue (NEW: slide-out navigation)
├── <router-view /> (main content)
└── FloatingActionButton.vue (NEW: persistent "+" button)

Storyline Views:
├── StorylineListView.vue (NEW: /storylines)
├── CreateStorylineView.vue (NEW: /storylines/new)
├── EditStorylineView.vue (NEW: /storylines/:id/edit)
├── StorylineDetailView.vue (NEW: /storylines/:id)
└── InviteToStorylineView.vue (NEW: /storylines/:id/invite)

Modified Existing:
├── MemoryCard.vue (+ "Add to Storyline" menu item)
├── MemoryDetailView.vue (+ storyline display)
├── CreateMemoryView.vue (+ storyline picker)
├── EditMemoryView.vue (+ storyline picker)
└── StreamView.vue (- remove inline FAB)

New Shared Components:
├── StorylinePicker.vue (NEW: modal with checkbox list)
├── StorylineCard.vue (NEW: card for list view)
└── AddExistingMemoryModal.vue (NEW: pick existing memories to add)

New Services/Stores:
├── timelineApi.ts (NEW)
├── storyline.ts store (NEW)
└── types/index.ts (+ Storyline types)
```

---

## File Structure

```
fyli-fe-v2/src/
├── components/
│   ├── ui/
│   │   ├── AppNav.vue              (MODIFIED)
│   │   ├── AppBottomNav.vue        (DELETED)
│   │   ├── AppDrawer.vue           (NEW)
│   │   └── FloatingActionButton.vue (NEW)
│   └── storyline/
│       ├── StorylineCard.vue       (NEW)
│       ├── StorylinePicker.vue     (NEW)
│       └── AddExistingMemoryModal.vue (NEW)
├── layouts/
│   └── AppLayout.vue               (MODIFIED)
├── views/
│   ├── stream/
│   │   └── StreamView.vue          (MODIFIED - remove FAB)
│   ├── memory/
│   │   ├── CreateMemoryView.vue    (MODIFIED - add storyline field)
│   │   ├── EditMemoryView.vue      (MODIFIED - add storyline field)
│   │   └── MemoryDetailView.vue    (MODIFIED - show storylines)
│   └── storyline/
│       ├── StorylineListView.vue   (NEW)
│       ├── CreateStorylineView.vue (NEW)
│       ├── EditStorylineView.vue   (NEW)
│       ├── StorylineDetailView.vue (NEW)
│       └── InviteToStorylineView.vue (NEW)
├── services/
│   ├── timelineApi.ts              (NEW)
│   └── connectionApi.ts            (MODIFIED - add getConnections)
├── stores/
│   └── storyline.ts                (NEW)
├── types/
│   └── index.ts                    (MODIFIED - add Storyline types)
└── router/
    └── index.ts                    (MODIFIED - add routes)
```

---

## Phase 1: Navigation Restructure

### 1.1 Types — Add to `src/types/index.ts`

```typescript
// Add to existing types/index.ts
export interface Storyline {
  id: number
  name: string
  description: string
  active: boolean
  following: boolean
  creator: boolean
  selected: boolean
}
```

Also update the existing `Drop` interface to type the `timeline` field:

```typescript
// Change in existing Drop interface
timeline: Storyline | null  // was: unknown | null
```

### 1.2 AppDrawer.vue (NEW)

**Path:** `src/components/ui/AppDrawer.vue`

```vue
<script setup lang="ts">
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

defineProps<{
  open: boolean
}>()

const emit = defineEmits<{
  close: []
}>()

const route = useRoute()
const auth = useAuthStore()

interface DrawerItem {
  name: string
  label: string
  icon: string
  iconActive: string
  to: string
  matchPaths: string[]
}

const drawerItems: DrawerItem[] = [
  {
    name: 'memories',
    label: 'Memories',
    icon: 'mdi-home-outline',
    iconActive: 'mdi-home',
    to: '/',
    matchPaths: ['/', '/memory'],
  },
  {
    name: 'storylines',
    label: 'Storylines',
    icon: 'mdi-book-outline',
    iconActive: 'mdi-book-open-variant',
    to: '/storylines',
    matchPaths: ['/storylines'],
  },
  {
    name: 'questions',
    label: 'Questions',
    icon: 'mdi-comment-question-outline',
    iconActive: 'mdi-comment-question',
    to: '/questions',
    matchPaths: ['/questions'],
  },
  {
    name: 'account',
    label: 'Account',
    icon: 'mdi-account-outline',
    iconActive: 'mdi-account',
    to: '/account',
    matchPaths: ['/account'],
  },
]

function isActive(item: DrawerItem): boolean {
  return item.matchPaths.some((path) => {
    if (path === '/') return route.path === '/'
    return route.path.startsWith(path)
  })
}

// Swipe-to-close gesture support
let touchStartX = 0

function handleTouchStart(e: TouchEvent) {
  touchStartX = e.touches[0]?.clientX ?? 0
}

function handleTouchEnd(e: TouchEvent) {
  const touchEndX = e.changedTouches[0]?.clientX ?? 0
  if (touchStartX - touchEndX > 50) {
    emit('close')
  }
}
</script>

<template>
  <Teleport to="body">
    <Transition name="backdrop">
      <div v-if="open" class="drawer-backdrop" @click="emit('close')"></div>
    </Transition>
    <Transition name="drawer">
      <nav
        v-if="open"
        class="drawer"
        aria-label="Main navigation"
        @keydown.escape="emit('close')"
        @touchstart.passive="handleTouchStart"
        @touchend.passive="handleTouchEnd"
      >
        <div class="drawer-header">
          <span class="fw-semibold">{{ auth.user?.name || auth.user?.email || '' }}</span>
        </div>
        <ul class="drawer-list">
          <li v-for="item in drawerItems" :key="item.name">
            <RouterLink
              :to="item.to"
              class="drawer-item"
              :class="{ active: isActive(item) }"
              @click="emit('close')"
            >
              <span class="mdi" :class="isActive(item) ? item.iconActive : item.icon"></span>
              <span>{{ item.label }}</span>
            </RouterLink>
          </li>
        </ul>
      </nav>
    </Transition>
  </Teleport>
</template>

<style scoped>
.drawer-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.4);
  z-index: 1040;
}

.drawer {
  position: fixed;
  top: 0;
  left: 0;
  bottom: 0;
  width: min(280px, 80vw);
  background: var(--fyli-bg, #fff);
  z-index: 1050;
  display: flex;
  flex-direction: column;
  box-shadow: 2px 0 8px rgba(0, 0, 0, 0.15);
}

.drawer-header {
  padding: 1.5rem 1rem 1rem;
  border-bottom: 1px solid var(--fyli-border, #dee2e6);
}

.drawer-list {
  list-style: none;
  margin: 0;
  padding: 0.5rem 0;
}

.drawer-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1rem;
  text-decoration: none;
  color: var(--fyli-text, #212529);
  transition: background-color 0.15s ease-in-out;
}

.drawer-item .mdi {
  font-size: 1.5rem;
}

.drawer-item:hover {
  background-color: var(--fyli-bg-light, #f8f9fa);
}

.drawer-item.active {
  color: var(--fyli-primary);
  background-color: var(--fyli-primary-light, #e8f7f0);
}

/* Transitions */
.backdrop-enter-active,
.backdrop-leave-active {
  transition: opacity 0.25s ease;
}
.backdrop-enter-from,
.backdrop-leave-to {
  opacity: 0;
}

.drawer-enter-active,
.drawer-leave-active {
  transition: transform 0.25s ease;
}
.drawer-enter-from,
.drawer-leave-to {
  transform: translateX(-100%);
}
</style>
```

**Key decisions:**
- Uses `<Teleport to="body">` for proper stacking above all content (same pattern as `ConfirmModal.vue`)
- Drawer width: `min(280px, 80vw)` — 280px on wider screens, 80% on narrow
- Transition: 250ms slide + fade backdrop (matches PRD requirement of 200-300ms)
- Active state uses `--fyli-primary-light` background (consistent with style guide)
- `drawerItems` array is easily extensible — adding a feature = adding an object to the array
- User name/email displayed at top via `useAuthStore`
- Swipe-left gesture closes drawer (50px threshold on `@touchstart`/`@touchend`)
- `@keydown.escape` closes drawer for keyboard accessibility

### 1.3 FloatingActionButton.vue (NEW)

**Path:** `src/components/ui/FloatingActionButton.vue`

```vue
<script setup lang="ts">
defineProps<{
  to: string
}>()
</script>

<template>
  <RouterLink :to="to" class="fab btn btn-primary rounded-circle shadow" aria-label="Create memory">
    <span class="mdi mdi-plus"></span>
  </RouterLink>
</template>

<style scoped>
.fab {
  position: fixed;
  bottom: calc(1rem + env(safe-area-inset-bottom));
  right: 1.5rem;
  width: 56px;
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1030;
}

.fab .mdi {
  font-size: 1.5rem;
}
</style>
```

**Key decisions:**
- Extracted into its own component (was inline in StreamView.vue)
- `bottom: calc(1rem + env(safe-area-inset-bottom))` — no longer needs 80px offset since bottom nav is gone
- `z-index: 1030` — above content, below drawer backdrop (1040) and drawer (1050)
- Accepts `to` prop for reuse (currently always `/memory/new`)
- `aria-label` for accessibility on icon-only button

### 1.4 AppNav.vue (MODIFIED)

**Path:** `src/components/ui/AppNav.vue`

Add hamburger menu icon on the left side.

```vue
<script setup lang="ts">
defineEmits<{
  toggleDrawer: []
}>()
</script>

<template>
  <nav class="navbar navbar-expand navbar-light bg-white border-bottom px-3">
    <button
      class="btn btn-link text-dark p-0 me-2"
      aria-label="Open menu"
      @click="$emit('toggleDrawer')"
    >
      <span class="mdi mdi-menu" style="font-size: 1.5rem"></span>
    </button>
    <RouterLink class="navbar-brand fw-bold mb-0" to="/">fyli</RouterLink>
    <div class="ms-auto d-flex align-items-center gap-2">
      <RouterLink to="/invite" class="btn btn-sm btn-outline-secondary">
        <span class="mdi mdi-account-plus-outline me-1"></span>Invite
      </RouterLink>
    </div>
  </nav>
</template>
```

**Changes from current:**
- Added `<script setup>` with `toggleDrawer` emit
- Added hamburger button (`mdi-menu`) before the logo
- Logo gets `mb-0` to fix vertical alignment with new button

### 1.5 AppLayout.vue (MODIFIED)

```vue
<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import AppNav from '@/components/ui/AppNav.vue'
import AppDrawer from '@/components/ui/AppDrawer.vue'
import FloatingActionButton from '@/components/ui/FloatingActionButton.vue'

const route = useRoute()
const drawerOpen = ref(false)

// Auto-close drawer on any route change (e.g. browser back/forward)
watch(() => route.path, () => {
  drawerOpen.value = false
})
</script>

<template>
  <div class="app-shell bg-light">
    <AppNav @toggle-drawer="drawerOpen = !drawerOpen" />
    <main class="app-main">
      <div class="container py-3" style="max-width: 600px">
        <slot />
      </div>
    </main>
    <FloatingActionButton to="/memory/new" />
    <AppDrawer :open="drawerOpen" @close="drawerOpen = false" />
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  flex-direction: column;
  height: 100vh;
  height: 100dvh;
}

.app-main {
  flex: 1 1 0;
  min-height: 0;
  overflow-y: auto;
}
</style>
```

**Changes from current:**
- Removed `AppBottomNav` import and usage
- Added `AppDrawer` with reactive `drawerOpen` state
- Added `FloatingActionButton`
- Drawer state managed with a simple `ref` (no Pinia store needed)

### 1.6 StreamView.vue (MODIFIED)

Remove the inline FAB since it now lives in AppLayout.

**Remove** this block from the template:
```html
<RouterLink to="/memory/new" class="fab btn btn-primary rounded-circle shadow">
  <span class="mdi mdi-plus" style="font-size: 1.5rem"></span>
</RouterLink>
```

**Remove** the `.fab` scoped style block.

No other changes to StreamView.

### 1.7 Phase 1 Tests

#### AppDrawer.test.ts
**Path:** `src/components/ui/AppDrawer.test.ts`

```typescript
// Test cases:
// 1. renders nothing when open=false
// 2. renders drawer panel when open=true
// 3. renders all nav items (Memories, Storylines, Questions, Account)
// 4. highlights active item based on current route
// 5. emits 'close' when backdrop is clicked
// 6. emits 'close' when a nav item is clicked
// 7. renders user name from auth store
// 8. emits 'close' on Escape keydown
// 9. emits 'close' on swipe-left gesture (touchstart → touchend with >50px left delta)
```

Mock setup:
- `vi.mock('vue-router')` — provide `useRoute` returning configurable path
- `vi.mock('@/stores/auth')` — provide `useAuthStore` returning test user
- Mount with `open: true` prop for rendering tests

#### FloatingActionButton.test.ts
**Path:** `src/components/ui/FloatingActionButton.test.ts`

```typescript
// Test cases:
// 1. renders RouterLink with correct 'to' prop
// 2. displays plus icon
// 3. has aria-label for accessibility
```

#### AppNav.test.ts
**Path:** `src/components/ui/AppNav.test.ts`

```typescript
// Test cases:
// 1. renders hamburger menu button
// 2. emits 'toggleDrawer' when hamburger clicked
// 3. renders fyli logo linking to /
// 4. renders invite button
```

#### AppLayout.test.ts
**Path:** `src/layouts/AppLayout.test.ts`

```typescript
// Test cases:
// 1. renders AppNav and FloatingActionButton
// 2. does not render AppDrawer initially (closed)
// 3. opens drawer when AppNav emits toggleDrawer
// 4. closes drawer when AppDrawer emits close
// 5. closes drawer on route change
```

---

## Phase 2: Storyline API & List

### 2.1 timelineApi.ts (NEW)

**Path:** `src/services/timelineApi.ts`

```typescript
import api from './api'
import type { Storyline } from '@/types'
import type { DropsResponse } from './memoryApi'

export function getStorylines() {
  return api.get<Storyline[]>('/timelines')
}

export function getStoryline(id: number) {
  return api.get<Storyline>(`/timelines/${id}`)
}

export function createStoryline(data: { name: string; description?: string }) {
  return api.post<Storyline>('/timelines', data)
}

export function updateStoryline(id: number, data: { name: string; description?: string }) {
  return api.put<Storyline>(`/timelines/${id}`, data)
}

export function deleteStoryline(id: number) {
  return api.delete<Storyline>(`/timelines/${id}`)
}

export function getStorylineDrops(id: number, skip = 0, ascending = true) {
  return api.get<DropsResponse>(`/drops/timelines/${id}`, {
    params: { skip, ascending },
  })
}

export function getStorylinesForDrop(dropId: number) {
  return api.get<Storyline[]>(`/timelines/drops/${dropId}`)
}

export function addDropToStoryline(dropId: number, timelineId: number) {
  return api.post(`/timelines/drops/${dropId}/timelines/${timelineId}`)
}

export function removeDropFromStoryline(dropId: number, timelineId: number) {
  return api.delete(`/timelines/drops/${dropId}/timelines/${timelineId}`)
}

export function inviteToStoryline(id: number, userIds: number[]) {
  return api.post(`/timelines/${id}/invite`, { ids: userIds })
}

export interface InvitedUser {
  id: number
  name: string
}

export function getStorylineInvited(id: number) {
  return api.get<InvitedUser[]>(`/timelines/${id}/invited`)
}
```

**Key decisions:**
- Uses `/drops/timelines/{id}` route for fetching drops (from DropController, returns `DropsResponse` which matches existing `DropsResponse` shape)
- Default `ascending = true` for storyline drops (oldest first = chronological storytelling)
- Reuses existing `DropsResponse` type from `memoryApi.ts`

### 2.2 connectionApi.ts (MODIFIED)

Add `getConnections` function:

```typescript
import api from './api'

export interface Connection {
  id: number
  name: string
  emailNotifications: boolean
}

export function getConnections() {
  return api.get<Connection[]>('/connections')
}

export function sendInvitation(email: string) {
  return api.post('/connections', { email })
}

export function confirmConnection(name: string) {
  return api.post('/connections/confirm', { name })
}
```

### 2.3 StorylineCard.vue (NEW)

**Path:** `src/components/storyline/StorylineCard.vue`

```vue
<script setup lang="ts">
import type { Storyline } from '@/types'

defineProps<{
  storyline: Storyline
}>()
</script>

<template>
  <RouterLink
    :to="`/storylines/${storyline.id}`"
    class="card mb-2 text-decoration-none"
  >
    <div class="card-body py-3">
      <div class="d-flex justify-content-between align-items-start">
        <div>
          <h6 class="mb-1 text-dark">{{ storyline.name }}</h6>
          <p v-if="storyline.description" class="mb-0 text-muted small text-truncate" style="max-width: 280px">
            {{ storyline.description }}
          </p>
        </div>
        <span v-if="!storyline.creator" class="badge bg-light text-muted">Shared</span>
      </div>
    </div>
  </RouterLink>
</template>
```

### 2.4 StorylineListView.vue (NEW)

**Path:** `src/views/storyline/StorylineListView.vue`

```vue
<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { getStorylines } from '@/services/timelineApi'
import type { Storyline } from '@/types'
import StorylineCard from '@/components/storyline/StorylineCard.vue'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'

const router = useRouter()
const storylines = ref<Storyline[]>([])
const loading = ref(true)
const error = ref(false)

const myStorylines = computed(() => storylines.value.filter((s) => s.creator))
const sharedStorylines = computed(() => storylines.value.filter((s) => !s.creator))

onMounted(async () => {
  try {
    const { data } = await getStorylines()
    storylines.value = data
  } catch {
    error.value = true
  } finally {
    loading.value = false
  }
})
</script>

<template>
  <div>
    <div class="d-flex justify-content-between align-items-center mb-3">
      <h4 class="mb-0">Storylines</h4>
      <RouterLink to="/storylines/new" class="btn btn-sm btn-primary">
        <span class="mdi mdi-plus me-1"></span>Create
      </RouterLink>
    </div>

    <LoadingSpinner v-if="loading" />
    <ErrorState v-else-if="error" @retry="router.go(0)" />
    <EmptyState
      v-else-if="storylines.length === 0"
      icon="mdi-book-open-page-variant-outline"
      message="No storylines yet. Create one to start curating memories around a person or place."
      actionLabel="Create Storyline"
      @action="router.push('/storylines/new')"
    />
    <template v-else>
      <div v-if="myStorylines.length">
        <h6 class="text-muted mb-2">Your Storylines</h6>
        <StorylineCard
          v-for="s in myStorylines"
          :key="s.id"
          :storyline="s"
        />
      </div>
      <div v-if="sharedStorylines.length" :class="{ 'mt-4': myStorylines.length }">
        <h6 class="text-muted mb-2">Shared with You</h6>
        <StorylineCard
          v-for="s in sharedStorylines"
          :key="s.id"
          :storyline="s"
        />
      </div>
    </template>
  </div>
</template>
```

### 2.5 CreateStorylineView.vue (NEW)

**Path:** `src/views/storyline/CreateStorylineView.vue`

```vue
<script setup lang="ts">
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { createStoryline } from '@/services/timelineApi'
import { getErrorMessage } from '@/utils/errorMessage'

const router = useRouter()
const name = ref('')
const description = ref('')
const submitting = ref(false)
const error = ref('')

async function handleSubmit() {
  if (submitting.value || !name.value.trim()) return
  submitting.value = true
  error.value = ''
  try {
    const { data } = await createStoryline({
      name: name.value.trim(),
      description: description.value.trim() || undefined,
    })
    router.push(`/storylines/${data.id}`)
  } catch (e: any) {
    error.value = getErrorMessage(e, 'Failed to create storyline.')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div>
    <h4 class="mb-3">New Storyline</h4>
    <form @submit.prevent="handleSubmit">
      <div v-if="error" class="alert alert-danger">{{ error }}</div>
      <div class="mb-3">
        <label class="form-label">Name</label>
        <input
          v-model="name"
          type="text"
          class="form-control"
          placeholder="e.g. Emma's First Year"
          required
          maxlength="200"
        />
      </div>
      <div class="mb-3">
        <label class="form-label">Description <span class="text-muted">(optional)</span></label>
        <textarea
          v-model="description"
          class="form-control"
          rows="3"
          placeholder="What is this storyline about?"
          maxlength="4000"
        ></textarea>
      </div>
      <div class="d-flex gap-2">
        <button type="submit" class="btn btn-primary" :disabled="submitting">
          {{ submitting ? 'Creating...' : 'Create Storyline' }}
        </button>
        <button type="button" class="btn btn-outline-secondary" @click="router.back()">
          Cancel
        </button>
      </div>
    </form>
  </div>
</template>
```

### 2.6 EditStorylineView.vue (NEW)

**Path:** `src/views/storyline/EditStorylineView.vue`

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getStoryline, updateStoryline, deleteStoryline } from '@/services/timelineApi'
import { getErrorMessage } from '@/utils/errorMessage'
import ConfirmModal from '@/components/ui/ConfirmModal.vue'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)

const name = ref('')
const description = ref('')
const loading = ref(true)
const submitting = ref(false)
const error = ref('')
const showDeleteConfirm = ref(false)
const isCreator = ref(false)

onMounted(async () => {
  try {
    const { data } = await getStoryline(id)
    name.value = data.name
    description.value = data.description || ''
    isCreator.value = data.creator
  } catch {
    error.value = 'Failed to load storyline.'
  } finally {
    loading.value = false
  }
})

async function handleSubmit() {
  if (submitting.value || !name.value.trim()) return
  submitting.value = true
  error.value = ''
  try {
    await updateStoryline(id, {
      name: name.value.trim(),
      description: description.value.trim() || undefined,
    })
    router.push(`/storylines/${id}`)
  } catch (e: any) {
    error.value = getErrorMessage(e, 'Failed to update storyline.')
  } finally {
    submitting.value = false
  }
}

async function handleDelete() {
  showDeleteConfirm.value = false
  try {
    await deleteStoryline(id)
    router.push('/storylines')
  } catch {
    error.value = 'Failed to remove storyline.'
  }
}
</script>

<template>
  <div>
    <h4 class="mb-3">Edit Storyline</h4>
    <LoadingSpinner v-if="loading" />
    <form v-else @submit.prevent="handleSubmit">
      <div v-if="error" class="alert alert-danger">{{ error }}</div>
      <div class="mb-3">
        <label class="form-label">Name</label>
        <input
          v-model="name"
          type="text"
          class="form-control"
          required
          maxlength="200"
        />
      </div>
      <div class="mb-3">
        <label class="form-label">Description <span class="text-muted">(optional)</span></label>
        <textarea
          v-model="description"
          class="form-control"
          rows="3"
          maxlength="4000"
        ></textarea>
      </div>
      <div class="d-flex gap-2">
        <button type="submit" class="btn btn-primary" :disabled="submitting">
          {{ submitting ? 'Saving...' : 'Save' }}
        </button>
        <button type="button" class="btn btn-outline-secondary" @click="router.back()">
          Cancel
        </button>
        <button type="button" class="btn btn-outline-danger ms-auto" @click="showDeleteConfirm = true">
          {{ isCreator ? 'Delete' : 'Unfollow' }}
        </button>
      </div>
    </form>
    <ConfirmModal
      v-if="showDeleteConfirm"
      :title="isCreator ? 'Delete Storyline' : 'Unfollow Storyline'"
      :message="isCreator
        ? 'This will remove the storyline from your list. Memories in the storyline will not be deleted.'
        : 'This will remove the storyline from your list. You can be re-invited later.'"
      :confirmLabel="isCreator ? 'Delete' : 'Unfollow'"
      @confirm="handleDelete"
      @cancel="showDeleteConfirm = false"
    />
  </div>
</template>
```

**Note:** The backend's `PUT /api/timelines/{id}` updates the `TimelineUser` record (user-specific name/description) for non-creators and the `Timeline` record for creators. The `TimelineService.MapFromTimeline` method prefers user-specific values when rendering, so customized names/descriptions show correctly per-user (PRD 5.2).

### 2.7 Router Updates (MODIFIED)

**Path:** `src/router/index.ts`

Add these routes to the authenticated section:

```typescript
{
  path: '/storylines',
  name: 'storylines',
  component: () => import('@/views/storyline/StorylineListView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/storylines/new',
  name: 'create-storyline',
  component: () => import('@/views/storyline/CreateStorylineView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/storylines/:id/edit',
  name: 'edit-storyline',
  component: () => import('@/views/storyline/EditStorylineView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/storylines/:id/invite',
  name: 'invite-storyline',
  component: () => import('@/views/storyline/InviteToStorylineView.vue'),
  meta: { auth: true, layout: 'app' },
},
{
  path: '/storylines/:id',
  name: 'storyline-detail',
  component: () => import('@/views/storyline/StorylineDetailView.vue'),
  meta: { auth: true, layout: 'app' },
},
```

**Note:** `/storylines/:id` must come after `/storylines/new` to avoid route matching conflicts.

### 2.8 Phase 2 Tests

#### timelineApi.test.ts
**Path:** `src/services/timelineApi.test.ts`

```typescript
// Mock api module (same pattern as memoryApi.test.ts)
// Test cases:
// 1. getStorylines sends GET /timelines
// 2. getStoryline sends GET /timelines/{id}
// 3. createStoryline sends POST /timelines with body
// 4. updateStoryline sends PUT /timelines/{id} with body
// 5. deleteStoryline sends DELETE /timelines/{id}
// 6. getStorylineDrops sends GET /drops/timelines/{id} with params
// 7. getStorylineDrops defaults ascending=true, skip=0
// 8. getStorylinesForDrop sends GET /timelines/drops/{dropId}
// 9. addDropToStoryline sends POST /timelines/drops/{dropId}/timelines/{timelineId}
// 10. removeDropFromStoryline sends DELETE /timelines/drops/{dropId}/timelines/{timelineId}
// 11. inviteToStoryline sends POST /timelines/{id}/invite with { ids }
```

#### StorylineListView.test.ts
**Path:** `src/views/storyline/StorylineListView.test.ts`

```typescript
// Mock timelineApi, vue-router
// Test cases:
// 1. shows loading spinner during fetch
// 2. renders storyline cards after fetch
// 3. separates "Your Storylines" and "Shared with You"
// 4. shows empty state when no storylines
// 5. shows error state on fetch failure
// 6. "Create" button links to /storylines/new
```

#### CreateStorylineView.test.ts
**Path:** `src/views/storyline/CreateStorylineView.test.ts`

```typescript
// Mock timelineApi, vue-router
// Test cases:
// 1. renders form with name and description fields
// 2. submits and navigates to detail view on success
// 3. shows error on submission failure
// 4. disables submit button while submitting
// 5. cancel navigates back
```

#### EditStorylineView.test.ts
**Path:** `src/views/storyline/EditStorylineView.test.ts`

```typescript
// Mock timelineApi, vue-router
// Test cases:
// 1. shows loading spinner then pre-populated form
// 2. submits update and navigates to detail view
// 3. shows error on update failure
// 4. shows delete button for creator
// 5. shows unfollow button for non-creator
// 6. opens confirm modal on delete click
// 7. calls deleteStoryline and navigates on confirm
// 8. cancel navigates back
```

#### StorylineCard.test.ts
**Path:** `src/components/storyline/StorylineCard.test.ts`

```typescript
// Test cases:
// 1. renders storyline name
// 2. renders description when present
// 3. shows "Shared" badge when not creator
// 4. hides "Shared" badge when creator
// 5. links to correct detail route
```

---

## Phase 3: Storyline Detail & Memory Association

### 3.1 Storyline Store (NEW)

**Path:** `src/stores/storyline.ts`

```typescript
import { ref } from 'vue'
import { defineStore } from 'pinia'
import { getStorylineDrops } from '@/services/timelineApi'
import type { Drop } from '@/types'

export const useStorylineStore = defineStore('storyline', () => {
  const memories = ref<Drop[]>([])
  const skip = ref(0)
  const hasMore = ref(true)
  const loading = ref(false)
  const timelineId = ref<number | null>(null)
  const ascending = ref(true)

  async function fetchPage(id: number) {
    if (loading.value || !hasMore.value) return
    if (timelineId.value !== id) reset()
    timelineId.value = id
    loading.value = true
    try {
      const { data } = await getStorylineDrops(id, skip.value, ascending.value)
      memories.value.push(...data.drops)
      skip.value = data.skip
      hasMore.value = !data.done
    } finally {
      loading.value = false
    }
  }

  function toggleSort() {
    ascending.value = !ascending.value
    memories.value = []
    skip.value = 0
    hasMore.value = true
  }

  function reset() {
    memories.value = []
    skip.value = 0
    hasMore.value = true
    loading.value = false
    timelineId.value = null
    ascending.value = true
  }

  return { memories, skip, hasMore, loading, timelineId, ascending, fetchPage, toggleSort, reset }
})
```

**Pattern:** Mirrors `useStreamStore` with additions: `timelineId` to track which storyline is loaded, `ascending` for sort direction, `toggleSort` that resets pagination and flips direction.

### 3.2 StorylineDetailView.vue (NEW)

**Path:** `src/views/storyline/StorylineDetailView.vue`

```vue
<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getStoryline } from '@/services/timelineApi'
import { useStorylineStore } from '@/stores/storyline'
import type { Storyline } from '@/types'
import MemoryCard from '@/components/memory/MemoryCard.vue'
import AddExistingMemoryModal from '@/components/storyline/AddExistingMemoryModal.vue'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'
import EmptyState from '@/components/ui/EmptyState.vue'
import ErrorState from '@/components/ui/ErrorState.vue'

const route = useRoute()
const router = useRouter()
const store = useStorylineStore()
const id = Number(route.params.id)

const storyline = ref<Storyline | null>(null)
const error = ref(false)
const sentinel = ref<HTMLElement>()
const showAddExisting = ref(false)

let observer: IntersectionObserver | null = null

onMounted(async () => {
  store.reset()
  try {
    const { data } = await getStoryline(id)
    storyline.value = data
    await store.fetchPage(id)
  } catch {
    error.value = true
  }

  observer = new IntersectionObserver(
    (entries) => {
      if (entries[0]?.isIntersecting && store.hasMore && !store.loading) {
        store.fetchPage(id)
      }
    },
    { threshold: 0.1 },
  )
  if (sentinel.value) observer.observe(sentinel.value)
})

onUnmounted(() => {
  observer?.disconnect()
})

async function handleToggleSort() {
  store.toggleSort()
  await store.fetchPage(id)
}
</script>

<template>
  <div>
    <ErrorState v-if="error" @retry="router.go(0)" />
    <template v-else-if="storyline">
      <div class="d-flex justify-content-between align-items-start mb-3">
        <div>
          <h4 class="mb-1">{{ storyline.name }}</h4>
          <p v-if="storyline.description" class="text-muted mb-0">{{ storyline.description }}</p>
        </div>
        <div class="d-flex gap-1">
          <RouterLink
            v-if="storyline.creator"
            :to="`/storylines/${id}/invite`"
            class="btn btn-sm btn-outline-primary"
            aria-label="Invite people"
          >
            <span class="mdi mdi-account-plus-outline"></span>
          </RouterLink>
          <RouterLink
            :to="`/storylines/${id}/edit`"
            class="btn btn-sm btn-outline-secondary"
            aria-label="Edit storyline"
          >
            <span class="mdi mdi-pencil-outline"></span>
          </RouterLink>
        </div>
      </div>

      <!-- Action bar: Add Memory + Sort Toggle -->
      <div class="d-flex justify-content-between align-items-center mb-3">
        <div class="dropdown">
          <button
            class="btn btn-sm btn-primary dropdown-toggle"
            data-bs-toggle="dropdown"
          >
            <span class="mdi mdi-plus me-1"></span>Add Memory
          </button>
          <ul class="dropdown-menu">
            <li>
              <RouterLink
                :to="`/memory/new?storylineId=${id}`"
                class="dropdown-item"
              >
                <span class="mdi mdi-pencil-plus-outline me-2"></span>Create New Memory
              </RouterLink>
            </li>
            <li>
              <button class="dropdown-item" @click="showAddExisting = true">
                <span class="mdi mdi-book-plus-outline me-2"></span>Add Existing Memory
              </button>
            </li>
          </ul>
        </div>
        <button
          class="btn btn-sm btn-outline-secondary"
          @click="handleToggleSort"
        >
          <span
            class="mdi me-1"
            :class="store.ascending ? 'mdi-sort-calendar-ascending' : 'mdi-sort-calendar-descending'"
          ></span>
          {{ store.ascending ? 'Oldest First' : 'Newest First' }}
        </button>
      </div>

      <EmptyState
        v-if="!store.loading && store.memories.length === 0"
        icon="mdi-book-open-page-variant-outline"
        message="This storyline has no memories yet."
        actionLabel="Create Memory"
        @action="router.push(`/memory/new?storylineId=${id}`)"
      />
      <MemoryCard
        v-for="memory in store.memories"
        :key="memory.dropId"
        :memory="memory"
      />
      <div ref="sentinel" style="height: 1px"></div>
      <LoadingSpinner v-if="store.loading" />
    </template>
    <LoadingSpinner v-else />

    <!-- Add Existing Memory picker (reuses StorylinePicker pattern in reverse) -->
    <AddExistingMemoryModal
      v-if="showAddExisting"
      :storylineId="id"
      @close="showAddExisting = false"
      @added="store.reset(); store.fetchPage(id)"
    />
  </div>
</template>
```

**Key decisions:**
- Reuses `MemoryCard` component for consistent memory display
- Same infinite scroll pattern as StreamView (IntersectionObserver + sentinel)
- Edit and Invite buttons in header (invite only for creators)
- "Add Memory" dropdown with two options: Create New and Add Existing (PRD 4.2)
- Sort toggle button switches between oldest-first and newest-first (PRD 3.1)
- Empty state CTA links to create memory with `?storylineId` query param
- Default sort is ascending (oldest first) via store default
- `aria-label` on icon-only buttons for accessibility

### 3.3 StorylinePicker.vue (NEW)

**Path:** `src/components/storyline/StorylinePicker.vue`

Modal component showing user's storylines with checkboxes to add/remove a memory.

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import {
  getStorylinesForDrop,
  addDropToStoryline,
  removeDropFromStoryline,
} from '@/services/timelineApi'
import type { Storyline } from '@/types'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'

const props = defineProps<{
  dropId: number
}>()

const emit = defineEmits<{
  close: []
}>()

const storylines = ref<Storyline[]>([])
const loading = ref(true)
const toggling = ref<number | null>(null)

onMounted(async () => {
  try {
    const { data } = await getStorylinesForDrop(props.dropId)
    storylines.value = data
  } finally {
    loading.value = false
  }
})

async function toggle(storyline: Storyline) {
  if (toggling.value !== null) return
  toggling.value = storyline.id
  const previousState = storyline.selected
  // Optimistically update UI
  storyline.selected = !storyline.selected
  try {
    if (previousState) {
      await removeDropFromStoryline(props.dropId, storyline.id)
    } else {
      await addDropToStoryline(props.dropId, storyline.id)
    }
  } catch {
    // Revert on failure
    storyline.selected = previousState
  } finally {
    toggling.value = null
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-backdrop fade show"></div>
    <div class="modal fade show d-block" tabindex="-1" @click.self="emit('close')">
      <div class="modal-dialog modal-dialog-centered">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Add to Storyline</h5>
            <button type="button" class="btn-close" @click="emit('close')"></button>
          </div>
          <div class="modal-body">
            <LoadingSpinner v-if="loading" />
            <div v-else-if="storylines.length === 0" class="text-center text-muted py-3">
              <p class="mb-2">No storylines yet.</p>
              <RouterLink to="/storylines/new" class="btn btn-sm btn-primary" @click="emit('close')">
                Create Storyline
              </RouterLink>
            </div>
            <div v-else class="list-group list-group-flush">
              <button
                v-for="s in storylines"
                :key="s.id"
                class="list-group-item list-group-item-action d-flex align-items-center gap-2"
                :disabled="toggling === s.id"
                @click="toggle(s)"
              >
                <span
                  class="mdi"
                  :class="s.selected ? 'mdi-checkbox-marked text-primary' : 'mdi-checkbox-blank-outline text-muted'"
                  style="font-size: 1.25rem"
                ></span>
                <span>{{ s.name }}</span>
                <span
                  v-if="toggling === s.id"
                  class="spinner-border spinner-border-sm ms-auto"
                ></span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
```

**Key decisions:**
- Uses same modal pattern as `ConfirmModal.vue` (Teleport to body, Bootstrap modal classes)
- `getStorylinesForDrop` returns all user's storylines with `selected` flag indicating which already contain this drop
- Toggle saves immediately (no save button) — matches PRD requirement
- Loading spinner per-item while toggling prevents double-clicks
- Empty state offers link to create a storyline

### 3.4 AddExistingMemoryModal.vue (NEW)

**Path:** `src/components/storyline/AddExistingMemoryModal.vue`

Modal that lets the user browse their recent memories and add them to a storyline.

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getDrops } from '@/services/memoryApi'
import { addDropToStoryline } from '@/services/timelineApi'
import type { Drop } from '@/types'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'

const props = defineProps<{
  storylineId: number
}>()

const emit = defineEmits<{
  close: []
  added: []
}>()

const memories = ref<Drop[]>([])
const loading = ref(true)
const adding = ref<number | null>(null)
const hasMore = ref(true)
const skip = ref(0)
const error = ref('')

onMounted(async () => {
  await fetchPage()
})

async function fetchPage() {
  loading.value = true
  try {
    const { data } = await getDrops(skip.value)
    memories.value.push(...data.drops)
    skip.value = data.skip
    hasMore.value = !data.done
  } finally {
    loading.value = false
  }
}

async function addMemory(dropId: number) {
  if (adding.value !== null) return
  adding.value = dropId
  error.value = ''
  try {
    await addDropToStoryline(dropId, props.storylineId)
    emit('added')
    // Remove from list to indicate it was added
    memories.value = memories.value.filter((m) => m.dropId !== dropId)
  } catch {
    error.value = 'Failed to add memory.'
  } finally {
    adding.value = null
  }
}
</script>

<template>
  <Teleport to="body">
    <div class="modal-backdrop fade show"></div>
    <div class="modal fade show d-block" tabindex="-1" @click.self="emit('close')">
      <div class="modal-dialog modal-dialog-centered modal-dialog-scrollable">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Add Existing Memory</h5>
            <button type="button" class="btn-close" @click="emit('close')"></button>
          </div>
          <div class="modal-body">
            <div v-if="error" class="alert alert-danger alert-sm mb-2">{{ error }}</div>
            <div
              v-for="memory in memories"
              :key="memory.dropId"
              class="d-flex align-items-start gap-2 py-2 border-bottom"
            >
              <div class="flex-grow-1">
                <p class="mb-0 small">{{ memory.content?.stuff }}</p>
                <small class="text-muted">{{ new Date(memory.date).toLocaleDateString() }}</small>
              </div>
              <button
                class="btn btn-sm btn-outline-primary flex-shrink-0"
                :disabled="adding === memory.dropId"
                @click="addMemory(memory.dropId)"
              >
                <span
                  v-if="adding === memory.dropId"
                  class="spinner-border spinner-border-sm"
                ></span>
                <span v-else class="mdi mdi-plus"></span>
              </button>
            </div>
            <LoadingSpinner v-if="loading" />
            <button
              v-if="!loading && hasMore"
              class="btn btn-sm btn-outline-secondary w-100 mt-2"
              @click="fetchPage"
            >
              Load More
            </button>
            <p v-if="!loading && memories.length === 0" class="text-center text-muted py-3 mb-0">
              No memories to add.
            </p>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
```

**Key decisions:**
- Uses `modal-dialog-scrollable` for scrolling within the modal body
- Reuses existing `getDrops` API with pagination (same as main stream)
- "+" button per memory — adds to storyline, then removes from the list
- "Load More" button for pagination (simpler than infinite scroll inside a modal)
- Emits `added` so parent can refresh the storyline feed

### 3.5 MemoryDetailView.vue — Show Storylines (MODIFIED)

**Path:** `src/views/memory/MemoryDetailView.vue`

Add storyline display to show which storylines a memory belongs to (PRD user story 10).

Add to `<script setup>`:

```typescript
import { getStorylinesForDrop } from '@/services/timelineApi'
import type { Storyline } from '@/types'

const storylines = ref<Storyline[]>([])

// Inside existing onMounted, after getDrop succeeds:
try {
  const { data } = await getStorylinesForDrop(dropId)
  storylines.value = data.filter((s) => s.selected)
} catch {
  // storylines are optional display — fail silently
}
```

Add to template (after the content/photos section, before CommentList):

```html
<div v-if="storylines.length" class="mb-3">
  <small class="text-muted d-block mb-1">Storylines</small>
  <div class="d-flex flex-wrap gap-1">
    <RouterLink
      v-for="s in storylines"
      :key="s.id"
      :to="`/storylines/${s.id}`"
      class="badge bg-light text-dark text-decoration-none"
    >
      <span class="mdi mdi-book-outline me-1"></span>{{ s.name }}
    </RouterLink>
  </div>
</div>
```

**Key decisions:**
- Fetches storylines in parallel with drop data (non-blocking, fails silently)
- Filters to only `selected` storylines (ones this drop actually belongs to)
- Renders as clickable badges linking to each storyline's detail page
- Uses `bg-light text-dark` badge style consistent with StorylineCard "Shared" badge

### 3.6 MemoryCard.vue — Add "Add to Storyline" Menu Item (MODIFIED)

Add to the dropdown menu (after "Share Link", before "Edit"):

```html
<button class="dropdown-item" @click="openStorylinePicker">
  <span class="mdi mdi-book-plus-outline me-2"></span>Add to Storyline
</button>
```

Add state and handler in `<script setup>`:

```typescript
const showStorylinePicker = ref(false)

function openStorylinePicker() {
  menuOpen.value = false
  showStorylinePicker.value = true
}
```

Add component at end of template (after ConfirmModal):

```html
<StorylinePicker
  v-if="showStorylinePicker"
  :dropId="memory.dropId"
  @close="showStorylinePicker = false"
/>
```

Add import:

```typescript
import StorylinePicker from '@/components/storyline/StorylinePicker.vue'
```

### 3.7 CreateMemoryView.vue — Add Storyline Field (MODIFIED)

Add storyline selection to the create memory form.

Add to `<script setup>`:

```typescript
import { getStorylines } from '@/services/timelineApi'
import type { Storyline } from '@/types'

const route = useRoute()
const storylines = ref<Storyline[]>([])
const selectedStorylineIds = ref<number[]>([])

// Pre-select storyline if navigated from storyline detail
onMounted(async () => {
  // ... existing groups fetch ...
  try {
    const { data } = await getStorylines()
    storylines.value = data
  } catch {
    // storylines are optional
  }
  const storylineId = Number(route.query.storylineId)
  if (storylineId) {
    selectedStorylineIds.value = [storylineId]
  }
})
```

Add to form template (after group selector, before buttons):

```html
<div v-if="storylines.length" class="mb-3">
  <label class="form-label">Storylines <span class="text-muted">(optional)</span></label>
  <div class="list-group">
    <button
      v-for="s in storylines"
      :key="s.id"
      type="button"
      class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-2"
      @click="toggleStoryline(s.id)"
    >
      <span
        class="mdi"
        :class="selectedStorylineIds.includes(s.id)
          ? 'mdi-checkbox-marked text-primary'
          : 'mdi-checkbox-blank-outline text-muted'"
      ></span>
      <span>{{ s.name }}</span>
    </button>
  </div>
</div>
```

Add toggle helper:

```typescript
function toggleStoryline(id: number) {
  const idx = selectedStorylineIds.value.indexOf(id)
  if (idx === -1) {
    selectedStorylineIds.value.push(id)
  } else {
    selectedStorylineIds.value.splice(idx, 1)
  }
}
```

Pass `timelineIds` in the createDrop call:

```typescript
const { data: created } = await createDrop({
  information: text.value.trim(),
  date: date.value,
  dateType: 0,
  tagIds: groupId.value ? [groupId.value] : undefined,
  timelineIds: selectedStorylineIds.value.length ? selectedStorylineIds.value : undefined,
})
```

**Note:** The `createDrop` function in `memoryApi.ts` already accepts `timelineIds?: number[]` — no API service change needed.

### 3.8 EditMemoryView.vue — Add Storyline Field (MODIFIED)

Same pattern as CreateMemoryView. On mount, also fetch storylines for this drop to pre-select:

```typescript
const { data: dropStorylines } = await getStorylinesForDrop(dropId)
storylines.value = dropStorylines
selectedStorylineIds.value = dropStorylines.filter(s => s.selected).map(s => s.id)
```

Pass `timelineIds` in the `updateDrop` call.

### 3.9 Phase 3 Tests

#### storyline.test.ts (store)
**Path:** `src/stores/storyline.test.ts`

```typescript
// Mock timelineApi
// Test cases:
// 1. fetchPage fetches first page and stores memories
// 2. fetchPage appends on subsequent calls
// 3. fetchPage sets hasMore=false when done
// 4. fetchPage skips when already loading
// 5. reset clears all state
// 6. fetchPage resets when timelineId changes
// 7. toggleSort flips ascending and resets pagination
// 8. fetchPage uses ascending value when calling API
```

#### StorylineDetailView.test.ts
**Path:** `src/views/storyline/StorylineDetailView.test.ts`

```typescript
// Mock timelineApi, stores, vue-router, IntersectionObserver
// Test cases:
// 1. renders storyline name and description
// 2. renders memory cards from store
// 3. shows empty state when no memories
// 4. shows error state on fetch failure
// 5. shows edit button always
// 6. shows invite button only for creator
// 7. empty state CTA includes storylineId in query
```

#### StorylinePicker.test.ts
**Path:** `src/components/storyline/StorylinePicker.test.ts`

```typescript
// Mock timelineApi
// Test cases:
// 1. shows loading spinner then storyline list
// 2. renders checked state for selected storylines
// 3. calls addDropToStoryline on toggle on
// 4. calls removeDropFromStoryline on toggle off
// 5. shows empty state with create link when no storylines
// 6. emits close when backdrop clicked
// 7. emits close when X clicked
```

#### AddExistingMemoryModal.test.ts
**Path:** `src/components/storyline/AddExistingMemoryModal.test.ts`

```typescript
// Mock memoryApi, timelineApi
// Test cases:
// 1. shows loading spinner then memory list
// 2. adds memory to storyline on "+" click
// 3. removes added memory from list after success
// 4. shows error on add failure
// 5. loads more memories on "Load More" click
// 6. shows empty state when no memories
// 7. emits close when backdrop clicked
```

#### MemoryCard storyline integration
**Path:** `src/components/memory/MemoryCard.test.ts` (add to existing)

```typescript
// Additional test cases:
// 1. menu shows "Add to Storyline" option
// 2. clicking "Add to Storyline" opens StorylinePicker
```

---

## Phase 4: Collaboration

### 4.1 InviteToStorylineView.vue (NEW)

**Path:** `src/views/storyline/InviteToStorylineView.vue`

```vue
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { getStoryline, inviteToStoryline, getStorylineInvited } from '@/services/timelineApi'
import { getConnections, type Connection } from '@/services/connectionApi'
import { getErrorMessage } from '@/utils/errorMessage'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'
import ErrorState from '@/components/ui/ErrorState.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)

const storylineName = ref('')
const connections = ref<Connection[]>([])
const alreadyInvitedIds = ref<Set<number>>(new Set())
const selectedIds = ref<number[]>([])
const loading = ref(true)
const submitting = ref(false)
const error = ref('')

onMounted(async () => {
  try {
    const [storylineRes, connectionsRes, invitedRes] = await Promise.all([
      getStoryline(id),
      getConnections(),
      getStorylineInvited(id),
    ])
    storylineName.value = storylineRes.data.name
    connections.value = connectionsRes.data
    // Track already-invited user IDs so we can show them as disabled
    alreadyInvitedIds.value = new Set(invitedRes.data.map((u) => u.id))
  } catch {
    error.value = 'Failed to load data.'
  } finally {
    loading.value = false
  }
})

function toggleConnection(connId: number) {
  const idx = selectedIds.value.indexOf(connId)
  if (idx === -1) {
    selectedIds.value.push(connId)
  } else {
    selectedIds.value.splice(idx, 1)
  }
}

async function handleInvite() {
  if (submitting.value || selectedIds.value.length === 0) return
  submitting.value = true
  error.value = ''
  try {
    await inviteToStoryline(id, selectedIds.value)
    router.push(`/storylines/${id}`)
  } catch (e: any) {
    error.value = getErrorMessage(e, 'Failed to send invitations.')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div>
    <h4 class="mb-1">Invite to Storyline</h4>
    <p class="text-muted mb-3">{{ storylineName }}</p>

    <LoadingSpinner v-if="loading" />
    <ErrorState v-else-if="error && !connections.length" @retry="router.go(0)" />
    <template v-else>
      <div v-if="error" class="alert alert-danger">{{ error }}</div>

      <div v-if="connections.length === 0" class="text-center text-muted py-4">
        <p>No connections yet.</p>
        <RouterLink to="/invite" class="btn btn-sm btn-primary">Invite someone to fyli</RouterLink>
      </div>
      <template v-else>
        <p class="text-muted small mb-2">Select people to invite:</p>
        <div class="list-group mb-3">
          <button
            v-for="conn in connections"
            :key="conn.id"
            type="button"
            class="list-group-item list-group-item-action d-flex align-items-center gap-2"
            :disabled="alreadyInvitedIds.has(conn.id)"
            @click="toggleConnection(conn.id)"
          >
            <span
              class="mdi"
              :class="alreadyInvitedIds.has(conn.id)
                ? 'mdi-checkbox-marked text-muted'
                : selectedIds.includes(conn.id)
                  ? 'mdi-checkbox-marked text-primary'
                  : 'mdi-checkbox-blank-outline text-muted'"
              style="font-size: 1.25rem"
            ></span>
            <span>{{ conn.name }}</span>
            <span v-if="alreadyInvitedIds.has(conn.id)" class="ms-auto small text-muted">
              Already invited
            </span>
          </button>
        </div>
        <div class="d-flex gap-2">
          <button
            class="btn btn-primary"
            :disabled="submitting || selectedIds.length === 0"
            @click="handleInvite"
          >
            {{ submitting ? 'Inviting...' : `Invite (${selectedIds.length})` }}
          </button>
          <button class="btn btn-outline-secondary" @click="router.back()">Cancel</button>
        </div>
      </template>
    </template>
  </div>
</template>
```

**Key decisions:**
- Fetches storyline info, connections, and already-invited users in parallel
- Already-invited connections shown as disabled with "Already invited" label
- Checkbox list with immediate visual feedback
- Submit button shows count of selected connections
- Empty connections state links to the existing invite page
- After inviting, navigates back to storyline detail

### 4.2 Phase 4 Tests

#### InviteToStorylineView.test.ts
**Path:** `src/views/storyline/InviteToStorylineView.test.ts`

```typescript
// Mock timelineApi, connectionApi, vue-router
// Test cases:
// 1. renders storyline name
// 2. renders connection list with checkboxes
// 3. toggles selection on click
// 4. calls inviteToStoryline with selected IDs
// 5. navigates to detail on success
// 6. shows error on failure
// 7. shows empty state when no connections
// 8. disables invite button when none selected
// 9. shows already-invited users as disabled with label
// 10. already-invited users cannot be toggled
```

#### connectionApi.test.ts (update existing or create)
**Path:** `src/services/connectionApi.test.ts`

```typescript
// Test cases:
// 1. getConnections sends GET /connections
// 2. sendInvitation sends POST /connections with email
// 3. confirmConnection sends POST /connections/confirm with name
```

---

## Implementation Order

| Order | Phase | Deliverable | Depends On |
|-------|-------|-------------|------------|
| 1 | Phase 1 | AppDrawer, FAB, AppNav changes, AppLayout changes, remove AppBottomNav | — |
| 2 | Phase 1 | Phase 1 tests | Phase 1 code |
| 3 | Phase 2 | timelineApi.ts, types, connectionApi update | — |
| 4 | Phase 2 | StorylineCard, StorylineListView, Create/Edit views, routes | Phase 2 services |
| 5 | Phase 2 | Phase 2 tests | Phase 2 code |
| 6 | Phase 3 | Storyline store, StorylineDetailView, StorylinePicker | Phase 2 |
| 7 | Phase 3 | MemoryCard/CreateMemory/EditMemory modifications | Phase 3 views |
| 8 | Phase 3 | Phase 3 tests | Phase 3 code |
| 9 | Phase 4 | InviteToStorylineView, connectionApi | Phase 3 |
| 10 | Phase 4 | Phase 4 tests | Phase 4 code |

---

## Test Fixtures

Add to `src/test/fixtures.ts`:

```typescript
import type { Storyline } from '@/types'

export function createStoryline(overrides: Partial<Storyline> = {}): Storyline {
  return {
    id: 1,
    name: 'Test Storyline',
    description: 'A test storyline description',
    active: true,
    following: true,
    creator: true,
    selected: false,
    ...overrides,
  }
}
```

This fixture should be used across all storyline-related tests for consistency.

---

## Test Summary

| Category | Test File | Count |
|----------|-----------|-------|
| **Phase 1** | AppDrawer.test.ts | 9 |
| | FloatingActionButton.test.ts | 3 |
| | AppNav.test.ts | 4 |
| | AppLayout.test.ts | 5 |
| **Phase 2** | timelineApi.test.ts | 11 |
| | StorylineListView.test.ts | 6 |
| | CreateStorylineView.test.ts | 5 |
| | EditStorylineView.test.ts | 8 |
| | StorylineCard.test.ts | 5 |
| **Phase 3** | storyline.test.ts (store) | 8 |
| | StorylineDetailView.test.ts | 7 |
| | StorylinePicker.test.ts | 7 |
| | AddExistingMemoryModal.test.ts | 7 |
| | MemoryCard.test.ts (additions) | 2 |
| **Phase 4** | InviteToStorylineView.test.ts | 10 |
| | connectionApi.test.ts | 3 |
| **Total** | | **105** |

---

*Document Version: 1.0*
*Created: 2026-02-09*
*Status: Draft*
