# Investigation: Comment Photo Upload Fails on Other Users' Posts

**Status:** ✅ Resolved
**Date opened:** 2026-03-14
**Date resolved:** 2026-03-14

## Problem Statement

Users can upload photos when commenting on their own posts, but photo uploads silently fail when commenting on another user's post. The comment text is saved successfully — only the file upload breaks.

## Evidence

- User reports: commenting with photos works on own posts, fails on others' posts
- Comment text is always saved successfully (the comment itself is created)
- The upload appears to hang/never finish from the UI perspective
- Frontend silently catches upload errors (`CommentList.vue:53` — empty catch block)

## Root Cause

**Divergent permission logic between `DropsService.GetAllDrops` and `PermissionService.GetAllDrops`.**

### `DropsService.GetAllDrops` (line 481-488) — used by `AddComment`:

```csharp
var drops = Context.Drops.Where(x =>
    (x.TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
    || x.UserId == userId
    || x.OtherUsersDrops.Any(ud => ud.UserId == userId)));  // ← PRESENT
```

### `PermissionService.GetAllDrops` (line 28-34) — used by `ImageService.DropImageId`:

```csharp
var drops = Context.Drops.Where(x =>
    (x.TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
    || x.UserId == userId));
    // ← MISSING: OtherUsersDrops check
```

The `PermissionService` is missing the `|| x.OtherUsersDrops.Any(ud => ud.UserId == userId)` condition. When a user has access to another user's drop via the `UserDrop` table (but not through `TagDrop`/`TagViewer`):

1. `DropsService.CanView` → **true** → comment creation succeeds
2. `PermissionService.CanView` → **false** → `NotAuthorizedException` thrown in `ImageService.DropImageId`
3. Frontend catch block in `CommentList.vue:53` silently swallows the error

### Call chain for photo upload:

1. `ImageController.PostFormData` → `imageService.Add(file, CurrentUserId, dropId, commentId)`
2. `ImageService.Add` → `AddWithId` → `DropImageId(dropId, userId, commentId)`
3. `ImageService.DropImageId` → `permissionService.CanView(userId, dropId)` → **FAILS**

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | `PermissionService.GetAllDrops` missing `OtherUsersDrops` check | 9/10 | ✅ Confirmed |

## Investigation Log

### Round 1 — Testing H1

**Test performed:** Compared `GetAllDrops` in `DropsService` (line 481) vs `PermissionService` (line 28). Traced the call chain from frontend upload through backend permission checks.

**Findings:**
- `DropsService.GetAllDrops` includes three conditions: TagDrops viewers, owner, AND `OtherUsersDrops`
- `PermissionService.GetAllDrops` only includes two: TagDrops viewers and owner
- Comment creation uses `DropsService.CanView` (passes for shared drops)
- Image upload uses `PermissionService.CanView` via `ImageService.DropImageId` (fails for drops shared via `UserDrop`)
- The `NotAuthorizedException` is thrown but silently caught by the frontend

**Conclusion:** ✅ Confirmed

## Resolution

**Root Cause:** `PermissionService.GetAllDrops` is missing the `OtherUsersDrops` condition that `DropsService.GetAllDrops` has, causing photo uploads to fail with a permission error for drops shared via the `UserDrop` table.

**Recommended Action:** Add the missing `OtherUsersDrops` check to `PermissionService.GetAllDrops`:

```csharp
private IQueryable<Drop> GetAllDrops(int userId)
{
    DateTime now = DateTime.UtcNow.AddHours(1);
    var drops = Context.Drops.Where(x => (x.TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
        || x.UserId == userId
        || x.OtherUsersDrops.Any(ud => ud.UserId == userId)));
    return drops;
}
```

**Additional note:** `PermissionService.CanView` is also used by `PermissionService.DropImageId` (line 36) and `PermissionService.DropMovieId` (line 55), so this fix will also resolve video upload issues for the same scenario.

**Secondary issue found:** `DropsService.GetComments` (line 814) has swapped arguments: `CanView(dropId, currentUserId)` — passing `dropId` as `userId` and `currentUserId` as `dropId`. This is a separate bug that should be fixed.
