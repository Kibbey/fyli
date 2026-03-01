# TDD: Onboarding Experience

## Overview

New users sign up for Fyli and land on an empty stream with no guidance. This TDD implements a two-phase onboarding experience: a guided "First Moment" flow that walks users through creating their first memory with AI polish in under 60 seconds, followed by three optional missions that introduce Storylines, Questions, and Sharing.

**PRD:** `docs/prd/PRD_ONBOARDING.md`

## Design

### Approach

**Phase 1 — First Moment Flow:**
1. Add `OnboardingState` JSON field to `UserProfile` entity (mirrors the `CurrentNotifications` pattern)
2. Add `OnboardingState` to `UserModel` response so the frontend knows onboarding status
3. Remove `AddHelloWorldDrop` calls from all registration paths — the First Moment flow replaces the sample memory
4. Initialize `OnboardingState` for new users during registration
5. Build a multi-step frontend flow: Welcome → Prompt Selection → Quick Capture → AI Polish → Save & Celebrate
6. Add router guard to redirect new users who haven't completed First Moment

**Phase 2 — Getting Started Missions:**
1. Add `PUT /api/users/onboarding` endpoint for dismissing/updating mission state
2. Add completion triggers in `TimelineService`, `QuestionService`, and `MemoryShareLinkService`
3. Build `MissionCard.vue` component for the stream view
4. Add 30-day auto-expiry logic

### Component Diagram

```
                    ┌─────────────────────┐
                    │   UserController    │
                    │ GET /api/users      │ ← returns OnboardingState
                    │ PUT /api/users/     │
                    │     onboarding      │ ← dismiss/update missions
                    └─────────┬───────────┘
                              │
                    ┌─────────▼───────────┐
                    │    UserService      │
                    │ GetUser()           │ ← deserializes OnboardingState JSON
                    │ UpdateOnboarding()  │ ← serializes OnboardingState JSON
                    │ InitOnboarding()    │ ← called during registration
                    └─────────┬───────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
    ┌─────────▼─────┐  ┌─────▼──────┐  ┌─────▼──────────┐
    │TimelineService│  │QuestionSvc │  │ShareLinkService│
    │ AddTimeline() │  │CreateQSet()│  │CreateLinkAsync()│
    │  ↓ trigger    │  │  ↓ trigger │  │  ↓ trigger     │
    │ "storyline"   │  │ "question" │  │ "share"        │
    └───────────────┘  └────────────┘  └────────────────┘

Frontend:
┌─────────────────────────────────────────────────────┐
│ Router Guard: needsFirstMoment → /onboarding/first-moment │
├─────────────────────────────────────────────────────┤
│ FirstMomentView.vue (replaces existing onboarding)  │
│  ├── Step 0: Welcome screen                         │
│  ├── Step 1: Prompt selection                       │
│  ├── Step 2: Quick capture + file upload            │
│  ├── Step 3: AI polish (split view)                 │
│  └── Step 4: Save & celebrate                       │
├─────────────────────────────────────────────────────┤
│ StreamView.vue                                      │
│  └── MissionCard.vue (top of stream)                │
│       ├── Mission progress (0/3)                    │
│       ├── Current mission CTA                       │
│       ├── Dismiss button                            │
│       └── "Resume getting started" link             │
└─────────────────────────────────────────────────────┘
```

### Data Flow

**First Moment Flow:**
```
1. User registers → backend initializes OnboardingState JSON
2. Frontend calls GET /api/users → receives onboardingState with firstMomentCompletedAt=null
3. Router guard redirects to /onboarding/first-moment
4. User completes flow → frontend calls POST /api/drops (creates memory)
5. Frontend calls PUT /api/users/onboarding { action: "completeFirstMoment" }
6. Backend sets firstMomentCompletedAt = now
7. Frontend navigates to StreamView
```

**Mission Completion:**
```
1. User creates a storyline → TimelineService.AddTimeline()
2. Service calls UserService.CompleteMission(userId, "storyline")
3. UserService deserializes OnboardingState, adds "storyline" to completedMissions, saves
4. Next GET /api/users returns updated onboardingState
5. Frontend MissionCard reacts to updated state
```

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Entities/
│   │   └── UserProfile.cs           (ADD OnboardingState field)
│   ├── Models/
│   │   ├── UserModel.cs             (ADD OnboardingState property)
│   │   └── OnboardingStateModel.cs  (NEW)
│   └── Repositories/
│       ├── UserService.cs           (ADD onboarding methods)
│       ├── TimelineService.cs       (ADD completion trigger)
│       ├── QuestionService.cs       (ADD completion trigger)
│       ├── MemoryShareLinkService.cs (ADD completion trigger)
│       ├── GoogleAuthService.cs     (REMOVE AddHelloWorldDrop)
│       └── DropsService.cs          (REMOVE AddHelloWorldDrop method)
├── Memento/
│   ├── Controllers/
│   │   └── UserController.cs        (ADD onboarding endpoint)
│   └── Models/
│       └── OnboardingRequest.cs     (NEW)
└── Bridge/
    └── UserModel.cs                 (ADD OnboardingState property)

fyli-fe-v2/src/
├── types/
│   └── index.ts                     (ADD OnboardingState, update User)
├── services/
│   └── onboardingApi.ts             (NEW)
├── stores/
│   └── auth.ts                      (ADD onboarding computed properties)
├── views/
│   └── onboarding/
│       └── FirstMomentView.vue      (NEW — replaces FirstMemoryView)
├── components/
│   └── onboarding/
│       └── MissionCard.vue          (NEW)
└── router/
    └── index.ts                     (ADD first moment guard)
```

## Implementation

### Phase 1: Backend — OnboardingState Model & Data Layer

#### 1.1 Create OnboardingStateModel

**File:** `cimplur-core/Memento/Domain/Models/OnboardingStateModel.cs` (NEW)

```csharp
using System;
using System.Collections.Generic;

