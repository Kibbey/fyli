# Investigation: Production GetTimeline SQL Timeout

**Status:** 🟢 **ROOT CAUSE IDENTIFIED (Round 7): `RESOURCE_SEMAPHORE` — query memory grant starvation.** First explanation that accounts for every observation. Fix migration `20260918032350_AddDropSortIndexes` written, not yet applied to prod. Reopened 2026-09-17; — production telemetry shows the underlying condition was never fixed, only pushed below the 30s timeout. See Round 3, then **Round 4 (infrastructure)**, which corrects a wrong diagnosis made mid-Round-4 and is the current state.
**Date opened:** 2026-09-09
**Date resolved:** ~~2026-09-09~~ — reopened

## Problem Statement

Production `GET /api/drops/timelines/{id}` (`DropController.GetTimeline` → `DropsService.GetTimelineDrops` → `MapDrops`) throws `Microsoft.Data.SqlClient.SqlException`: **Execution Timeout Expired** at `ToListAsync` (`DropsService.cs:396`). The endpoint should return a page of timeline memories within a few seconds; instead the SQL command exceeds the default ~30s `CommandTimeout` and fails.

## Evidence

- Stack trace (2026-09-09 ~11:41 local / 16:40 UTC, `fyli-api`, task `cdbc7aacb5fa42769a25b97f4e1168cb`) dies at:
  - `DropController.GetTimeline` line 85
  - `DropsService.GetTimelineDrops` line 224
  - `DropsService.MapDrops` line 396 (`returnDrops.ToListAsync()`)
- Inner exception: `Win32Exception (258)` — client-side wait timeout, not a SQL syntax error.
- CloudWatch export `~/Downloads/log-events-viewer-result.csv` (200 events, 16:37:11–16:41:06 UTC, same task). Not copied into git (contains recipient emails).
- Query construction in `GetTimelineDrops`:
  1. `GetAllDrops(currentUserId)` — permission filter over **all** drops:
     ```
     TagDrops.Any(t => t.UserTag.TagViewers.Any(a => a.UserId == userId))
     OR UserId == userId
     OR OtherUsersDrops.Any(ud => ud.UserId == userId)
     ```
  2. Then `Where(x => x.TimelineDrops.Any(a => a.TimelineId == timelineId))`
  3. `MapDrops` pages 50 rows, orders by `Drop.Date`, and projects nested Images, Movies, TagDrops, Comments (with nested media), Prompt, Timeline, AlbumDrops.
- `GetAllDrops` starts from `Context.Drops`, not from `TimelineDrops`. The share-link path already does the inverse (IDs from `TimelineDrops` first) in `TimelineShareLinkService.GetPreviewByTokenAsync`.
- `OtherUsersDrops` OR was added 2026-02-14 (`60f802f`) to include UserDrop-granted memories. That makes the permission predicate three-way OR + nested EXISTS.
- `Drops` indexes: `UserId`, `TimelineId`, `PromptId`, `ParentDropId`, `CompletedByUserId`. **No index on `Date`**, which is the `ORDER BY` for timeline pages.
- `TimelineDrops` PK is `(TimelineId, DropId)` — a seek by timeline id is cheap if the plan starts there.
- **Index inventory verified against `StreamContextModelSnapshot.cs` (Round 2).** Every correlated lookup the permission predicate needs is already indexed — see the table in Round 2. The index that would make this query fast (`TimelineDrops` PK) already exists and is simply not used as the driving table.
- `MapDrops` chains `.Include(...)` and then ends in `.Select(...)`. **EF Core ignores `Include` when the query terminates in a projection** — the six `Include` calls at `DropsService.cs:326-333` are dead code. Any cartesian risk lives in the projection, not the Includes.
- `.Skip(skip).Take(take)` is applied *before* the `Select`, so EF emits `OFFSET/FETCH 50` in a subquery and LEFT JOINs the collections onto those 50 rows — bounding the projection blowup to 50 drops.
- `MapDrops` does **not** use `AsSplitQuery()`. `QuestionService` already does, for similar nested graphs. (`AsSplitQuery` does apply to collection projections, so the fix is still valid — just not for the reason originally stated.)
- EF Core version is **9.0.8** (`Domain.csproj`), so captured collections in `Contains()` are parameterized via `OPENJSON`.
- Default SQL command timeout is used (`BaseService` calls `UseSqlServer(connectionString)` with no `CommandTimeout`).
- Frontend `storyline` store pages with `skip` and `take=50` (`ascending` defaults to `true`).
- GetTimeline passes `tagIds = new List<long>()` into `MapDrops`; the Tags projection does `tagIds.Contains(x.UserTagId)` on that empty list.

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | The LINQ starts from all permission-visible Drops (nested EXISTS + OR) and only then filters by timeline, so SQL Server evaluates the expensive permission predicate against a large Drops set instead of seeking `TimelineDrops` by `TimelineId` first. Combined with `ORDER BY Date` and a 50-row nested projection, the command exceeds 30s. | 9/10 | 🔍 Untested (shape). Compounded by H9. |
| H2 | Nested projection of Images/Movies/Comments. Previously demoted because Skip/Take bounds to 50 drops — **re-raised:** prod has **no DropId index** on ImageDrops, MovieDrops, or Comments, so those 50 lookups are table scans. | 6/10 | ⚠️ Re-raised (Round 4) |
| H3 | Missing index on `Drops.Date` forces a sort of all candidate rows for chronological `ORDER BY`. Confirmed absent in prod (also absent from migrations). Expensive when H1/H9 leave a large set. | 3/10 | ⚠️ Confirmed absent; not sufficient alone |
| H4 | Empty `tagIds.Contains()` in the Tags projection generates degenerate SQL that uniquely hurts GetTimeline (main feed passes real tag ids). On EF Core 9 this goes through `OPENJSON`, whose fixed 50-row cardinality estimate can distort plans — but it is correlated over an already-bounded 50-row set, so it is a plan-shape nuisance, not a timeout on its own. | 5/10 | 🔍 Untested |
| H5 | The SELECT is blocked by concurrent writers (notification jobs, comment/drop saves) until `CommandTimeout`. Message includes “or the server is not responding.” | 2/10 | ⚠️ Weakened — Error Number **-2** (client command timeout, not deadlock 1205 / lock timeout 1222). Third timeout is ~90s after the write/email burst ended. | 
| H6 | One (or a few) timelines have a very large `TimelineDrops` count, so even a decent plan exceeds 30s at `take=50` with the full graph. Main feed uses `take=15`. | 4/10 | 🔍 Untested |
| H7 | RDS CPU / IOPS / connection-pool saturation at 11:41 slowed all queries; GetTimeline is the heaviest so it hits the timeout first. | 1/10 | ⚠️ Weakened — emails are Postmark HTTP; no other SQL endpoints fail in this window besides GetTimelineDrops. |
| H8 | **Plan flip / parameter sniffing.** The endpoint worked for months and then failed. The `OtherUsersDrops` OR landed 2026-02-14; the failure is 2026-09-09 — seven months apart. Data volume crossing a threshold flipped the optimizer from a seek-based plan to a scan of `Drops`. Explains "worked yesterday, dies today" better than any static-code hypothesis. | 6/10 | 🔍 Untested (Round 2). H9 makes a flip more likely: the new EXISTS has no supporting index in prod. |
| H9 | **Prod is missing secondary indexes that exist in the EF Initial migration.** Old EF6 names (`PK_dbo.Drop`) confirm prod was not built from the 2021 snapshot. Missing `Drops.UserId`, `NetworkDrops.DropId`, all `UserDrops` secondary indexes, and DropId on Images/Movies/Comments. | 9/10 | ✅ Confirmed (Round 4) |

