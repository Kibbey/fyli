# Technical Design Document: Memory Sharing at Creation

**PRD:** `docs/prd/PRD_MEMORY_SHARING_AT_CREATION.md`
**Status:** Draft
**Created:** 2026-02-11

---

## Overview

Add a two-step memory creation wizard where Step 1 is the existing form (text, date, photos, storylines) and Step 2 lets users choose who to share with: Everyone (default), Specific People, or Only Me.

The backend models each connection as its own group (`UserTag` with one `TagViewer`). The frontend passes `userTagId` values as `tagIds` to the existing `createDrop` API — no changes to the drop creation contract.

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (fyli-fe-v2)                     │
│                                                             │
│  CreateMemoryView.vue (two-step wizard)                     │
│    Step 1: text, date, photos, storylines                   │
│    Step 2: sharing mode (Everyone / Specific / Only Me)     │
│                                                             │
│  Services:                                                  │
│    connectionApi.ts → GET /api/connections/sharing-recipients│
│    groupApi.ts      → GET /api/groups (All Connections only)│
│    memoryApi.ts     → POST /api/drops (unchanged)           │
├─────────────────────────────────────────────────────────────┤
│                    Backend (cimplur-core)                    │
│                                                             │
│  ConnectionController                                       │
│    └── GET sharing-recipients (new)                         │
│                                                             │
│  GroupController                                            │
│    └── GET groups (filtered to All Connections only)        │
│                                                             │
│  GroupService                                               │
│    ├── EnsurePerUserGroup() (new)                           │
│    ├── GetSharingRecipients() (new)                         │
│    └── AllGroups() (unchanged internally)                   │
│                                                             │
│  Existing tables (no schema changes):                       │
│    UserTag, TagViewer, TagDrop, UserUser                    │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Models/
│   │   └── SharingRecipientModel.cs          (new)
│   └── Repositories/
│       └── GroupService.cs                    (modified - 2 new methods)
├── Memento/
│   └── Controllers/
│       ├── ConnectionController.cs            (modified - 1 new endpoint)
│       └── GroupController.cs                 (modified - filter response)

