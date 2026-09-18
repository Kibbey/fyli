# Storyline feed: optional query hardening

**Status:** ⚠️ **SUPERSEDED IN PART 2026-09-17.** The permission rewrite this doc parks has been measured, built and tested — see *Phase 2 — UN-PARKED* below. Phase 0a/1 (storyline drive-order) remain optional and unstarted.
**Date:** 2026-09-09 (updated after red-team review)
**Related:** `docs/investigations/2026-09-09-gettimeline-sql-timeout.md`
**Prod indexes:** already applied via `docs/migrations/AddMissingGetTimelineIndexes.sql`

The storyline page (`GET /api/drops/timelines/{id}`) timed out in production. **Indexes plus a SQL reboot recovered it.** That is the incident fix. This doc is optional hardening so the query stays cheap if data grows.

**Who can see a memory must not change.** No API changes. No frontend changes. No new tables.

A review of the first draft found several proposed changes that would not help, or would make other screens worse. Those are parked at the bottom. What remains is: **prove the current SQL, then maybe root the storyline (and album) query at the membership table.**

---

## In plain English

### What already happened

We added missing database indexes (lookup by owner, by storyline membership, by granted access, by photos/videos/comments). We restarted SQL Server, which also cleared a stale query plan. The timeouts stopped.

### What we might still do

Today the storyline query is: “all memories this person can see, that also happen to be on this storyline.” After indexes, SQL Server may already start from the storyline list. **We do not know until we look at the actual SQL.**

If that capture still shows a walk over all visible memories, we change the question to: “memories on this storyline, that this person is allowed to see” — same answer, different starting point. Same for albums.

| Helps | Hurts |
|-------|--------|
| Only if the capture still shows the slow shape | If we forget the permission check, people would see storyline memories they should not |
| Touches only storyline and album feeds, not the home feed | Does not speed up the home feed |
| Empty storyline still returns empty | If we download every storyline memory id into the app first, a huge storyline gets slower. Keep it one database question |

**Risk:** Low if permission stays in the query and we do not download id lists into the app. **Value:** Unknown until Phase 0. If the plan already starts at the storyline table, **stop. Do not ship a rewrite.**

### What we will not do (and why)

| Idea from the first draft | Why it is out |
|---------------------------|----------------|
| Rewrite “who can see what” as three lists combined for the whole app | Home feed, albums, export (`take: 500`), and “can I open this?” all share that rule. Building the **full** list of visible memories on every request can make those slower. The timeout was storyline-only |
| Check “can I open this memory?” with three separate database round trips | Today that is already one check on that one memory. Three trips is slower when the answer is no (common) |
| “Read only” flag on the card query | The card query already copies into a card object. The database is not tracking rows to save. The flag does nothing here |
| Skip tag lookup when the storyline asks for no tags | Empty tag list already means “no tags.” Splitting the big copy-into-card step in two is extra code for almost no gain |
| Load photos/comments as several small questions | That pattern is used elsewhere for a different style of load. On this query it can attach the wrong photo to a comment. Not worth it unless the feed times out again |
| Delete the “also load related rows” lines (`Include`) | Added in the EF6 → EF Core port. `Edit` / `Delete` / `AddComment` still need that style of load. Leave `MapDrops` Includes alone |
| Cite public invite preview as the same idea | That path loads 20 ids **without** the usual permission check. Do not copy it |

### What we will not do (product)

- Raise the 30-second timeout and call it fixed.
- Change who can see a memory.
- Change the JSON (`drops`, `skip`, `done`, empty `tags` on storyline).
- Replace skip/take paging.
- Add a “must be a storyline follower” check to this endpoint. **It does not have one today.** Metadata `GET /timelines/{id}` does. Mixing that in would hide memories from people who can see the memory but are not followers.

### Order

1. Capture SQL / plan for the current storyline query (and album if easy).
2. If it already starts at `TimelineDrops` (or `AlbumDrops`), **done.**
3. If not, write tests that lock who sees what, then rewrite only those two methods so membership is the root, permission still applies.

---

## Current code