## Investigation Log

### Round 0 — User clarification

**New information:** The timeout also occurs (or recurs) on **timeline drops**. Original stack was already `DropController.GetTimeline` → `GetTimelineDrops` → `MapDrops.ToListAsync`. Two possible readings:

1. **Same endpoint repeating** (`GET /drops/timelines/{id}` / `GetTimelineDrops`) — confirms the failure is systematic, not a single 11:41 blip.
2. **A second endpoint** (`GET /timelines/drops/{dropId}` / `GetTimelinesForDrop`) — different query (`TimelineUsers.Include(Timeline.TimelineDrops)` plus `TimelineDrops.Any(DropId == dropId)`). Not confirmed without a stack.

**Hypothesis updates:**
- H5 (lock blocking) and H7 (RDS saturation) demoted: a repeat on the same feed path is more consistent with a bad query than a transient stall.
- H1/H2 unchanged and still leading: both live on `GetAllDrops` + `MapDrops`, which `GetTimelineDrops` always uses.
- H6 slightly up if the same storyline is involved; still untested without row counts.
- If the second endpoint (`GetTimelinesForDrop`) is also timing out, add H8: `Include(Timeline.TimelineDrops)` may load every drop on every storyline the user follows. Waiting on a stack before adding it.

### Round 1 — CloudWatch CSV (`log-events-viewer-result.csv`)

**Test performed:** Parsed the 200-event CloudWatch export (16:37:11–16:41:06 UTC, single ECS task `cdbc7aac…`). Sanitized; file not committed (PII emails).

**Findings:**

Sequence on this task:

| UTC | Event |
|-----|--------|
| 16:37:11 | Writing-assist call to `api.x.ai/v1/chat/completions` (~1.8s, 200) |
| 16:38:31–16:39:08 | 24 “Memory shared with you” emails (one recipient inactive / Postmark suppression) |
| 16:38:42 | MediaConvert job submitted (`MovieService`) — video memory |
| 16:40:06 | SQL timeout #1 — `GetTimelineDrops` → `MapDrops` — `ClientConnectionId:8e0a6b9d…` — **Error Number:-2, State:0, Class:11** |
| 16:40:12 | Separate bug: `InvalidOperationException` Invalid non-ASCII in **Location** header `0xFFFD` (Kestrel). Not the timeout. |
| 16:40:36 | SQL timeout #2 — **same stack** `GetTimelineDrops` → `MapDrops` — different connection `75d21e9c…` — Error **-2** |
| 16:41:06 | SQL timeout #3 — same exception; stack truncated at end of export. +30.05s after #2 |

What this adds:
- **Three timeouts, ~30s apart**, two confirmed on `GetTimelineDrops` with **different SQL connections**. Matches default `SqlCommand.CommandTimeout` (30s) plus a client retry. Not `GET /timelines/drops/{dropId}`.
- **Error Number -2** is a client-side command timeout. Not deadlock (1205), not lock-request timeout (1222). Does not prove the query was blocked; it only proves it did not finish in 30s.
- Timeouts continue **after** the share/email/MediaConvert burst. Emails ended 16:39:08; first timeout implies the query started ~16:39:36. Third timeout at 16:41:06 is still the same failure ~2 minutes later. That is a slow SELECT, not a brief lock from the save.
- Triggering user flow: AI-assisted **video** memory, shared with a large network (~24 notification emails), then the storyline feed is requested.
- Logs do **not** include SQL text, timeline id, skip, user id, or duration other than the 30s timeout.
- Side issue (unrelated to timeout): exception-handler/redirect writes a `Location` header containing U+FFFD.

**Conclusion:** ⚠️ Partially confirms the “timeline drops” report — it is the **same** endpoint retried, not a second API. Strengthens H1/H2 (query too slow to finish in 30s, repeatedly). Weakens H5/H7.

**Hypothesis updates:**
- H1 still 9/10, still the first test: generate SQL and see whether the plan starts from all drops.
- H2 still 8/10 (cartesian projection still plausible; logs cannot distinguish H1 vs H2).
- H5/H7 further weakened by Error -2 + retries after the write burst.
- H6 unchanged — still need TimelineDrops counts. The new video row alone would not add 30s.
- New side bug noted, out of scope: `Location` header `0xFFFD`.

### Round 2 — Source + index inventory audit

**Test performed:** Read `DropsService.GetTimelineDrops`/`MapDrops`, `PermissionService.GetAllDrops`, and the full index inventory in `Memento/Domain/Migrations/StreamContextModelSnapshot.cs`. Static analysis only — no execution plan captured yet.

**Finding 1 — this is a query-shape problem, not a missing index (~80/20).**

Every correlated lookup the permission predicate performs is backed by an index **in the local EF model / 2021 Initial migration**. That is not proof they exist in prod (prod predates that snapshot and later scripts were applied by hand). Until `sys.indexes` is checked, treat the table below as “should exist,” not “does exist.”

| Correlated lookup | Supporting index | Status |
|---|---|---|
| `TagDrops.Any(t.DropId == d.DropId)` | `NetworkDrops.IX(DropId)` | ✓ |
| `.TagViewers.Any(a.UserId == userId)` | PK `(UserTagId, UserId)` on `NetworkViewers` | ✓ seek |
| `OtherUsersDrops.Any(ud.UserId == userId)` | `UserDrops.IX(DropId)`, `IX(UserId)` | ✓ (separate, not composite) |
| `TimelineDrops.Any(a.TimelineId == id)` | **PK `(TimelineId, DropId)`** | ✓ ideal seek |

The last row is the important one: **the index that would make this query fast already exists.** "Give me every drop on timeline N" is a single range seek on the `TimelineDrops` PK. The query never uses it as the driving table because `GetTimelineDrops` starts from `Context.Drops` with the permission filter and bolts the timeline on as an `EXISTS` afterward. Adding indexes cannot fix this — it would only make a scan of `Drops` marginally cheaper, when the fix is to not scan `Drops` at all.

