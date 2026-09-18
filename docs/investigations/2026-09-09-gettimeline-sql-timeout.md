# Investigation: Production GetTimeline SQL Timeout

**Status:** ✅ Resolved (incident). Remaining query-shape work not done.
**Date opened:** 2026-09-09
**Date resolved:** 2026-09-09

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

## Resolution

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
