# TDD: Admin Usage Metrics

**PRD:** `docs/prd/PRD_ADMIN_USAGE_METRICS.md` (v1.0)
**Status:** Draft
**Created:** 2026-09-19

---

## Overview

Give the Fyli owner an in-product **Usage** section on the existing `/admin` page so they can see whether families are coming back, capturing memories, and commenting — without running SQL.

Three metrics: **visits** (authenticated app sessions), **comments** (`Kind = Normal`), and **memory creations** (`Drop.Created`). Headline counts for today, last 7 days, and last 30 days, plus a last-7-days unique-visitor (DAU) strip. Tap a metric (or a DAU day) to see who, when, and — for comments and creations — which memory as an id plus an 80-character snippet.

This is operator tooling. Regular family users never see it. Existing Admin work (asks/bugs, 30-day joins, email change) is unchanged. Drops, comments, sharing, and drop access are untouched.

**Frontend is `fyli-fe-v2` only.** `fyli-fe` and `fyli-html` are out of scope.

Visit logging is silent, fire-and-forget, and must never block opening Fyli. A failed visit write never surfaces in the family UI.

### Closed product decisions (from PRD)

| Topic | Decision |
|-------|----------|
| What is a visit | Authenticated app session, not a memory open or feed impression |
| Session window | 30 minutes, server is source of truth |
| Time windows | Today (UTC calendar day) + rolling 7d + rolling 30d. No date picker |
| "Today" | UTC calendar day for bucketing; event times display in the admin's local timezone |
| Placement | New Usage card on `/admin`, after Asks & bugs, before Joined last 30 days |
| Comments | `Kind = Normal` only |
| Creations | `Drop.Created`, including archived and question-answer drops |
| History | Comments/creations full; visits from ship |
| List size | No cap, no paging |
| Owner's own visits | Count them |
| Snippets | First 80 characters, server-side, no media |

---

## !IMPORTANT! — Issues that must be addressed

The PRD has no `!IMPORTANT!` markers. Two implementation gaps still need an explicit choice because the written requirements and the current code do not line up 1:1.

### 1. Onboarding does not use `AppLayout`

PRD §1.1: record a visit when a signed-in user is in the authenticated app chrome (`AppLayout` / `meta.auth` routes), **including onboarding**.

Current routes:

| Route | `meta.auth` | `meta.layout` |
|-------|-------------|---------------|
| `/`, `/questions`, `/admin`, … | `true` | `'app'` → `AppLayout` |
| `/onboarding/welcome`, `/onboarding/first-moment` | `true` | `'public'` → `PublicLayout` |
| `/login`, `/s/:token`, `/email-change-notice/:token`, … | unset | `'public'` |

`App.vue` switches layout on `route.meta.layout === 'app'`. Firing only from `AppLayout` **misses onboarding**, which the PRD counts as using Fyli.

**Option A (recommended): `useVisitTracking` composable called from `App.vue`.**

Record when `route.meta.auth === true`. Covers AppLayout routes and authenticated PublicLayout routes (onboarding). Does not fire on share links, login, invites, or the email-change notice.

Triggers:

1. First time `meta.auth` is true (mount, or login → app / onboarding)
2. `document.visibilitychange` → `visible`, still subject to the 30-minute **server** debounce

Do **not** fire on every Vue route change. Watching `() => route.meta.auth` does not re-fire while the user stays authenticated (`/` → `/questions` stays `true`).

**Option B: Duplicate the call in `AppLayout` and `PublicLayout`, gated on auth.**

Same coverage, two call sites, easy to miss a third layout later.

**Decision: Option A.** One composable, one call site, matches "authenticated shell" rather than "one layout component."

### 2. Tapping a DAU day must update headlines, but `GET /api/admin/usage` has no `day`

PRD §3.4: tap a day in the 7-day strip to set the event list **and headline window conceptually** to that UTC day.

PRD §5.1 summary query is only `?window=today|7d|30d`. PRD §5.2 events already accept optional `day=YYYY-MM-DD` (when set, ignore `window`).

If headlines must follow the selected day, the summary endpoint has to know that day. Deriving counts on the client would mean fetching all three event lists (PII over the wire, three round trips, snippets unused for the cards).

**Option A (recommended): add optional `day=YYYY-MM-DD` to `GET /api/admin/usage`.**

When `day` is set, ignore `window` for the three metric counts. `dailyVisitors` is always the last 7 UTC days (unchanged). Same rule as events. Still no arbitrary from/to.

**Option B: only the event list filters to that day; headlines stay on the window control.**

Fewer API changes. Conflicts with "headline window conceptually."

**Decision: Option A.** Window control and day selection are mutually exclusive query modes (see UI). Both summary and events accept `day`.

---

## Do not reuse `Usages` / `EventService`

`Usages` (`EventName`, `UserId`, `CreatedAt`) is a generic fire-and-forget event log (`ADD_DROP`, `EDIT_DROP`, `VIEW_DROP`) with no path and no FK. `VIEW_DROP` is a drop open, which the PRD explicitly is **not** a visit.

Do **not** add visit rows there. Do **not** reuse `MemoryShareLink.ViewCount`. Do **not** add visit columns to `UserProfile`. New table: `AppVisits`.

---

## Component Diagram

```
fyli-fe-v2
├── App.vue                 useVisitTracking() — any meta.auth route
├── useVisitTracking.ts     mount / auth-true / visibilitychange → recordVisit
├── visitApi.ts             POST /api/visits (catch and ignore)
├── AdminView               /admin; Usage card between Asks and Joins
├── AdminUsageCard          window, headlines, DAU strip, event list
└── adminApi.ts             GET /api/admin/usage, GET /api/admin/usage/events

                    HTTPS / JSON
                           │
cimplur-core
├── VisitController         POST /api/visits  [CustomAuthorization]
├── AdminController         GET usage, GET usage/events  [AdminAuthorization]
├── VisitService            debounce + insert AppVisit
├── AdminService            summary + event lists (PII stays here)
├── UsageSnippet            whitespace collapse + 80-char truncate
└── StreamContext           AppVisit (+ existing Comment, Drop, ContentDrop)
```