fyli-fe-v2/src/
├── views/memory/
│   └── CreateMemoryView.vue                   (modified - two-step wizard)
├── services/
│   ├── connectionApi.ts                       (new file)
│   └── groupApi.ts                            (modified - fix return type)
├── types/
│   └── index.ts                               (modified - fix Group, add GroupsResponse, SharingRecipient)
```

---

## Phase 1: Backend Changes

### 1.1 New Model: SharingRecipientModel

**File:** `cimplur-core/Memento/Domain/Models/SharingRecipientModel.cs` (new)

```csharp
namespace Domain.Models
{
    public class SharingRecipientModel
    {
        public int UserId { get; set; }
        public long UserTagId { get; set; }
        public string DisplayName { get; set; }
        public string Email { get; set; }
    }
}
```

### 1.2 GroupService: New Methods

**File:** `cimplur-core/Memento/Domain/Repositories/GroupService.cs`

**Add two new methods:**

#### EnsurePerUserGroup

Creates a per-user `UserTag` named `__person:{targetUserId}` with a single `TagViewer` for that user. Idempotent — returns existing group if already created. Handles concurrent creation via unique constraint catch.

```csharp
public async Task<long> EnsurePerUserGroup(int ownerUserId, int targetUserId)
{
    var groupName = $"__person:{targetUserId}";
    var existing = await Context.UserNetworks
        .FirstOrDefaultAsync(x => x.UserId == ownerUserId && x.Name == groupName);

    if (existing != null)
    {
        return existing.UserTagId;
    }

    try
    {
        var userTag = new UserTag
        {
            Name = groupName,
            Created = DateTime.UtcNow,
            UserId = ownerUserId,
            Archived = false,
            IsTask = false
        };
        userTag.TagViewers.Add(new TagViewer { UserId = targetUserId });
        Context.UserNetworks.Add(userTag);
        await Context.SaveChangesAsync();
        return userTag.UserTagId;
    }
    catch (DbUpdateException)
    {
        // Concurrent insert hit unique constraint (UserId, Name) — re-query
        Context.ChangeTracker.Clear();
        var concurrentlyCreated = await Context.UserNetworks
            .FirstAsync(x => x.UserId == ownerUserId && x.Name == groupName);
        return concurrentlyCreated.UserTagId;
    }
}
```

**Key design decisions:**
- Single `SaveChangesAsync` — `UserTag` and `TagViewer` created atomically (no orphan risk)
- Race condition handled via `try/catch` on `DbUpdateException` — unique index `(UserId, Name)` prevents duplicates
- `ChangeTracker.Clear()` after exception to discard the failed entity before re-querying

#### GetSharingRecipients

Returns all connections with their per-user group IDs. Queries `UserUser` (connections) and `TimelineUser` (timeline invites that may not have a connection). Bulk-fetches existing per-user groups and creates missing ones.

```csharp
public async Task<List<SharingRecipientModel>> GetSharingRecipients(int userId)
{
    // 1. Get all active connections (covers invites + question recipients who registered)
    var connections = await Context.UserUsers
        .Include(uu => uu.ReaderUser)
        .Where(uu => uu.OwnerUserId == userId && !uu.Archive)
        .ToListAsync();

    // 2. Get timeline invitees who may not have a UserUser connection
    var timelineUserIds = await Context.TimelineUsers
        .Where(tu => tu.Timeline.UserId == userId
            && tu.UserId != userId
            && tu.Active)
        .Select(tu => tu.UserId)
        .Distinct()
        .ToListAsync();

    // 3. Merge and deduplicate
    var connectionUserIds = connections.Select(c => c.ReaderUserId).ToHashSet();
    var timelineOnlyUserIds = timelineUserIds
        .Where(id => !connectionUserIds.Contains(id)).ToList();

    // Load profiles for timeline-only users
    var timelineOnlyProfiles = timelineOnlyUserIds.Any()
        ? await Context.UserProfiles
            .Where(u => timelineOnlyUserIds.Contains(u.UserId))
            .ToListAsync()
        : new List<UserProfile>();

    // 4. Bulk-fetch existing __person:* groups for this user
    var existingGroups = await Context.UserNetworks
        .Where(x => x.UserId == userId && x.Name.StartsWith("__person:"))
        .ToDictionaryAsync(x => x.Name, x => x.UserTagId);

    // 5. Build recipient list, creating missing per-user groups
    var recipients = new List<SharingRecipientModel>();

    foreach (var conn in connections)
    {
        var groupName = $"__person:{conn.ReaderUserId}";
        if (!existingGroups.TryGetValue(groupName, out var userTagId))
        {
            userTagId = await EnsurePerUserGroup(userId, conn.ReaderUserId);
            existingGroups[groupName] = userTagId;
        }
        recipients.Add(new SharingRecipientModel
        {
            UserId = conn.ReaderUserId,
            UserTagId = userTagId,
            DisplayName = conn.ReaderName ?? conn.ReaderUser?.Name,
            Email = conn.ReaderUser?.Email
        });
    }

    foreach (var profile in timelineOnlyProfiles)
    {
        var groupName = $"__person:{profile.UserId}";
        if (!existingGroups.TryGetValue(groupName, out var userTagId))
        {
            userTagId = await EnsurePerUserGroup(userId, profile.UserId);
            existingGroups[groupName] = userTagId;
        }
        recipients.Add(new SharingRecipientModel
        {
            UserId = profile.UserId,
            UserTagId = userTagId,
            DisplayName = profile.Name,
            Email = profile.Email
        });
    }

    return recipients.OrderBy(r => r.DisplayName ?? r.Email).ToList();
}
```

**Data source coverage:**
- **Connection invites (accepted):** `UserUser` table — always creates bidirectional records
- **Question recipients (registered):** `UserUser` table — `QuestionService.LinkAnswersToUserAsync` calls `EnsureConnectionAsync`
- **Timeline invites (direct):** `TimelineUser` table — `InviteToTimeline` does NOT create `UserUser` records, so we query `TimelineUser` separately
- **Timeline share links:** `UserUser` table — `TimelineShareLinkService` calls `EnsureConnectionAsync`

**Performance:** Bulk-fetches existing `__person:*` groups in a single query. Only calls `EnsurePerUserGroup` (1 DB round-trip) for connections that don't have a group yet. After first call, subsequent calls are O(1) lookups from the dictionary.

### 1.3 GroupController: Filter to All Connections Only

**File:** `cimplur-core/Memento/Memento/Controllers/GroupController.cs`

**Modify the `Groups()` action** (line 30):

```csharp
// BEFORE:
[HttpGet]
[Route("")]
public async Task<IActionResult> Groups()
{
    return Ok(new TagsViewModel(
         await groupService.AllGroups(CurrentUserId)));
}