**Finding 2 — two shapes the optimizer cannot recover from:**

1. **The 3-way `OR` spanning three tables** (`NetworkDrops` / `Drops.UserId` / `UserDrops`). SQL Server cannot collapse `A OR B OR C` across different tables into one seek. It either builds a concatenation of three seeks plus a distinct sort, or — as estimates drift — gives up and scans `Drops`, evaluating three correlated subqueries per row.
2. **`ORDER BY Date` + `OFFSET/FETCH`** forces full materialization and sort of the permission-filtered set before discarding `skip` rows, with no index on `Drops.Date`. Every page pays full freight; deep pages pay more.

Net effect: scan all drops → three EXISTS per row → sort everything by `Date` → discard all but 50.

**Finding 3 — H2's stated mechanism is wrong.** `Include` is discarded by EF Core ahead of a `Select`, and `Skip/Take` runs before the projection, bounding the join blowup to 50 drops. See Evidence. H2 restated and demoted to 4/10.

**Finding 4 — the seven-month gap.** `OtherUsersDrops` landed 2026-02-14; the failure is 2026-09-09. The code did not change in between. That argues the optimizer flipped plans as data grew, which is exactly what a query whose shape only works while tables are small does. Added as H8.

**Finding 5 — `GetAllDrops` is duplicated verbatim** in `PermissionService.cs:28` and `DropsService.cs:481`, both carrying an unused `DateTime now`. Any fix must land in both.

**Conclusion:** ✅ H1 is the leading cause and the mechanism is now specific. H2 restated/demoted, H3 shown to be dependent on H1 rather than independent, H8 added.

**Hypothesis updates:**
- H1 → **9/10, unchanged and now mechanistically explained.** Still needs a plan to confirm.
- H2 → 4/10, restated (projection, not `Include`).
- H3 → 3/10, not independent of H1.
- H8 → new, 6/10 (plan flip / data-volume threshold).

---

## Proposed Fix (pending plan confirmation)

**Primary — invert the drive order** in `GetTimelineDrops`, matching what `TimelineShareLinkService.GetPreviewByTokenAsync` already does:

```csharp
var timelineDropIds = Context.TimelineDrops
    .Where(td => td.TimelineId == timelineId)
    .Select(td => td.DropId);

var drops = GetAllDrops(currentUserId)
    .Where(x => timelineDropIds.Contains(x.DropId));
```

Small change, gives the optimizer a seekable driving set. If the plan is still bad, split the 3-way OR into a `UNION` of three seeks over the timeline's drop ids.

**Secondary — cheap, but not expected to fix it alone:**
- `UserDrops (DropId, UserId)` composite — turns seek-plus-lookup into a covering seek.
- `Drops (Date) INCLUDE (DropId, UserId)` — only helps while the current shape stands; moot after the rewrite.
- `AsSplitQuery()` on the `MapDrops` projection — still correct, addresses H2.

**Backwards compatibility:** the rewrite changes only *how* the drop set is reached, not which drops are visible — the same `GetAllDrops` permission predicate still applies. No change to drop access semantics.

### Next test — capture the actual execution plan

One look discriminates the two leading hypotheses:
- **Clustered Index Scan on `Drops` feeding a Sort** → H1 confirmed, apply the rewrite.
- **Seek on `TimelineDrops`, time in the collection joins** → H2, apply `AsSplitQuery()`.

Supporting data worth pulling at the same time:
1. `SELECT TimelineId, COUNT(*) FROM TimelineDrops GROUP BY TimelineId ORDER BY 2 DESC` — tests H6.
2. Total `Drops` row count and drop count for the affected user — sizes H1.
3. `OPTION (RECOMPILE)` on the generated SQL — tests H8.
4. Main-feed latency in the same window. Same `GetAllDrops` + `MapDrops` path; if it is *also* slow, H1 is confirmed and H6 dies. If only the timeline endpoint is slow, the `TimelineDrops.Any()` filter or `take=50` vs `take=15` is implicated.
5. **Prod index inventory** (script in Round 3). Do not assume the local model.

### Round 3 — Indexes to verify in prod

Do not trust local `HasIndex` / `StreamContextModelSnapshot`. Prod may have been created from the old EF6 schema and later scripts applied by hand. Check **PKs as well as named IX_** — a missing or differently-keyed PK is as bad as a missing secondary index.

**Must exist or the current SQL cannot seek (H1 path)**

| Table | Object | Columns | Used for |
|-------|--------|---------|----------|
| TimelineDrops | **PK_TimelineDrops** | `(TimelineId, DropId)` | `TimelineDrops.Any(TimelineId == id)`. If PK is identity/`DropId`-leading/missing, this is a scan. |
| TimelineDrops | IX_TimelineDrops_DropId | DropId | drop → timelines |
| Drops | **PK_Drops** | DropId | join target |
| Drops | IX_Drops_UserId | UserId | owner branch of `GetAllDrops` |
| NetworkDrops | IX_NetworkDrops_DropId | DropId | `TagDrops.Any` from a drop |
| NetworkDrops | IX_TagDrop_UserTagId_DropId | `(UserTagId, DropId)` unique | tag → drops |
| NetworkViewers | **PK_NetworkViewers** | `(UserTagId, UserId)` | `TagViewers.Any(UserId)` per tag |
| NetworkViewers | IX_NetworkViewers_UserId | UserId | reverse: all tags this user can see |
| UserDrops | IX_UserDrops_UserId | UserId | `OtherUsersDrops.Any(UserId)` |
| UserDrops | IX_UserDrops_DropId | DropId | drop → granted users |

**Nested projection (H2)**

| Table | Object | Columns | Used for |
|-------|--------|---------|----------|
| ImageDrops | IX_ImageDrops_DropId | DropId | images per drop |
| MovieDrops | IX_MovieDrops_DropId | DropId | movies per drop |
| Comments | IX_Comments_DropId | DropId | comments per drop |
| AlbumDrops | IX_AlbumDrops_DropId | DropId | `HasAlbums` (PK is `(AlbumId, DropId)`, DropId is not leading) |

`ContentDrops` PK `ContentDropId` (= DropId, 1:1) is enough.

**Never in any EF migration — confirm they are also absent in prod (H3)**

| Table | Columns | Notes |
|-------|---------|-------|
| Drops | Date | GetTimeline always `ORDER BY Date`. No `IX` in Initial or later scripts. |
| Drops | Created | non-chronological `MapDrops`. Same. |
| UserDrops | `(UserId, DropId)` covering composite | model has two single-column indexes only |

If `Date` is missing, that matches the repo, not a failed deploy. Still verify — someone may have added it by hand, or prod may be missing things the 2021 snapshot *does* list.

**Skip for this timeout** (run after `ToListAsync`): `UserUsers` (MapUserNames), `QuestionResponses` (AddQuestionContext).