---

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Entities/
│   │   ├── AppVisit.cs                         NEW
│   │   └── StreamContext.cs                    MODIFY (OnModelCreating + DbSet)
│   ├── Models/
│   │   ├── UsageModels.cs                      NEW
│   │   └── AdminModels.cs                      unchanged
│   ├── Utilities/
│   │   └── UsageSnippet.cs                     NEW
│   ├── Repositories/
│   │   ├── VisitService.cs                     NEW
│   │   └── AdminService.cs                     MODIFY (GetUsageAsync, GetUsageEventsAsync)
│   └── Migrations/                             NEW (AddAppVisit, generated)
├── Memento/
│   ├── Controllers/
│   │   ├── VisitController.cs                  NEW
│   │   └── AdminController.cs                  MODIFY (two GET actions)
│   ├── Models/
│   │   └── RecordVisitRequest.cs               NEW
│   └── Startup.cs                              MODIFY (AddScoped VisitService)
└── DomainTest/
    ├── Repositories/
    │   ├── VisitServiceTest.cs                 NEW
    │   ├── AdminServiceTest.cs                 MODIFY (usage + events)
    │   └── TestServiceFactory.cs               MODIFY (CreateVisitService)
    └── Utilities/
        ├── UsageSnippetTest.cs                 NEW
        └── UsageRangeTest.cs                   NEW

docs/
├── DATABASE_GUIDE.md                           MODIFY (entity summary + migration row)
├── release_note.md                             MODIFY
└── migrations/
    └── AddAppVisit.sql                         NEW (from EF, after generate)

fyli-fe-v2/src/
├── App.vue                                     MODIFY (useVisitTracking)
├── App.test.ts                                 NEW
├── composables/
│   ├── useVisitTracking.ts                     NEW
│   └── useVisitTracking.test.ts                NEW
├── services/
│   ├── visitApi.ts                             NEW
│   ├── visitApi.test.ts                        NEW
│   ├── adminApi.ts                             MODIFY
│   └── adminApi.test.ts                        MODIFY
├── views/admin/
│   ├── AdminView.vue                           MODIFY (insert Usage card)
│   ├── AdminView.test.ts                       MODIFY
│   ├── AdminUsageCard.vue                      NEW
│   └── AdminUsageCard.test.ts                  NEW
```

Do **not** change `AppBottomNav`, `AppDrawer`, router `/admin` gate, or `fyli-fe`.

---

## Interface Definitions

### Constants

```csharp
// Domain/Models/UsageModels.cs
public static class UsageWindows
{
    public const string Today = "today";
    public const string SevenDays = "7d";
    public const string ThirtyDays = "30d";
}

public static class UsageMetrics
{
    public const string Visits = "visits";
    public const string Comments = "comments";
    public const string Creations = "creations";
}

public static class VisitLimits
{
    public const int SessionMinutes = 30;
    public const int PathMaxLength = 200;
    public const int SnippetLength = 80;
}
```

Window and metric strings are compared case-insensitively. Persist and return the canonical lowercase values (`today`, `7d`, `30d`, `visits`, `comments`, `creations`). Event `Kind` uses those same metric strings.

`UsageRange` lives in `UsageModels.cs` (no extra file).

### Range resolution

```csharp
public static class UsageRange
{
    // Returns [start, end) in UTC.
    // day (YYYY-MM-DD) wins over window when both are present.
    public static (DateTime Start, DateTime End) Resolve(
        string window, string day, DateTime utcNow)
}
```

Parse `day` with **only**:

```csharp
DateTime.TryParseExact(
    day.Trim(),
    "yyyy-MM-dd",
    CultureInfo.InvariantCulture,
    DateTimeStyles.None,
    out var parsed)
```

Then `DateTime.SpecifyKind(parsed, DateTimeKind.Utc)`. Do **not** use `DateTime.Parse` / locale `TryParse` — those accept `2026/09/18`, `9-19-2026`, and other non-UTC-calendar values.

`string.IsNullOrWhiteSpace(day)` → ignore `day` and use `window`.

| Input | Start | End (exclusive) |
|-------|-------|-----------------|
| `day=YYYY-MM-DD` | that UTC date 00:00 | next UTC date 00:00 |
| `window=today` | `utcNow.Date` | `utcNow.Date.AddDays(1)` |
| `window=7d` | `utcNow.AddDays(-7)` | `utcNow.AddMinutes(1)` |
| `window=30d` | `utcNow.AddDays(-30)` | `utcNow.AddMinutes(1)` |
| missing both | treat as `today` | |
| invalid window (and no day) | `BadRequestException` | |
| invalid `day` format | `BadRequestException` | |

Rolling 7d/30d use a slightly-future exclusive end so a row inserted during the request is included. Do **not** accept an arbitrary `from`/`to`.

`dailyVisitors` ignores the requested window/day and is always the last 7 UTC calendar days ending today: `[utcNow.Date.AddDays(-6), utcNow.Date.AddDays(1))`. Oldest first. Days with no visits return `uniquePeople: 0`.

### Domain / response models

```csharp
public class UsageCountModel
{
    public int Count { get; set; }
    public int UniquePeople { get; set; }
}

public class DailyVisitorModel
{
    public string Date { get; set; }   // "YYYY-MM-DD" UTC
    public int UniquePeople { get; set; }
}

public class UsageSummaryModel
{
    public string Window { get; set; }          // "today"|"7d"|"30d", or null when Day is set
    public string Day { get; set; }             // "YYYY-MM-DD" or null
    public UsageCountModel Visits { get; set; }
    public UsageCountModel Comments { get; set; }
    public UsageCountModel Creations { get; set; }
    public List<DailyVisitorModel> DailyVisitors { get; set; }
}

