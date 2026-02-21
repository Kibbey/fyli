# TDD: Auto-Connections & Connections Page

**PRD:** `docs/prd/PRD_AUTO_CONNECTIONS.md`
**Status:** Complete
**Created:** 2026-02-14

---

## Overview

Add a Connections page to the navigation where users can see, rename, and disconnect from connections. Enhance share link claiming to return auto-connection status for toast notifications. The core auto-connection infrastructure already exists — `EnsureConnectionAsync` creates bidirectional `UserUser` records and `PopulateEveryone` adds connections to the "All Connections" group.

### Key Discovery: Auto-Connection Already Works

The share link flow already creates bidirectional connections:
1. `SharedMemoryView.vue` calls `claimAccess(token)` when authenticated (line 91)
2. `ShareLinkController.ClaimAccess` → `MemoryShareLinkService.ClaimDropAccessAsync`
3. `GrantDropAccessAsync` → `sharingService.EnsureConnectionAsync(creatorUserId, viewerUserId)` (line 161)
4. `EnsureConnectionAsync` creates **two** `UserUser` rows (A→B and B→A)
5. `groupService.PopulateEveryone()` called for both users (lines 207-208)

**What's missing:** The frontend has no Connections page, no way to view/manage connections, and no toast when auto-connected.

---

## !IMPORTANT! Bidirectional Connection Handling

Every connection requires **two** `UserUser` rows:

```
Connection between User A (id=1) and User B (id=2):
  Row 1: OwnerUserId=1, ReaderUserId=2, ReaderName="User B"   (A's view of B)
  Row 2: OwnerUserId=2, ReaderUserId=1, ReaderName="User A"   (B's view of A)
```

**Methods that already handle this correctly:**
- `SharingService.EnsureConnectionAsync` — creates both rows (lines 735-771)
- `SharingService.RemoveConnection` — removes both rows + TagViewers (lines 219-234)
- `SharingService.ConfirmationSharingRequest` — creates both rows (lines 302-387)

**Methods that are one-directional (by design):**
- `SharingService.UpdateName` — only updates the current user's view (OwnerUserId=currentUser)
- `UserService.GetConnections` — only returns connections from current user's perspective (OwnerUserId=currentUser)

**Verification required:** No new bidirectional logic is needed. All existing methods correctly handle both directions. The TDD uses only these existing methods.

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Frontend                                  │
│                                                                  │
│  AppDrawer ─── "Connections" nav item ──→ ConnectionsView        │
│                                                                  │
│  ConnectionsView ─── getConnections() ──→ GET /api/connections   │
│                  ─── deleteConnection() → DELETE /api/conn/{id}  │
│                  ─── renameConnection() → PUT /api/conn/{id}/name│
│                  ─── sendInvitation() ──→ POST /api/connections  │
│                                                                  │
│  SharedMemoryView ── claimAccess() ─────→ POST /sharelinks/claim │
│                  ─── shows toast if newConnection=true            │
└──────────────────────────────┬───────────────────────────────────┘
                               │
┌──────────────────────────────▼───────────────────────────────────┐
│                        Backend                                    │
│                                                                  │
│  ConnectionController                                            │
│    GET  /api/connections         → UserService.GetConnections     │
│    DEL  /api/connections/{id}    → SharingService.RemoveConnection│
│    PUT  /api/connections/{id}/name → SharingService.UpdateName   │
│    POST /api/connections         → SharingService.RequestConnection│
│                                                                  │
│  ShareLinkController                                             │
│    POST /sharelinks/{token}/claim → MemoryShareLinkService       │
│         returns { success, newConnection, connectionName }       │
│                                                                  │
│  EnsureConnectionAsync ── creates TWO UserUser rows ──┐          │
│  PopulateEveryone ── adds to "All Connections" group ─┘          │
│                                                                  │
│  RemoveConnection ── removes BOTH UserUser rows ──┐              │
│                  ── removes TagViewer records ─────┘              │
└──────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
cimplur-core/
├── Memento/Domain/
│   ├── Models/
│   │   └── ConnectionModel.cs              # ADD Email property
│   └── Repositories/
│       ├── UserService.cs                  # UPDATE GetConnections to include Email
│       ├── SharingService.cs               # UPDATE EnsureConnectionAsync return type → Task<bool>
│       └── MemoryShareLinkService.cs       # UPDATE ClaimDropAccessAsync return type
├── Memento/Memento/Controllers/
│   └── ShareLinkController.cs              # UPDATE ClaimAccess response

fyli-fe-v2/src/
├── composables/
│   └── useToast.ts                         # NEW - shared toast composable
├── views/connections/
│   ├── ConnectionsView.vue                 # NEW - connections list page
│   ├── ConnectionsView.test.ts             # NEW - component tests
│   └── InviteView.vue                      # EXISTING - no changes
├── components/ui/
│   ├── AppDrawer.vue                       # UPDATE - Invite → Connections
│   └── AppDrawer.test.ts                   # UPDATE - test nav item
├── services/
│   └── connectionApi.ts                    # UPDATE - add delete, rename, update types
│   └── connectionApi.test.ts               # UPDATE - add tests for new functions
├── views/share/
│   └── SharedMemoryView.vue                # UPDATE - add toast on auto-connection
│   └── SharedMemoryView.test.ts            # UPDATE - test toast
└── router/
    └── index.ts                            # UPDATE - add /connections, redirect /invite