```sql
-- Paste on prod. Expected rows: the objects in the tables above.
-- Also dumps every index on these tables so we catch renamed/extra/wrong-key PKs.

SELECT
    t.name  AS TableName,
    i.name  AS IndexName,
    i.type_desc,
    i.is_primary_key,
    i.is_unique,
    STUFF((
        SELECT ', ' + c.name
            + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 0
        ORDER BY ic.key_ordinal
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '') AS KeyCols,
    STUFF((
        SELECT ', ' + c.name
        FROM sys.index_columns ic
        JOIN sys.columns c
          ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE ic.object_id = i.object_id
          AND ic.index_id = i.index_id
          AND ic.is_included_column = 1
        ORDER BY ic.index_column_id
        FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 2, '') AS IncludeCols
FROM sys.tables t
JOIN sys.indexes i ON i.object_id = t.object_id
WHERE t.name IN (
    'TimelineDrops', 'Drops', 'NetworkDrops', 'NetworkViewers',
    'UserDrops', 'ImageDrops', 'MovieDrops', 'Comments',
    'AlbumDrops', 'ContentDrops'
)
  AND i.name IS NOT NULL
ORDER BY t.name, i.is_primary_key DESC, i.name;
```

Expected-present checklist (name *or* equivalent key — names can differ):

```
PK_TimelineDrops              (TimelineId, DropId)
IX_TimelineDrops_DropId       DropId
PK_Drops                      DropId
IX_Drops_UserId               UserId
IX_NetworkDrops_DropId        DropId
IX_TagDrop_UserTagId_DropId   (UserTagId, DropId) unique
PK_NetworkViewers             (UserTagId, UserId)
IX_NetworkViewers_UserId      UserId
IX_UserDrops_UserId           UserId
IX_UserDrops_DropId           DropId
IX_ImageDrops_DropId          DropId
IX_MovieDrops_DropId          DropId
IX_Comments_DropId            DropId
IX_AlbumDrops_DropId          DropId
```

Highest-impact misses: **PK_TimelineDrops not leading with TimelineId**, **IX_NetworkViewers_UserId**, **IX_UserDrops_UserId**, **IX_Drops_UserId**. A missing `Drops.Date` index is expected from migrations and does not by itself explain a 30s timeout if the timeline filter seeks.

### Round 4 — Prod index inventory (user paste)

**Test performed:** Diffed the prod `sys.indexes` dump against the Round 3 checklist. Names are EF6-style (`PK_dbo.Drop`), so prod was built from the old schema, not the 2021 Core Initial migration.

**Present (keys match; names differ):**

| Table | Prod object | Key |
|-------|-------------|-----|
| TimelineDrops | PK_dbo.TimelineDrop | (TimelineId, DropId) clustered |
| TimelineDrops | IX_DropId, IX_TimelineId, IX_UserId | DropId; TimelineId (redundant with PK); UserId |
| Drops | PK_dbo.Drop | DropId |
| Drops | IX_Drop_ParentDropId, IX_PromptId, IX_TimelineId | ParentDropId, PromptId, TimelineId |
| NetworkDrops | PK_dbo.TagDrop | TagDropId |
| NetworkDrops | IX_TagDrop_UserTagId_DropId unique | (UserTagId, DropId) |
| NetworkViewers | PK_dbo.TagViewer | (UserTagId, UserId) |
| AlbumDrops | PK_dbo.AlbumDrop, IX_AlbumId, IX_DropId | (AlbumId, DropId); AlbumId; DropId |
| ContentDrops | PK_dbo.ContentDrop | ContentDropId (= DropId) |

**Missing vs EF Initial (and vs what this query needs):**

| Table | Missing key | Impact on GetTimelineDrops |
|-------|-------------|----------------------------|
| **Drops** | **UserId** | Owner branch of `GetAllDrops` cannot seek. Clustered scan of Drops. |
| **NetworkDrops** | **DropId** (standalone) | Unique index is `(UserTagId, DropId)` — DropId is not leading. `TagDrops.Any` from a drop scans NetworkDrops. |
| **NetworkViewers** | **UserId** | Nested EXISTS has UserTagId first, so PK still seeks. Reverse plan ("tags this user can see") cannot. Lower urgency. |
| **UserDrops** | **UserId and DropId** — no secondary indexes at all | `OtherUsersDrops.Any(UserId)` (added 2026-02-14) scans the whole table per candidate drop. |
| **ImageDrops** | **DropId** | Only PK + CommentId. Loading images for 50 drops scans ImageDrops. |
| **MovieDrops** | **DropId** | Same. This incident included a new video. |
| **Comments** | **DropId** (and UserId) | Only PK. Loading comments for 50 drops scans Comments. |
| Drops | Date / Created | Absent, as in migrations. Sort of whatever set H1/H9 leave. |

**Conclusion:** ✅ H9 confirmed. Prod is not missing the TimelineDrops PK (that part of H1 is *not* an index gap). It *is* missing the indexes that make the permission EXISTS and the nested media/comment loads seek.

H1 is still the right query-shape fix. H9 is a confirmed compounding cause: even a TimelineDrops-first plan still hits `GetAllDrops` EXISTS against NetworkDrops/UserDrops with no DropId/UserId indexes, then MapDrops scans ImageDrops/MovieDrops/Comments.

**Hypothesis updates:**
- H9 added at 9/10, confirmed.
- H2 re-raised to 6/10 — no DropId on Images/Movies/Comments turns the 50-row projection into table scans.
- H8 more plausible: Feb 2026 added `UserDrops` EXISTS against a table with only `PK UserDropId`.
- TimelineDrops side of H1 is healthy in prod; do not add indexes there.

**Recommended Action (indexes, does not replace the H1 rewrite):** add the missing *lookup* indexes that already exist in the EF model. Highest first:

1. `UserDrops (UserId)` and `UserDrops (DropId)`
2. `NetworkDrops (DropId)`
3. `Drops (UserId)`
4. `ImageDrops (DropId)`, `MovieDrops (DropId)`, `Comments (DropId)`
5. Optional: `NetworkViewers (UserId)`

Do **not** treat `Drops.Date` as the first fix. A new EF migration locally would be empty (model already has 1–4). Prod needs a raw SQL script of those CREATE INDEX statements.

---

## Round 3 — Production telemetry after SlowQueryInterceptor deploy (2026-09-17)

**Reopens this investigation.** The 09-09 resolution ("indexes fixed it") is incomplete.

### How this was found

`SlowQueryInterceptor` (commit `be13506`) deployed to prod 2026-09-17 20:10 CDT. It logs any
command over `SlowQueryThresholdMs` (default 2000ms). Within the first 30 minutes it captured
**eight commands between 15.1s and 25.6s against a 30s `CommandTimeout`.**

Captured SQL is saved under `docs/investigations/sql-captures/` (no parameter values are
logged, so the files carry no PII).

### The eight slow commands