// AFTER:
[HttpGet]
[Route("")]
public async Task<IActionResult> Groups()
{
    var allGroups = await groupService.AllGroups(CurrentUserId);
    var filtered = allGroups.Where(g => g.Name == "All Connections").ToList();
    return Ok(new TagsViewModel(filtered));
}
```

This suppresses legacy groups and per-user `__person:*` groups from the API response. The `AllGroups` method still runs its internal logic (creating/populating "All Connections"), but only "All Connections" is returned to clients.

**Other group endpoints intentionally unchanged:**
- `GET /api/groups/editable` — used by old frontend for group management. Returns all groups except "All Connections." Not called anywhere in fyli-fe-v2. Left unchanged.
- `GET /api/groups/allSelected` — used by old frontend for drop creation. Not called in fyli-fe-v2. Left unchanged.
- `GET /api/groups/includeMembers` — used by old frontend for member management. Not called in fyli-fe-v2. Left unchanged.
- `GET /api/groups/viewers` — used internally. Left unchanged.

**Impact:** Only `CreateMemoryView.vue` calls `GET /api/groups` in fyli-fe-v2, and we're rewriting it. `DropsService` calls `AllNetworkModels()` directly (not through the API), so drop permissions are unaffected.

### 1.4 ConnectionController: New Endpoint

**File:** `cimplur-core/Memento/Memento/Controllers/ConnectionController.cs`

**Add new endpoint:**

```csharp
[HttpGet]
[Route("sharing-recipients")]
public async Task<IActionResult> SharingRecipients()
{
    var recipients = await groupService.GetSharingRecipients(CurrentUserId);
    return Ok(recipients);
}
```

**Verified:** `ConnectionController` already injects `GroupService` (field on line 17, constructor param on line 21). No DI changes needed.

### 1.5 API Contract

#### GET /api/connections/sharing-recipients

**Response:** `200 OK`

```json
[
  {
    "userId": 42,
    "userTagId": 17,
    "displayName": "Mom",
    "email": "mom@email.com"
  },
  {
    "userId": 55,
    "userTagId": 23,
    "displayName": null,
    "email": "dad@email.com"
  }
]
```

#### GET /api/groups (modified response)

Now returns only "All Connections" in `activeTags`. Legacy groups no longer appear.

```json
{
  "activeTags": [
    { "name": "All Connections", "tagId": 5, "canNotEdit": true }
  ],
  "archivedTags": []
}
```

#### POST /api/drops (unchanged)

Request body still accepts `tagIds: number[]`. The frontend passes:
- **Everyone:** `[allConnectionsTagId]`
- **Specific people:** `[userTagId1, userTagId2, ...]`
- **Only me:** `[]` (or omit `tagIds`)

---

## Phase 2: Frontend Changes

### 2.1 Type Updates

**File:** `fyli-fe-v2/src/types/index.ts`

Add `SharingRecipient` and fix `Group` to match the actual backend response:

```typescript
// Fix existing Group interface to match backend GroupModel (camelCase serialization)
export interface Group {
  tagId: number
  name: string
  canNotEdit: boolean
}

// Response shape from GET /api/groups (TagsViewModel)
export interface GroupsResponse {
  activeTags: Group[]
  archivedTags: Group[]
}

// New type for sharing recipients
export interface SharingRecipient {
  userId: number
  userTagId: number
  displayName: string | null
  email: string
}
```

**Note:** The existing `Group` interface has `id: number` and `name: string`, but the backend `GroupModel` serializes as `{ tagId, name, canNotEdit, ... }` via Newtonsoft.Json camelCase (configured in `Startup.cs` line 73: `AddNewtonsoftJson()`). The current `getGroups()` return type is `Group[]` but the actual response is `{ activeTags: [...], archivedTags: [...] }`. This is why the group dropdown in the current `CreateMemoryView.vue` never renders — `groups.length` is undefined on an object.

### 2.2 API Services

**File:** `fyli-fe-v2/src/services/connectionApi.ts` (new)

```typescript
import api from "./api"
import type { SharingRecipient } from "@/types"

export function getSharingRecipients() {
  return api.get<SharingRecipient[]>("/connections/sharing-recipients")
}
```

**File:** `fyli-fe-v2/src/services/groupApi.ts` (modified — fix return type)

```typescript
import api from "./api"
import type { GroupsResponse } from "@/types"