```

---

## Phase 1: Backend Enhancements

### 1.1 Add Email to ConnectionModel

**File:** `cimplur-core/Memento/Domain/Models/ConnectionModel.cs`

```csharp
namespace Domain.Models
{
    public class ConnectionModel
    {
        public string Name { get; set; }
        public string Email { get; set; }          // NEW
        public bool EmailNotifications { get; set; }
        public DateTime Age { get; set; }
        public Guid Token { get; set; }
        public int Id { get; set; }
    }
}
```

### 1.2 Update GetConnections Query

**File:** `cimplur-core/Memento/Domain/Repositories/UserService.cs` (line 151)

```csharp
public List<ConnectionModel> GetConnections(int userId)
{
    return Context.UserUsers
        .Where(x => x.OwnerUserId == userId)
        .Select(s => new ConnectionModel
        {
            EmailNotifications = s.SendNotificationEmail,
            Name = s.ReaderName ?? s.ReaderUser.Name,
            Email = s.ReaderUser.Email,              // NEW
            Id = s.ReaderUserId
        })
        .ToList()
        .OrderBy(s => s.Name)
        .ToList();
}
```

### 1.3 Update EnsureConnectionAsync to Return Bool

**File:** `cimplur-core/Memento/Domain/Repositories/SharingService.cs` (line 735)

Change return type from `Task` to `Task<bool>`. Returns `true` if a new connection was created (either direction), `false` if connection already existed.

```csharp
public async Task<bool> EnsureConnectionAsync(int userIdA, int userIdB, bool saveChanges = true)
{
    bool created = false;

    var existingAtoB = await Context.UserUsers
        .AnyAsync(uu => uu.OwnerUserId == userIdA && uu.ReaderUserId == userIdB);

    if (!existingAtoB)
    {
        var userB = await Context.UserProfiles.SingleAsync(u => u.UserId == userIdB);
        Context.UserUsers.Add(new UserUser
        {
            OwnerUserId = userIdA,
            ReaderUserId = userIdB,
            ReaderName = userB.Name,
            SendNotificationEmail = true
        });
        created = true;
    }

    var existingBtoA = await Context.UserUsers
        .AnyAsync(uu => uu.OwnerUserId == userIdB && uu.ReaderUserId == userIdA);

    if (!existingBtoA)
    {
        var userA = await Context.UserProfiles.SingleAsync(u => u.UserId == userIdA);
        Context.UserUsers.Add(new UserUser
        {
            OwnerUserId = userIdB,
            ReaderUserId = userIdA,
            ReaderName = userA.Name,
            SendNotificationEmail = true
        });
        created = true;
    }

    if (saveChanges)
    {
        await Context.SaveChangesAsync();
    }

    return created;
}
```

**Callers of EnsureConnectionAsync** (verify no breakage):
- `MemoryShareLinkService.GrantDropAccessAsync` — will capture return value (Phase 1.4)
- `MemoryShareLinkService.RegisterAndConnectAsync` — calls `await GrantDropAccessAsync(viewerUserId, link)` at line 118, discards return → compiles fine with new `Task<ClaimResult>` return type, no change needed
- `SharingService.ConnectFamilyPlan` — currently ignores return value → no change needed (just ignore bool)
- `SharingService.ConfirmationSharingRequest` — doesn't call `EnsureConnectionAsync` (creates UserUser directly) → no change needed

### 1.4 Update ClaimDropAccessAsync to Return Connection Info

**File:** `cimplur-core/Memento/Domain/Repositories/MemoryShareLinkService.cs`

Update `ClaimDropAccessAsync` and `GrantDropAccessAsync` to return connection result:

```csharp
/// <summary>
/// Result of claiming access to a shared drop.
/// </summary>
public class ClaimResult
{
    public bool NewConnection { get; set; }
    public string ConnectionName { get; set; }
}
```

Place `ClaimResult` in `cimplur-core/Memento/Domain/Models/ClaimResult.cs`.

```csharp
public async Task<ClaimResult> ClaimDropAccessAsync(Guid token, int userId)
{
    var link = await ValidateLinkAsync(token);
    return await GrantDropAccessAsync(userId, link);
}