```
GET /api/drops/timelines/{id}
  DropController.GetTimeline   -- no storyline membership check
    DropsService.GetTimelineDrops
      GetAllDrops(userId)                          -- 3-way OR (owner / group / grant)
        .Where(x => x.TimelineDrops.Any(timelineId))
        MapDrops(..., take: 50, tagIds: [])
```

`GetAlbumDrops` is the same with `AlbumDrops`. `GetDrops` (home feed) uses `GetAllDrops` + `MapDrops` with `take: 15` and real tag ids. Leave it alone.

`GetAllDrops` (copied in `DropsService` and `PermissionService`):

```
TagDrops.Any(t => t.UserTag.TagViewers.Any(userId))
OR UserId == userId
OR OtherUsersDrops.Any(userId)
```

`CanView` is `GetAllDrops(userId).Any(x => x.DropId == dropId)` — one SQL `EXISTS` on that drop. Leave it.

Hard constraint after any rewrite: **same set of drop ids** for the same user and storyline/album. Order is only well-defined where dates are unique — see the finding below.

---

## Separate finding — paging can duplicate or drop memories (unstable sort)

Found while writing the characterization tests. **This is a live user-facing bug, independent of the timeout and of everything else in this TDD.** It is worth fixing on its own even if Phase 0a says ship nothing.

`MapDrops` orders by `Date` with **no tie-breaker**:

```csharp
dropInclude = ascending ? dropInclude.OrderBy(o => o.Date) : dropInclude.OrderByDescending(o => o.Date);
```

Under `OFFSET/FETCH`, an unstable sort has no stable page boundary. SQL Server may order tied rows differently between the query for page 1 and the query for page 2, so a memory with a tied `Date` can be **returned on both pages, or skipped entirely**.

This is not theoretical here: `Date` is user-entered and frequently coarse. Every memory a user dated "1998" with no month or day shares a `Date`. A long storyline built from scanned photos can have dozens of ties in one page window.

**Fix — add a deterministic tie-breaker:**

```csharp
dropInclude = ascending
    ? dropInclude.OrderBy(o => o.Date).ThenBy(o => o.DropId)
    : dropInclude.OrderByDescending(o => o.Date).ThenByDescending(o => o.DropId);
```

This does **not** violate the backwards-compatibility constraint. It returns the same set of drops and makes an order that is currently nondeterministic deterministic — strictly better. Ties currently resolve arbitrarily; after the fix they resolve by insertion order, which is the intuitive reading of "same date."

It touches `MapDrops`, so it affects the home feed and albums too — the same latent bug exists on both.

**Test:**

| Test | Arrange | Assert |
|------|---------|--------|
| `MapDrops_TiedDates_PagesWithoutDuplicatesOrGaps` | 60 drops on a storyline, **all with the identical `Date`** | Page 1 (50) ∪ page 2 (10) = all 60 distinct ids, no id on both pages. Expected to **fail on `main`** — this is the regression test for the fix, not a characterization test |

Note this is the one test in this document that is *supposed* to fail before the change. Every other test in Phase 0b must pass on `main` first.

---

## Phase 0 — Prove the current SQL (gate)

Do this before writing a rewrite.

### 0a. Capture

Add a short-lived log or a local test that prints:

```csharp
GetAllDrops(userId)
    .Where(x => x.TimelineDrops.Any(a => a.TimelineId == timelineId))
    .OrderBy(x => x.Date)
    .Skip(0).Take(50)
    .Select(s => s.DropId)
    .ToQueryString()
```

Same for albums with `AlbumDrops`.

On prod or a restore, if possible: actual execution plan for that SQL with a real user/storyline from the 2026-09-09 incident.

**Look for**

| If you see | Then |
|------------|------|
| Seek/scan on `TimelineDrops` with `(TimelineId, DropId)`, then join `Drops` | **Stop.** Indexes did the job. Do not rewrite. |
| Clustered scan of `Drops` (or of all visible drops) before the storyline filter | Continue to Phase 1. |
| Sort of a huge set, then `OFFSET/FETCH 50` | Rewrite still worth it; membership-root should shrink the sort. |

Save the captured SQL (sanitized, no emails) next to this TDD or in the investigation log.

