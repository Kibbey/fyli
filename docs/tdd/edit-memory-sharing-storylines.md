# TDD: Edit Memory — Sharing & Storyline Editing

## Overview

Extend the Edit Memory flow to support two features:
1. **Sharing editing** — Let users change who can see a memory (Everyone / Specific People / Only Me), reusing the same UI pattern from Create Memory's Step 2
2. **Fix storyline editing** — The current storyline selection in Edit Memory is broken (backend ignores `timelineIds` in `PUT /api/drops/{id}`). Switch to using the individual add/remove timeline API calls that already work.

### Current State

- `EditMemoryView.vue` supports editing text, date, media, and has a storyline checkbox list
- **Sharing**: No UI exists to change who sees the memory after creation. The backend `DropsService.Edit()` already handles `tagIds` (adds/removes `TagDrop` records), and the `UpdateDropModel` already accepts `TagIds` — but the frontend never sends them
- **Storylines**: The frontend sends `timelineIds` in the PUT body, but `DropController.UpdateDrop()` never passes them to any service — storyline changes are silently lost
- `CreateMemoryView.vue` has a fully working two-step wizard with sharing UI (Everyone / Specific people / Only me)

### Target State

- Edit Memory becomes a two-step flow matching Create Memory: **Step 1: Edit** → **Step 2: Share**
- Step 2 pre-populates the current sharing state from the drop's existing tags
- Storyline changes use individual `addDropToStoryline()` / `removeDropFromStoryline()` API calls (same as `StorylinePicker.vue`)
- `tagIds` are sent in the `updateDrop()` PUT request (backend already supports this)

---

## Key Discovery: What Already Works

| Concern | Backend Status | Frontend Status |
|---------|---------------|-----------------|
| Tag/sharing update via `PUT /api/drops/{id}` | Works — `DropsService.Edit()` diffs TagDrops | Not wired up — no sharing UI |
| `GET /api/connections/sharing-recipients` | Works — returns recipients with `userTagId` | Used in CreateMemoryView only |
| `GET /api/groups` | Works — returns "All Connections" group | Used in CreateMemoryView only |
| `GET /api/drops/{id}` → `drop.tags` | Works — returns current tag names/IDs | Available but not used for sharing |
| `POST /api/timelines/drops/{dropId}/timelines/{timelineId}` | Works | Used in StorylinePicker |
| `DELETE /api/timelines/drops/{dropId}/timelines/{timelineId}` | Works | Used in StorylinePicker |
| `GET /api/timelines/drops/{dropId}` | Works — returns storylines with `selected` flag | Already used in EditMemoryView |
| `PUT /api/drops/{id}` with `timelineIds` | **BROKEN** — controller ignores field | Frontend sends it but it's a no-op |

**No backend changes are required.** All needed APIs exist and work correctly.

---

## Phase 1: Refactor EditMemoryView to Two-Step Flow

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.vue`

### 1.1 Step Indicator

Add the same step indicator used in CreateMemoryView:

```html
<div class="d-flex align-items-center mb-3 gap-2">
    <span class="badge" :class="step === 0 ? 'bg-primary' : 'bg-secondary'">1</span>
    <span :class="step === 0 ? 'fw-semibold' : 'text-muted'">Edit</span>
    <span class="mdi mdi-chevron-right text-muted"></span>
    <span class="badge" :class="step === 1 ? 'bg-primary' : 'bg-secondary'">2</span>
    <span :class="step === 1 ? 'fw-semibold' : 'text-muted'">Share</span>