private async Task<ClaimResult> GrantDropAccessAsync(int viewerUserId, MemoryShareLink shareLink)
{
    int creatorUserId = shareLink.CreatorUserId;
    int dropId = shareLink.DropId;

    if (viewerUserId == creatorUserId)
        return new ClaimResult { NewConnection = false };

    bool newConnection = await sharingService.EnsureConnectionAsync(creatorUserId, viewerUserId);

    // ... rest of existing logic unchanged ...

    string connectionName = null;
    if (newConnection)
    {
        var creator = await Context.UserProfiles.SingleAsync(u => u.UserId == creatorUserId);
        connectionName = creator.Name;
    }

    return new ClaimResult
    {
        NewConnection = newConnection,
        ConnectionName = connectionName
    };
}
```

### 1.5 Update ShareLinkController ClaimAccess Response

**File:** `cimplur-core/Memento/Memento/Controllers/ShareLinkController.cs` (line 120)

```csharp
[CustomAuthorization]
[HttpPost]
[Route("{token:guid}/claim")]
public async Task<IActionResult> ClaimAccess(Guid token)
{
    var result = await shareLinkService.ClaimDropAccessAsync(token, CurrentUserId);
    return Ok(new
    {
        success = true,
        newConnection = result.NewConnection,
        connectionName = result.ConnectionName
    });
}
```

### 1.6 No Database Migration Required

All changes use existing tables. No new entities, no schema changes.

---

## Phase 1 Tests (Backend)

### 1.7 Test: GetConnections Returns Email

**File:** `cimplur-core/Memento/DomainTest/Repositories/UserServiceTest.cs`

```csharp
[TestMethod]
public void GetConnections_ReturnsEmailField()
{
    // Arrange: create two users and a bidirectional connection
    var userA = CreateUser("User A", "usera@test.com");
    var userB = CreateUser("User B", "userb@test.com");
    CreateConnection(userA.UserId, userB.UserId, "User B");
    CreateConnection(userB.UserId, userA.UserId, "User A");
    DetachAllEntities(_context);

    // Act
    var service = CreateUserService();
    var connections = service.GetConnections(userA.UserId);

    // Assert
    Assert.AreEqual(1, connections.Count);
    Assert.AreEqual("userb@test.com", connections[0].Email);
    Assert.AreEqual("User B", connections[0].Name);
    Assert.AreEqual(userB.UserId, connections[0].Id);
}
```

### 1.8 Test: EnsureConnectionAsync Returns True for New Connection

**File:** `cimplur-core/Memento/DomainTest/Repositories/SharingServiceTest.cs`

```csharp
[TestMethod]
public async Task EnsureConnectionAsync_NewConnection_ReturnsTrueAndCreatesBidirectionalRecords()
{
    // Arrange
    var userA = CreateUser("Alice", "alice@test.com");
    var userB = CreateUser("Bob", "bob@test.com");
    DetachAllEntities(_context);

    // Act
    var service = CreateSharingService();
    bool created = await service.EnsureConnectionAsync(userA.UserId, userB.UserId);

    // Assert
    Assert.IsTrue(created);
    using var verify = CreateVerificationContext();
    var connections = verify.UserUsers.Where(uu =>
        (uu.OwnerUserId == userA.UserId && uu.ReaderUserId == userB.UserId) ||
        (uu.OwnerUserId == userB.UserId && uu.ReaderUserId == userA.UserId))
        .ToList();
    Assert.AreEqual(2, connections.Count); // Bidirectional
}

[TestMethod]
public async Task EnsureConnectionAsync_ExistingConnection_ReturnsFalse()
{
    // Arrange
    var userA = CreateUser("Alice", "alice@test.com");
    var userB = CreateUser("Bob", "bob@test.com");
    CreateConnection(userA.UserId, userB.UserId, "Bob");
    CreateConnection(userB.UserId, userA.UserId, "Alice");
    DetachAllEntities(_context);

    // Act
    var service = CreateSharingService();
    bool created = await service.EnsureConnectionAsync(userA.UserId, userB.UserId);

    // Assert
    Assert.IsFalse(created);
}
```

### 1.9 Test: ClaimDropAccessAsync Returns NewConnection Info

**File:** `cimplur-core/Memento/DomainTest/Repositories/MemoryShareLinkServiceTest.cs`

```csharp
[TestMethod]
public async Task ClaimDropAccessAsync_NewUser_ReturnsNewConnectionTrue()
{
    // Arrange: creator with a drop and active share link, viewer has no connection
    var creator = CreateUser("Creator", "creator@test.com");
    var viewer = CreateUser("Viewer", "viewer@test.com");
    var drop = CreateDrop(creator.UserId);
    var token = await CreateShareLink(creator.UserId, drop.DropId);
    DetachAllEntities(_context);

    // Act
    var service = CreateMemoryShareLinkService();
    var result = await service.ClaimDropAccessAsync(token, viewer.UserId);

    // Assert
    Assert.IsTrue(result.NewConnection);
    Assert.AreEqual("Creator", result.ConnectionName);
}