namespace Domain.Models
{
    public class OnboardingStateModel
    {
        public OnboardingStateModel()
        {
            CompletedMissions = new List<string>();
        }

        public DateTime? FirstMomentCompletedAt { get; set; }
        public bool MissionsDismissed { get; set; }
        public List<string> CompletedMissions { get; set; }
    }
}
```

#### 1.2 Add OnboardingState field to UserProfile

**File:** `cimplur-core/Memento/Domain/Entities/UserProfile.cs`

Add after the existing `Reasons` field:

```csharp
[MaxLength(1000), Column(TypeName = "varchar")]
public string OnboardingState { get; set; }
```

#### 1.3 Add OnboardingState to UserModel (Domain)

**File:** `cimplur-core/Memento/Domain/Models/UserModel.cs`

Add property:

```csharp
public OnboardingStateModel OnboardingState { get; set; }
```

#### 1.4 Add OnboardingState to UserModel (Bridge)

**File:** `cimplur-core/Memento/Bridge/UserModel.cs`

Add import and property:

```csharp
using Domain.Models;
// ...
public OnboardingStateModel OnboardingState { get; set; }
```

#### 1.5 Generate EF Core migration

```bash
cd cimplur-core/Memento && dotnet ef migrations add AddOnboardingState --project Domain --startup-project Memento
```

#### 1.6 Raw SQL reference (for production deployment)

> **Note:** The SQL below is a placeholder reference showing the expected schema change. The actual production script **must** be generated after creating the EF Core migration:
> ```bash
> cd cimplur-core/Memento && dotnet ef migrations script <PreviousMigration> AddOnboardingState --project Domain --startup-project Memento --idempotent
> ```
> Save the generated script to `docs/migrations/AddOnboardingState.sql`.

```sql
IF NOT EXISTS (
    SELECT * FROM sys.columns
    WHERE [object_id] = OBJECT_ID(N'[UserProfiles]')
      AND [name] = N'OnboardingState'
)
BEGIN
    ALTER TABLE [UserProfiles]
        ADD [OnboardingState] VARCHAR(1000) NULL;
END;
GO

INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
VALUES (N'YYYYMMDDHHMMSS_AddOnboardingState', N'9.0.8');
GO
```

### Phase 2: Backend — UserService Onboarding Methods

#### 2.1 Update GetUser to include OnboardingState

**File:** `cimplur-core/Memento/Domain/Repositories/UserService.cs`

Update the `GetUser` method to deserialize and include `OnboardingState`:

```csharp
public async Task<UserModel> GetUser(int currentUserId)
{
    var now = DateTime.UtcNow;
    var user = await Context.UserProfiles
        .Include(i => i.PremiumPlans)
        .SingleOrDefaultAsync(x => x.UserId == currentUserId);
    if (user == null) throw new NotFoundException();

    OnboardingStateModel onboardingState = null;
    if (!string.IsNullOrWhiteSpace(user.OnboardingState))
    {
        onboardingState = JsonConvert.DeserializeObject<OnboardingStateModel>(
            user.OnboardingState);
    }

    var userModel = new UserModel {
        Name = user.Name ?? user.UserName,
        CanShareDate = user.PremiumExpiration.HasValue
            && user.PremiumExpiration.Value > now
            ? user.PremiumExpiration : null,
        PremiumMember = user.PremiumExpiration.HasValue
            && user.PremiumExpiration.Value > now,
        Variants = GetVariants(currentUserId),
        PrivateMode = user.PrivateMode,
        Email = user.Email,
        NeedsProfileCompletion = !user.AcceptedTerms.HasValue,
        OnboardingState = onboardingState
    };
    return userModel;
}
```

#### 2.2 Add InitializeOnboarding methods

**File:** `cimplur-core/Memento/Domain/Repositories/UserService.cs`

Two overloads: one accepts a `UserProfile` entity (avoids redundant query when the caller already has it), the other accepts a `userId` for callers that don't.

```csharp
/// <summary>
/// Initializes onboarding state on an already-loaded user entity.
/// Use this overload when the caller already has the UserProfile
/// to avoid a redundant database query.
/// </summary>
public void InitializeOnboarding(UserProfile user)
{
    var state = new OnboardingStateModel();
    user.OnboardingState = JsonConvert.SerializeObject(state);
}

/// <summary>
/// Initializes onboarding state for a newly registered user by userId.
/// Called from registration paths (UserController.Register,
/// GoogleAuthService, QuestionService, TimelineShareLinkService)
/// where the caller does not have the UserProfile entity in scope.
/// </summary>
public async Task InitializeOnboardingAsync(int userId)
{
    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.UserId == userId);
    if (user == null) return;

    InitializeOnboarding(user);
    await Context.SaveChangesAsync();
}
```

#### 2.3 Add UpdateOnboarding method

**File:** `cimplur-core/Memento/Domain/Repositories/UserService.cs`

```csharp
private static readonly HashSet<string> ValidMissions =
    new() { "storyline", "question", "share" };

private static readonly
    Dictionary<string, Action<OnboardingStateModel, string>>
    OnboardingActions = new()
{
    ["completeFirstMoment"] = (s, _) =>
        s.FirstMomentCompletedAt = DateTime.UtcNow,
    ["dismiss"] = (s, _) =>
        s.MissionsDismissed = true,
    ["resume"] = (s, _) =>
        s.MissionsDismissed = false,
    ["completeMission"] = (s, m) =>
    {
        if (!string.IsNullOrWhiteSpace(m)
            && ValidMissions.Contains(m)
            && !s.CompletedMissions.Contains(m))
        {
            s.CompletedMissions.Add(m);
        }
    },
};