public class UsageEventModel
{
    public string Kind { get; set; }           // "visits"|"comments"|"creations"
    public int UserId { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    public DateTime Created { get; set; }

    // visits
    public int? AppVisitId { get; set; }
    public string Path { get; set; }

    // comments + creations
    public int? DropId { get; set; }
    public string Snippet { get; set; }

    // comments
    public int? CommentId { get; set; }
}
```

Unused optional fields serialize as null. Do **not** add photo URLs, video URLs, or full `Stuff` / `Content`.

Day-mode is `Day != null` — do **not** invent `window: "day"`. When `day` is queried, set `Window = null` and `Day = "YYYY-MM-DD"`. When querying by window, set `Window` to the canonical window and `Day = null`.

Every event row sets `Kind` to the metric that produced it (`visits` / `comments` / `creations`).

### Request DTO (Memento.Web.Models)

```csharp
public class RecordVisitRequest
{
    public string Path { get; set; }
}
```

Admin GETs take query strings, not a body.

### Frontend types (`adminApi.ts` / `visitApi.ts`)

```typescript
export type UsageWindow = 'today' | '7d' | '30d'
export type UsageMetric = 'visits' | 'comments' | 'creations'

export interface UsageCount {
  count: number
  uniquePeople: number
}

export interface DailyVisitor {
  date: string
  uniquePeople: number
}

export interface UsageSummary {
  window: UsageWindow | null
  day: string | null
  visits: UsageCount
  comments: UsageCount
  creations: UsageCount
  dailyVisitors: DailyVisitor[]
}

interface UsageEventBase {
  kind: UsageMetric
  userId: number
  name: string | null
  email: string | null
  created: string
}

export interface VisitEvent extends UsageEventBase {
  kind: 'visits'
  appVisitId: number
  path: string
}

export interface CommentEvent extends UsageEventBase {
  kind: 'comments'
  dropId: number
  snippet: string
  commentId: number
}

export interface CreationEvent extends UsageEventBase {
  kind: 'creations'
  dropId: number
  snippet: string
}

export type UsageEvent = VisitEvent | CommentEvent | CreationEvent
```

C# `string` name/email may be null at runtime; TypeScript types them `| null` to match existing admin types.

**Render event rows from `selectedMetric` (and `event.kind`), never by sniffing `event.path`.** Unused C# fields still serialize as null, so duck-typing is wrong. Narrow on `kind` when you need a field that only one variant has (`appVisitId`, `commentId`).

---

## Data Flow

### Record a visit (family path — not admin)

```
Authenticated fyli-fe-v2 route (meta.auth === true)
  → useVisitTracking: first auth-true, or visibilitychange → visible
  → visitApi.recordVisit(route.path)   // fire-and-forget; catch → ignore
  → POST /api/visits { path }
       CustomAuthorization (401 if unsigned)
       Identity = CurrentUserId  (ignore any userId in the body)
  → VisitService.RecordAsync(userId, path)
       1. Sanitize path (below)
       2. If any AppVisit for userId with Created >= UtcNow - 30 minutes
          → return (idempotent no-op)
       3. Insert AppVisit { UserId, Path, Created = UtcNow }
  → 200 (insert and no-op)
```

Client must **not** POST on every Vue route change. Server debounce is the only real session window. Concurrent double-POST inside the window can insert two rows. **Do not** add a serializable transaction or unique constraint for this (same stance as the ask rate limit).

Visit write failures: controller does not catch. Global `CustomErrorHandler` logs and returns 5xx. Client swallows. The parent never sees an error.

### Usage summary (admin)

```
GET /api/admin/usage?window=today|7d|30d&day=YYYY-MM-DD
  → AdminAuthorization (401 / 403)
  → AdminService.GetUsageAsync(window, day)
       1. UsageRange.Resolve
       2. Visits: count + distinct UserId on AppVisit in [start, end)
       3. Comments: Kind == Normal, TimeStamp in range; count + distinct UserId
       4. Creations: Drop.Created in range (no Archived filter);
          count + distinct UserId
       5. dailyVisitors: last 7 UTC days, oldest first, zeros filled
  → 200 UsageSummaryModel
```

Do not join `ContentDrop` for the summary. Do not return event rows.

### Usage events (admin)

```
GET /api/admin/usage/events?metric=visits|comments|creations
                         &window=today|7d|30d
                         &day=YYYY-MM-DD
  → AdminAuthorization
  → AdminService.GetUsageEventsAsync(metric, window, day)
       1. UsageRange.Resolve (same as summary)
       2. Factory dictionary by metric (no switch/if-else chain)
       3. Join UserProfile for name/email
       4. Snippets via UsageSnippet.From (never send full text)
       5. Set Kind to the metric key on every row
       6. OrderByDescending timestamp, no Take/Skip
  → 200 UsageEventModel[]
```

Invalid `metric` → `BadRequestException`.

---

## Database Changes

EF Core Code-First. Do not hand-write the schema into production. After the entity and `OnModelCreating` exist:

```bash
cd cimplur-core/Memento
dotnet ef migrations add AddAppVisit --project Domain --startup-project Memento
dotnet ef migrations script 20260918032350_AddDropSortIndexes AddAppVisit \
  --project Domain --startup-project Memento --idempotent
```

Save the generated script to `docs/migrations/AddAppVisit.sql`, then adapt the history insert to production's EF6 `[__MigrationHistory]` table (same pattern as `docs/migrations/AddAsk.sql`). Production does **not** use EF migrations directly.

### Entity: `AppVisit`

**File:** `cimplur-core/Memento/Domain/Entities/AppVisit.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class AppVisit
    {
        [Key]
        public int AppVisitId { get; set; }

        public int UserId { get; set; }

        [Required]
        [MaxLength(200), Column(TypeName = "varchar")]
        public string Path { get; set; }

        public DateTime Created { get; set; }

        [ForeignKey("UserId")]
        public virtual UserProfile User { get; set; }
    }
}
```

No unique constraint on `(UserId, Created)`. Debounce is application logic.

Do **not** add `ICollection<AppVisit>` on `UserProfile` (same as `Ask`).

### StreamContext

`OnModelCreating`:

```csharp
modelBuilder.Entity<AppVisit>(entity =>
{
    entity.ToTable("AppVisits");
    entity.HasKey(e => e.AppVisitId);
    entity.HasIndex(e => e.Created);
    entity.HasIndex(e => new { e.UserId, e.Created });
    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

DbSet:

```csharp
public DbSet<AppVisit> AppVisits { get; set; }
```

Index `(Created)` serves window counts. Index `(UserId, Created)` serves the debounce lookup (`UserId` + `Created >= cutoff`).

### Reference SQL (builder regenerates from EF; production uses the generated file)

```sql
-- AddAppVisit. Safe to re-run.
-- Production history table is EF6 [__MigrationHistory], not EF Core [__EFMigrationsHistory].

IF OBJECT_ID(N'[AppVisits]', N'U') IS NULL
BEGIN
    CREATE TABLE [AppVisits] (
        [AppVisitId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Path] VARCHAR(200) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        CONSTRAINT [PK_AppVisits] PRIMARY KEY ([AppVisitId]),
        CONSTRAINT [FK_AppVisits_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId])
            ON DELETE NO ACTION
    );
    CREATE INDEX [IX_AppVisits_Created] ON [AppVisits] ([Created]);
    CREATE INDEX [IX_AppVisits_UserId_Created]
        ON [AppVisits] ([UserId], [Created]);
END
GO

IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM [__MigrationHistory]
    WHERE [MigrationId] LIKE N'%AddAppVisit'
)
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        INSERT INTO [__MigrationHistory]
            ([MigrationId], [ContextKey], [Model], [ProductVersion])
        VALUES (N'YYYYMMDDHHMMSS_AddAppVisit',
            N'Domain.Entities.StreamContext', 0x, N'9.0.8');
    ELSE
        INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
        VALUES (N'YYYYMMDDHHMMSS_AddAppVisit', N'9.0.8');
END
GO
```

Replace `YYYYMMDDHHMMSS` with the EF-generated migration id after `dotnet ef migrations add`. On SQL Server, EF `Restrict` emits `ON DELETE NO ACTION`.

Existing `Comment`, `Drop`, and `ContentDrop` are **unchanged**.

---

## API Endpoints

### New: Visit (not under `/api/admin`)

| Method | Path | Auth | Role | Notes |
|--------|------|------|------|-------|
| POST | `/api/visits` | JWT | none | Body `{ path?: string }`. 200 on insert and debounce no-op. |

`[CustomAuthorization]` only. Do **not** put `[AdminAuthorization]` on it. Do **not** accept `userId` in the body.

The client **always** sends a JSON body (`{ path }`). `BaseApiController` has `[ApiController]`; a missing body is **400** (do not claim empty POST → 200). `{ }` or `{ path: null }` is a valid body and sanitizes to `"/"`. 200 on insert and debounce no-op, empty object (or no body). Do not return the new id; the no-op has none.

### New: Admin usage (`[AdminAuthorization]` already on `AdminController`)

| Method | Path | Response |
|--------|------|----------|
| GET | `/api/admin/usage?window=&day=` | `UsageSummaryModel` |
| GET | `/api/admin/usage/events?metric=&window=&day=` | `UsageEventModel[]` newest first, **unbounded** |

Status codes (same as the rest of Admin):

| Case | Status |
|------|--------|
| Not authenticated | 401 |
| Authenticated, not admin | 403 |
| Invalid window / metric / day format | 400 |

Existing `GET /api/admin/asks`, `GET /api/admin/signups`, search, and email change are **unchanged**. Do not fold joins into Usage.

---

## Backend Design

This codebase uses `BaseService` + `StreamContext` (not a separate repository layer). New services follow that pattern. Throw typed exceptions (`BadRequestException`); global `CustomErrorHandler` formats the response.

### Path sanitization (`VisitService`)

```
1. Null → "/"
2. Trim
3. If empty after trim → "/"
4. Take substring before '?' (no query string)
5. Take substring before '#' (no hash)
6. If empty after that → "/"
7. Truncate to VisitLimits.PathMaxLength (do not 400 — logging must not fail closed)
```

Trim **before** stripping query/hash so `" /foo?x=1"` becomes `"/foo"`, not `" /foo"`. Do not add token-stripping beyond query/hash. Do not store user agent, IP, or referrer.

### `VisitService` (new)

Extends `BaseService`. No extra constructor dependencies.

```csharp
public async Task RecordAsync(int userId, string path)
{
    var sanitized = SanitizePath(path);
    var cutoff = DateTime.UtcNow.AddMinutes(-VisitLimits.SessionMinutes);
    var exists = await Context.AppVisits.AnyAsync(v =>
        v.UserId == userId && v.Created >= cutoff);
    if (exists)
        return;

    Context.AppVisits.Add(new AppVisit
    {
        UserId = userId,
        Path = sanitized,
        Created = DateTime.UtcNow
    });
    await Context.SaveChangesAsync();
}
```

### `VisitController` (new)

```csharp
[Route("api/visits")]
public class VisitController : BaseApiController
{
    private readonly VisitService visitService;

    public VisitController(VisitService visitService)
    {
        this.visitService = visitService;
    }

    [CustomAuthorization]
    [HttpPost]
    [Route("")]
    public async Task<IActionResult> Create(RecordVisitRequest request)
    {
        await visitService.RecordAsync(CurrentUserId, request?.Path);
        return Ok();
    }
}
```

### `UsageSnippet` (new)

Do **not** use `TextFormatter.CleanupWhiteSpace` — it only collapses double spaces, not newlines/tabs. PRD requires collapsing all whitespace.

```csharp
public static class UsageSnippet
{
    public static string From(string text, int maxLength = VisitLimits.SnippetLength)
    {
        if (string.IsNullOrWhiteSpace(text))
            return "";

        var collapsed = string.Join(" ",
            text.Split((char[])null, StringSplitOptions.RemoveEmptyEntries));

        return collapsed.Length <= maxLength
            ? collapsed
            : collapsed.Substring(0, maxLength);
    }
}
```

No ellipsis (PRD: optional; skip so the stored/returned snippet is at most 80 characters). Apply in C# after the query; do not send `Stuff` / `Content` to the client.

### `AdminService` (modify)

Add two public methods. Keep existing asks / signups / search / email-change methods untouched.

```csharp
public async Task<UsageSummaryModel> GetUsageAsync(string window, string day)
public async Task<List<UsageEventModel>> GetUsageEventsAsync(
    string metric, string window, string day)
```

Event loaders — **static** factory dictionary, not a switch, not allocated per request:

```csharp
private static readonly Dictionary<string,
    Func<AdminService, DateTime, DateTime, Task<List<UsageEventModel>>>>
    EventLoaders = new(StringComparer.OrdinalIgnoreCase)
{
    [UsageMetrics.Visits] = (s, a, b) => s.LoadVisitEventsAsync(a, b),
    [UsageMetrics.Comments] = (s, a, b) => s.LoadCommentEventsAsync(a, b),
    [UsageMetrics.Creations] = (s, a, b) => s.LoadCreationEventsAsync(a, b)
};
```

Look up with `EventLoaders.TryGetValue(metric, out var loader)`. Each loader sets `Kind` on every row to that metric key.

Unknown metric → `BadRequestException("Unknown metric.")`.

Comment filter: `c.Kind == KindOfComments.Normal` (enum 0). Do not require the parent drop to be un-archived.

Creation query: `Drops` by `Created` in range. **No** `Archived` filter. **No** filter on `Assisted`, timeline, or sharing. Left-join `ContentDrop` only to read `Stuff` for the snippet. Missing content → empty snippet. Headline number is drops created, not unique memories after edits.

Visit events: `AppVisit` + `UserProfile`. Include `AppVisitId` (v-for key). `Kind = "visits"`. No snippet.

All lists: `OrderByDescending` on the event timestamp (`Created` / `TimeStamp`). No `Take` / `Skip`.

Count unique people with `Select(x => x.UserId).Distinct().Count()` (or equivalent) on the same filtered set as `Count`. Do not exclude the admin's own user id.

Split `GetUsageAsync` so no method exceeds 100 lines: resolve range, three count helpers, `GetDailyVisitorsAsync`.

### `AdminController` (modify)

```csharp
[HttpGet]
[Route("usage")]
public async Task<IActionResult> GetUsage(
    [FromQuery] string window, [FromQuery] string day)
{
    return Ok(await adminService.GetUsageAsync(window, day));
}

[HttpGet]
[Route("usage/events")]
public async Task<IActionResult> GetUsageEvents(
    [FromQuery] string metric,
    [FromQuery] string window,
    [FromQuery] string day)
{
    return Ok(await adminService.GetUsageEventsAsync(metric, window, day));
}
```

### DI

`Startup.cs`: `services.AddScoped<VisitService, VisitService>();`

`TestServiceFactory.CreateVisitService()` returns `new VisitService()`.

---

## Frontend Components

**Target: `fyli-fe-v2` only.** Style: Bootstrap 5 + `var(--fyli-*)`. No hardcoded hex. No chart library. No new route. No admin sub-nav.

### `visitApi.ts`

```typescript
import api from './api'

export async function recordVisit(path: string): Promise<void> {
  try {
    await api.post('/visits', { path })
  } catch {
    // Visit logging must never surface in the family UI.
  }
}
```

Always resolve. Never rethrow. Tests: posts `/visits` with `{ path }`; rejected axios does not throw to the caller.

### `useVisitTracking.ts`

Called from `App.vue` (root, always mounted).

```typescript
export function useVisitTracking() {
  const route = useRoute()

  function maybeRecord() {
    if (route.meta.auth !== true) return
    void recordVisit(route.path)
  }

  onMounted(() => {
    maybeRecord()
    document.addEventListener('visibilitychange', onVisible)
  })

  onUnmounted(() => {
    document.removeEventListener('visibilitychange', onVisible)
  })

  function onVisible() {
    if (document.visibilityState === 'visible') maybeRecord()
  }

  watch(() => route.meta.auth, (auth, previous) => {
    if (auth === true && previous !== true) maybeRecord()
  })
}
```

No client-side 30-minute skip is required (server debounce is enough at ~100 DAU). Do not watch `route.path`.

`App.vue`:

```vue
<script setup lang="ts">
import { useRoute } from 'vue-router'
import PublicLayout from '@/layouts/PublicLayout.vue'
import AppLayout from '@/layouts/AppLayout.vue'
import { useVisitTracking } from '@/composables/useVisitTracking'

const route = useRoute()
useVisitTracking()
</script>
```

Do **not** call `recordVisit` from `AdminView` only.

### `adminApi.ts` (add)

```typescript
export function getUsage(window: UsageWindow, day?: string) {
  return api.get<UsageSummary>('/admin/usage', {
    params: day ? { day } : { window },
  })
}

export function getUsageEvents(
  metric: UsageMetric,
  window: UsageWindow,
  day?: string,
) {
  return api.get<UsageEvent[]>('/admin/usage/events', {
    params: day ? { metric, day } : { metric, window },
  })
}
```

When `day` is set, omit `window` so the server does not have two sources of truth in the query string (it would ignore `window` anyway).

### `AdminView.vue` (modify)

Page order becomes:

1. Asks & bugs
2. **Usage** (`AdminUsageCard`)
3. Joined last 30 days
4. Change user email

Place `<AdminUsageCard />` after the asks card, still inside the `v-else` of `loadError` so a 403/error on asks keeps current whole-page behavior. `loadError` starts false, so the Usage card **mounts on first paint** and fetches in parallel with `getAsks` / `getSignups`.

Do **not** add `getUsage` to the existing `Promise.all`. Usage failure must not set `loadError`.

Keep existing 403 redirect on asks/signups. `AdminUsageCard` also redirects on 403 (same as today: any admin usage endpoint 403 leaves `/admin`).

### `AdminUsageCard.vue` (new)

Single-responsibility card. Own loading, error, retry, window, day, metric, and event list. Uses `useRouter` for 403.

#### State

| Ref | Default | Meaning |
|-----|---------|---------|
| `window` | `'today'` | Last explicit window button |
| `selectedDay` | `null` | UTC `YYYY-MM-DD` when a DAU cell is selected |
| `selectedMetric` | `null` | Event list closed until a metric (or day) is chosen |
| `summary` | empty zeros + 7 zero days | Headline + strip |
| `events` | `[]` | Drill-down rows |
| `summaryLoading` / `summaryError` | | Card-level |
| `eventsLoading` / `eventsError` | | List-level only |

Query mode is mutually exclusive:

- Tapping **Today / 7 days / 30 days** sets `window`, clears `selectedDay`, reloads summary (and events if a metric is open).
- Tapping a **DAU day** sets `selectedDay`, and if `selectedMetric` is null sets it to `'visits'` (the strip is DAU). Reloads summary with `day` and events for that day.
- Tapping the **already-selected metric collapses** the list (`selectedMetric = null`) and does not fetch. Tapping a different metric opens that list. **Decision: toggle**, not persist-open.

Window buttons, metric buttons, and DAU cells all use `aria-pressed` (not `aria-checked`). Window `aria-pressed` is true only when that window is selected **and** `selectedDay` is null. DAU `aria-pressed` is true when that date equals `selectedDay`. A selected day may leave every window button unpressed — that is why this is a toggle group, not a radiogroup.

#### Layout (inside existing `card` / `card-body`)

```
Usage                         h2.h6
[ Today | 7 days | 30 days ]  btn-group, role=group, aria-label="Time window"
[ Visits ] [ Comments ] [ Memories ]
  14          3            2
  8 people    2 people     2 people
[ Sun 13 ] [ Mon 14 ] … [ Sat 19 ]   unique visitors; 0 not blank
(event list if selectedMetric)
```

Labels: **Visits**, **Comments**, **Memories** (creations — family word). Unique subtitle: `1 person` / `N people`.

#### Markup rules

- Real `<button type="button">` for window, metrics, and DAU cells. Not clickable divs.
- Window control: `role="group"` `aria-label="Time window"`. **Not** `role="radiogroup"` (a selected DAU day leaves zero radios checked).
- Metric `aria-label` includes the count: `"Visits, 14"`.
- Metric selected: `btn btn-primary`. Unselected: `btn btn-outline-secondary`. Same for window and DAU cells. No new palette.
- Three metric buttons: `row row-cols-3 g-2`; each `btn w-100`. `min-height: 44px` in scoped CSS (touch target).
- DAU strip: `d-flex gap-1`; each `btn btn-sm flex-fill` with `min-height: 44px`. Weekday label via `toLocaleDateString(undefined, { weekday: 'short', timeZone: 'UTC' })` so the label matches the UTC day, not local midnight.
- Numbers: `font-variant-numeric: tabular-nums` in scoped CSS. Do **not** animate counters.
- Event list: `<ul class="list-unstyled">` / `<li class="border-bottom py-3">`. Newest first (server order). No pager. **No virtual scroll** (PRD; accepted exception to the long-list checklist at ~100 DAU).
- `v-for` keys: visits `appVisitId`, comments `commentId`, creations `dropId`. Not the array index.
- Row template is chosen from `selectedMetric` (visit vs comment vs creation). Do **not** duck-type `event.path`.
- Name: same helper as Admin — empty/whitespace name → email.
- Times: `<time :datetime="row.created">{{ localString }}</time>` using `toLocaleString()` (admin browser local tz).
- Visit path: `small font-monospace text-muted text-break`. Interpolate with `{{ }}` only.
- Snippet: `text-break`, visible on the row (not tooltip-only). Interpolate with `{{ }}` only.
- **Never `v-html`** on snippets, paths, names, or emails. Vue escaping is the XSS control.
- Empty: `EmptyState` with "No visits yet in this window" / "No comments yet in this window" / "No memories created in this window".
- Summary error: existing `ErrorState` + retry for the card; asks/signups stay visible.
- Events error: `ErrorState` + retry for the list only.
- Loading: existing `LoadingSpinner`.
- No photos, no videos, no link to memory detail.

#### Fetch

- On mount: `getUsage('today')`.
- On window / day change: `getUsage(window, day?)`.
- On metric open (and when range changes while a metric is open): `getUsageEvents(metric, window, day?)`.
- Do not fetch events on first page load until a metric or day is selected.

403 → `router.replace('/')`. Other errors stay on the card.

---

## Designer Review

Reviewed against `docs/FRONTEND_STYLE_GUIDE.md` and the designer skill checklist.

### Design decisions

- Usage lives in the same Bootstrap `card mb-3` pattern as Asks and Joins so the Admin page stays one column inside `AppLayout` max-width 600px.
- Selected state is existing `btn-primary` (`#56c596` via Bootstrap `$primary`). Unselected is `btn-outline-secondary`. No new colors, no charts.
- Window control is a full-width `btn-group` directly under the heading (PRD). Metric buttons are a 3-column row of stacked label / number / people so the pulse is scannable before any list.
- DAU strip is always visible and visually quieter (`btn-sm`) than the headline metrics — it is a pulse, not a third set of KPIs.
- Event rows copy Asks (`border-bottom`, name, muted metadata). Snippets wrap. Path is muted monospace so it does not compete with the person.

### Consistency

- Heading `h2.h6`, `card` / `card-body`, `EmptyState`, `ErrorState`, `LoadingSpinner`, `displayName` helper — all existing Admin patterns.
- No hardcoded hex. Scoped CSS is limited to `min-height: 44px` and `tabular-nums`.
- Primary CTA language is unused here (this card has no save). Destructive styles unused.

### Accessibility

- `role="group"` + `aria-pressed` for the window (not a radiogroup); `aria-pressed` for metric and DAU toggles; metric accessible name includes the count.
- 44px minimum touch targets on every control.
- Event list is a list. Times have a human-readable string plus `datetime`.
- Selected primary buttons: Bootstrap sets white text on `$primary`. Do **not** apply `text-muted` on the people subtitle when the metric is selected (contrast would fail). Unselected subtitle uses `text-muted`.
- DAU weekday labels use `timeZone: 'UTC'` so a Pacific-time admin does not see UTC Monday labeled as Sunday.

### Visual hierarchy

1. Section title
2. Window (what period)
3. Three headline counts (the pulse)
4. DAU strip (secondary pulse)
5. Event list (detail, only when asked)

### Recommended implementation notes (already in the component spec)

- `row-cols-3` rather than stacking on phone: PRD allows 3-across wrapping; 600px is enough if each button is ≥44px tall.
- Empty visits after ship is expected copy, not an error.
- Do not add hover-lift on metric buttons beyond Bootstrap `btn` — this is a dense operator tool, not a marketing card.

No blocking design issues.

---

## Testing Plan

Write failing tests first. Backend tests are MSTest integration tests against local SQL Server (`CreateTestContext`, **no** transaction, `DetachAllEntities` before service calls, verify with `CreateVerificationContext` where asserting inserts). Frontend: Vitest + Vue Test Utils. After adding types, run `npx vue-tsc --noEmit` (Vite build does not typecheck). `noUncheckedIndexedAccess`: guard or `!` on `[i]` / `.split()[0]`.

### Backend — `UsageSnippetTest`

No SQL Server. Pure unit tests.

| Test | Expect |
|------|--------|
| `From_Null_ReturnsEmpty` | `""` |
| `From_Whitespace_ReturnsEmpty` | `""` |
| `From_NewlinesAndTabs_CollapsesToSingleSpaces` | `"a b c"` |
| `From_Exactly80_Unchanged` | length 80, no truncation |
| `From_81_TruncatesTo80` | length 80, first 80 chars, no ellipsis |

### Backend — `UsageRangeTest`

No SQL Server. Pure unit tests. Pass an explicit `utcNow`.

| Test | Expect |
|------|--------|
| `Resolve_Day_WinsOverWindow` | `[day, day+1)` even if `window=30d` |
| `Resolve_Today` | `[utcNow.Date, utcNow.Date+1)` |
| `Resolve_7d` | start = `utcNow.AddDays(-7)` |
| `Resolve_30d` | start = `utcNow.AddDays(-30)` |
| `Resolve_MissingBoth_TreatsAsToday` | same as today |
| `Resolve_InvalidWindow_ThrowsBadRequest` | `BadRequestException` |
| `Resolve_InvalidDay_SlashFormat_ThrowsBadRequest` | `"2026/09/18"` throws |
| `Resolve_InvalidDay_UsFormat_ThrowsBadRequest` | `"9-19-2026"` throws |
| `Resolve_BlankDay_FallsThroughToWindow` | whitespace `day` uses `window` |

### Backend — `VisitServiceTest`

Category `Integration`, `VisitService`. Unique users per test (shared `Master` DB).

| Test | Expect |
|------|--------|
| `RecordAsync_FirstCall_InsertsRow` | one `AppVisit`, `UserId`, sanitized path, `Created` ≈ UtcNow |
| `RecordAsync_Within30Minutes_DoesNotInsert` | still one row |
| `RecordAsync_After30Minutes_InsertsSecond` | two rows (backdate first `Created` to UtcNow - 31 min) |
| `RecordAsync_NullPath_StoresSlash` | `"/"` |
| `RecordAsync_WhitespacePath_StoresSlash` | `"   "` → `"/"` |
| `RecordAsync_QueryString_Stripped` | `"/questions?x=1"` → `"/questions"` |
| `RecordAsync_Hash_Stripped` | `"/#foo"` → `"/"` |
| `RecordAsync_LeadingSpaceAndQuery_TrimmedThenStripped` | `" /foo?x=1"` → `"/foo"` |
| `RecordAsync_LongPath_TruncatedTo200` | length 200 |
| `RecordAsync_DoesNotWriteOtherUser` | recording for A does not create a row for B |

### Backend — `AdminServiceTest` (add)

Do not break existing asks/signups/search/email tests.

Shared `Master` DB: **never assert global exact counts.** Create users in the test, filter results to those `UserId`s (or `Any` / `Where` like existing signup tests). `Count` / `UniquePeople` assertions are on the filtered subset, not `result.Visits.Count == 3` against the whole table.

| Test | Expect |
|------|--------|
| `GetUsageAsync_Today_IncludesTodayExcludesYesterday` | visit at UtcNow in; `Date.AddTicks(-1)` out |
| `GetUsageAsync_7d_IncludesInsideExcludesOutside` | 6.9 days in; 8 days out |
| `GetUsageAsync_30d_IncludesInsideExcludesOutside` | 29 days in; 31 days out |
| `GetUsageAsync_Visits_CountAndUniquePeople` | 3 rows, 2 users → count 3, unique 2 (filtered to those users) |
| `GetUsageAsync_Comments_ExcludesThankAndUnThank` | only `Kind = Normal` |
| `GetUsageAsync_Creations_IncludesArchived` | archived drop still counted |
| `GetUsageAsync_Creations_UsesCreatedNotDate` | old `Created`, recent `Date` → not in today |
| `GetUsageAsync_IncludesAdminOwnVisits` | admin user's visit counted |
| `GetUsageAsync_DailyVisitors_Always7DaysOldestFirst_ZerosFilled` | length 7, first = today-6 UTC, zeros present |
| `GetUsageAsync_DayParam_IgnoresWindow_WindowNullOnResponse` | only that UTC day; `Day` set; `Window` null |
| `GetUsageAsync_InvalidWindow_ThrowsBadRequest` | `BadRequestException` |
| `GetUsageAsync_InvalidDay_ThrowsBadRequest` | `BadRequestException` |
| `GetUsageEventsAsync_Visits_NewestFirst_HasPathNoSnippet` | order, path set, snippet null, `Kind = "visits"` |
| `GetUsageEventsAsync_Comments_Snippet80_NoMedia` | truncated snippet; no image fields; `Kind = "comments"` |
| `GetUsageEventsAsync_Comments_ExcludesThankAndUnThank` | Thank/UnThank rows absent from the list |
| `GetUsageEventsAsync_Creations_EmptyStuff_EmptySnippet` | `""`; `Kind = "creations"` |
| `GetUsageEventsAsync_Comments_EmptyContent_EmptySnippet` | `""` |
| `GetUsageEventsAsync_UnknownMetric_ThrowsBadRequest` | `BadRequestException` |
| `GetUsageEventsAsync_DayParam_OnlyThatUtcDay` | excludes other days |
| `GetUsageEventsAsync_ListLengthMatchesSummaryCount` | same window, same metric, filtered to test users |

Backdate `AppVisit.Created`, `Comment.TimeStamp`, and `Drop.Created` on committed rows, then `DetachAllEntities`.

### Frontend — `visitApi.test.ts`

- `recordVisit` POSTs `/visits` with `{ path }`.
- Mock `api.post` rejection → `recordVisit` resolves, does not throw.

### Frontend — `useVisitTracking.test.ts`

Stub `vue-router` `useRoute` with a mutable `meta` / `path`. Mock `visitApi`. Call `wrapper.unmount()` (or invoke the composable's `onUnmounted`) so listeners do not leak across tests.

- `meta.auth === true` on mount → `recordVisit` called with `route.path`.
- `meta.auth` unset (login) → not called.
- `meta.auth` unset → `true` (login / first authenticated navigation) → `recordVisit` called. This is why tracking lives in `App.vue`.
- `visibilitychange` to `visible` while auth → called again.
- `visibilitychange` to `hidden` → not called.
- `route.path` change while `auth` stays true → not called.
- `recordVisit` rejection → composable does not throw.
- After unmount, `visibilitychange` to `visible` → **not** called (listener removed).

### Frontend — `App.test.ts`

Mock `useVisitTracking`. Mount `App.vue` (stub layouts / `RouterView` as needed). Expect `useVisitTracking` to have been called. If this call is omitted, composable tests still pass and no visits are recorded.

### Frontend — `adminApi.test.ts`

- `getUsage('today')` → `GET /admin/usage` `{ params: { window: 'today' } }`.
- `getUsage('7d', '2026-09-18')` → params `{ day: '2026-09-18' }` (no window).
- `getUsageEvents('visits', 'today')` → params `{ metric: 'visits', window: 'today' }`.
- `getUsageEvents('comments', '7d', '2026-09-18')` → params `{ metric, day }` (no window).

### Frontend — `AdminUsageCard.test.ts`

Fixture: non-zero visits/comments/creations, 7 `dailyVisitors` (mix of 0 and >0).

| Test | Expect |
|------|--------|
| Renders heading Usage, window Today/7 days/30 days, three metric labels | |
| Default window is Today; `getUsage` called with `'today'` | |
| Switching to 7 days calls `getUsage('7d')` and updates counts | |
| Switching to 7 days **while Visits is open** also calls `getUsageEvents('visits', '7d')` | |
| Metric tap (Visits) calls `getUsageEvents('visits', 'today')` and renders rows | |
| Tapping selected metric collapses the list (no extra fetch) | |
| Visit row shows name (or email), email, user id, local time, path | |
| Comment/creation row shows dropId + snippet, no `<img>` | |
| Snippet containing `<script>` / `<img>` is text (`{{ }}`); no `v-html`, no extra elements | |
| DAU cell with 0 shows `0` | |
| Tapping a DAU day calls `getUsage` with `day` and loads visit events for that day | |
| Empty visits copy | "No visits yet in this window" |
| Summary failure shows ErrorState; Retry calls `getUsage` again | |
| 403 on `getUsage` → `replace('/')` | |
| 403 on `getUsageEvents` → `replace('/')` | |
| Events failure does not hide headline counts | |

### Frontend — `AdminView.test.ts` (modify)

- Mock `getUsage` / `getUsageEvents` (module mock currently omits them; `AdminUsageCard` will call them).
- Heading order: Asks & bugs, **Usage**, Joined last 30 days, Change user email.
- Existing 403 on asks still redirects.
- `getUsage` rejection (non-403) does **not** set whole-page `loadError` (asks still render).
- Asks / signups / email-change tests still pass.

No new Pinia store. No fixture changes to `User` / `Drop` required.

---

## Implementation Order

TDD: failing tests first, then minimum code, then refactor.

### Phase 1: Record visits + Usage summary

1. `AppVisit` entity, `StreamContext` config + `DbSet`.
2. `dotnet ef migrations add AddAppVisit`; copy idempotent SQL to `docs/migrations/AddAppVisit.sql` (adapt `__MigrationHistory`).
3. `UsageSnippet` + `UsageRange` unit tests (no SQL).
4. `VisitService` + `VisitServiceTest`; `RecordVisitRequest`; `VisitController`; DI.
5. `GetUsageAsync` + AdminService tests for summary (no events yet).
6. `GET /api/admin/usage` on `AdminController`.
7. `visitApi` + `useVisitTracking` + `App.vue` + `App.test.ts`.
8. `getUsage` in `adminApi`; `AdminUsageCard` without the event list (window, headlines, DAU strip, empty/error/403). DAU cells in this phase may set `selectedDay` and refetch summary; no list yet.
9. Insert card into `AdminView`; update AdminView tests.
10. `DATABASE_GUIDE.md` entity summary + migration row; `release_note.md`.

### Phase 2: Event-list drill-down

1. `GetUsageEventsAsync` + factory loaders + AdminService tests.
2. `GET /api/admin/usage/events`.
3. `getUsageEvents` in `adminApi`.
4. Metric toggle + event rows + DAU day → list in `AdminUsageCard`.
5. Remaining AdminUsageCard tests (list, snippets, collapse, list-only error).

Do not ship Phase 2 without Phase 1 logging live — otherwise the visit list is always empty and the owner cannot tell "no one came" from "we are not recording yet." Phase 1 empty copy ("No visits yet in this window") is the expected first-day state.

---

## Backwards Compatibility

- Additive table, additive endpoints, additive Admin card.
- Users with no role: unchanged. They generate visits when they use the app.
- JWT shape unchanged (`id` claim only).
- Drops, comments, sharing, drop access: **untouched**.
- `GET /api/admin/signups` stays; do not fold joins into Usage.
- Existing `Usages` / `EventService` unchanged.
- `fyli-fe` and `fyli-html` unchanged.

---

## Security and Privacy

- Usage and event APIs are admin-only (other users' names, emails, snippets).
- Visit POST is authenticated and bound to `CurrentUserId`.
- Snippets computed server-side. Do not send full `Stuff` / `Content`.
- No photos, video URLs, or memory-detail links.
- Paths: no query string (tokens live there on some public routes; those routes must not call this POST).
- Frontend: **never `v-html`** snippets, paths, names, or emails — `{{ }}` only.
- Do not log visit payloads into client-visible errors.
- Do not add a generic "run this SQL" endpoint.

---

## Scale

Assumed max ~100 DAU. Count/distinct on source tables for the window is acceptable. No Redis, no rollup table, no background aggregation, no virtual scroll, no paging. If a 30-day visit list ever feels long, that is a later problem.

---

## Documentation

| File | Change |
|------|--------|
| `docs/DATABASE_GUIDE.md` | Entity summary: **AppVisit** — authenticated session log. Migration history row for `AddAppVisit`. |
| `docs/release_note.md` | Admin Usage section; silent visit logging; no family-facing change. |
| `docs/migrations/AddAppVisit.sql` | Generated + `__MigrationHistory` adapt. |
| `docs/AI_PROMPTS.md` | **Do not modify.** |

---

## Out of Scope (this TDD)

Matches the PRD: memory-detail views, share-link `ViewCount`, anonymous/marketing traffic, date picker, charts, `/admin/usage` route, by-person ranking, opening the full memory, Thanks as a fourth metric, derived retention metrics, websockets, excluding the owner, geo/device/UTM, daily rollup table, `fyli-fe`, third-party analytics.

---

## Review

Code-review of this TDD (2026-09-19) against `.claude/skills/code-review/SKILL.md`. Findings below were **applied in v1.1** (this document). No implementation exists yet.

Checklist notes that apply to the spec:

- 3-tier / existing `BaseService` pattern: yes (no separate repository layer in this codebase)
- Controllers thin, services own logic, EF Code-First + SQL Server reference SQL: yes
- Drops and drop access: untouched (additive `AppVisits` only)
- Frontend `fyli-fe-v2`, Composition API, no new Pinia store: yes
- Tests for backend services/utilities and frontend components/APIs/composables: yes
- Designer review present: yes
- `cimplur-core/docs/DATA_SCHEMA.md` is not the project doc — TDD correctly updates `docs/DATABASE_GUIDE.md`

### Critical Issues

None. Additive schema and endpoints; JWT unchanged; visit POST is authenticated and bound to `CurrentUserId`; usage/event reads stay behind `[AdminAuthorization]`; snippets are server-truncated; no jsonb.

### Applied from review (v1.1)

1. Event `Kind` discriminator (`visits` / `comments` / `creations`). Rows render from `selectedMetric` / `kind`, not `event.path`.
2. `day` parsed with `TryParseExact("yyyy-MM-dd", InvariantCulture)` only.
3. Window control is `role="group"` + `aria-pressed`, not a radiogroup.
4. Missing JSON body on `POST /api/visits` is 400 (`[ApiController]`). Client always sends `{ path }`. `{ }` / `{ path: null }` → `"/"`.
5. Path trim happens before stripping `?` / `#`.
6. `EventLoaders` is a static `readonly` dictionary.
7. Tests added: login `auth` unset → true; unmount removes `visibilitychange`; window change while a list is open; Thank/UnThank excluded from events; `UsageRange` unit tests; `App.test.ts` asserts `useVisitTracking` is called; AdminService asserts filter to the test's users.
8. `{{ }}` only — never `v-html` on snippets, paths, names, emails.
9. Summary day-mode is `Day != null` / `Window = null`. No invented `window: "day"`.
10. No virtual scroll (PRD; accepted at ~100 DAU). Client 30-minute skip remains optional; server debounce is enough.

### Positive Notes

- Onion layout matches Admin: thin controllers, writes in `VisitService`, PII reads in `AdminService` behind `[AdminAuthorization]`.
- Factory dictionary for event metrics, not a switch.
- Onboarding coverage via `App.vue` + `meta.auth` instead of `AppLayout` only.
- Independent Usage error so asks/signups do not die with the new card.
- Snippets truncated server-side; `Usages` / `VIEW_DROP` not reused.
- Toggle-to-collapse and day-wins-over-window are explicit.
- Designer pass stayed on Bootstrap + `btn-primary` and called out the `text-muted`-on-selected contrast trap.
- `noUncheckedIndexedAccess` / `vue-tsc` called out in the testing plan.

---

*Document Version: 1.1*
*Created: 2026-09-19*
*Updated: 2026-09-19 (code-review findings applied)*
*Status: Draft*