</div>
```

### 1.2 Step 1: Edit Form

Keep all existing form fields (text, date, photos, videos, new files, storylines). Changes:

- Replace `<form @submit.prevent="handleSubmit">` with `<form @submit.prevent="goToStep2">`
- Replace "Save Changes" button with "Next" button (disabled while loading sharing data)
- Wrap form content in `<div v-show="step === 0">`

### 1.3 Step 2: Share Selection

Add the same sharing UI from CreateMemoryView (Everyone / Specific People / Only Me), wrapped in `<div v-show="step === 1">`.

**Pre-population logic** — Determine current sharing mode from `drop.tags`:

```typescript
function determineCurrentShareMode(
    dropTags: DropTag[],
    allConnectionsTagId: number | null,
    recipients: SharingRecipient[]
): { mode: ShareMode; selectedUserIds: Set<number> } {
    if (dropTags.length === 0) {
        return { mode: "only-me", selectedUserIds: new Set() }
    }

    const dropTagIds = new Set(dropTags.map(t => t.tagId))

    // If "All Connections" is the only tag or is present
    if (allConnectionsTagId && dropTagIds.has(allConnectionsTagId)) {
        return { mode: "everyone", selectedUserIds: new Set() }
    }

    // Otherwise, it's specific people — match tag IDs to recipients
    const selected = new Set<number>()
    for (const r of recipients) {
        if (dropTagIds.has(r.userTagId)) {
            selected.add(r.userId)
        }
    }
    return { mode: "specific", selectedUserIds: selected }
}
```

### 1.4 New State Variables

```typescript
// Step management
const step = ref(0)

// Sharing state (Step 2)
type ShareMode = "everyone" | "specific" | "only-me"
const shareMode = ref<ShareMode>("everyone")
const allConnectionsTagId = ref<number | null>(null)
const recipients = ref<SharingRecipient[]>([])
const selectedUserIds = ref<Set<number>>(new Set())
const recipientsLoaded = ref(false)
const loadingSharing = ref(false)

// Preserve original drop tags for pre-population
const originalDropTags = ref<DropTag[]>([])
```

### 1.5 New Imports

```typescript
import { getGroups } from "@/services/groupApi"
import { getSharingRecipients } from "@/services/connectionApi"
import { addDropToStoryline, removeDropFromStoryline } from "@/services/timelineApi"
import type { Storyline, SharingRecipient, DropTag } from "@/types"
```

### 1.6 Load Sharing Data (lazy, on first Step 2 entry)

```typescript
async function loadSharingData() {
    if (recipientsLoaded.value) return
    loadingSharing.value = true

    try {
        const [groupsRes, recipientsRes] = await Promise.all([
            getGroups(),
            getSharingRecipients(),
        ])

        const allConn = groupsRes.data.activeTags?.find(
            (g) => g.name === "All Connections"
        )
        if (allConn) {
            allConnectionsTagId.value = allConn.tagId
        }

        recipients.value = recipientsRes.data
        recipientsLoaded.value = true

        // Pre-populate sharing mode from drop's current tags
        const { mode, selectedUserIds: selected } = determineCurrentShareMode(
            originalDropTags.value,
            allConnectionsTagId.value,
            recipients.value
        )
        shareMode.value = mode
        selectedUserIds.value = selected
    } catch {
        // Non-critical — user can still save as "Only me"
    } finally {
        loadingSharing.value = false
    }
}
```

### 1.7 goToStep2 Function

```typescript
async function goToStep2() {
    if (!text.value.trim()) return
    error.value = ""

    await loadSharingData()

    // If no connections, skip Step 2 and save directly
    if (recipients.value.length === 0) {
        shareMode.value = "only-me"
        await handleSubmit()
        return
    }

    step.value = 1
}
```

### 1.8 Save originalDropTags in onMounted

In the existing `onMounted`, after loading the drop, store the tags:

```typescript
originalDropTags.value = data.tags ?? []
```

---

## Phase 2: Fix Storyline Editing

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.vue`

### Problem

The backend `DropController.UpdateDrop()` does not handle `timelineIds`:

```csharp
// Current backend — timelineIds is never used
public async Task<IActionResult> UpdateDrop(UpdateDropModel dropModel, int id)
{
    var isTask = await dropService.Edit(new Domain.Models.DropModel { ... },
        dropModel.TagIds, dropModel.Images, dropModel.Movies, CurrentUserId);
    // dropModel.TimelineIds is ignored!
}
```

### Solution

Use the individual timeline API calls that already work (same as `StorylinePicker.vue`):