/// <summary>
/// Updates onboarding state: complete first moment, dismiss missions,
/// or mark a mission as complete.
/// </summary>
public async Task<OnboardingStateModel> UpdateOnboardingAsync(
    int userId, string action, string mission = null)
{
    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.UserId == userId);
    if (user == null) throw new NotFoundException();

    if (!OnboardingActions.TryGetValue(action, out var handler))
        throw new BadRequestException("Invalid onboarding action.");

    var state = string.IsNullOrWhiteSpace(user.OnboardingState)
        ? new OnboardingStateModel()
        : JsonConvert.DeserializeObject<OnboardingStateModel>(
            user.OnboardingState);

    handler(state, mission);

    user.OnboardingState = JsonConvert.SerializeObject(state);
    await Context.SaveChangesAsync();
    return state;
}

/// <summary>
/// Completes a mission by name if the user has active onboarding state.
/// Safe to call when user has no onboarding state (no-ops for pre-existing users).
/// </summary>
public async Task TryCompleteMissionAsync(int userId, string mission)
{
    if (!ValidMissions.Contains(mission)) return;

    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.UserId == userId);
    if (user == null) return;
    if (string.IsNullOrWhiteSpace(user.OnboardingState)) return;

    var state = JsonConvert.DeserializeObject<OnboardingStateModel>(
        user.OnboardingState);
    if (state.CompletedMissions.Contains(mission)) return;

    state.CompletedMissions.Add(mission);
    user.OnboardingState = JsonConvert.SerializeObject(state);
    await Context.SaveChangesAsync();
}
```

#### 2.4 Remove AddHelloWorldDrop, initialize onboarding instead

**Removals and changes across multiple files:**

**File:** `cimplur-core/Memento/Domain/Repositories/DropsService.cs`
- Delete the `AddHelloWorldDrop` method entirely (lines ~873-884)

**File:** `cimplur-core/Memento/Domain/Repositories/UserService.cs`
- In `CompleteProfileAsync` (line 128): Remove `await dropService.AddHelloWorldDrop(userId);`
- After `groupService.AddHelloWorldNetworks(userId);` add: `await InitializeOnboardingAsync(userId);`

Updated `CompleteProfileAsync` (uses the entity overload to avoid a redundant query):
```csharp
public async Task CompleteProfileAsync(int userId, string name)
{
    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.UserId == userId);
    if (user == null) throw new NotFoundException();

    if (user.AcceptedTerms.HasValue)
        throw new BadRequestException("Profile is already complete.");

    user.Name = name?.Trim();
    user.AcceptedTerms = DateTime.UtcNow;
    user.PremiumExpiration = DateTime.UtcNow.AddYears(10);

    var hasDrops = await Context.Drops
        .AnyAsync(d => d.UserId == userId);
    if (!hasDrops)
    {
        groupService.AddHelloWorldNetworks(userId);
        InitializeOnboarding(user);
    }

    await Context.SaveChangesAsync();
}
```

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`
- In `Register` (line 260): Remove `await dropService.AddHelloWorldDrop(userId);`
- Add: `await userService.InitializeOnboardingAsync(userId);`

Updated Register (relevant section):
```csharp
int userId = await userService.AddUser(
    model.Email, userName, model.Token, true, model.Name, reasons?.Reasons);
var token = userWebToken.generateJwtToken(userId);
groupService.AddHelloWorldNetworks(userId);
await userService.InitializeOnboardingAsync(userId);
```

**File:** `cimplur-core/Memento/Domain/Repositories/GoogleAuthService.cs`
- In `FindOrCreateUserAsync` (line 128): Remove `await dropsService.AddHelloWorldDrop(userId);`
- Add: `await userService.InitializeOnboardingAsync(userId);`

Updated (relevant section):
```csharp
else
{
    userId = await userService.AddUser(
        email, email, null, true, name, null);
    groupService.AddHelloWorldNetworks(userId);
    await userService.InitializeOnboardingAsync(userId);
}
```

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`
- In `RegisterAndLinkAnswers` (line 735): Remove `await dropsService.AddHelloWorldDrop(userId);`
- Replace with: `await userService.InitializeOnboardingAsync(userId);`
- `QuestionService` already injects `UserService userService` in its constructor.

Updated (relevant section, lines ~730-736):
```csharp
var hasDrops = await Context.Drops
    .AnyAsync(d => d.UserId == userId);
if (!hasDrops)
{
    groupService.AddHelloWorldNetworks(userId);
    await userService.InitializeOnboardingAsync(userId);
}
```

**File:** `cimplur-core/Memento/Domain/Repositories/TimelineShareLinkService.cs`
- In `RegisterAndJoinTimeline` (line 155): Remove `await dropsService.AddHelloWorldDrop(userId);`
- Replace with: `await userService.InitializeOnboardingAsync(userId);`
- `TimelineShareLinkService` already has `UserService` available via its injected dependencies.

Updated (relevant section, lines ~150-156):
```csharp
else
{
    userId = await userService.AddUser(
        email, email, null, acceptTerms, name, null);
    groupService.AddHelloWorldNetworks(userId);
    await userService.InitializeOnboardingAsync(userId);
}
```

#### 2.5 Add onboarding endpoint

**File:** `cimplur-core/Memento/Memento/Models/OnboardingRequest.cs` (NEW)

```csharp
namespace Memento.Models
{
    public class OnboardingRequest
    {
        public string Action { get; set; }
        public string Mission { get; set; }
    }
}
```

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

Add endpoint:

```csharp
[CustomAuthorization]
[HttpPut]
[Route("onboarding")]
public async Task<IActionResult> UpdateOnboarding(OnboardingRequest model)
{
    if (string.IsNullOrWhiteSpace(model.Action))
        return BadRequest("Action is required.");

    var state = await userService.UpdateOnboardingAsync(
        CurrentUserId, model.Action, model.Mission);
    return Ok(state);
}
```

### Phase 3: Backend — Mission Completion Triggers

All three trigger services already inject `UserService` via their constructors — no DI changes needed. Just add the `TryCompleteMissionAsync` call inside each method.

#### 3.1 TimelineService — Storyline completion trigger

**File:** `cimplur-core/Memento/Domain/Repositories/TimelineService.cs`

`TimelineService` already has `UserService userService` in its constructor. In `AddTimeline`, add after `SaveChangesAsync`:

```csharp
// After await Context.SaveChangesAsync();
await userService.TryCompleteMissionAsync(currentUserId, "storyline");
```

#### 3.2 QuestionService — Question completion trigger

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

`QuestionService` already has `UserService userService` in its constructor. In `CreateQuestionSet`, add after `SaveChangesAsync`:

```csharp
// After await Context.SaveChangesAsync();
await userService.TryCompleteMissionAsync(userId, "question");
```

#### 3.3 MemoryShareLinkService — Share completion trigger

**File:** `cimplur-core/Memento/Domain/Repositories/MemoryShareLinkService.cs`

`MemoryShareLinkService` already has `UserService userService` in its constructor. In `CreateLinkAsync`, add after `SaveChangesAsync`:

```csharp
// After await Context.SaveChangesAsync();
await userService.TryCompleteMissionAsync(userId, "share");
```

### Phase 4: Frontend — Types & API Service

#### 4.1 Update TypeScript types

**File:** `fyli-fe-v2/src/types/index.ts`

Add `OnboardingState` interface and update `User`:

```typescript
export interface OnboardingState {
  firstMomentCompletedAt: string | null
  missionsDismissed: boolean
  completedMissions: string[]
}