### 0b. Characterization tests (only if Phase 1 is needed)

**New file:** `cimplur-core/Memento/DomainTest/Repositories/TimelineFeedPerformanceTest.cs`

Setup like `FeedVisibilityTest`: `CreateTestContext()` (no transaction), `DetachAllEntities` before service calls, `TestServiceFactory.CreateDropsService`. `[TestCategory("Integration")]`.

Do **not** require `TimelineService.AddTimeline` / `TimelineUser` unless the test is about adding a drop through `TimelineService.AddDropToTimeline` (that path checks storyline access). For feed tests, use `CreateTestTimeline` + `AddDropToTimeline` on the test context.

Give every drop a **distinct `Date`** (`CreateTestDrop(..., date: ...)`). Otherwise paging tests flake — because of the real bug documented in *Separate finding — paging can duplicate or drop memories* above. Distinct dates work around it for these tests; they do not fix it.

Do **not** re-write `CanView` cases; `PermissionServiceTest` and `FeedVisibilityTest` already cover owner / stranger / tag / `UserDrop`.

| Test | Arrange | Assert |
|------|---------|--------|
| `GetTimelineDrops_OwnerSeesOwnDropOnTimeline` | A owns drop on A's storyline | A's list contains it |
| `GetTimelineDrops_ViewerSeesTagSharedDropOnTimeline` | A shares a group with B; drop tagged to that group, on the storyline | B sees it; C does not |
| `GetTimelineDrops_ViewerSeesUserDropGrantedMemoryOnTimeline` | A's untagged drop on the storyline; `UserDrop` grants B | B sees it; C does not |
| `GetTimelineDrops_OtherUserDoesNotSeePrivateDropOnTimeline` | A's private drop on the storyline; B has no tag/`UserDrop` | B's list does not include it; A still sees it. **Do not** describe B as a “follower” — follower status is irrelevant to this endpoint |
| `GetTimelineDrops_DropOnOtherTimeline_NotReturned` | Drop on storyline 1, query storyline 2 | Not in the list |
| `GetTimelineDrops_EmptyTimeline_ReturnsEmptyAndDone` | No drops | `drops` empty, `done` true, `skip` unchanged |
| `GetTimelineDrops_DropOnTwoTimelines_AppearsOnBoth` | Same drop on two storylines | Each query returns it |
| `GetTimelineDrops_OrdersByDate_AscendingAndDescending` | Dates D1 < D2 < D3 | `ascending: true` → D1,D2,D3; `false` → D3,D2,D1 |
| `GetTimelineDrops_SkipTake_PagesWithoutDuplicates` | 60 drops, **unique dates** | Page 1: 50, `skip` 50, `done` false. Page 2: remaining 10, no overlap, `done` true |
| `GetTimelineDrops_SameDropMatchingOwnerAndTag_AppearsOnce` | Owner tagged their own drop | Exactly one card |
| `GetTimelineDrops_TagsEmpty_WhenNoTagIdsPassed` | Drop has tags | `Tags` is empty, not null (today's contract) |
| `GetTimelineDrops_CommentImageNotCountedAsDropImage` | 2 drop images, 1 comment image, 1 movie, 2 comments | Drop images exclude the comment image; that comment has the image; movie present |

Album: only the visibility/empty/order cases that matter (`GetAlbumDrops_OwnerSeesOwnDrop`, `GetAlbumDrops_OtherUserDoesNotSeePrivateDrop`, `GetAlbumDrops_OrdersByDate`). Do not clone all ten storyline tests.

These tests must pass on **current `main`** before the rewrite.

```bash
cd cimplur-core/Memento
dotnet test DomainTest/DomainTest.csproj --filter "FullyQualifiedName~TimelineFeedPerformanceTest|FullyQualifiedName~FeedVisibilityTest"
```

---

## Phase 1 — Root at membership (only if Phase 0a says so)

### Files

| File | Change |
|------|--------|
| `cimplur-core/Memento/Domain/Repositories/DropsService.cs` | `GetTimelineDrops`, `GetAlbumDrops` only |
| `cimplur-core/Memento/DomainTest/Repositories/TimelineFeedPerformanceTest.cs` | Phase 0b |

No controller, API, frontend, `GetAllDrops`, `CanView`, or `MapDrops` changes.

### Why not `Contains(subquery)`

This is **not** enough (first draft). It is the same question as today's `TimelineDrops.Any(...)`, and SQL Server often writes the same plan:

```csharp
// STILL rooted at Drops + permission. Do not ship this as the fix.
var ids = Context.TimelineDrops.Where(td => td.TimelineId == timelineId).Select(td => td.DropId);
var drops = GetAllDrops(currentUserId).Where(x => ids.Contains(x.DropId));
```

The rewrite writes `FROM TimelineDrops` and applies the same permission filter on top.

**Be honest about what that buys.** It changes the generated SQL text, not the plan. SQL Server reorders joins freely, so writing `FROM TimelineDrops` does **not** pin the driving table any more than `IN (subquery)` did — the optimizer may still choose to drive from `Drops`. Rooting at membership makes the cheap plan easier to find and gives the optimizer better cardinality information; it does not guarantee it.

This is exactly why the after-capture in Phase 1 is not optional. **Do not treat "the SQL text now starts at `TimelineDrops`" as success.** Success is the captured plan being cheaper. If it is not, revert.

### Implementation

Keep `GetAllDrops`. Do **not** `.ToList()` membership ids.

**The permission rule must not be copied.** It already exists in two places (`DropsService.cs:481`, `PermissionService.cs:28`). A third hand-maintained copy is the highest-risk change in this document — `CLAUDE.md` requires access to drops to be 100% backwards compatible, and "keep these three copies byte-for-byte identical" is a comment, not a mechanism. Compose `GetAllDrops`; do not inline the OR.

```csharp
public async Task<DropViewModel> GetTimelineDrops(
    int currentUserId, int timelineId, int skip, bool ascending)
{
    int take = 50;
    if (skip <= 0) skip = 0;

    // Root at membership, reuse the existing permission rule. One copy.
    var drops = Context.TimelineDrops
        .Where(td => td.TimelineId == timelineId)
        .Join(GetAllDrops(currentUserId),
              td => td.DropId,
              d  => d.DropId,
              (td, d) => d);

    var model = new DropViewModel();
    model.Drops = await MapDrops(
        drops, take, currentUserId, skip, new List<long>(), true, ascending);
    model.Skip = model.Drops.Any() ? skip + take : skip;
    model.Done = model.Drops.Count < take;
    return model;
}
```

**If `Join` will not translate,** extract the predicate once and share it — still one definition, two callers:

```csharp
// DropVisibility.cs (or beside GetAllDrops) — the ONLY definition of the rule.
public static Expression<Func<Drop, bool>> CanSee(int userId) =>
    d => d.UserId == userId
      || d.OtherUsersDrops.Any(ud => ud.UserId == userId)
      || d.TagDrops.Any(t => t.UserTag.TagViewers.Any(v => v.UserId == userId));

// GetAllDrops in BOTH services becomes:
private IQueryable<Drop> GetAllDrops(int userId) => Context.Drops.Where(CanSee(userId));

// GetTimelineDrops:
var drops = Context.TimelineDrops
    .Where(td => td.TimelineId == timelineId)
    .Select(td => td.Drop)
    .Where(CanSee(currentUserId));
```

This is *not* the parked `DropVisibility` union rewrite — the predicate is unchanged, it just stops being duplicated. If even that will not translate, **stop and revert.** Do not paste the OR inline as a third copy.

`GetAlbumDrops`: same shape, rooted at `Context.AlbumDrops.Where(ad => ad.AlbumId == albumId)`.

### `GetAlbumDrops` — preserve the `take` parameter

Its signature is `GetAlbumDrops(int currentUserId, int albumId, int skip, bool ascending, int take = 50)`. **`ExportService.cs:26` calls it with `take: 500`.** The `GetTimelineDrops` snippet above hardcodes `int take = 50` because that method has no `take` parameter — do **not** carry that line into `GetAlbumDrops`.

Hardcoding 50 there silently truncates every album export from 500 memories to 50. No existing test covers it. Add one:

| Test | Assert |
|------|--------|
| `GetAlbumDrops_RespectsTakeParameter` | 60 drops in an album, `take: 500` → all 60 returned, `done` true. Must pass on `main` before and after Phase 1 |

After the rewrite, capture `ToQueryString()` again. Confirm `FROM TimelineDrops` (or `AlbumDrops`) with a seek on `TimelineId` / `AlbumId`. If the new SQL is not clearly cheaper, **revert.**

### Must not

- Filter only on `Drop.TimelineId` (first storyline, not membership).
- `.ToList()` ids in C#, then `Contains`.
- Skip the permission predicate.
- Call `HasAccess` / require `TimelineUser` (behavior change).
- Replace `GetAllDrops` globally.
- Change `CanView` to three round trips.

### Tests

Phase 0b green on the rewrite. `FeedVisibilityTest` still green (home feed untouched).

Diff is only `GetTimelineDrops` / `GetAlbumDrops` (plus the new test file).

### Done when

- Phase 0a captured SQL **before and after**.
- After SQL starts at `TimelineDrops` / `AlbumDrops` and 0b is green.
- Or: after SQL was already good in 0a, and **no code shipped**.

---

## Parked (do not implement in this TDD)

### ~~Global "visible ids" union (`DropVisibility` / new `GetAllDrops`)~~ — ✅ UN-PARKED AND BUILT

**This section's reasoning was wrong and is superseded. See "Phase 2 — UN-PARKED" below.**

It was parked on two premises, both since falsified by production telemetry
(investigation Rounds 3–5):

| Premise | Reality |
|---|---|
| "The timeout was storyline-only" | The **home feed** is the slowest endpoint in production (~25s, six samples) |
| "Would compute every visible id for every feed. Hurts home feed and album export" | It makes the home feed **533x cheaper in logical reads**, not more expensive |

The remaining warnings in the original text were right and were followed: never `.ToList()`
the ids, never `Concat`.

### `CanView` as three `Any()` calls

Today is one `EXISTS` on that drop. Three round trips is a miss-path regression (`Drop`, `Thank`, `AddComment`, `DropImageId`). Leave `CanView` / `PermissionService.GetAllDrops` as they are.

### `AsNoTracking` on `MapDrops`

`MapDrops` already `Select`s into `DropModel`. Nothing is tracked. No-op.

### Skip empty `tagIds` by duplicating `Select`

Empty `Contains` in EF Core 9 is already a constant false. Not why we timed out.

### `AsSplitQuery` on `MapDrops`

`QuestionService` uses it on `Include` graphs, not on filtered collection projections (`Images.Where(CommentId == null)`). Risk of wrong child rows. Only revisit if the feed times out **after** Phase 1 and a profiler points at the card projection.

### Removing `Include`s on `MapDrops`

EF6 → EF Core port. `Edit` / `Delete` / `AddComment` (`1847475`) still need Includes when they load entities and walk them in C#. Out of scope.

### `GetDropsByIds` card-shape test

That method does **not** use `GetAllDrops`, passes real tag ids, and sorts by `Date` (not input order). It does not lock storyline behavior.

---

## Phase 2 — UN-PARKED: permission rewrite (BUILT 2026-09-17)

### Why it moved out of Parked

`EXPLAIN`-level measurement of the production home-feed query (investigation Round 5):

| | Before | After | Change |
|---|---|---|---|
| Logical reads (15 rows) | ~68,800 | **129** | **533x fewer** |
| `UserDrops` scan count | 2,128 | **1** | per-row evaluation gone |
| `NetworkViewers` scan count | 2,133 | **1** | per-row evaluation gone |
| `UserNetworks` reads | 29,844 | **0** | drops out of the plan entirely |
| CPU time | 26 ms | ~1 ms | floor-limited at local data size |

`CPU time == elapsed time` on the original, so it is pure CPU burn — which also rules out
any instance upgrade as a fix (see Round 4).

### What was built

**New:** `Domain/Repositories/DropVisibility.cs` — the single definition of the rule.

```csharp
public static IQueryable<int> VisibleDropIds(StreamContext context, int userId)
{
    var owned   = context.Drops.Where(d => d.UserId == userId).Select(d => d.DropId);

    var tagged  = from viewer in context.NetworkViewers
                  where viewer.UserId == userId
                  join tagDrop in context.NetworkDrops
                     on viewer.UserTagId equals tagDrop.UserTagId
                  select tagDrop.DropId;

    var granted = context.UserDrops.Where(ud => ud.UserId == userId).Select(ud => ud.DropId);

    return owned.Union(tagged).Union(granted);   // Union, never Concat
}

public static IQueryable<Drop> VisibleDrops(StreamContext context, int userId)
{
    var visibleIds = VisibleDropIds(context, userId);
    return context.Drops.Where(drop => visibleIds.Contains(drop.DropId));
}
```

`GetAllDrops` in **both** `DropsService` and `PermissionService` now delegates to it — the rule
exists in one place instead of two copies. `CanView` is untouched.

### ⚠️ `Contains`, not `Join` — this doc predicted the failure

The first attempt used `.Join(...)`. All feed tests failed with:

```
InvalidOperationException: Unable to translate a collection subquery in a projection
since either parent or the subquery doesn't project necessary information required to
uniquely identify it...
```

`MapDrops` projects nested collections (Images, Movies, Comments with their own media). EF Core
can only correlate those when `Drops` is the **root** entity; a `Join` makes it a join output.

This doc's parked text already said exactly this — *"combine **ints**, then `Where(id in …)`,
then `MapDrops`"* — and it was right. Switching to `Contains` fixed all 25 failures, and
measured slightly **better** than `Join` (129 vs 139 reads).

### Test results

- **Phase 0b characterization tests written first**: 18 new tests in
  `DomainTest/Repositories/TimelineFeedPerformanceTest.cs`, **green on unmodified `main`** before
  any production code changed.
- After the rewrite: **40/40** on `TimelineFeedPerformanceTest` + `FeedVisibilityTest` +
  `PermissionServiceTest`.
- Full suite: **416 passed, 3 failed** — the 3 are `AdminServiceTest` / `AskServiceTest`, part of
  an unrelated in-progress admin feature, and are test-isolation failures (leftover
  `ExternalLogins` and admin rows in the shared local database). Neither service references
  `GetAllDrops`, `DropsService`, or `DropVisibility`.

### Known limits

- **Equivalence is sampled, not exhaustive.** A 30-user comparison (15 most-active + 15 random)
  of the full visible set showed 0 lost / 0 leaked / 0 duplicates. An all-users comparison was
  attempted and **killed the local SQL Server session** — because the *original* query is
  O(users × drops). Running it against a production restore was explicitly skipped.
- **The sort is unchanged.** `ORDER BY Created DESC` with `OFFSET/FETCH` still sorts the whole
  visible set per page, and `Drops.Created` has no index. That is the next ceiling, and it is the
  keyset-pagination item still listed as out of scope.

---

## Implementation order

| Step | Work | Stop if |
|------|------|---------|
| 0a | `ToQueryString()` / plan for current storyline (and album) query | Plan already seeks `TimelineDrops` by `TimelineId` — **no code** |
| 0b | Characterization tests with unique dates | Tests fail on `main` — fix tests, not product |
| 1 | Root `GetTimelineDrops` / `GetAlbumDrops` at membership; same permission rule (compose `GetAllDrops`, never inline a third copy of the OR); preserve `GetAlbumDrops`'s `take` | New SQL is not cheaper — revert |
| * | **Independent:** `ThenBy(DropId)` tie-breaker in `MapDrops` | Ship regardless of 0a — not gated on anything in this TDD |
| — | Full filter: `TimelineFeedPerformanceTest` + `FeedVisibilityTest` + `DropsServiceTest` | Any visibility test fails |

```bash
cd cimplur-core/Memento
dotnet test DomainTest/DomainTest.csproj --filter "FullyQualifiedName~TimelineFeedPerformanceTest|FullyQualifiedName~FeedVisibilityTest|FullyQualifiedName~DropsServiceTest"
```

---

## Rollback

Phase 1 is two methods. Revert that commit. Indexes stay. No schema rollback. If Phase 0a said stop, there is nothing to revert.