```typescript
// Track original storyline selection for diffing
const originalStorylineIds = ref<number[]>([])

// In onMounted, after loading storylines:
originalStorylineIds.value = dropStorylines.filter(s => s.selected).map(s => s.id)
selectedStorylineIds.value = [...originalStorylineIds.value]
```

In `handleSubmit`, diff and make individual calls:

```typescript
// Compute storyline additions and removals
const addedStorylines = selectedStorylineIds.value.filter(
    id => !originalStorylineIds.value.includes(id)
)
const removedStorylines = originalStorylineIds.value.filter(
    id => !selectedStorylineIds.value.includes(id)
)

// Execute timeline changes via individual API calls
await Promise.all([
    ...addedStorylines.map(tid => addDropToStoryline(dropId, tid)),
    ...removedStorylines.map(tid => removeDropFromStoryline(dropId, tid)),
])
```

### Remove timelineIds from updateDrop call

Stop passing `timelineIds` in the PUT body (it was being ignored anyway):

```typescript
await updateDrop(dropId, {
    information: text.value.trim(),
    date: date.value,
    dateType: 0,
    tagIds: getTagIds(),  // NEW: pass sharing tags
    images: imageIdsToKeep,
    movies: movieIdsToKeep,
    // timelineIds removed — handled via separate API calls
})
```

---

## Phase 3: Wire Up tagIds in handleSubmit

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.vue`

### 3.1 getTagIds Function

Reuse the exact same logic from CreateMemoryView:

```typescript
function getTagIds(): number[] {
    if (shareMode.value === "everyone" && allConnectionsTagId.value) {
        return [allConnectionsTagId.value]
    }
    if (shareMode.value === "specific") {
        return recipients.value
            .filter((r) => selectedUserIds.value.has(r.userId))
            .map((r) => r.userTagId)
    }
    return [] // "only-me"
}
```

### 3.2 toggleRecipient Function

```typescript
function toggleRecipient(userId: number) {
    const next = new Set(selectedUserIds.value)
    if (next.has(userId)) {
        next.delete(userId)
    } else {
        next.add(userId)
    }
    selectedUserIds.value = next
}
```

### 3.3 Updated handleSubmit

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

        // Update drop with sharing tags
        await updateDrop(dropId, {
            information: text.value.trim(),
            date: date.value,
            dateType: 0,
            tagIds: getTagIds(),
            images: imageIdsToKeep,
            movies: movieIdsToKeep,
        })

        // Handle storyline changes via individual API calls
        const addedStorylines = selectedStorylineIds.value.filter(
            id => !originalStorylineIds.value.includes(id)
        )
        const removedStorylines = originalStorylineIds.value.filter(
            id => !selectedStorylineIds.value.includes(id)
        )
        if (addedStorylines.length > 0 || removedStorylines.length > 0) {
            await Promise.all([
                ...addedStorylines.map(tid => addDropToStoryline(dropId, tid)),
                ...removedStorylines.map(tid => removeDropFromStoryline(dropId, tid)),
            ])
        }

        // Upload new files
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

---

## Phase 4: Frontend Tests

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.test.ts`

### 4.1 Component Tests

```
describe("EditMemoryView")
  describe("Step 1 - Edit Form")
    it("renders the step indicator with Edit highlighted")
    it("shows Next button instead of Save Changes")
    it("advances to Step 2 when Next is clicked")
    it("does not advance if text is empty")

  describe("Step 2 - Share Selection")
    it("renders Everyone / Specific people / Only me options")
    it("pre-populates Everyone when drop has All Connections tag")
    it("pre-populates Specific people with correct users checked")
    it("pre-populates Only me when drop has no tags")
    it("shows Back button that returns to Step 1")
    it("disables Save when Specific people selected with no one checked")

  describe("Sharing Mode Determination")
    it("returns only-me when drop.tags is empty")
    it("returns everyone when All Connections tag is present")
    it("returns specific with matched user IDs when per-user tags present")

  describe("Storyline Editing")
    it("sends addDropToStoryline for newly selected storylines")
    it("sends removeDropFromStoryline for deselected storylines")
    it("does not make timeline API calls when no changes")
    it("does not pass timelineIds in updateDrop body")

  describe("Save Flow")
    it("calls updateDrop with tagIds from selected sharing mode")
    it("handles file uploads after updateDrop")
    it("navigates to memory detail on success")

  describe("Skip Step 2")
    it("saves directly as Only me when user has no connections")
```