export interface User {
  name: string
  email: string
  premiumMember: boolean
  privateMode: boolean
  canShareDate: string
  variants: Record<string, string>
  needsProfileCompletion: boolean
  onboardingState: OnboardingState | null
}
```

#### 4.2 Create onboarding API service

**File:** `fyli-fe-v2/src/services/onboardingApi.ts` (NEW)

```typescript
import api from './api'
import type { OnboardingState } from '@/types'

export function updateOnboarding(action: string, mission?: string) {
  return api.put<OnboardingState>('/users/onboarding', { action, mission })
}
```

#### 4.3 Update test fixture

**File:** `fyli-fe-v2/src/test/fixtures.ts`

Add `onboardingState: null` default to the `createUser` factory so `vue-tsc` doesn't fail when the `User` interface adds the required field:

```typescript
export function createUser(overrides: Partial<User> = {}): User {
	return {
		name: "Test User",
		email: "test@example.com",
		premiumMember: false,
		privateMode: false,
		canShareDate: "2025-01-01",
		variants: {},
		needsProfileCompletion: false,
		onboardingState: null,
		...overrides,
	};
}
```

#### 4.4 Update auth store

**File:** `fyli-fe-v2/src/stores/auth.ts`

Add computed properties for onboarding state:

```typescript
const needsFirstMoment = computed(
  () => user.value?.onboardingState != null
    && user.value.onboardingState.firstMomentCompletedAt == null
)