[TestMethod]
public async Task ClaimDropAccessAsync_ExistingConnection_ReturnsNewConnectionFalse()
{
    // Arrange: already connected
    var creator = CreateUser("Creator", "creator@test.com");
    var viewer = CreateUser("Viewer", "viewer@test.com");
    var drop = CreateDrop(creator.UserId);
    var token = await CreateShareLink(creator.UserId, drop.DropId);
    CreateConnection(creator.UserId, viewer.UserId, "Viewer");
    CreateConnection(viewer.UserId, creator.UserId, "Creator");
    DetachAllEntities(_context);

    // Act
    var service = CreateMemoryShareLinkService();
    var result = await service.ClaimDropAccessAsync(token, viewer.UserId);

    // Assert
    Assert.IsFalse(result.NewConnection);
    Assert.IsNull(result.ConnectionName);
}
```

### 1.10 Test: ClaimDropAccessAsync for Own Share Link

**File:** `cimplur-core/Memento/DomainTest/Repositories/MemoryShareLinkServiceTest.cs`

```csharp
[TestMethod]
public async Task ClaimDropAccessAsync_OwnShareLink_DoesNotCreateConnectionReturnsFalse()
{
    // Arrange: creator views their own share link
    var creator = CreateUser("Creator", "creator@test.com");
    var drop = CreateDrop(creator.UserId);
    var token = await CreateShareLink(creator.UserId, drop.DropId);
    DetachAllEntities(_context);

    // Act
    var service = CreateMemoryShareLinkService();
    var result = await service.ClaimDropAccessAsync(token, creator.UserId);

    // Assert
    Assert.IsFalse(result.NewConnection);
    Assert.IsNull(result.ConnectionName);
    using var verify = CreateVerificationContext();
    var connections = verify.UserUsers.Where(uu => uu.OwnerUserId == creator.UserId).ToList();
    Assert.AreEqual(0, connections.Count); // No self-connection created
}
```

### 1.11 Test: RemoveConnection Removes Both Directions and TagViewers

```csharp
[TestMethod]
public void RemoveConnection_RemovesBidirectionalRecordsAndTagViewers()
{
    // Arrange: bidirectional connection + TagViewer records
    var userA = CreateUser("Alice", "alice@test.com");
    var userB = CreateUser("Bob", "bob@test.com");
    CreateConnection(userA.UserId, userB.UserId, "Bob");
    CreateConnection(userB.UserId, userA.UserId, "Alice");
    var groupA = CreateGroup(userA.UserId, "Test Group");
    CreateTagViewer(groupA.UserTagId, userB.UserId);
    DetachAllEntities(_context);

    // Act
    var service = CreateSharingService();
    service.RemoveConnection(userA.UserId, userB.UserId);

    // Assert
    using var verify = CreateVerificationContext();
    var connections = verify.UserUsers.Where(uu =>
        (uu.OwnerUserId == userA.UserId && uu.ReaderUserId == userB.UserId) ||
        (uu.OwnerUserId == userB.UserId && uu.ReaderUserId == userA.UserId))
        .ToList();
    Assert.AreEqual(0, connections.Count); // Both directions removed

    var tagViewers = verify.NetworkViewers.Where(nv =>
        nv.UserId == userB.UserId && nv.UserTag.UserId == userA.UserId)
        .ToList();
    Assert.AreEqual(0, tagViewers.Count); // Content access removed
}
```

---

## Phase 2: Frontend — Connections Page

### 2.1 Update connectionApi.ts

**File:** `fyli-fe-v2/src/services/connectionApi.ts`

```typescript
import api from './api'
import type { SharingRecipient } from '@/types'

export interface Connection {
  id: number
  name: string
  email: string                    // NEW
  emailNotifications: boolean
}

export function getConnections() {
  return api.get<Connection[]>('/connections')
}

export function sendInvitation(email: string, requestorName: string) {
  return api.post('/connections', { email, requestorName })
}

export function confirmConnection(name: string) {
  return api.post('/connections/confirm', { name })
}

export function getSharingRecipients() {
  return api.get<SharingRecipient[]>('/connections/sharing-recipients')
}

// NEW
export function deleteConnection(userId: number) {
  return api.delete(`/connections/${userId}`)
}

// NEW
export function renameConnection(userId: number, name: string) {
  return api.put<{ name: string }>(`/connections/${userId}/name`, { name })
}
```

### 2.2 Update shareLinkApi.ts Response Type

**File:** `fyli-fe-v2/src/services/shareLinkApi.ts`

Update `claimAccess` return type:

```typescript
export interface ClaimResult {
  success: boolean
  newConnection: boolean
  connectionName: string | null
}

export function claimAccess(token: string) {
  return api.post<ClaimResult>(`/sharelinks/${token}/claim`)
}
```

### 2.3 Create useToast Composable

**File:** `fyli-fe-v2/src/composables/useToast.ts`

Extracts the repeated toast pattern used in `UnifiedQuestionsView.vue`, `ConnectionsView.vue`, and `SharedMemoryView.vue`.

```typescript
import { ref, onUnmounted } from "vue"

export function useToast(duration = 2000) {
  const toastMessage = ref("")
  let toastTimer: ReturnType<typeof setTimeout> | null = null

  onUnmounted(() => {
    if (toastTimer) clearTimeout(toastTimer)
  })

  function showToast(msg: string) {
    if (toastTimer) clearTimeout(toastTimer)
    toastMessage.value = msg
    toastTimer = setTimeout(() => { toastMessage.value = "" }, duration)
  }

  return { toastMessage, showToast }
}
```

**Toast template snippet** (use in any component):
```vue
<div v-if="toastMessage" class="toast-container position-fixed bottom-0 end-0 p-3">
  <div class="toast show" role="alert">
    <div class="toast-body">{{ toastMessage }}</div>
  </div>