### 4.2 Mock Setup

```typescript
vi.mock("@/services/memoryApi", () => ({
    getDrop: vi.fn(),
    updateDrop: vi.fn(),
}))
vi.mock("@/services/groupApi", () => ({
    getGroups: vi.fn(),
}))
vi.mock("@/services/connectionApi", () => ({
    getSharingRecipients: vi.fn(),
}))
vi.mock("@/services/timelineApi", () => ({
    getStorylinesForDrop: vi.fn(),
    addDropToStoryline: vi.fn(),
    removeDropFromStoryline: vi.fn(),
}))
```

---

## Summary of Changes

**Files Modified:**
- `fyli-fe-v2/src/views/memory/EditMemoryView.vue` — Two-step flow with sharing UI and fixed storyline editing

**Files Created:**
- `fyli-fe-v2/src/views/memory/EditMemoryView.test.ts` — Component tests

**No Backend Changes Required.** All APIs already exist:
- `PUT /api/drops/{id}` with `tagIds` — sharing changes (already wired in `DropsService.Edit`)
- `GET /api/connections/sharing-recipients` — recipient list with per-user group IDs
- `GET /api/groups` — "All Connections" group ID
- `POST /api/timelines/drops/{dropId}/timelines/{timelineId}` — add to storyline
- `DELETE /api/timelines/drops/{dropId}/timelines/{timelineId}` — remove from storyline

**No new API endpoints, no database changes, no migrations.**

---

## Implementation Order

1. **Phase 1** — Refactor EditMemoryView to two-step flow with sharing UI and pre-population
2. **Phase 2** — Fix storyline editing to use individual API calls
3. **Phase 3** — Wire up tagIds in handleSubmit
4. **Phase 4** — Frontend tests

Phases 1-3 are tightly coupled and should be implemented together as a single change to `EditMemoryView.vue`. Phase 4 follows.

---

## Data Flow Diagram

```
EditMemoryView.vue — onMounted
├─ GET /api/drops/{dropId}
│  └─ Populate: text, date, images, movies, originalDropTags
└─ GET /api/timelines/drops/{dropId}
   └─ Populate: storylines, originalStorylineIds, selectedStorylineIds

EditMemoryView.vue — goToStep2 (lazy load)
├─ GET /api/groups
│  └─ Find "All Connections" → allConnectionsTagId
├─ GET /api/connections/sharing-recipients
│  └─ Populate: recipients
└─ determineCurrentShareMode(originalDropTags, allConnectionsTagId, recipients)
   └─ Set: shareMode, selectedUserIds

EditMemoryView.vue — handleSubmit
├─ PUT /api/drops/{dropId}
│  body: { information, date, dateType, tagIds, images, movies }
│  └─ Backend DropsService.Edit() diffs TagDrops
├─ POST /api/timelines/drops/{dropId}/timelines/{tid} (for each added storyline)
├─ DELETE /api/timelines/drops/{dropId}/timelines/{tid} (for each removed storyline)
├─ POST /api/images or presigned URL upload (for each new file)
└─ GET /api/drops/{dropId}
   └─ Refresh stream store
```

---

## Backwards Compatibility

- **Existing memories unaffected** — tags and timeline associations are only modified when the user explicitly saves changes
- **No API contract changes** — `updateDrop()` already accepts `tagIds` in its interface; we're simply sending them now
- **No data model changes** — reuses existing `TagDrop`, `TimelineDrop`, `UserTag`, `TagViewer` tables
- **Edit flow for users with zero connections** — Step 2 is skipped entirely, same as Create Memory behavior