const onboardingState = computed(() => user.value?.onboardingState ?? null)
```

Add to the return statement:

```typescript
return {
  token, user, shareToken, isAuthenticated,
  needsProfileCompletion, needsFirstMoment, onboardingState,
  setToken, setShareToken, fetchUser, completeProfile, logout,
}
```

#### 4.4 Update router guard

**File:** `fyli-fe-v2/src/router/index.ts`

Update existing routes — replace the three onboarding routes with a single First Moment route:

```typescript
{
  path: '/onboarding/welcome',
  name: 'onboarding-welcome',
  component: () => import('@/views/auth/WelcomeView.vue'),
  meta: { auth: true, layout: 'public' },
},
{
  path: '/onboarding/first-moment',
  name: 'onboarding-first-moment',
  component: () => import('@/views/onboarding/FirstMomentView.vue'),
  meta: { auth: true, layout: 'public' },
},
```

Remove the old `onboarding-first-memory` and `onboarding-first-share` routes.

Update the router guard:

```typescript
router.beforeEach((to) => {
  const jwt = localStorage.getItem('token')

  if (to.meta.auth && !jwt) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }

  const auth = useAuthStore()

  // Force profile completion first
  if (auth.isAuthenticated && auth.needsProfileCompletion
      && to.name !== 'onboarding-welcome') {
    return { name: 'onboarding-welcome' }
  }

  // Then force First Moment flow
  if (auth.isAuthenticated && !auth.needsProfileCompletion
      && auth.needsFirstMoment
      && to.name !== 'onboarding-first-moment'
      && to.name !== 'onboarding-welcome') {
    return { name: 'onboarding-first-moment' }
  }

  // Prevent accessing onboarding after completion
  if (auth.isAuthenticated && !auth.needsProfileCompletion
      && to.name === 'onboarding-welcome') {
    return { path: '/' }
  }
})
```

#### 4.5 Update WelcomeView to navigate to First Moment

**File:** `fyli-fe-v2/src/views/auth/WelcomeView.vue`

Update `handleSubmit` to route to First Moment instead of stream:

```typescript
async function handleSubmit() {
  if (!name.value.trim()) {
    error.value = "Please enter your name.";
    return;
  }
  submitting.value = true;
  error.value = "";
  try {
    await auth.completeProfile(name.value.trim());
    // Route to First Moment flow if onboarding is active
    if (auth.needsFirstMoment) {
      router.replace("/onboarding/first-moment");
    } else {
      router.replace("/");
    }
  } catch (e: unknown) {
    error.value = getErrorMessage(e, "Something went wrong.");
  } finally {
    submitting.value = false;
  }
}
```

### Phase 5: Frontend — First Moment Flow

#### 5.1 Create FirstMomentView

**File:** `fyli-fe-v2/src/views/onboarding/FirstMomentView.vue` (NEW)

This is a multi-step view with 5 internal steps (0-4). Uses `layout: 'public'` so no app chrome is visible.

```vue
<template>
  <div class="d-flex justify-content-center align-items-center min-vh-100 p-3">
    <div class="first-moment-container">

      <!-- Step dots -->
      <nav
        v-if="step > 0 && step < 4"
        aria-label="Onboarding progress"
        class="text-center mb-4"
      >
        <span
          v-for="i in totalSteps"
          :key="i"
          class="d-inline-block rounded-circle mx-1 step-dot"
          :class="{ 'step-dot--active': i - 1 <= currentStepIndex }"
          :aria-label="`Step ${i} of ${totalSteps}${i - 1 <= currentStepIndex ? ' (completed)' : ''}`"
          role="img"
        ></span>
      </nav>

      <!-- Steps 0-3 use v-show for snappier transitions (DOM stays mounted) -->
      <!-- Step 4 uses v-if since it only renders after save -->

      <!-- Step 0: Welcome -->
      <div v-show="step === 0" class="step-panel text-center">
        <h2 class="fw-semibold mb-3">
          You're busy. We get it.
        </h2>
        <p class="text-muted mb-4 subtitle">
          Let's capture one moment in under 60 seconds.
        </p>
        <button class="btn btn-primary btn-lg px-5" @click="step = 1">
          Let's go
        </button>
      </div>

      <!-- Step 1: Prompt selection -->
      <div v-show="step === 1" class="step-panel">
        <h4 class="text-center mb-4">Pick a prompt, or write your own:</h4>
        <div class="d-flex flex-column gap-2">
          <button
            v-for="prompt in prompts"
            :key="prompt"
            class="btn btn-outline-primary text-start py-3 px-4"
            @click="selectPrompt(prompt)"
          >
            {{ prompt }}
          </button>
          <button
            class="btn btn-outline-secondary text-start py-3 px-4"
            @click="selectCustom"
          >
            Write your own
          </button>
        </div>
      </div>

      <!-- Step 2: Quick capture -->
      <div v-show="step === 2" class="step-panel">
        <h4 class="text-center mb-4">Capture your moment</h4>
        <textarea
          ref="captureTextarea"
          v-model="text"
          class="form-control mb-3"
          rows="5"
          :placeholder="placeholderText"
        ></textarea>

        <!-- File attachment -->
        <div class="mb-3">
          <label class="btn btn-outline-secondary btn-sm">
            <span class="mdi mdi-camera me-1"></span>
            Add a photo or video
            <input
              type="file"
              accept="image/*,video/*"
              class="d-none"
              @change="onFileChange"
            />
          </label>
          <div v-if="fileEntries.length > 0" class="mt-2 d-flex flex-wrap gap-2">
            <div
              v-for="entry in fileEntries"
              :key="entry.id"
              class="position-relative file-thumbnail"
            >
              <img
                v-if="entry.type === 'image'"
                :src="entry.previewUrl"
                class="rounded file-thumbnail-media"
              />
              <video
                v-else
                :src="entry.previewUrl"
                class="rounded file-thumbnail-media"
              ></video>
            </div>
          </div>
        </div>

        <div v-if="error" class="alert alert-danger py-2">{{ error }}</div>

        <div class="d-flex justify-content-between">
          <button class="btn btn-outline-secondary" @click="step = 1">
            Back
          </button>
          <button
            class="btn btn-primary"
            :disabled="!canProceedToPolish || polishing"
            @click="handlePolish"
          >
            <span v-if="polishing" class="spinner-border spinner-border-sm me-1"></span>
            {{ polishing ? "Polishing..." : "Next" }}
          </button>
        </div>
      </div>

      <!-- Step 3: AI polish -->
      <div v-show="step === 3" class="step-panel">
        <h4 class="text-center mb-4">Your moment, polished</h4>

        <!-- Original text -->
        <div class="mb-3">
          <label class="form-label text-muted small">What you wrote</label>
          <div class="p-3 rounded original-text">
            {{ text }}
          </div>
        </div>

        <!-- Polished text -->
        <div class="mb-4">
          <label class="form-label text-muted small">Polished by Fyli</label>
          <div v-if="!editing" class="card shadow-sm polished-card">
            <div class="card-body">
              {{ polishedText }}
            </div>
          </div>
          <textarea
            v-else
            v-model="editedText"
            class="form-control"
            rows="5"
          ></textarea>
        </div>

        <div v-if="error" class="alert alert-danger py-2">{{ error }}</div>

        <div class="d-flex flex-column gap-2">
          <button
            class="btn btn-primary"
            :disabled="saving"
            @click="usePolishedVersion"
          >
            <span v-if="saving" class="spinner-border spinner-border-sm me-1"></span>
            Use polished version
          </button>
        </div>
        <div class="d-flex flex-column gap-2 mt-2">
          <button
            class="btn btn-outline-secondary"
            :disabled="saving"
            @click="saveMemory(false)"
          >
            Keep my original
          </button>
          <button
            v-if="!editing"
            class="btn btn-link text-muted"
            @click="startEditing"
          >
            Edit
          </button>
          <button
            v-else
            class="btn btn-link text-muted"
            @click="saveEdit"
          >
            Done editing
          </button>
        </div>
      </div>

      <!-- Step 4: Celebrate (v-if — only mounts after save completes) -->
      <div v-if="step === 4" class="text-center">
        <div class="mb-3">
          <span
            class="mdi mdi-check-circle celebrate-icon"
          ></span>
        </div>
        <h3 class="mb-2">Your first moment is safe.</h3>
        <p class="text-muted mb-4">
          It's waiting for you in your stream.
        </p>
        <button class="btn btn-primary btn-lg" @click="goToStream">
          See my memories
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch, nextTick } from "vue"
import { useRouter } from "vue-router"
import { useAuthStore } from "@/stores/auth"
import { useStreamStore } from "@/stores/stream"
import { useFileUpload } from "@/composables/useFileUpload"
import { createDrop, getDrop } from "@/services/memoryApi"
import { getWritingAssist } from "@/services/writingAssistApi"
import { updateOnboarding } from "@/services/onboardingApi"
import { getErrorMessage } from "@/utils/errorMessage"