export function getGroups() {
  return api.get<GroupsResponse>("/groups")
}
```

### 2.3 Refactor CreateMemoryView.vue

**File:** `fyli-fe-v2/src/views/memory/CreateMemoryView.vue`

Replace the current single-form component with a two-step wizard. The full replacement:

```vue
<template>
  <div>
    <!-- Step Indicator -->
    <div class="d-flex align-items-center mb-3 gap-2">
      <span
        class="badge"
        :class="step === 0 ? 'bg-primary' : 'bg-secondary'"
      >1</span>
      <span :class="step === 0 ? 'fw-semibold' : 'text-muted'">Write</span>
      <span class="mdi mdi-chevron-right text-muted"></span>
      <span
        class="badge"
        :class="step === 1 ? 'bg-primary' : 'bg-secondary'"
      >2</span>
      <span :class="step === 1 ? 'fw-semibold' : 'text-muted'">Share</span>
    </div>

    <!-- Step 1: Create Memory (v-show preserves DOM state across step transitions) -->
    <div v-show="step === 0">
      <h4 class="mb-3">New Memory</h4>
      <p v-if="helperText" class="text-muted">{{ helperText }}</p>
      <form @submit.prevent="goToStep2">
        <div v-if="error" class="alert alert-danger">{{ error }}</div>
        <div v-if="fileError" class="alert alert-warning">{{ fileError }}</div>
        <div class="mb-3">
          <textarea
            v-model="text"
            class="form-control"
            rows="4"
            placeholder="What happened?"
            required
          ></textarea>
        </div>
        <div class="mb-3">
          <label class="form-label">Date</label>
          <input v-model="date" type="date" class="form-control" required />
        </div>
        <div class="mb-3">
          <label class="form-label">Photos & Videos</label>
          <input
            type="file"
            class="form-control"
            accept="image/*,video/*"
            multiple
            @change="onFileChange"
          />
          <div v-if="fileEntries.length" class="d-flex gap-2 mt-2 flex-wrap">
            <div
              v-for="entry in fileEntries"
              :key="entry.id"
              class="position-relative"
            >
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
                @click="removeFile(entry.id)"
              >&times;</button>
            </div>
          </div>
        </div>
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
        <div class="d-flex gap-2">
          <button type="submit" class="btn btn-primary" :disabled="!text.trim() || loadingSharing">
            <span v-if="loadingSharing" class="spinner-border spinner-border-sm me-1"></span>
            {{ loadingSharing ? "Loading..." : "Next" }}
          </button>
          <button type="button" class="btn btn-outline-secondary" @click="router.back()">
            Cancel
          </button>
        </div>
      </form>
    </div>

    <!-- Step 2: Share Selection (v-show preserves DOM state across step transitions) -->
    <div v-show="step === 1">
      <h4 class="mb-3">Share this memory</h4>
      <div v-if="error" class="alert alert-danger">{{ error }}</div>

      <!-- Sharing Mode Radio Options -->
      <div class="list-group mb-3">
        <button
          type="button"
          class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-3"
          :class="{ active: shareMode === 'everyone' }"
          @click="shareMode = 'everyone'"
        >
          <span class="mdi" :class="shareMode === 'everyone' ? 'mdi-radiobox-marked' : 'mdi-radiobox-blank'"></span>
          <div>
            <div class="fw-semibold">Everyone</div>
            <small class="text-muted" :class="{ 'text-white-50': shareMode === 'everyone' }">
              Sharing with all {{ recipients.length }} connections
            </small>
          </div>
        </button>

        <button
          type="button"
          class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-3"
          :class="{ active: shareMode === 'specific' }"
          @click="shareMode = 'specific'"
        >
          <span class="mdi" :class="shareMode === 'specific' ? 'mdi-radiobox-marked' : 'mdi-radiobox-blank'"></span>
          <div>
            <div class="fw-semibold">Specific people</div>
            <small class="text-muted" :class="{ 'text-white-50': shareMode === 'specific' }">
              Choose who sees this memory
            </small>
          </div>
        </button>

        <button
          type="button"
          class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-3"
          :class="{ active: shareMode === 'only-me' }"
          @click="shareMode = 'only-me'"
        >
          <span class="mdi" :class="shareMode === 'only-me' ? 'mdi-radiobox-marked' : 'mdi-radiobox-blank'"></span>
          <div>
            <div class="fw-semibold">Only me</div>
            <small class="text-muted" :class="{ 'text-white-50': shareMode === 'only-me' }">
              Keep this memory private
            </small>
          </div>
        </button>
      </div>

      <!-- People List (shown when "Specific people" selected) -->
      <div v-if="shareMode === 'specific'" class="mb-3">
        <div class="list-group" style="max-height: 300px; overflow-y: auto">
          <!-- Select All -->
          <button
            type="button"
            class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-2 fw-semibold"
            @click="toggleSelectAll"
          >
            <span
              class="mdi"
              :class="allSelected
                ? 'mdi-checkbox-marked text-primary'
                : someSelected
                  ? 'mdi-minus-box text-primary'
                  : 'mdi-checkbox-blank-outline text-muted'"
            ></span>
            <span>Select All</span>
          </button>

          <!-- Individual People -->
          <button
            v-for="r in recipients"
            :key="r.userId"
            type="button"
            class="list-group-item list-group-item-action d-flex align-items-center gap-2 py-2"
            @click="toggleRecipient(r.userId)"
          >
            <span
              class="mdi"
              :class="selectedUserIds.has(r.userId)
                ? 'mdi-checkbox-marked text-primary'
                : 'mdi-checkbox-blank-outline text-muted'"
            ></span>
            <span>{{ r.displayName || r.email }}</span>
          </button>
        </div>

        <div
          v-if="shareMode === 'specific' && selectedUserIds.size === 0"
          class="text-danger small mt-1"
        >
          Select at least one person, or choose "Only me"
        </div>
      </div>

      <div class="d-flex gap-2">
        <button
          type="button"
          class="btn btn-primary"
          :disabled="submitting || (shareMode === 'specific' && selectedUserIds.size === 0)"
          @click="handleSubmit"
        >
          {{ submitting ? "Saving..." : "Save Memory" }}
        </button>
        <button
          type="button"
          class="btn btn-outline-secondary"
          :disabled="submitting"
          @click="step = 0"
        >
          Back
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from "vue"
import { useRoute, useRouter } from "vue-router"
import { createDrop, getDrop } from "@/services/memoryApi"
import { getGroups } from "@/services/groupApi"
import { getSharingRecipients } from "@/services/connectionApi"
import { getStorylines } from "@/services/timelineApi"
import { useStreamStore } from "@/stores/stream"
import { useFileUpload, getTranscodeDelay } from "@/composables/useFileUpload"
import { getErrorMessage } from "@/utils/errorMessage"
import type { Storyline, SharingRecipient } from "@/types"