| Duration | Query | Capture |
|----------|-------|---------|
| 25604 / 25260 / 25252 / 25171 ms | **Home feed** `GetDrops` → `MapDrops` | `2026-09-17-getdrops-homefeed-25s.sql` |
| 25146 ms | `QuestionSets` | `2026-09-17-questionsets-25s.sql` |
| 18922 / 15158 ms | `Timelines` + `TimelineUsers` | `2026-09-17-timelines-19s.sql` |
| 16337 ms | `Questions` ordered by `AnsweredAt DESC` | `2026-09-17-questions-16s.sql` |

All eight fall in a 2.5-minute window, 01:16:38–01:19:08 UTC.

### Finding 1 — the home feed is the slowest endpoint in production

Four identical 25s commands. The outer shape is exactly H1, on `GetDrops` rather than
`GetTimelineDrops`:

```sql
FROM [Drops] AS [d]
WHERE EXISTS (SELECT 1 FROM [NetworkDrops] [n] JOIN [UserNetworks] [u] ...
              AND EXISTS (SELECT 1 FROM [NetworkViewers] [n0] WHERE ... [n0].[UserId] = @__userId_0))
   OR [d].[UserId] = @__userId_0
   OR EXISTS (SELECT 1 FROM [UserDrops] [u0] WHERE [d].[DropId] = [u0].[DropId] AND [u0].[UserId] = @__userId_0)
ORDER BY [d].[Created] DESC
OFFSET @__p_1 ROWS FETCH NEXT @__p_2 ROWS ONLY
```

Root is `Drops`, the full three-way permission OR is evaluated, then `OFFSET/FETCH`. No
`TimelineDrops` anywhere — this is the home feed at `take: 15`.

Note the sort column: **`Created`, not `Date`.** `MapDrops` uses `OrderByDescending(o => o.Created)`
when `chronological: false`. `Drops` has no index on `Created` either, so H3's missing-sort-index
argument applies to the home feed as well — and neither `Date` nor `Created` was in the
09-09 index catch-up.

### Finding 2 — this is not one bad query

Three unrelated query families are also 15–25s. The `Timelines` one is only 686 characters:

```sql
FROM [Timelines] [t] LEFT JOIN [TimelineUsers] [t1] ON ...
WHERE [t].[UserId] IN (SELECT [c].[value] FROM OPENJSON(@__connectedUserIds_0) ...)
   OR EXISTS (SELECT 1 FROM [TimelineUsers] [t0] WHERE ... [t0].[UserId] IN (SELECT ... OPENJSON(@__connectedUserIds_0) ...))
ORDER BY [t].[TimelineId]
```

A small two-table query taking 18.9s is not a query-shape problem. Two things stand out:

- **`OPENJSON` twice, combined with `OR`.** `OPENJSON` without a schema carries a fixed 50-row
  cardinality estimate (the H4 mechanism), and here it feeds both sides of an `OR` — a reliable
  bad-plan generator.
- **`Timelines.UserId` / `TimelineUsers` indexes were never part of the 09-09 catch-up.**
  `AddMissingGetTimelineIndexes.sql` covered only seven indexes on the `GetTimeline` path:
  `UserDrops`, `NetworkDrops`, `Drops.UserId`, `ImageDrops`, `MovieDrops`, `Comments`,
  `NetworkViewers`. If the 2021 Initial migration's indexes never landed *generally*, then
  `Timelines`, `TimelineUsers`, `Questions`, `QuestionSets`, and `QuestionResponses` are all
  still missing theirs — which would explain all four query families at once.

### Finding 3 — what the 09-09 fix actually did

It took `GetTimelineDrops` below 30s. It did not address the condition. The same `GetAllDrops`
shape is running 25s on the home feed today, **4 seconds from throwing the same
`SqlException -2`** — on the app's most-trafficked endpoint.

The 09-09 incident is better read as: `GetAllDrops` is too slow everywhere, and the storyline
path happened to cross 30s first.

### What this invalidates

- **Resolution as written** ("recovered after indexes + reboot") describes the symptom, not the cause.
- **`docs/tdd/gettimeline-query-performance.md`** states "The timeout was storyline-only" and
  "`GetDrops` (home feed) … Leave it alone," and parks the `DropVisibility` permission rewrite
  partly on the premise that touching the shared rule risks the home feed for no gain. The home
  feed is the slowest thing in production. **Phase 2 — the parked one — is the change that
  addresses this. Phase 1, the only one still live, would do nothing for the home feed.**
- **H5 / H7** (contention, resource saturation) were demoted on 09-09 reasoning. Four unrelated
  query families slow in the same 2.5-minute window is consistent with them again.

### Two competing readings — not yet distinguished

| | Reading A — broad schema drift | Reading B — post-deploy cold start / contention |
|---|---|---|
| Claim | The Initial migration's indexes never landed generally; many tables still lack them | All eight cluster 5–8 min after an ECS task swap: cold plan cache, cold buffer pool, clients reconnecting at once |
| Supports | Four unrelated families slow; the 09-09 audit only fixed 7 indexes on one path | Tight 2.5-min window, nothing logged since |
| Against | Does not explain the tight clustering | 25s for a 686-char two-table query is extreme for cold cache alone |

**These are not exclusive** — drift would make a cold-start burst far worse. Do not act as if
one is settled.

### Next tests

1. **Full index drift audit**, not just the `GetTimeline` path — diff every `HasIndex` in
   `StreamContextModelSnapshot.cs` against prod `sys.indexes`. This is the single highest-value
   step and directly tests Reading A.
2. **Leave the interceptor running and re-check in 24h.** If slow commands appear steadily
   outside deploy windows, Reading B is dead. If they only ever cluster after a deploy, Reading A
   is at most a contributing factor.
3. **Lower `SlowQueryThresholdMs` to ~500** for a day to get the real latency distribution of
   the home feed rather than only its worst outliers.
4. **Capture the actual plan** for `2026-09-17-getdrops-homefeed-25s.sql` — this answers the
   TDD's Phase 0a question for the feed instead of the storyline.

**Hypothesis updates:**
- **H1 → confirmed in production, on the home feed.** No longer storyline-specific.
- **H9 (missing indexes) → still confirmed, but scoped too narrowly.** The 09-09 catch-up fixed
  one code path, not the schema.
- **H4 (`OPENJSON` cardinality) → raised.** Now observed in a real 18.9s query with `OPENJSON` on
  both sides of an `OR`.
- **H3 → applies to `Created` as well as `Date`.** Neither is indexed.
- **H5 / H7 → un-demoted**, pending test 2.

---

## Round 4 — Infrastructure: the database instance (2026-09-17)

Triggered by the question "the app gets almost no use — why are we low on CPU credit?"

### Finding 1 — there is essentially no database traffic