const router = useRouter()
const auth = useAuthStore()
const stream = useStreamStore()
const { fileEntries, onFileChange, uploadFiles } = useFileUpload()

// Step management
const step = ref(0)
const error = ref("")
const captureTextarea = ref<HTMLTextAreaElement | null>(null)

// Focus textarea when step 2 becomes visible (autofocus won't work with v-show)
watch(step, async (val) => {
  if (val === 2) {
    await nextTick()
    captureTextarea.value?.focus()
  }
})

// Step 1: Prompt selection
const prompts = [
  "Something funny your kid said recently",
  "A meal your family loved",
  "A moment you want to remember from this week",
]
const selectedPrompt = ref("")
const isCustomPrompt = ref(false)

// Step 2: Quick capture
const text = ref("")
const saving = ref(false)

// Step 3: AI polish
const polishing = ref(false)
const polishedText = ref("")
const editing = ref(false)
const editedText = ref("")

const placeholderText = computed(() => {
  if (isCustomPrompt.value) return "What moment do you want to remember?"
  return selectedPrompt.value || "What moment do you want to remember?"
})

const canProceedToPolish = computed(() => text.value.trim().length >= 10)

// Step indicators
const totalSteps = 4
const currentStepIndex = computed(() => Math.min(step.value, totalSteps - 1))

function selectPrompt(prompt: string) {
  selectedPrompt.value = prompt
  isCustomPrompt.value = false
  step.value = 2
}

function selectCustom() {
  isCustomPrompt.value = true
  selectedPrompt.value = ""
  step.value = 2
}

async function handlePolish() {
  if (!canProceedToPolish.value) return
  polishing.value = true
  error.value = ""
  try {
    const { data } = await getWritingAssist({ text: text.value.trim() })
    polishedText.value = data.polishedText
    step.value = 3
  } catch (e: unknown) {
    error.value = getErrorMessage(e, "Unable to polish. Please try again.")
  } finally {
    polishing.value = false
  }
}

function startEditing() {
  editedText.value = polishedText.value
  editing.value = true
}

function saveEdit() {
  polishedText.value = editedText.value
  editing.value = false
}

function usePolishedVersion() {
  if (editing.value) saveEdit()
  saveMemory(true)
}

async function saveMemory(usePolished: boolean) {
  saving.value = true
  error.value = ""
  try {
    const content = usePolished ? polishedText.value : text.value.trim()
    const now = new Date().toISOString().split("T")[0]!
    const { data: created } = await createDrop({
      information: content,
      date: now,
      dateType: 0,
      assisted: usePolished,
    })

    // Upload files if any
    if (fileEntries.value.length > 0) {
      await uploadFiles(fileEntries.value, created.dropId)
    }

    // Mark first moment complete
    await updateOnboarding("completeFirstMoment")
    await auth.fetchUser()

    // Prepend to stream
    const { data: drop } = await getDrop(created.dropId)
    stream.prependMemory(drop)

    step.value = 4
  } catch (e: unknown) {
    error.value = getErrorMessage(e, "Something went wrong saving your memory.")
  } finally {
    saving.value = false
  }
}

function goToStream() {
  router.replace("/")
}
</script>

<style scoped>
.first-moment-container {
  max-width: 600px;
  width: 100%;
}

.subtitle {
  font-size: 1.125rem;
}

/* Step dots */
.step-dot {
  width: 8px;
  height: 8px;
  background-color: var(--fyli-border);
}

.step-dot--active {
  background-color: var(--fyli-primary);
}

/* Step panels — fade transition when v-show toggles display */
.step-panel {
  transition: opacity 0.2s ease;
}

/* File thumbnails */
.file-thumbnail {
  width: 80px;
  height: 80px;
}