defineProps<{
  helperText?: string
}>()

const route = useRoute()
const router = useRouter()
const stream = useStreamStore()

const {
  fileEntries,
  videoProgress,
  fileError,
  onFileChange,
  removeFile,
  uploadFiles,
} = useFileUpload()

// Step management
const step = ref(0)

// Step 1 state
const text = ref("")
const date = ref(new Date().toISOString().slice(0, 10))
const storylines = ref<Storyline[]>([])
const selectedStorylineIds = ref<number[]>([])
const submitting = ref(false)
const error = ref("")

// Step 2 state
type ShareMode = "everyone" | "specific" | "only-me"
const shareMode = ref<ShareMode>("everyone")
const allConnectionsTagId = ref<number | null>(null)
const recipients = ref<SharingRecipient[]>([])
const selectedUserIds = ref<Set<number>>(new Set())
const recipientsLoaded = ref(false)
const loadingSharing = ref(false)

const allSelected = computed(() =>
  recipients.value.length > 0 && selectedUserIds.value.size === recipients.value.length
)
const someSelected = computed(() =>
  selectedUserIds.value.size > 0 && selectedUserIds.value.size < recipients.value.length
)

onMounted(async () => {
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

function toggleStoryline(id: number) {
  const idx = selectedStorylineIds.value.indexOf(id)
  if (idx === -1) {
    selectedStorylineIds.value.push(id)
  } else {
    selectedStorylineIds.value.splice(idx, 1)
  }
}

async function loadSharingData() {
  if (recipientsLoaded.value) return
  loadingSharing.value = true

  try {
    const [groupsRes, recipientsRes] = await Promise.all([
      getGroups(),
      getSharingRecipients(),
    ])

    // Find "All Connections" group ID from GroupsResponse
    const allConn = groupsRes.data.activeTags?.find(
      (g) => g.name === "All Connections"
    )
    if (allConn) {
      allConnectionsTagId.value = allConn.tagId
    }

    recipients.value = recipientsRes.data
    recipientsLoaded.value = true
  } catch {
    // Non-critical — user can still save as "Only me"
  } finally {
    loadingSharing.value = false
  }
}

async function goToStep2() {
  if (!text.value.trim()) return
  error.value = ""

  await loadSharingData()

  // If no connections, skip Step 2 and save as private
  if (recipients.value.length === 0) {
    await handleSubmit()
    return
  }

  step.value = 1
}

function toggleSelectAll() {
  if (allSelected.value) {
    selectedUserIds.value = new Set()
  } else {
    selectedUserIds.value = new Set(recipients.value.map((r) => r.userId))
  }
}

function toggleRecipient(userId: number) {
  const next = new Set(selectedUserIds.value)
  if (next.has(userId)) {
    next.delete(userId)
  } else {
    next.add(userId)
  }
  selectedUserIds.value = next
}

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

async function handleSubmit() {
  if (submitting.value || !text.value.trim()) return
  submitting.value = true
  error.value = ""
  videoProgress.value = {}
  let dropId: number | null = null

  try {
    const tagIds = getTagIds()
    const { data: created } = await createDrop({
      information: text.value.trim(),
      date: date.value,
      dateType: 0,
      tagIds: tagIds.length > 0 ? tagIds : undefined,
      timelineIds: selectedStorylineIds.value.length
        ? selectedStorylineIds.value
        : undefined,
    })
    dropId = created.dropId

    if (fileEntries.value.length > 0) {
      const failedCount = await uploadFiles(fileEntries.value, dropId)
      if (failedCount > 0) {
        error.value = `${failedCount} file(s) failed to upload. You can add them from the memory detail.`
      }
      const delay = getTranscodeDelay(fileEntries.value)
      if (delay > 0) {
        await new Promise((r) => setTimeout(r, delay))
      }
    }
  } catch (e: any) {
    error.value = getErrorMessage(e, "Failed to create memory.")
  }

  if (dropId) {
    try {
      const { data: drop } = await getDrop(dropId)
      stream.prependMemory(drop)
    } catch {
      // Drop was created but fetch failed; stream will show it on next refresh
    }
    router.push("/")
  }

  submitting.value = false
}
</script>
```

### 2.4 Key Frontend Design Decisions

1. **Lazy loading:** Sharing data (groups + recipients) is fetched only when advancing to Step 2, not on mount
2. **Loading state:** "Next" button shows a spinner and is disabled while sharing data loads
3. **Zero connections → auto-private:** If `recipients.length === 0` after loading, `goToStep2()` calls `handleSubmit()` directly, skipping Step 2
4. **`v-show` for steps:** Uses `v-show` (not `v-if`) to preserve DOM state — textarea cursor position, file input state, and scroll position are maintained when toggling between steps
5. **State preservation:** Step 1 form state (text, date, files, storylines) is preserved when going back from Step 2 — both steps share the same component instance
6. **Set for selections:** `selectedUserIds` uses a `Set<number>` for O(1) lookups when rendering the checkbox list
7. **No group dropdown:** The old `v-if="groups.length"` group dropdown is removed entirely
8. **Fixed Group types:** `getGroups()` return type corrected to `GroupsResponse` (was incorrectly typed as `Group[]`). `Group` interface updated to use `tagId` (matching backend `GroupModel` camelCase serialization)
9. **Single component:** Step 2 is kept inline rather than extracted to a separate component. At ~230 lines of template this is manageable and avoids prop/emit overhead for the tightly coupled step state. Can be extracted later if the component grows.

---

## Phase 3: Testing

### 3.1 Backend Tests

**File:** `cimplur-core/Memento/DomainTest/GroupServiceTest.cs` (add tests to existing or new file)

#### Test: EnsurePerUserGroup_CreatesNewGroup

```
Given: User A has connection to User B, no per-user group exists
When: EnsurePerUserGroup(userA.Id, userB.Id) is called
Then: A UserTag named "__person:{userB.Id}" is created for User A
  AND: A TagViewer is created linking the UserTag to User B
  AND: Returns the new UserTagId
```

#### Test: EnsurePerUserGroup_ReturnsExistingGroup

```
Given: User A already has a "__person:{userB.Id}" group
When: EnsurePerUserGroup(userA.Id, userB.Id) is called
Then: Returns the existing UserTagId (no duplicate created)
```

#### Test: GetSharingRecipients_ReturnsConnections

```
Given: User A has 3 active connections (B, C, D) and 1 archived connection (E)
When: GetSharingRecipients(userA.Id) is called
Then: Returns 3 recipients (B, C, D) each with a userTagId
  AND: Results are sorted alphabetically by displayName
  AND: Archived connection E is not included
```

#### Test: GetSharingRecipients_DisplayNameFallsBackToEmail

```
Given: User A has a connection to User B where ReaderName is null
When: GetSharingRecipients(userA.Id) is called
Then: The recipient's displayName is null, email is populated
  (Frontend handles the display fallback)
```

#### Test: GetSharingRecipients_CreatesPerUserGroups

```
Given: User A has 2 connections, no per-user groups exist
When: GetSharingRecipients(userA.Id) is called
Then: 2 UserTag records named "__person:{userId}" are created
  AND: Each has a corresponding TagViewer record
```

#### Test: EnsurePerUserGroup_HandlesRaceCondition

```
Given: User A has no per-user group for User B
When: Two concurrent calls to EnsurePerUserGroup(userA.Id, userB.Id) occur
Then: Only one UserTag is created (unique constraint prevents duplicates)
  AND: Both calls return the same UserTagId
```

#### Test: GetSharingRecipients_IncludesTimelineInvitees

```
Given: User A invited User F to a timeline (TimelineUser exists)
  AND: User F has no UserUser connection to User A
When: GetSharingRecipients(userA.Id) is called
Then: User F is included in the results with a valid userTagId
```

#### Test: Groups_ReturnsOnlyAllConnections

```
Given: User A has groups: "All Connections", "Family", "Friends", "__person:42"
When: GET /api/groups is called
Then: Response contains only "All Connections" in activeTags
  AND: archivedTags is empty
```

### 3.2 Frontend Tests

**File:** `fyli-fe-v2/src/views/memory/CreateMemoryView.test.ts` (new)

Tests use Vitest + @vue/test-utils. Mock all API calls.

#### Test: renders Step 1 by default

```
Mount CreateMemoryView
Assert: Step 1 form is visible (textarea, date input, "Next" button)
Assert: Step 2 is NOT visible
```

#### Test: Next button advances to Step 2

```
Mock getGroups → { activeTags: [{ name: "All Connections", tagId: 5 }] }
Mock getSharingRecipients → [{ userId: 1, userTagId: 10, displayName: "Mom", email: "mom@test.com" }]
Mount, fill in text, click "Next"
Assert: Step 2 is visible with sharing options
Assert: "Everyone" is pre-selected
```

#### Test: skips Step 2 when no connections

```
Mock getGroups → { activeTags: [{ name: "All Connections", tagId: 5 }] }
Mock getSharingRecipients → []
Mock createDrop → { dropId: 1 }
Mock getDrop → full drop object
Mount, fill in text, click "Next"
Assert: createDrop called with tagIds undefined (private)
Assert: router.push("/") called
```

#### Test: Everyone mode passes allConnectionsTagId

```
Mock getGroups → { activeTags: [{ name: "All Connections", tagId: 5 }] }
Mock getSharingRecipients → [recipient]
Mock createDrop → { dropId: 1 }
Mount, fill text, click Next, verify "Everyone" selected, click "Save Memory"
Assert: createDrop called with tagIds: [5]
```

#### Test: Specific people mode passes selected userTagIds

```
Mock with 3 recipients (userTagIds: 10, 11, 12)
Mount, advance to Step 2, select "Specific people"
Click recipients 1 and 3
Click "Save Memory"
Assert: createDrop called with tagIds: [10, 12]
```

#### Test: Select All toggles all recipients

```
Mock with 3 recipients
Mount, advance to Step 2, select "Specific people"
Click "Select All"
Assert: all 3 checkboxes checked
Click "Select All" again
Assert: all unchecked
```

#### Test: Only Me passes no tagIds

```
Mock with recipients
Mount, advance to Step 2, select "Only me", click "Save Memory"
Assert: createDrop called with tagIds: undefined
```

#### Test: Back button returns to Step 1 with state preserved

```
Mount, fill text "Hello", add date, click Next
Click "Back"
Assert: Step 1 visible, text still "Hello", date preserved
```

#### Test: displays displayName, falls back to email

```
Mock recipients: [{ displayName: "Mom", email: "m@t.com" }, { displayName: null, email: "x@t.com" }]
Mount, advance to Step 2, select "Specific people"
Assert: list shows "Mom" and "x@t.com"
```

#### Test: shows loading state while fetching sharing data

```
Mock getSharingRecipients with delayed response
Mount, fill text, click "Next"
Assert: "Next" button is disabled, shows spinner with "Loading..."
After resolve: Step 2 is visible, button re-enabled
```

#### Test: API failure during loadSharingData falls back to Only Me

```
Mock getGroups → throws Error
Mock getSharingRecipients → throws Error
Mount, fill text, click "Next"
Assert: recipients is empty, handleSubmit called directly (auto-private)
Assert: createDrop called with tagIds undefined
```

#### Test: API failure during handleSubmit shows error

```
Mock sharing data successfully, mock createDrop → throws Error("Server error")
Mount, fill text, advance to Step 2, click "Save Memory"
Assert: error alert shows "Failed to create memory."
Assert: router.push NOT called
Assert: submitting returns to false
```

**File:** `fyli-fe-v2/src/services/connectionApi.test.ts` (new)

#### Test: getSharingRecipients calls correct endpoint

```
Mock axios.get
Call getSharingRecipients()
Assert: axios.get called with "/connections/sharing-recipients"
```

---

## Implementation Order

1. **Phase 1.1** — Create `SharingRecipientModel.cs`
2. **Phase 1.2** — Add `EnsurePerUserGroup` and `GetSharingRecipients` to `GroupService`
3. **Phase 1.3** — Modify `GroupController.Groups()` to filter to "All Connections" only
4. **Phase 1.4** — Add `GET /api/connections/sharing-recipients` endpoint to `ConnectionController`
5. **Phase 1.5** — Write backend tests
6. **Phase 2.1** — Add `SharingRecipient` type to `fyli-fe-v2/src/types/index.ts`
7. **Phase 2.2** — Create `connectionApi.ts` service
8. **Phase 2.3** — Refactor `CreateMemoryView.vue` to two-step wizard
9. **Phase 3** — Write frontend tests

---

## Database Changes

**None.** No schema changes, no migrations. All data is stored using existing tables:

| Table | DbSet Name | Role |
|-------|-----------|------|
| `UserNetworks` (`UserTag`) | `Context.UserNetworks` | Per-user groups named `__person:{userId}` |
| `NetworkViewers` (`TagViewer`) | `Context.NetworkViewers` | Links per-user group to target user |
| `NetworkDrops` (`TagDrop`) | `Context.NetworkDrops` | Links drop to groups (created by `DropsService.Add`) |
| `UserUsers` (`UserUser`) | `Context.UserUsers` | Source of truth for connections |

---

## Backwards Compatibility

- **Existing memories:** Unaffected. No data migration needed.
- **Drop access:** The `DropsService.Add` method is unchanged. Drops shared to per-user groups follow the same `TagDrop` → `TagViewer` → `UserProfile` access path as all other groups.
- **Notifications:** The existing `NotificationService.AddNotificationDropAdded` resolves `tagIds` → user IDs via `GroupService.GetUsersToShareWith`. Per-user groups with a single `TagViewer` will resolve correctly to the target user.
- **API contract:** `POST /api/drops` body unchanged. `GET /api/groups` returns fewer results (only "All Connections") but the response shape is unchanged.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `EnsurePerUserGroup` creates many UserTag records over time | Groups are small (1 row each). Scales linearly with connections, not drops. |
| Concurrent calls to `EnsurePerUserGroup` for same user pair | Unique index `(UserId, Name)` prevents duplicates. `try/catch DbUpdateException` with re-query handles race condition gracefully. |
| `GetSharingRecipients` performance for users with many connections | Bulk-fetches existing `__person:*` groups in one query. Only creates missing groups (first call only). Subsequent calls are mostly reads. |
| Filtering `GET /api/groups` breaks other frontend features | Only `CreateMemoryView.vue` calls this endpoint in fyli-fe-v2 (verified via grep). Other group endpoints (`/editable`, `/allSelected`, `/includeMembers`) are intentionally left unchanged. `DropsService` calls `AllNetworkModels()` directly, not through the API. |
| Timeline invitees missing from recipients list | `GetSharingRecipients` queries both `UserUser` and `TimelineUser` tables, deduplicating by userId. |

---

*Document Version: 1.1*
*Created: 2026-02-11*
*Updated: 2026-02-11 — Addressed code review feedback (v1.0 → v1.1)*
*Status: Draft*