| Metric | 7-day value | Reading |
|---|---|---|
| `DatabaseConnections` | **avg 0.01–0.31**, max 7 | Idle almost always |
| `CPUUtilization` | avg 24.7% → 32.1%, **min never below ~17–25%** | No idle period in 7 days, trending up |
| `ReadIOPS` | flat ~25/sec, 24/7, near-zero variance | Constant, traffic-independent |
| `WriteIOPS` | ~1/sec | Nothing being written |
| `BurstBalance` | 99% | Storage not a bottleneck |
| `ReadLatency` | 0.66 ms | Disk healthy |

A database averaging 0.03 connections while burning 28% CPU and 25 IOPS is not running application
queries. Over seven days — including weekend nights — CPU **never** drops to idle.

### Finding 2 — the instance

`fyli` is **`db.t3.small`** (2 vCPU / 2 GB), engine **`sqlserver-ex` (SQL Server Express)**, 20 GB gp2,
Single-AZ. Express caps the buffer pool at **1410 MB** and the database at **10 GB** regardless of
instance size, so a larger instance buys memory the engine will not use.

`FreeableMemory` ~178 MB on a 2 GB box: Express likely cannot even reach its own 1410 MB cap.

### Finding 3 — ⚠️ CORRECTION: the instance is NOT CPU-throttled

**An earlier conclusion in this round was wrong and is corrected here.** On seeing
`CPUCreditBalance: 0.0` sustained for 24h, it was concluded that CPU was hard-throttled to the 20%
baseline, and the recommended fix was "enable T3 Unlimited." Both were wrong:

- **RDS `db.t3` instances run in Unlimited mode by default and it is not configurable.** There is no
  `--credit-specification` parameter on `rds modify-db-instance` (verified, AWS CLI 2.27.49). That is
  an EC2 feature.
- **T3 (unlike T2) bursts above baseline even at zero credit balance.** `CPUUtilization` reaching
  41–45% against a 20% baseline was visible in the same data that prompted the throttling claim and
  contradicted it. The surplus metrics were not checked before concluding.

What the metrics actually show:

| Metric | Value | Meaning |
|---|---|---|
| `CPUCreditBalance` | 0.0 for 24h+ | No earned credits — expected, since it never idles |
| `CPUSurplusCreditBalance` | **576.00, pinned** | Borrowed credits at the **maximum** for t3.small (24/hr × 24h) |
| `CPUSurplusCreditsCharged` | **0.76–2.23 per hour, continuous** | Already being billed for surplus |

Surplus is repaid only during genuine idle. This instance never idles, so it borrowed to the ceiling
and parked there. **At the surplus ceiling AWS does begin throttling to baseline** — so the position
is: paying surplus charges every hour *and* unable to borrow further. Roughly $4–5/month for an
instance that still cannot go faster on demand.

### Finding 4 — this is a known, documented SQL Server + RDS burstable problem

Not specific to this application. Widely reported:

- *"Amazon RDS Instance Using 25~35% CPU While Completely Idle (Zero Sessions, Zero Queries)"* — AWS re:Post
- *"High CPU Usage on an Idle MSSQL RDS database"* — AWS re:Post
- A `t3.micro` running SQL Server Express is reported to sit at a **minimum of 25% CPU when not in
  use**; older t2 instances used far less.

Cited causes: SQL Server background processes and memory management; burstable instances *barely
meeting SQL Server's minimum hardware requirements*; and insufficient memory forcing disk I/O that
itself drives CPU. The consensus is that there is **no configuration fix** — SQL Server's resting
footprint exceeds what a small burstable class provides.

Our numbers (min ~20–25%, flat ~25 IOPS, zero connections) match that profile exactly.

### Finding 5 — no monitoring overhead to reclaim

Checked in response to "can we shut down monitoring to lower load":

| Setting | State |
|---|---|
| Enhanced Monitoring | Off (interval 0) |
| Performance Insights | Off |
| CloudWatch log exports | None |
| Backup retention | 7 days (keep) |

All already disabled. The resting load is SQL Server plus the mandatory RDS agent, neither optional.
Enabling Performance Insights would *add* load — though it is the tool that would identify which
internal task spends the CPU.

### What remains unexplained

**The home feed's ~25s is not yet accounted for.** The throttling explanation is withdrawn. Remaining
candidates, none confirmed:

1. **Query shape (Round 2 / H1)** — starts from every drop the user can see, sorts all of them, keeps 15.
2. **CPU starvation at the surplus ceiling** — weaker than the withdrawn throttling claim, but not zero.
3. **Memory** — Express on 2 GB with ~178 MB free cannot cache the working set, forcing physical reads.

Note the home feed timings are remarkably consistent: 25260 / 25604 / 25171 / 25252 / 25292 / 25329 ms
across 23 minutes. That consistency favours a **deterministic query cost** over variable contention —
which points back at candidate 1. By contrast the `UserNetworks` single-table query varied widely
(5811 / 10349 / 14720 ms), which does look like contention.

### Next tests

1. **Capture the execution plan** for `sql-captures/2026-09-17-getdrops-homefeed-25s.sql`. Free, and
   it separates candidate 1 from 2 and 3. **Do this before buying hardware.**
2. **Check database size against the Express 10 GB limit.** That is a wall, not a slowdown.
3. **Apply `IX_TimelineUsers_TimelineId`** (see `AddMissingIndexes-2026-09-17.sql`) — the only missing
   index tied to a measured slow query (18.9s `Timelines` query).
4. **Do not resize to `db.t3.medium`** — same 20% baseline, no improvement. Only a non-burstable class
   (`db.m5.large`+, ~$250–280/mo vs ~$38 today) removes the credit system. That is a large jump for a
   near-zero-traffic app and deserves a decision about whether SQL Server on RDS is the right home.

**Hypothesis updates:**
- **New H10 — infrastructure undersizing.** SQL Server Express's resting footprint (~25%) exceeds the
  `db.t3.small` 20% baseline, so the instance is permanently in surplus. Confirmed as a *condition*;
  not yet confirmed as the cause of the 25s feed.
- **H1 → still the leading explanation for the home feed**, supported by the consistency of its timings.
- **H5 / H7 (contention)** → partially supported, but by `UserNetworks`, not the feed.
- **H8 (plan flip)** → unchanged.

---

## Round 5 — Execution plan captured: H1 confirmed with numbers (2026-09-17)

**This closes the question Round 4 left open.** The home feed's ~25s is a **query defect**, not
infrastructure.

Captured with `sql-captures/capture-homefeed-plan.sql` against a local database carrying ~2,128 drops.
Local reproduces the plan *shape*; production differs only in cardinality and CPU speed.

### The plan, for 15 returned rows

| Table | Scan count | Logical reads |
|---|---|---|
| `Drops` | **1** (full pass) | 50 |
| `UserDrops` | **2,128** | 4,802 |
| `NetworkViewers` | **2,133** | 4,266 |
| `NetworkDrops` | — | **29,844** |
| `UserNetworks` | — | **29,844** |
| **Total** | | **~68,800** |