</div>
```

### 2.4 Create ConnectionsView.vue (uses `useToast`)

**File:** `fyli-fe-v2/src/views/connections/ConnectionsView.vue`

```vue
<template>
  <div>
    <div class="d-flex justify-content-between align-items-center mb-3">
      <h4 class="mb-0">Connections</h4>
      <button class="btn btn-sm btn-primary" @click="showInvite = !showInvite">
        <span class="mdi mdi-account-plus me-1"></span>Invite
      </button>
    </div>

    <!-- Inline invite form -->
    <div v-if="showInvite" class="card mb-3">
      <div class="card-body">
        <form @submit.prevent="handleInvite">
          <div class="mb-2">
            <label for="invite-email" class="form-label">Email address</label>
            <input
              id="invite-email"
              v-model="inviteEmail"
              type="email"
              class="form-control"
              placeholder="family@example.com"
              required
            />
          </div>
          <div class="d-flex gap-2">
            <button type="submit" class="btn btn-primary btn-sm" :disabled="inviting">
              {{ inviting ? 'Sending...' : 'Send Invitation' }}
            </button>
            <button type="button" class="btn btn-outline-secondary btn-sm" @click="showInvite = false">
              Cancel
            </button>
          </div>
          <div v-if="inviteSuccess" class="text-success mt-2">
            <span class="mdi mdi-check-circle-outline me-1"></span>Invitation sent!
          </div>
          <div v-if="inviteError" class="text-danger mt-2">{{ inviteError }}</div>
        </form>
      </div>
    </div>

    <LoadingSpinner v-if="loading" />
    <ErrorState v-else-if="error" @retry="loadConnections" />
    <EmptyState
      v-else-if="connections.length === 0"
      icon="mdi-account-group-outline"
      message="No connections yet. Invite family and friends to start sharing memories together."
      actionLabel="Invite Someone"
      @action="showInvite = true"
    />
    <ul v-else class="list-unstyled">
      <li
        v-for="conn in connections"
        :key="conn.id"
        class="d-flex align-items-center py-2 border-bottom"
      >
        <!-- Avatar -->
        <div
          class="rounded-circle d-flex align-items-center justify-content-center me-3 flex-shrink-0"
          :style="{
            width: '40px', height: '40px',
            backgroundColor: 'var(--fyli-primary-light)',
            color: 'var(--fyli-primary)'
          }"
        >
          <span class="fw-bold">{{ conn.name.charAt(0).toUpperCase() }}</span>
        </div>

        <!-- Name / Email / Rename -->
        <div class="flex-grow-1 min-width-0">
          <template v-if="editingId === conn.id">
            <input
              ref="renameInput"
              v-model="editName"
              class="form-control form-control-sm"
              @keydown.enter="saveRename(conn)"
              @keydown.escape="cancelRename"
              @blur="saveRename(conn)"
            />
          </template>
          <template v-else>
            <div class="fw-medium text-truncate">{{ conn.name }}</div>
            <small class="text-muted text-truncate d-block">{{ conn.email }}</small>
          </template>
        </div>

        <!-- Actions -->
        <button
          class="btn btn-sm btn-outline-secondary border-0 ms-2"
          title="Rename"
          :aria-label="`Rename ${conn.name}`"
          @click="startRename(conn)"
        >
          <span class="mdi mdi-pencil-outline"></span>
        </button>
        <button
          class="btn btn-sm btn-outline-danger border-0 ms-1"
          title="Disconnect"
          :aria-label="`Disconnect from ${conn.name}`"
          @click="confirmDisconnect(conn)"
        >
          <span class="mdi mdi-close-circle-outline"></span>
        </button>
      </li>
    </ul>

    <!-- Disconnect confirmation modal -->
    <Teleport to="body">
      <div v-if="disconnecting" class="modal d-block" tabindex="-1" style="background: var(--bs-modal-backdrop-bg, rgba(0,0,0,0.5))">
        <div class="modal-dialog modal-dialog-centered">
          <div class="modal-content">
            <div class="modal-header">
              <h5 class="modal-title">Disconnect?</h5>
              <button type="button" class="btn-close" @click="disconnecting = null"></button>
            </div>
            <div class="modal-body">
              Disconnect from {{ disconnecting.name }}? They won't see your memories shared with Everyone, and you won't see theirs.
            </div>
            <div class="modal-footer">
              <button class="btn btn-secondary" @click="disconnecting = null">Cancel</button>
              <button class="btn btn-danger" @click="handleDisconnect">Disconnect</button>
            </div>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Toast -->
    <div v-if="toastMessage" class="toast-container position-fixed bottom-0 end-0 p-3">
      <div class="toast show" role="alert">
        <div class="toast-body">{{ toastMessage }}</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, nextTick } from 'vue'
import {
  getConnections,
  deleteConnection,
  renameConnection,
  sendInvitation,
  type Connection,
} from '@/services/connectionApi'
import { useAuthStore } from '@/stores/auth'
import { useToast } from '@/composables/useToast'
import { getErrorMessage } from '@/utils/errorMessage'
import LoadingSpinner from '@/components/ui/LoadingSpinner.vue'
import ErrorState from '@/components/ui/ErrorState.vue'
import EmptyState from '@/components/ui/EmptyState.vue'

const auth = useAuthStore()
const { toastMessage, showToast } = useToast()

const connections = ref<Connection[]>([])
const loading = ref(true)
const error = ref(false)

// Invite state
const showInvite = ref(false)
const inviteEmail = ref('')
const inviting = ref(false)
const inviteSuccess = ref(false)
const inviteError = ref('')

