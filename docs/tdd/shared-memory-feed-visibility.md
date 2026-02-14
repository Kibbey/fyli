# TDD: Shared Memory Feed Visibility Bug

## Problem Statement

When a user creates a memory and shares it (to "All Connections" or specific people), the shared memory does **not** appear in their connections' main feed. Additionally, question answers granted via `UserDrop` records also don't appear.

## Root Cause Analysis

There are **two layered bugs**:

### Bug 1: Frontend hardcodes `includeMe: true` (PRIMARY CAUSE)

**File:** `fyli-fe-v2/src/services/memoryApi.ts:10-12`

```typescript
export function getDrops(skip = 0) {
  return api.get<DropsResponse>('/drops', { params: { skip, includeMe: true } })
}
```

The `includeMe` parameter is always sent as `true`. In the backend's `FilterPeople` method (`DropsService.cs:490-499`):

```csharp
private IQueryable<Drop> FilterPeople(List<int> people, int currentUserId, IQueryable<Drop> drops, bool me)
{
    if (people == null) people = new List<int>();
    if (!people.Any() && !me) return drops;  // ← only this path returns ALL drops
    me = !people.Any() || me;
    return drops.Where(x => people.Contains(x.CreatedBy.UserId) || (me && x.UserId == currentUserId));
}
```

When `people=[]` and `me=true`:
- The early return (`!people.Any() && !me`) is skipped because `me` is `true`
- The filter becomes `x.UserId == currentUserId` — **only the user's own drops**
- All shared drops from connections are excluded

The old frontend (`fyli-fe`) passed `$scope.filters.me` which defaulted to `false` (from `UserProfile.Me`), meaning the main feed showed all visible drops.

### Bug 2: `GetAllDrops` didn't check `UserDrops` (ALREADY FIXED)

This was fixed earlier in this session — `GetAllDrops` now includes `x.OtherUsersDrops.Any(ud => ud.UserId == userId)`.

## Fix

### Phase 1: Backend Test — Validate the bug exists

Add integration tests to `FeedVisibilityTest.cs` that prove:
1. Shared drops from connections appear via `GetAllDrops` (already works via `CanView`)
2. Shared drops from connections are **filtered out** by `GetDrops` when `includeMe=true` and `people=[]`
3. Shared drops from connections appear via `GetDrops` when `includeMe=false` and `people=[]`
4. Question answer drops (via `UserDrop`) appear in `GetDrops` when `includeMe=false`

### Phase 2: Frontend Fix

Remove the hardcoded `includeMe: true` from the default `getDrops` call.

**File:** `fyli-fe-v2/src/services/memoryApi.ts`
```typescript
// Before:
export function getDrops(skip = 0) {
  return api.get<DropsResponse>('/drops', { params: { skip, includeMe: true } })
}

// After:
export function getDrops(skip = 0) {
  return api.get<DropsResponse>('/drops', { params: { skip } })
}
```

This causes `includeMe` to default to `false` in the backend (`model.IncludeMe ?? false`), which hits the `!people.Any() && !me` early return in `FilterPeople`, returning all visible drops unfiltered.

Note: The controller also calls `UpdateMe(currentUserId, includeMe)` which persists the value on `UserProfile.Me`. So the current code is also corrupting the user's stored preference to `true` on every feed load.

## Test Plan

### New Tests in `FeedVisibilityTest.cs`

```
Test 1: SharedDrop_AppearsInConnectionFeed_WhenNoFiltersApplied
  - Connect User A ↔ User B
  - User A creates a drop tagged to "All Connections"
  - Call GetDrops(userB, albumIds=[], people=[], me=false)
  - Assert: User A's drop appears in the results

Test 2: SharedDrop_FilteredOut_WhenIncludeMeTrue
  - Connect User A ↔ User B
  - User A creates a drop tagged to "All Connections"
  - Call GetDrops(userB, albumIds=[], people=[], me=true)
  - Assert: User A's drop does NOT appear (documents the bug)

Test 3: GrantedAccessDrop_AppearsInFeed_WhenNoFiltersApplied
  - User A creates a drop (no tags)
  - Grant User B access via UserDrop
  - Call GetDrops(userB, albumIds=[], people=[], me=false)
  - Assert: The drop appears in the results

Test 4: OwnDrop_AlwaysAppearsInFeed_RegardlessOfFilter
  - User A creates a drop tagged to "All Connections"
  - Call GetDrops(userA, albumIds=[], people=[], me=false)
  - Assert: Own drop appears
  - Call GetDrops(userA, albumIds=[], people=[], me=true)
  - Assert: Own drop still appears
```

### Implementation Order

1. Write backend tests (Phase 1)
2. Fix frontend (Phase 2)
3. Verify all tests pass