**~4,600 logical reads per row returned.**

Scan counts of 2,128 / 2,133 equal the row count of `Drops`. The three permission `EXISTS` subqueries
are re-evaluated **once per row of the entire table**, then everything is sorted, then `OFFSET/FETCH`
discards all but 15. This is exactly H1, now measured rather than argued.

### It is CPU-bound — which settles the hardware question

```
CPU time = 26 ms,  elapsed time = 26 ms.
```

CPU time **equals** elapsed time: zero waiting, on disk, locks, or memory. `physical reads = 0` on
every table — everything was already cached.

Therefore:
- **`db.t3.medium` cannot help.** Identical 20% CPU baseline, and CPU is 100% of the cost.
- **More RAM cannot help.** Nothing is waiting on I/O; the whole ~1 GB database already fits in cache.
- **The ~$250–280/mo non-burstable upgrade is not indicated.** It would mask a query doing 4,600
  reads per returned row.

Local runs in 26 ms because it has ~2,100 drops on an unthrottled CPU. Production has more rows and
roughly 0.4 effective vCPU — same shape, ~1000x the wall time.

### The rewrite, measured on the same data

Replacing the three-way correlated `OR` with a `UNION` of three seekable sets, then joining:

```sql
FROM [Drops] AS [d]
INNER JOIN (
    SELECT [DropId] FROM [Drops] WHERE [UserId] = @userId
    UNION
    SELECT [n].[DropId] FROM [NetworkDrops] AS [n]
      INNER JOIN [NetworkViewers] AS [nv] ON [n].[UserTagId] = [nv].[UserTagId]
      WHERE [nv].[UserId] = @userId
    UNION
    SELECT [DropId] FROM [UserDrops] WHERE [UserId] = @userId
) AS [v] ON [v].[DropId] = [d].[DropId]
ORDER BY [d].[Created] DESC OFFSET 0 ROWS FETCH NEXT 15 ROWS ONLY
```

| | Current | Rewrite | Change |
|---|---|---|---|
| Logical reads | ~68,800 | **139** | **495x fewer** |
| `UserDrops` scan count | 2,128 | **1** | per-row evaluation gone |
| `NetworkViewers` scan count | 2,133 | **1** | per-row evaluation gone |
| `UserNetworks` reads | 29,844 | **0** | table drops out entirely |
| CPU time | 26 ms | **~1 ms** | floor-limited at this size |

`UserNetworks` disappears because joining `NetworkViewers` directly is sufficient — the hop through
`UserNetworks` in the current query adds nothing but work.

### What this means for the TDD

`docs/tdd/gettimeline-query-performance.md` **parks** this rewrite (as "Global visible ids union")
on the reasoning that computing visible ids for every feed could hurt the home feed, and that the
timeout was storyline-only. Both premises are now false:

- The home feed is the slowest endpoint in production.
- The union rewrite makes it **495x cheaper in reads**, not more expensive.

**Phase 2 should be un-parked and is the fix.** Phase 1 (storyline drive-order) does not touch the
home feed at all.

**Hypothesis updates:**
- **H1 → CONFIRMED with measurements.** Root cause of the home feed's 25s.
- **H10 (infrastructure undersizing) → real but NOT the cause.** The instance is genuinely
  mis-specced for SQL Server (Round 4 stands), but fixing it would not fix this query.
- **H2 / H3 / H4 / H8 → not needed to explain the observed behaviour.**

---

## Round 6 — The rewrite shipped and did NOT fix production (2026-09-17)

**Round 5's conclusion ("a query defect, not a hardware shortage") is falsified.**

### What was deployed

Commit `16cd0ed` (union rewrite) + `8091395` (unrelated admin feature), image `sha256:eb76b2d3`,
ECS rollout `COMPLETED` 03:12 UTC. New task `684dda02`, old task `544150fc` drained.

### The result

Attribution by log stream, the 10 minutes spanning the swap:

| Task | Feed timeouts | Query shape |
|---|---|---|
| `544150fc` (old) | 5 | `SELECT [d0]` — the old three-way OR |
| `684dda02` (**new**) | **1** | `SELECT [d1]` — **the rewrite** |

The alias shift `[d0]` → `[d1]` is the extra nesting level introduced by `IN (subquery)`. The
rewritten query ran in production and still hit **`SQL TIMEOUT after 29997ms`**.

The 533x logical-read reduction measured locally is real. **Logical reads were not the binding
constraint in production.**

### Also note: the incident had escalated before the deploy

The old task logged five `SQL TIMEOUT after 30s` between 03:07 and 03:11 — the feed had gone from
25s *slow* to actually timing out. The 2026-09-09 outage was recurring while this work was underway.

### The unexplained ~25-second constant

This is now the central fact, and it was under-weighted in Rounds 3-5.

`UserNetworks` — one table, `WHERE UserId = @p`, index `(UserId, Name)` confirmed present by the
drift audit — is consistently slow:

```
25021 / 25004 / 25006 / 25017 / 25026 / 25082 ms
```

Six samples of a trivial single-table lookup, all within 80 ms of each other. No query-cost
explanation produces that signature; query cost varies with data. **A fixed ~25s wait does.**

The feed lands at the 30s `CommandTimeout` cap whether it performs ~68,800 logical reads (old) or
129 (new). Two structurally unrelated queries pinned at the same constant, indifferent to their own
cost, points away from query shape entirely.

**This resembles H5 (blocking), demoted in Round 0 on reasoning rather than evidence.** That
demotion should not have survived the appearance of the ~25s constant.

### Next test — catch it in the act

While the slow log is firing:

```sql
SELECT session_id, blocking_session_id, wait_type, wait_time, wait_resource, status, command
FROM sys.dm_exec_requests WHERE session_id > 50;
```

| Observation | Conclusion |
|---|---|
| non-zero `blocking_session_id`, or `LCK_*` wait | **Blocking.** Identify the writer holding the lock. |
| `SOS_SCHEDULER_YIELD` dominant | **CPU starvation** — Round 4's db.t3.small sizing becomes the fix after all. |
| `RESOURCE_SEMAPHORE` | **Memory grant starvation** — the 2 GB / Express 1410 MB ceiling. |

### Do not revert the rewrite

It is not harmful and should stay:
- Semantically verified — 0 orphans confirmed on production, so the union is provably equivalent
- 40/40 feed and permission tests green; 419 passed overall
- Strictly less database work than before
- The rule now has one definition instead of two duplicated copies

It is simply not sufficient, because the binding constraint is something else.

**Hypothesis updates:**
- **H1 → real but NOT the binding constraint.** The query defect was genuine and is now fixed; the
  feed still times out.