// Rename state
const editingId = ref<number | null>(null)
const editName = ref('')
const renameInput = ref<HTMLInputElement | null>(null)

// Disconnect state
const disconnecting = ref<Connection | null>(null)

onMounted(() => loadConnections())

async function loadConnections() {
  loading.value = true
  error.value = false
  try {
    const { data } = await getConnections()
    connections.value = data
  } catch {
    error.value = true
  } finally {
    loading.value = false
  }
}

// Invite
async function handleInvite() {
  inviting.value = true
  inviteError.value = ''
  inviteSuccess.value = false
  try {
    await sendInvitation(inviteEmail.value, auth.user?.name ?? '')
    inviteSuccess.value = true
    inviteEmail.value = ''
  } catch (e: unknown) {
    inviteError.value = getErrorMessage(e, 'Failed to send invitation')
  } finally {
    inviting.value = false
  }
}

// Rename
function startRename(conn: Connection) {
  editingId.value = conn.id
  editName.value = conn.name
  nextTick(() => {
    renameInput.value?.focus()
  })
}

function cancelRename() {
  editingId.value = null
}

async function saveRename(conn: Connection) {
  if (editingId.value !== conn.id) return
  const newName = editName.value.trim()
  editingId.value = null
  if (!newName || newName === conn.name) return
  try {
    const { data } = await renameConnection(conn.id, newName)
    conn.name = data.name
    showToast('Name updated')
  } catch {
    showToast('Failed to rename')
  }
}

// Disconnect
function confirmDisconnect(conn: Connection) {
  disconnecting.value = conn
}

async function handleDisconnect() {
  if (!disconnecting.value) return
  const conn = disconnecting.value
  disconnecting.value = null
  try {
    await deleteConnection(conn.id)
    connections.value = connections.value.filter(c => c.id !== conn.id)
    showToast(`Disconnected from ${conn.name}`)
  } catch {
    showToast('Failed to disconnect')
  }
}
</script>
```

### 2.5 Update AppDrawer.vue

**File:** `fyli-fe-v2/src/components/ui/AppDrawer.vue`

Change the "invite" drawer item:

```typescript
// BEFORE:
{
  name: 'invite',
  label: 'Invite',
  icon: 'mdi-account-plus-outline',
  iconActive: 'mdi-account-plus',
  to: '/invite',
  matchPaths: ['/invite'],
}

// AFTER:
{
  name: 'connections',
  label: 'Connections',
  icon: 'mdi-account-group-outline',
  iconActive: 'mdi-account-group',
  to: '/connections',
  matchPaths: ['/connections'],
}
```

### 2.6 Update Router

**File:** `fyli-fe-v2/src/router/index.ts`

Add `/connections` route and redirect `/invite`:

```typescript
// NEW: Connections page
{
  path: '/connections',
  name: 'connections',
  component: () => import('@/views/connections/ConnectionsView.vue'),
  meta: { auth: true, layout: 'app' },
},

// KEEP: Public invite acceptance — MUST appear BEFORE the /invite redirect
// so that /invite/:token is matched as a parameterized route, not a redirect.
{
  path: '/invite/:token',
  name: 'connection-invite',
  component: () => import('@/views/invite/ConnectionInviteView.vue'),
  meta: { layout: 'public' },
},

// CHANGE: Redirect bare /invite to /connections (after /invite/:token)
{
  path: '/invite',
  redirect: '/connections',
},
```

**Important:** The `/invite/:token` route MUST appear BEFORE the `/invite` redirect. Vue Router matches routes top-to-bottom — if the redirect came first, `/invite/abc-123` would redirect to `/connections` instead of showing `ConnectionInviteView.vue`.

---

## Phase 2 Tests (Frontend)

### 2.7 ConnectionsView Component Tests

**File:** `fyli-fe-v2/src/views/connections/ConnectionsView.test.ts`

```typescript
vi.mock('@/services/connectionApi')
vi.mock('vue-router')

describe('ConnectionsView', () => {
  // Setup: mount with pinia, mock getConnections

  it('renders loading spinner initially', () => {
    // mock getConnections to return a pending promise
    // assert LoadingSpinner exists
  })

  it('renders connection list with name, email, and avatar', async () => {
    // mock getConnections → [{ id: 1, name: 'Alice', email: 'alice@test.com', emailNotifications: true }]
    // assert: avatar shows "A", name shows "Alice", email shows "alice@test.com"
  })

  it('renders empty state when no connections', async () => {
    // mock getConnections → []
    // assert EmptyState with correct message
  })

  it('shows error state on API failure', async () => {
    // mock getConnections → reject
    // assert ErrorState rendered
  })

  it('invite form sends invitation and shows success', async () => {
    // click Invite button, fill email, submit
    // assert sendInvitation called with email
    // assert success message appears
  })

  it('disconnect shows confirmation modal', async () => {
    // render with connections, click disconnect button
    // assert modal text includes connection name
  })

  it('disconnect confirm calls deleteConnection and removes from list', async () => {
    // render with connections, click disconnect, click confirm
    // assert deleteConnection called with userId
    // assert connection removed from list
    // assert toast shows "Disconnected from {name}"
  })

  it('rename inline edit saves on Enter', async () => {
    // render with connections, click rename pencil icon
    // assert input appears with current name
    // type new name, press Enter
    // assert renameConnection called with (userId, newName)
    // assert name updated in list
  })

  it('rename inline edit cancels on Escape', async () => {
    // click rename, press Escape
    // assert name unchanged, input hidden
  })

  it('disconnect button has accessible aria-label', async () => {
    // assert button has aria-label="Disconnect from {name}"
  })
})
```

### 2.8 useToast Composable Tests

**File:** `fyli-fe-v2/src/composables/useToast.test.ts`

```typescript
import { describe, it, expect, vi, afterEach } from "vitest"