.file-thumbnail-media {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

/* AI polish — original vs polished text */
.original-text {
  background-color: var(--fyli-bg-light);
}

.polished-card {
  background-color: var(--fyli-primary-light);
}

/* Celebration animation */
.celebrate-icon {
  font-size: 3rem;
  color: var(--fyli-primary);
  animation: scale-in 0.4s ease-out;
}

@keyframes scale-in {
  from {
    transform: scale(0);
    opacity: 0;
  }
  to {
    transform: scale(1);
    opacity: 1;
  }
}
</style>
```

### Phase 6: Frontend — Mission Card Component

#### 6.1 Create MissionCard component

**File:** `fyli-fe-v2/src/components/onboarding/MissionCard.vue` (NEW)

```vue
<template>
  <!-- Resume link -->
  <div v-if="showResumeLink" class="text-center mb-3">
    <button class="btn btn-link text-muted small py-2 px-3" @click="resume">
      Resume getting started
    </button>
  </div>

  <!-- Mission card -->
  <div
    v-if="shouldShow"
    class="card mb-3 mission-card"
  >
    <div class="card-body position-relative">
      <!-- Dismiss button -->
      <button
        class="btn btn-link text-muted position-absolute dismiss-btn"
        aria-label="Dismiss getting started"
        @click="dismiss"
      >
        <span class="mdi mdi-close dismiss-icon"></span>
      </button>

      <!-- Progress -->
      <small class="text-muted">
        Getting Started &mdash; {{ completedCount }} of 3 complete
      </small>

      <!-- All complete celebration -->
      <div v-if="allComplete" class="mt-2">
        <p class="mb-0">
          You're all set. Capture moments as they happen &mdash; we'll be
          here.
        </p>
      </div>

      <!-- Just-completed celebration -->
      <div v-else-if="lastCompletedMission" class="mt-2">
        <div class="d-flex align-items-center gap-2">
          <span class="mdi mdi-check-circle completion-icon"></span>
          <p class="mb-0">{{ lastCompletedMission.completionMessage }}</p>
        </div>
      </div>

      <!-- Current mission -->
      <div v-else-if="currentMission" class="mt-2">
        <div class="d-flex align-items-start gap-3">
          <span
            class="mdi mission-icon"
            :class="currentMission.icon"
          ></span>
          <div class="flex-grow-1">
            <h6 class="mb-1">{{ currentMission.title }}</h6>
            <p class="text-muted small mb-2">
              {{ currentMission.description }}
            </p>
            <button
              class="btn btn-primary btn-sm"
              @click="currentMission.action()"
            >
              {{ currentMission.ctaLabel }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <!-- Toast (each component renders its own; a global ToastContainer
       could be added to AppLayout.vue in a future cleanup pass) -->
  <div
    v-if="toastMessage"
    class="position-fixed bottom-0 end-0 p-3 toast-wrapper"
  >
    <div class="toast show">
      <div class="toast-body">{{ toastMessage }}</div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from "vue"
import { useRouter } from "vue-router"
import { useAuthStore } from "@/stores/auth"
import { useStreamStore } from "@/stores/stream"
import { useToast } from "@/composables/useToast"
import { updateOnboarding } from "@/services/onboardingApi"

const router = useRouter()
const auth = useAuthStore()
const stream = useStreamStore()
const { toastMessage, showToast } = useToast(3000)
const justCompleted = ref<string | null>(null)
let autoDismissTimer: ReturnType<typeof setTimeout> | null = null

interface Mission {
  id: string
  icon: string
  title: string
  description: string
  ctaLabel: string
  completionMessage: string
  action: () => void
}

const missions: Mission[] = [
  {
    id: "storyline",
    icon: "mdi-book-open-page-variant",
    title: "Start a Storyline",
    description: "Organize memories around a person, place, or theme",
    ctaLabel: "Create Storyline",
    completionMessage:
      "Now you can curate memories for the people who matter most.",
    action: () => router.push("/storylines/new"),
  },
  {
    id: "question",
    icon: "mdi-comment-question-outline",
    title: "Ask a Question",
    description:
      "Ask someone to share a story — they don't need an account",
    ctaLabel: "Ask a Question",
    completionMessage:
      "When they answer, their story becomes a memory in your collection.",
    action: () => router.push("/questions"),
  },
  {
    id: "share",
    icon: "mdi-share-variant-outline",
    title: "Share a Memory",
    description: "Send a memory to someone with a private link",
    ctaLabel: "Share a Memory",
    completionMessage:
      "You're all set. Capture moments as they happen — we'll be here.",
    action: () => {
      if (stream.memories.length > 0) {
        router.push(`/memory/${stream.memories[0]!.dropId}`)
      } else {
        router.push("/")
      }
    },
  },
]

const state = computed(() => auth.onboardingState)

const completedCount = computed(
  () => state.value?.completedMissions.length ?? 0
)

const allComplete = computed(() => completedCount.value >= 3)

const isExpired = computed(() => {
  if (!auth.user) return true
  if (!state.value?.firstMomentCompletedAt) return false
  const firstMoment = new Date(state.value.firstMomentCompletedAt)
  const thirtyDaysLater = new Date(
    firstMoment.getTime() + 30 * 24 * 60 * 60 * 1000
  )
  return new Date() > thirtyDaysLater
})

const shouldShow = computed(
  () =>
    state.value != null &&
    state.value.firstMomentCompletedAt != null &&
    !state.value.missionsDismissed &&
    !allComplete.value &&
    !isExpired.value
)

const showResumeLink = computed(
  () =>
    state.value != null &&
    state.value.firstMomentCompletedAt != null &&
    state.value.missionsDismissed &&
    !allComplete.value &&
    !isExpired.value
)

const currentMission = computed(() => {
  if (!state.value) return null
  return (
    missions.find(
      (m) => !state.value!.completedMissions.includes(m.id)
    ) ?? null
  )
})

const lastCompletedMission = computed(() => {
  if (!justCompleted.value) return null
  return missions.find((m) => m.id === justCompleted.value) ?? null
})

async function dismiss() {
  try {
    await updateOnboarding("dismiss")
    await auth.fetchUser()
  } catch {
    showToast("Something went wrong. Please try again.")
  }
}

async function resume() {
  try {
    await updateOnboarding("resume")
    await auth.fetchUser()
  } catch {
    showToast("Something went wrong. Please try again.")
  }
}

// Detect newly completed missions by comparing previous state.
// No polling needed — StreamView.onMounted fetches fresh user
// state whenever the user navigates back to the stream after
// completing a mission on another page.
const previousCompleted = ref<string[]>([])

onMounted(async () => {
  await auth.fetchUser()

  const current = state.value?.completedMissions ?? []
  const newlyCompleted = current.filter(
    (m) => !previousCompleted.value.includes(m)
  )

  if (newlyCompleted.length > 0) {
    const completedMission = missions.find(
      (m) => m.id === newlyCompleted[0]
    )
    if (completedMission) {
      justCompleted.value = completedMission.id
      showToast(completedMission.completionMessage)
      setTimeout(() => {
        justCompleted.value = null
      }, 5000)
    }
  }

  previousCompleted.value = [...current]

  // Auto-dismiss after all complete
  if (allComplete.value) {
    autoDismissTimer = setTimeout(async () => {
      await dismiss()
    }, 5000)
  }
})

onUnmounted(() => {
  if (autoDismissTimer) clearTimeout(autoDismissTimer)
})
</script>

<style scoped>
.mission-card {
  border-left: 4px solid var(--fyli-primary);
}

.dismiss-btn {
  top: 0.5rem;
  right: 0.5rem;
  min-width: 44px;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.dismiss-icon {
  font-size: 1.25rem;
}

.mission-icon {
  font-size: 2rem;
  color: var(--fyli-primary);
}

.completion-icon {
  color: var(--fyli-primary);
  font-size: 1.5rem;
}

.toast-wrapper {
  z-index: 1050;
}
</style>
```

#### 6.2 Add MissionCard to StreamView

**File:** `fyli-fe-v2/src/views/stream/StreamView.vue`

Add the MissionCard import and place it above the memory list:

```vue
<script setup lang="ts">
// ... existing imports ...
import MissionCard from '@/components/onboarding/MissionCard.vue'
// ... rest of script ...
</script>

<template>
  <div>
    <ErrorState v-if="error" @retry="retry" />
    <template v-else>
      <!-- Mission card (onboarding Phase 2) -->
      <MissionCard />

      <EmptyState
        v-if="!stream.loading && stream.memories.length === 0"
        icon="mdi-book-open-page-variant-outline"
        message="No memories yet. Create your first one!"
        actionLabel="Create Memory"
        @action="router.push('/memory/new')"
      />
      <MemoryCard v-for="memory in stream.memories" :key="memory.dropId" :memory="memory" />
      <div ref="sentinel" style="height: 1px"></div>
      <LoadingSpinner v-if="stream.loading" />
    </template>
    <FloatingActionButton to="/memory/new" />
  </div>
</template>
```

### Phase 7: Cleanup & Polish

#### 7.1 Delete unused onboarding views

- Delete `fyli-fe-v2/src/views/onboarding/FirstMemoryView.vue`
- Delete `fyli-fe-v2/src/views/onboarding/FirstShareView.vue`

#### 7.2 Delete AddHelloWorldDrop method and clean up unused dependencies

- Remove `AddHelloWorldDrop` method from `DropsService.cs` (lines ~873-884)
- **`GoogleAuthService`**: Remove `DropsService dropsService` from constructor and the `dropsService` field. It is only used for `AddHelloWorldDrop` (line 128) — no other usages exist.
- **`UserController`**: Remove `DropsService dropsService` from constructor and the `dropService` field. It is only used for `AddHelloWorldDrop` (line 260) — no other usages exist.
- **`UserService`**: Keep `DropsService` — it is still used for `GetDrops` (line 463).
- **`QuestionService`**: Keep `DropsService` — it is used for other drop operations beyond `AddHelloWorldDrop`.
- **`TimelineShareLinkService`**: Check if `DropsService` is used for anything besides `AddHelloWorldDrop`. If not, remove it from the constructor.

#### 7.3 Remove old routes

Remove from router:
```typescript
// DELETE these routes:
{ path: '/onboarding/first-memory', ... },
{ path: '/onboarding/first-share', ... },
```

## Testing Plan

### Backend Tests

#### UserService Tests
1. `GetUser_ReturnsNullOnboardingState_ForExistingUsers` — users without `OnboardingState` field return null
2. `GetUser_ReturnsOnboardingState_WhenSet` — properly deserializes JSON
3. `InitializeOnboardingAsync_SetsEmptyState` — new user gets empty OnboardingState
4. `UpdateOnboardingAsync_CompleteFirstMoment_SetsTimestamp` — sets `firstMomentCompletedAt`
5. `UpdateOnboardingAsync_Dismiss_SetsMissionsDismissed` — sets `missionsDismissed = true`
6. `UpdateOnboardingAsync_Resume_ClearsMissionsDismissed` — sets `missionsDismissed = false`
7. `UpdateOnboardingAsync_CompleteMission_AddsMissionToList` — adds mission string
8. `UpdateOnboardingAsync_CompleteMission_NoDuplicates` — doesn't add same mission twice
9. `UpdateOnboardingAsync_InvalidAction_ThrowsBadRequest` — validates action input
10. `TryCompleteMissionAsync_NoOnboardingState_NoOps` — safe for existing users
11. `TryCompleteMissionAsync_CompletesNewMission` — adds mission when state exists
12. `CompleteProfileAsync_InitializesOnboarding_InsteadOfHelloWorldDrop` — no sample drop created

#### TimelineService Tests
13. `AddTimeline_TriggersStorylineMission` — calls TryCompleteMissionAsync

#### QuestionService Tests
14. `CreateQuestionSet_TriggersQuestionMission` — calls TryCompleteMissionAsync

#### MemoryShareLinkService Tests
15. `CreateLinkAsync_TriggersShareMission` — calls TryCompleteMissionAsync

### Frontend Tests

#### FirstMomentView Tests
1. `renders welcome screen on step 0`
2. `advances to prompt selection on "Let's go" click`
3. `advances to capture with selected prompt placeholder`
4. `advances to capture with custom prompt placeholder`
5. `disables Next button when text < 10 chars`
6. `calls writing assist API and shows polish step`
7. `saves with polished text when "Use polished version" clicked`
8. `saves with original text when "Keep my original" clicked`
9. `allows editing polished text`
10. `shows celebration step after save`
11. `navigates to stream on "See my memories"`

#### MissionCard Tests
12. `does not render when onboardingState is null`
13. `does not render when firstMomentCompletedAt is null`
14. `does not render when all missions complete`
15. `does not render when missions expired (30+ days)`
16. `shows current mission with correct icon, title, and CTA`
17. `dismisses and shows resume link`
18. `resumes from dismissed state`
19. `shows completion celebration message`

## Implementation Order

1. **Phase 1** — Backend data model (`OnboardingStateModel`, `UserProfile` field, migration)
2. **Phase 2** — Backend service methods (`UserService` onboarding methods, `AddHelloWorldDrop` removal)
3. **Phase 3** — Backend mission triggers (timeline, question, share link services)
4. **Phase 4** — Frontend types, API service, store updates, router guard
5. **Phase 5** — Frontend First Moment flow (`FirstMomentView.vue`)
6. **Phase 6** — Frontend Mission Card (`MissionCard.vue`, StreamView integration)
7. **Phase 7** — Cleanup (delete old views/routes, remove dead code)