- **H5 (blocking) → un-demoted, now a leading candidate.** The ~25s constant is its signature.
- **H10 (infrastructure) → back in contention.** If the wait is `SOS_SCHEDULER_YIELD`, Round 4 was
  right and Round 5 was wrong to rule out hardware.
- **Lesson:** three confident diagnoses in this investigation have now been falsified (missing
  indexes as root cause; CPU throttling; query shape as binding constraint). Each was measured but
  measured the wrong thing. Establish the wait type before the next change.

---

## Round 7 — ROOT CAUSE: query memory grant starvation (2026-09-17)

`sys.dm_exec_requests` during a slow period:

| session | blocking_session_id | wait_type | wait_time | status | command |
|---|---|---|---|---|---|
| 54 | 0 | **RESOURCE_SEMAPHORE** | 21829 | suspended | DELETE |
| 55 | 0 | **RESOURCE_SEMAPHORE** | 21804 | suspended | SELECT |
| 69 | 0 | NULL | 0 | running | SELECT |
| 72 | 0 | **RESOURCE_SEMAPHORE** | 24282 | suspended | SELECT |

`RESOURCE_SEMAPHORE` = the query is **suspended before it begins executing**, queueing for a memory
grant. SQL Server sizes the grant up front from the optimizer's estimate; if the pool cannot satisfy
it, the query waits.

### This is the first explanation that accounts for everything

| Observation | Explained |
|---|---|
| Unrelated queries at an identical ~25s | Same semaphore, same queue, same inherited wait |
| Feed unchanged by 533x fewer logical reads | The wait precedes execution — query cost is irrelevant to it |
| `blocking_session_id = 0` | Correct: a memory queue, not a lock (H5 is dead) |
| `physical reads = 0` | Nothing waiting on disk |
| CPU ~28% but never saturated | Not CPU-bound — parked |
| Trivial `UserNetworks` query at 25s | Small queries need grants too, and queue too |
| A **DELETE** waiting alongside | Not query-shape specific. Anything needing a grant is stuck |

### Why the grants are large

Memory grants are driven mainly by Sort and Hash operators. Both feeds sort on **unindexed** columns:

```
home feed   ORDER BY [Created] DESC   (chronological: false)
storyline   ORDER BY [Date]           (chronological: true)
```

`Drops` had no index on either. Every page therefore requested a grant large enough to sort the whole
visible set.

### Fix

`20260918032350_AddDropSortIndexes` — `IX_Drop_Created`, `IX_Drop_Date`. Removes the Sort operator
and most of the grant. Production script: `docs/migrations/AddDropSortIndexes.sql`.

**This reduces demand on the grant pool; it does not raise the ceiling.** The instance runs SQL Server
Express, capping `max server memory` at **1410 MB** on a 2 GB `db.t3.small`. Moving off Express is the
only way to raise it (Round 4).

### Corrections to earlier rounds

- **Round 4 was directionally right** — the instance *is* the problem — but the mechanism is memory,
  not CPU. Its specific CPU-throttling claim was already withdrawn within that round.
- **Round 5 was wrong.** The query defect was real and the 533x measurement was real, but it was never
  the binding constraint.
- **Round 6's H5 promotion was wrong.** `blocking_session_id = 0` rules out lock blocking. The ~25s
  constant was the right signal read as the wrong mechanism — a queue, but a memory queue.
- **The standing dismissal of a `Drops.Date` index was wrong.** It was dismissed on *cost* grounds
  ("only matters if the query scans a large set"). Under grant pressure the sort matters for an
  entirely different reason.

### Method note

Four diagnoses were falsified before this one: missing indexes as root cause, CPU throttling, query
shape as binding constraint, and lock blocking. Each rested on a real measurement of the wrong thing.
The wait type was decisive and was available from the first round — `sys.dm_exec_requests` and
`sys.dm_os_wait_stats` should be the *first* diagnostic for any "slow in prod, fast locally" report,
before any plan or index analysis.

### Next

1. Apply `AddDropSortIndexes.sql` to prod (off-peak — `Drops` is the largest table and the generated
   script builds both indexes in one transaction).
2. Re-check the interceptor. Expect the `RESOURCE_SEMAPHORE` waits and the ~25s constant to fall away.
3. If they persist, the Express 1410 MB ceiling is binding and the engine/instance decision from
   Round 4 returns.

**Hypothesis updates:**
- **H11 (new) — query memory grant starvation. CONFIRMED** by wait type.
- H1 real, fixed, not binding. H5 dead. H10 right in spirit, wrong mechanism.

---

## Resolution

> ⚠️ **Superseded by Round 3 (2026-09-17).** This section describes how the *incident* was
> stopped, not the root cause. Production telemetry shows the home feed running 25s against a
> 30s timeout. Read Round 3 before acting on anything below.

**Root Cause:** Prod was missing secondary indexes that the 2021 EF Initial migration declared (H9). Combined with a likely stale plan (reboot cleared the plan cache — H8). `GetTimelineDrops` recovered after indexes + SQL Server reboot.

**Confirmed:** Missing `Drops.UserId`, `NetworkDrops.DropId`, all `UserDrops` secondary indexes, and `DropId` on ImageDrops / MovieDrops / Comments.

**Not fixed:** Query still starts from all permission-visible drops (`GetAllDrops` 3-way OR) and only then filters by timeline (H1). That will get slow again as data grows even with indexes.

**Recommended Action:** Keep the new indexes. Next: invert `GetTimelineDrops` (and `GetAlbumDrops`) to drive from `TimelineDrops` / `AlbumDrops`, then apply permission on that small set.

### Follow-ups (performance, not required to stop the timeout)

1. **Drive from TimelineDrops** in `GetTimelineDrops` (same pattern as `TimelineShareLinkService.GetPreviewByTokenAsync`). Apply `GetAllDrops` only to that id set. Repeat for `GetAlbumDrops`.
2. **Replace the 3-way OR** in `GetAllDrops` with a `Union` of three seeks (owner / tag viewers / UserDrops) so the optimizer cannot fall back to scanning `Drops`. Same change in `PermissionService` (duplicated).
3. **`AsSplitQuery()` + drop dead `Include`s** in `MapDrops`. `QuestionService` already uses split queries. Skip the Tags projection when `tagIds` is empty (GetTimeline/GetAlbum pass `new List<long>()`).
4. **`AsNoTracking()`** on these read paths.
5. **Covering composites** if EXISTS still show up in plans: `UserDrops (UserId, DropId)`, `NetworkDrops (DropId, UserTagId)`. `Drops.Date` only after the rewrite, for `ORDER BY Date` on one timeline.
6. **Keyset pagination** instead of `OFFSET` if deep `skip` becomes slow. Reducing `take` from 50 to 15 matches the main feed but is a UX tradeoff.
7. Do not raise `CommandTimeout` as the fix. `CanView` should check one drop, not `GetAllDrops().Any(DropId)`.