describe("useToast", () => {
  afterEach(() => { vi.restoreAllMocks() })

  it("showToast sets toastMessage", () => {
    // call showToast("Hello")
    // assert toastMessage.value === "Hello"
  })

  it("toastMessage clears after duration", () => {
    // vi.useFakeTimers()
    // call showToast("Hello")
    // vi.advanceTimersByTime(2000)
    // assert toastMessage.value === ""
  })

  it("subsequent showToast resets timer", () => {
    // vi.useFakeTimers()
    // call showToast("First")
    // vi.advanceTimersByTime(1000)
    // call showToast("Second")
    // vi.advanceTimersByTime(1500)
    // assert toastMessage.value === "Second" (first timer cancelled)
  })
})
```

### 2.9 connectionApi Service Tests

**File:** `fyli-fe-v2/src/services/connectionApi.test.ts`

```typescript
describe('connectionApi', () => {
  // existing tests...

  it('deleteConnection sends DELETE /connections/{userId}', () => {
    deleteConnection(42)
    expect(api.delete).toHaveBeenCalledWith('/connections/42')
  })

  it('renameConnection sends PUT /connections/{userId}/name', () => {
    renameConnection(42, 'Grandma')
    expect(api.put).toHaveBeenCalledWith('/connections/42/name', { name: 'Grandma' })
  })
})
```

### 2.9 AppDrawer Test Update

**File:** `fyli-fe-v2/src/components/ui/AppDrawer.test.ts`

**Existing test to update:** The "renders all nav items" test (line 53) currently asserts `expect(text).toContain("Invite")`. Change to `"Connections"`.

```typescript
// UPDATE existing test "renders all nav items":
it('renders all nav items', () => {
  // ... existing setup ...
  const text = wrapper.text()
  expect(text).toContain("Memories")
  expect(text).toContain("Storylines")
  expect(text).toContain("Questions")
  expect(text).toContain("Connections")   // CHANGED from "Invite"
  expect(text).toContain("Account")
})

// ADD new test:
it('Connections nav item links to /connections with correct icon', () => {
  // mount AppDrawer with open=true
  // find link with text "Connections"
  // assert link href is /connections
  // assert icon is mdi-account-group-outline
})
```

---

## Phase 3: Auto-Connection Toast

### 3.1 Update SharedMemoryView.vue

**File:** `fyli-fe-v2/src/views/share/SharedMemoryView.vue`

Add toast notification when `claimAccess` returns `newConnection: true`.

**Import changes:**
```typescript
// ADD to existing imports:
import { useToast } from "@/composables/useToast";
```

```vue
<template>
  <div>
    <!-- ... existing template ... -->

    <!-- Auto-connection toast -->
    <div v-if="toastMessage" class="toast-container position-fixed bottom-0 end-0 p-3">
      <div class="toast show" role="alert">
        <div class="toast-body">{{ toastMessage }}</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
// ... existing imports ...
import { useToast } from "@/composables/useToast";

const { toastMessage, showToast } = useToast(3000)

onMounted(async () => {
  try {
    const { data } = await getSharedMemory(token)
    memory.value = data

    if (auth.isAuthenticated) {
      const { data: claimResult } = await claimAccess(token)
      claimed.value = true
      if (claimResult.newConnection && claimResult.connectionName) {
        showToast(`You're now connected with ${claimResult.connectionName}`)
      }
    }
  } catch {
    error.value = true
  } finally {
    loading.value = false
  }
})

async function handleAuthSuccess() {
  try {
    const { data: claimResult } = await claimAccess(token)
    claimed.value = true
    if (claimResult.newConnection && claimResult.connectionName) {
      showToast(`You're now connected with ${claimResult.connectionName}`)
    }
  } catch (e) {
    console.error('Failed to claim access:', e)
    claimed.value = true
  }
}
</script>
```

### 3.2 Update shareLinkApi Tests

**File:** `fyli-fe-v2/src/services/shareLinkApi.test.ts`

```typescript
it('claimAccess returns ClaimResult', async () => {
  const mockResult = { success: true, newConnection: true, connectionName: 'Alice' }
  vi.mocked(api.post).mockResolvedValue({ data: mockResult })
  const { data } = await claimAccess('tok-123')
  expect(data.newConnection).toBe(true)
  expect(data.connectionName).toBe('Alice')
})
```

### 3.3 SharedMemoryView Toast Tests

**File:** `fyli-fe-v2/src/views/share/SharedMemoryView.test.ts`

```typescript
it('shows toast when new auto-connection is created', async () => {
  // mock getSharedMemory → memory
  // mock claimAccess → { success: true, newConnection: true, connectionName: 'Alice' }
  // mock auth.isAuthenticated → true
  // mount, flushPromises
  // assert toast text contains "You're now connected with Alice"
})

it('does not show toast for existing connection', async () => {
  // mock claimAccess → { success: true, newConnection: false, connectionName: null }
  // mount, flushPromises
  // assert no toast element
})
```

---

## Phase 4: Verification Tests

Verify all sharing paths create bidirectional connections.

### 4.1 Backend Integration Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/SharingServiceTest.cs`

```csharp
[TestMethod]
public async Task ConfirmationSharingRequest_CreatesBidirectionalConnection()
{
    // Arrange: userA sends invite to userB's email
    var userA = CreateUser("Alice", "alice@test.com");
    var userB = CreateUser("Bob", "bob@test.com");
    var shareRequest = new ShareRequest
    {
        RequesterUserId = userA.UserId,
        RequestorName = "Alice",
        TargetsEmail = "bob@test.com",
        TargetsUserId = userB.UserId,
        TargetAlias = "Bob",
        RequestKey = Guid.NewGuid(),
        TagsToShare = "[]",
        Used = false,
        Ignored = false
    };
    _context.ShareRequests.Add(shareRequest);
    _context.SaveChanges();
    DetachAllEntities(_context);

    // Act
    var service = CreateSharingService();
    await service.ConfirmationSharingRequest(
        shareRequest.RequestKey.ToString(), userB.UserId, "Alice");

    // Assert: bidirectional UserUser records
    using var verify = CreateVerificationContext();
    var connections = verify.UserUsers.Where(uu =>
        (uu.OwnerUserId == userA.UserId && uu.ReaderUserId == userB.UserId) ||
        (uu.OwnerUserId == userB.UserId && uu.ReaderUserId == userA.UserId))
        .ToList();
    Assert.AreEqual(2, connections.Count);

    // Assert: both users in each other's "All Connections" group
    var allConnGroupA = verify.UserNetworks
        .Single(g => g.UserId == userA.UserId && g.Name == "All Connections");
    var viewerInA = verify.NetworkViewers
        .Any(nv => nv.UserTagId == allConnGroupA.UserTagId && nv.UserId == userB.UserId);
    Assert.IsTrue(viewerInA);
}
```

**File:** `cimplur-core/Memento/DomainTest/Repositories/MemoryShareLinkServiceTest.cs`

```csharp
[TestMethod]
public async Task ClaimDropAccess_CreatesBidirectionalConnectionAndPopulatesEveryone()
{
    // Arrange
    var creator = CreateUser("Creator", "creator@test.com");
    var viewer = CreateUser("Viewer", "viewer@test.com");
    var drop = CreateDrop(creator.UserId);
    var token = await CreateShareLink(creator.UserId, drop.DropId);
    // Create "All Connections" group for creator (normally auto-created)
    CreateGroup(creator.UserId, "All Connections");
    DetachAllEntities(_context);

    // Act
    var service = CreateMemoryShareLinkService();
    await service.ClaimDropAccessAsync(token, viewer.UserId);

    // Assert: bidirectional UserUser records
    using var verify = CreateVerificationContext();
    var connections = verify.UserUsers.Where(uu =>
        (uu.OwnerUserId == creator.UserId && uu.ReaderUserId == viewer.UserId) ||
        (uu.OwnerUserId == viewer.UserId && uu.ReaderUserId == creator.UserId))
        .ToList();
    Assert.AreEqual(2, connections.Count);

    // Assert: viewer is in creator's "All Connections" TagViewers
    var creatorAllConn = verify.UserNetworks
        .Single(g => g.UserId == creator.UserId && g.Name == "All Connections");
    var viewerInCreatorGroup = verify.NetworkViewers
        .Any(nv => nv.UserTagId == creatorAllConn.UserTagId && nv.UserId == viewer.UserId);
    Assert.IsTrue(viewerInCreatorGroup);
}
```

---

## Implementation Order

1. **Phase 1** — Backend: Add Email to ConnectionModel, update EnsureConnectionAsync return type, update ClaimDropAccessAsync/GrantDropAccessAsync, update controller response, add ClaimResult model. Run backend tests.
2. **Phase 2** — Frontend: Update connectionApi.ts + shareLinkApi.ts types, create ConnectionsView.vue, update AppDrawer, update router, redirect /invite. Run frontend tests.
3. **Phase 3** — Frontend: Add toast to SharedMemoryView.vue using new ClaimResult response. Run frontend tests.
4. **Phase 4** — Backend: Add verification tests for bidirectional connections across all triggers.

---

## Review Checklist

- [x] `EnsureConnectionAsync` creates TWO UserUser rows (verified — lines 737-765)
- [x] `RemoveConnection` removes BOTH UserUser rows AND TagViewers (verified — lines 219-234)
- [x] `UpdateName` only changes current user's view (correct — single-directional by design)
- [x] `GetConnections` returns from current user's perspective only (correct — OwnerUserId filter)
- [x] Share link claim already calls `EnsureConnectionAsync` + `PopulateEveryone` (verified — lines 161, 207-208)
- [x] No database migration needed
- [x] Backwards compatible — no existing behavior changes, only additions
