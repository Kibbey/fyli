# Technical Design Document: User Avatars

**PRD:** `docs/prd/PRD_USER_AVATARS.md`
**Status:** Draft — revised after code review
**Created:** 2026-09-19

---

## Overview

Users get one optional square photo. It is stored as a single 256 × 256 JPEG in the existing S3 bucket, keyed by an unguessable `AvatarToken` GUID that lives on `UserProfile`. Every surface that shows a name today gains an avatar beside it, rendered by one shared `UserAvatar` Vue component that falls back to the initials circle already in use.

Four properties drive the design:

1. **No new table, no new join.** Avatars are three nullable columns on `UserProfile`. Every projection that already walks `s.CreatedBy` or `t.Owner` picks up the token for free — critical given the open `GetTimeline` query-timeout investigation.
2. **The URL is the permission.** Avatars must be readable by anonymous share-link visitors (PRD decision). Serving them by `AvatarToken` rather than `UserId` means a link exposes exactly the faces on that page and nothing more; `/api/avatars/1`, `/2`, `/3` does not exist.
3. **A dedicated imaging path for avatars.** Avatars are the only images Fyli serves to unauthenticated viewers, so they are the only images that must be stripped of EXIF/GPS. Drop images keep their existing pipeline byte-for-byte; the two paths share primitives through a new pure utility, not through a shared mutable service method.
4. **Additive everywhere.** Every schema change is a nullable column. Every model change is an additive field on a transport-only model. No `Drop`, `Comment`, `UserUser`, `TagDrop`, or `TagViewer` row is read or written differently, and no permission check changes. A user with no avatar produces exactly the payload and exactly the UI they get today.

---

## Component Diagram

```
┌──────────────────────── Presentation ───────────────────────┐
│  AvatarController (api/avatars)                             │
│    GET  {token:guid}/photo.jpg   ← ANONYMOUS + "avatars"    │
│                                     rate-limit policy       │
│    POST   /                      ← [CustomAuthorization]    │
│    DELETE /                      ← [CustomAuthorization]    │
│    POST   /suggested             ← [CustomAuthorization]    │
│    DELETE /suggested             ← [CustomAuthorization]    │
│                                                             │
│  UserController        (UserModel gains AvatarUrl)          │
│  ConnectionController  (ConnectionModel, SharingRecipient-  │
│                         Model gain AvatarUrl)               │
│  ShareLinkController / TimelineShareLinkController          │
│    (DropModel + CommentModel gain AvatarUrl)                │
└────────────────────────────┬────────────────────────────────┘
                             │
┌──────────────────────── Domain ─────────────────────────────┐
│  AvatarService : BaseService                                │
│    UploadAsync / AcceptSuggestedAsync / SkipSuggestedAsync  │
│    RemoveAsync / OpenAsync(token)                           │
│         │                          │                        │
│         ▼                          ▼                        │
│  ImageProcessing (static)   IAvatarSourceFetcher            │
│    LoadAsync / ApplyExif-    (typed HttpClient, host        │
│    Orientation / StripAll-   allowlist, size + time bounds) │
│    Metadata / CropToSquare                                  │
│         ▲                                                   │
│         └── ImageService.RotateImage delegates here          │
│             (drop images: orientation only, metadata kept)  │
│                                                             │
│  GoogleAuthService  → records PendingAvatarSourceUrl        │
│  DropsService / MemoryShareLinkService /                    │
│  TimelineShareLinkService / UserService / GroupService      │
│         → project AvatarToken onto existing navigations     │
└────────────────────────────┬────────────────────────────────┘
                             │
┌──────────────────────── Data ───────────────────────────────┐
│  UserProfile (+3 nullable columns)        S3: cimplur       │
│    AvatarToken, AvatarUpdatedAt,            avatars/{token} │
│    PendingAvatarSourceUrl                                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Design Decisions

| # | Decision | Rationale | Alternative rejected |
|---|----------|-----------|----------------------|
| 1 | Columns on `UserProfile`, not a `UserAvatar` table | One avatar per user is a 1:1 fact. A table would force a join into `MapDrops`, the exact query already timing out in production | Separate table — correct normalization, wrong performance profile |
| 2 | Key by `AvatarToken` (GUID), not `UserId` | The anonymous read endpoint is required by the PRD. A user-id URL is an enumeration surface over every face in the product | `/api/avatars/{userId}` — simpler, harvestable |
| 3 | **Stream through the API**, not a presigned S3 URL | Presigned URLs expire (3 h in `ImageService.GetLink`) and cannot be cached, so a stream showing 20 avatars would re-presign and re-fetch constantly. Token-keyed URLs are immutable, so `max-age=31536000, immutable` gives one fetch per browser per version | Presigned redirect — matches drop images, wrong for a small image repeated dozens of times per screen |
| 4 | Token regenerates on every upload | Doubles as cache-busting and invalidates the previous URL | Stable token + `?v=` — query strings cache less reliably through intermediaries |
| 5 | `AvatarUrl` is a computed getter on **transport-only** models; the raw token is `[JsonIgnore]` | EF cannot translate a URL-building method inside a projection. Projecting the `Guid?` and computing the string on the materialized model keeps one round trip | Post-materialization loop — works, adds a pass for no gain |
| 6 | Google photo fetched **server-side, on accept only** | Never hotlink a URL whose lifetime Google controls, and never tell Google when a Fyli page is rendered | Render the Google URL directly — leaks viewing activity, breaks on URL rotation |
| 7 | `IAvatarSourceFetcher` enforces an https + `googleusercontent.com` host allowlist | The only place Fyli fetches an externally-supplied URL. Without an allowlist it is a server-side request forgery primitive | Timeout only — bounds cost, not reach |
| 8 | **Separate avatar imaging path** via a new pure `ImageProcessing` utility; `ImageService`'s drop-image behaviour unchanged | Avatars are the only images served to anonymous viewers, so they are the only ones that must be stripped of EXIF/GPS. Stripping metadata inside the shared drop-image path would silently change five years of existing behaviour for no user benefit | Reusing `ImageService.ReSizeImageAsync` — see Critical Fix 1; it does not strip metadata, and making it do so is a backwards-compatibility change to drop images |
| 9 | Avatar onboarding step placed **after** First Moment | Nothing is inserted ahead of the activation moment. See Open Question 1 |
| 10 | **`PersonModelV2` / `Asked` are out of scope** | They are persisted, not merely transported — see Critical Fix 2. The share/invite surface is served by `SharingRecipientModel`, which carries a real `UserId` and is never persisted | Adding `AvatarUrl` to `PersonModelV2` — writes stale URLs into a `varchar(8000)` column |

---

## Critical Fixes Applied After Review

These three points corrected errors in the first draft. They are recorded here because each is a trap a builder would otherwise walk into.

### Fix 1 — EXIF/GPS must be stripped explicitly; re-encoding does not do it

The first draft asserted that re-encoding drops source metadata. It does not. `ImageService.RotateImage` (`ImageService.cs:212-260`) removes exactly three tags:

```csharp
image.Metadata.ExifProfile.RemoveValue(ExifTag.Orientation);
image.Metadata.ExifProfile.RemoveValue(ExifTag.ImageWidth);
image.Metadata.ExifProfile.RemoveValue(ExifTag.ImageLength);
```

ImageSharp carries the remaining `ExifProfile` — including `GPSLatitude` / `GPSLongitude` — straight through `SaveAsJpegAsync`. Because avatars are served by an **unauthenticated** endpoint, a parent uploading a phone selfie taken at home would publish their home coordinates to anyone holding a share link.

The avatar path must therefore null the metadata profiles explicitly:

```csharp
/// <summary>Removes every profile that can carry personal data. Applied to
/// avatars ONLY: they are the one image class Fyli serves to unauthenticated
/// viewers. Drop images intentionally keep their metadata (existing behaviour).
/// IccProfile is preserved so colours do not shift.</summary>
public static void StripAllMetadata(Image image)
{
    image.Metadata.ExifProfile = null;
    image.Metadata.IptcProfile = null;
    image.Metadata.XmpProfile = null;
}
```

Orientation is applied *before* stripping, so rotation survives the strip. Covered by `ImageProcessingTest.StripAllMetadata_RemovesGpsCoordinates`.

### Fix 2 — `PersonModelV2` is persisted; it must not gain a serialized property

The first draft listed `PersonModelV2.cs [MODIFY]`. That model is not transport-only. `GroupService.SaveCurrentPeople` (`GroupService.cs:333`) does:

```csharp
string currentPeople = JsonConvert.SerializeObject(people);
user.CurrentPeople = currentPeople;   // UserProfile.CurrentPeople is varchar(8000)
```

A computed `AvatarUrl` getter serializes. Every avatar URL (~55 chars) would be written into a durable blob where it goes stale the moment a token rotates, while eating the 8000-character budget — a user with many connections could overflow into truncation or a `DbUpdateException` on a code path with nothing to do with avatars.

`PersonModelV2` and its subclass `Asked` are out of scope.

This also corrects a surface-mapping error. `GET /api/timelines/{id}/invited` returns `List<Asked>` built from `SharingService.GetExistingRequests` — **pending share requests**, whose `Id` is a `RequestId` and whose subjects may be contacts who are not Fyli users at all. There is no `UserProfile` behind those rows, so there is no avatar to show. The PRD's "share / invite screens" surface is served instead by `GET /api/connections/sharing-recipients` → `SharingRecipientModel`, which carries a real `UserId` and is never persisted.

### Fix 3 — Migration must be deployed before the application

Once `UserProfile` carries the three columns, every EF query against `UserProfiles` names them in its `SELECT` — login, `GetUser`, `GetConnections`, and every `MapDrops` projection. Deploying the app before the migration produces `Invalid column name 'AvatarToken'` on essentially every request, including all drop access. See **Deployment** below.

---

## Database Changes

No new entity, no new `DbSet`, no FK configuration — these are scalar columns on an existing entity.

### Entity: `Domain/Entities/UserProfile.cs`

```csharp
// --- Avatar (all nullable; absent = no avatar, renders initials fallback) ---

/// <summary>Unguessable key for the stored avatar image. Regenerated on every
/// upload so avatar URLs are immutable and safely cacheable.</summary>
public Guid? AvatarToken { get; set; }

/// <summary>Null means no avatar is set.</summary>
public DateTime? AvatarUpdatedAt { get; set; }

/// <summary>Google-supplied photo URL awaiting the user's consent. Nothing is
/// fetched or stored until they accept. Cleared on accept or skip.</summary>
[MaxLength(1000), Column(TypeName = "varchar")]
public string PendingAvatarSourceUrl { get; set; }
```

### Index: `StreamContext.OnModelCreating`

The anonymous read endpoint looks a user up by token on every uncached request. A filtered unique index keeps that a seek and enforces uniqueness without tripping over the many NULLs.

```csharp
modelBuilder.Entity<UserProfile>()
    .HasIndex(u => u.AvatarToken)
    .IsUnique()
    .HasFilter("[AvatarToken] IS NOT NULL")
    .HasDatabaseName("IX_UserProfiles_AvatarToken");
```

### Migration generation

```bash
cd cimplur-core/Memento
dotnet ef migrations add AddUserAvatar --project Domain --startup-project Memento

dotnet ef migrations script <PreviousMigrationId> AddUserAvatar \
    --project Domain --startup-project Memento --idempotent \
    --output ../../docs/migrations/AddUserAvatar.sql
```

The script is **generated, not hand-written** (project convention: production deploys by script, never by `dotnet ef database update`). Two edits are required after generation:

1. **Prepend ANSI SET options.** A filtered index (`CREATE INDEX … WHERE`) requires `QUOTED_IDENTIFIER ON` and `ANSI_NULLS ON` in the creating session; without them, index creation fails at deploy time. EF emits these for some providers but not reliably — add them unconditionally:

   ```sql
   SET QUOTED_IDENTIFIER ON;
   SET ANSI_NULLS ON;
   GO
   ```

2. **Verify batch separation.** SQL Server cannot reference a column added in the same batch, so the `ALTER TABLE … ADD` statements must be separated from `CREATE INDEX` by `GO`. EF's idempotent output already does this. Do **not** hand-wrap the whole script in a single `BEGIN TRANSACTION … COMMIT` spanning interior `GO` batches — that is legal under SQLCMD on one connection but breaks under any tool that opens a connection per batch.

Expected shape (verify against the actual generated file):

```sql
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT * FROM [__EFMigrationsHistory]
               WHERE [MigrationId] = N'<id>_AddUserAvatar')
BEGIN
    ALTER TABLE [UserProfiles] ADD [AvatarToken] uniqueidentifier NULL;
    ALTER TABLE [UserProfiles] ADD [AvatarUpdatedAt] datetime2 NULL;
    ALTER TABLE [UserProfiles] ADD [PendingAvatarSourceUrl] varchar(1000) NULL;
END;
GO

IF NOT EXISTS (SELECT * FROM [__EFMigrationsHistory]
               WHERE [MigrationId] = N'<id>_AddUserAvatar')
BEGIN
    CREATE UNIQUE INDEX [IX_UserProfiles_AvatarToken]
        ON [UserProfiles] ([AvatarToken])
        WHERE [AvatarToken] IS NOT NULL;
END;
GO

IF NOT EXISTS (SELECT * FROM [__EFMigrationsHistory]
               WHERE [MigrationId] = N'<id>_AddUserAvatar')
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'<id>_AddUserAvatar', N'9.0.8');
END;
GO
```

### S3 layout

```
cimplur/avatars/{AvatarToken}.jpg           (production)
cimplur/test/avatars/{AvatarToken}.jpg      (non-production)
```

Mirrors `ImageService.GetName`'s `Constants.InProduction` convention. Deliberately outside the drop-scoped `{userId}/{dropId}/{imageId}` key space, so no avatar object is reachable by drop-image code paths and `PermissionService.CanView` — drop-based and meaningless here — is never consulted.

---

## Deployment

**Order is mandatory: migration first, application second.**

1. Run `docs/migrations/AddUserAvatar.sql` against production.
2. Deploy the application.

Running the script ahead of the deploy is safe: the columns are nullable and the currently-deployed code neither reads nor writes them. The reverse order is an outage — see Critical Fix 3.

**Rollback:** redeploy the previous application build. Do **not** drop the columns; the old build ignores them, and dropping would destroy avatars uploaded in the interim. If a rollback is needed after users have uploaded, avatar rows simply stop being read.

---

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Entities/
│   │   ├── UserProfile.cs                      [MODIFY] +3 nullable columns
│   │   └── StreamContext.cs                    [MODIFY] +1 filtered index
│   ├── Utilities/
│   │   └── ImageProcessing.cs                  [NEW]  pure static primitives
│   ├── Models/
│   │   ├── AvatarModel.cs                      [NEW]
│   │   ├── AvatarUrl.cs                        [NEW]  static URL builder
│   │   ├── DropModel.cs                        [MODIFY] +AvatarToken/AvatarUrl
│   │   ├── CommentModel.cs                     [MODIFY] Domain.Models ONLY — see note
│   │   ├── ConnectionModel.cs                  [MODIFY] +AvatarToken/AvatarUrl
│   │   ├── SharingRecipientModel.cs            [MODIFY] +AvatarToken/AvatarUrl
│   │   ├── UserModel.cs                        [MODIFY] +AvatarUrl/+pending fields
│   │   └── OnboardingStateModel.cs             [MODIFY] +AvatarPromptedAt
│   └── Repositories/
│       ├── AvatarService.cs                    [NEW]
│       ├── IAvatarSourceFetcher.cs             [NEW]
│       ├── AvatarSourceFetcher.cs              [NEW]
│       ├── ImageService.cs                     [MODIFY] RotateImage delegates only
│       ├── UserService.cs                      [MODIFY] GetUser, GetConnections, onboarding
│       ├── GroupService.cs                     [MODIFY] GetSharingRecipients projection
│       ├── GoogleAuthService.cs                [MODIFY] record PendingAvatarSourceUrl
│       ├── DropsService.cs                     [MODIFY] projection only
│       ├── MemoryShareLinkService.cs           [MODIFY] projection only
│       └── TimelineShareLinkService.cs         [MODIFY] projection only
├── Memento/
│   ├── Controllers/AvatarController.cs         [NEW]
│   └── Startup.cs                              [MODIFY] DI, HttpClient, rate-limit policy
└── DomainTest/Repositories/
    ├── AvatarServiceTest.cs                    [NEW]
    ├── AvatarSourceFetcherTest.cs              [NEW]
    ├── ImageProcessingTest.cs                  [NEW]
    └── ImageServiceTest.cs                     [MODIFY] drop-image regression only

fyli-fe-v2/src/
├── components/ui/
│   ├── UserAvatar.vue                          [NEW]
│   ├── UserAvatar.test.ts                      [NEW]
│   ├── AppNav.vue / AppNav.test.ts             [MODIFY]
├── components/account/
│   ├── AvatarEditor.vue / .test.ts             [NEW]
├── views/onboarding/
│   ├── AvatarView.vue / .test.ts               [NEW]
├── services/avatarApi.ts / .test.ts            [NEW]
├── stores/auth.ts                              [MODIFY] avatar state + actions
├── types/index.ts                              [MODIFY] +avatarUrl fields
├── test/fixtures.ts                            [MODIFY] ← REQUIRED, see Frontend Types
├── router/index.ts                             [MODIFY] +/onboarding/avatar + guard
├── assets/main.css                             [MODIFY] +--fyli-primary-darker
├── components/memory/MemoryCard.vue            [MODIFY]
├── components/comment/CommentList.vue          [MODIFY]
├── views/connections/ConnectionsView.vue       [MODIFY] delete local .avatar rule
├── views/account/AccountView.vue               [MODIFY]
├── views/share/SharedMemoryView.vue            [MODIFY]
└── views/memory/…SharingRecipient picker       [MODIFY]

docs/migrations/AddUserAvatar.sql               [NEW, generated]
docs/release_note.md                            [MODIFY]
docs/FRONTEND_STYLE_GUIDE.md                    [MODIFY] +--fyli-primary-darker
cimplur-core/docs/DATA_SCHEMA.md                [NEW]    schema reference
```

> **`CommentModel` disambiguation.** Two classes share the name: `Bridge.CommentModel` and `Domain.Models.CommentModel`. Only `Domain/Models/CommentModel.cs` is modified. `Bridge` is untouched.

---

## Interface Definitions

### `Domain/Utilities/ImageProcessing.cs` (new, pure)

Extracted so the avatar path and the drop-image path share orientation logic without sharing a mutable service. Every method is static and side-effect-free beyond the `Image` passed in.

```csharp
public static class ImageProcessing
{
    /// <summary>Loads an image, routing HEIC/HEIF through ImageMagick.</summary>
    public static Task<Image> LoadAsync(Stream input, bool isHeic);

    /// <summary>Applies EXIF orientation and clears the now-invalid orientation
    /// tags. Behaviour is identical to the switch previously inlined in
    /// ImageService.RotateImage.</summary>
    public static Image ApplyExifOrientation(Image image);

    /// <summary>Removes Exif, Iptc and Xmp profiles. AVATARS ONLY — see Fix 1.</summary>
    public static void StripAllMetadata(Image image);

    /// <summary>Centre-crops to a square on the shorter edge.</summary>
    public static Image CropToSquare(Image image);

    /// <summary>Resizes a square image to size × size.</summary>
    public static Image ResizeSquare(Image image, int size);

    public static Task<Stream> ToJpegStreamAsync(Image image, int quality = 85);
}
```

`ImageService.RotateImage` becomes a one-line delegate to `ApplyExifOrientation`. **Its behaviour must not change**, which is what `ImageServiceTest` regression cases assert. `StripAllMetadata` is never called from the drop-image path.

### `Domain/Models/AvatarUrl.cs`

One place that knows the URL shape, so controller, projections, and tests cannot drift.

```csharp
public static class AvatarUrl
{
    /// <summary>Public, cacheable avatar URL. Null when no avatar is set —
    /// the signal for clients to render the initials fallback.</summary>
    public static string Build(Guid? token) =>
        token.HasValue ? $"/api/avatars/{token.Value}/photo.jpg" : null;
}
```

### Transport model additions

Applied identically to `DropModel`, `Domain.Models.CommentModel`, `ConnectionModel`, and `SharingRecipientModel` — all four are built per-request and never persisted:

```csharp
/// <summary>Projected from UserProfile.AvatarToken. Not serialized — it is
/// already carried inside AvatarUrl.</summary>
[Newtonsoft.Json.JsonIgnore]
public Guid? AvatarToken { get; set; }

public string AvatarUrl => Domain.Models.AvatarUrl.Build(AvatarToken);
```

`UserModel` additionally:

```csharp
public string AvatarUrl { get; set; }
public bool HasPendingAvatar { get; set; }    // a Google photo awaits consent
public string PendingAvatarUrl { get; set; }  // rendered only in the onboarding step
```

`OnboardingStateModel`:

```csharp
/// <summary>Set when the avatar step is resolved. Non-null means never ask
/// again, whatever the outcome.</summary>
public DateTime? AvatarPromptedAt { get; set; }
```

### `Domain/Models/AvatarModel.cs`

```csharp
public class AvatarModel
{
    public string AvatarUrl { get; set; }        // null after removal
    public DateTime? AvatarUpdatedAt { get; set; }
}
```

### `Domain/Repositories/IAvatarSourceFetcher.cs`

```csharp
public interface IAvatarSourceFetcher
{
    /// <summary>Fetches an externally-hosted profile photo. Returns null —
    /// never throws — when the URL is disallowed, unreachable, too large,
    /// or not an image.</summary>
    Task<Stream> FetchAsync(string url, CancellationToken ct = default);
}
```

`AvatarSourceFetcher` rules, all enforced before the request is issued or as it streams:

- scheme must be `https`
- host must equal `googleusercontent.com` or end with `.googleusercontent.com` — **suffix comparison on a parsed `Uri.Host`**, never `Contains`, so `googleusercontent.com.evil.com` is rejected
- 5 s timeout; response `Content-Type` must start with `image/`
- body capped at `AvatarService.MaxUploadBytes`, enforced while reading, not from the advertised `Content-Length`
- no redirects followed (`AllowAutoRedirect = false`), so an allowed host cannot bounce the request elsewhere

### `Domain/Repositories/AvatarService.cs`

```csharp
public class AvatarService : BaseService
{
    public const int AvatarSize = 256;
    public const long MaxUploadBytes = 10 * 1024 * 1024;

    private static readonly HashSet<string> AllowedContentTypes =
        new(StringComparer.OrdinalIgnoreCase)
        { "image/jpeg", "image/jpg", "image/png", "image/heic", "image/heif" };

    public AvatarService(IAvatarSourceFetcher sourceFetcher,
                         UserService userService,
                         ILogger<AvatarService> logger) { … }

    /// <summary>Processes and stores an uploaded photo, replacing and deleting
    /// any existing one.</summary>
    public Task<AvatarModel> UploadAsync(int userId, IFormFile file);

    /// <summary>Fetches the pending Google photo server-side, stores it, clears
    /// the suggestion. Throws BadRequestException when there is no pending
    /// suggestion or the fetch fails.</summary>
    public Task<AvatarModel> AcceptSuggestedAsync(int userId);

    /// <summary>Clears the pending suggestion without storing anything.</summary>
    public Task SkipSuggestedAsync(int userId);

    /// <summary>Deletes the stored object and clears the token. Idempotent.</summary>
    public Task RemoveAsync(int userId);

    /// <summary>Anonymous read. Returns null for an unknown token. The caller
    /// owns the returned stream.</summary>
    public Task<Stream> OpenAsync(Guid token);
}
```

Shared private processing, used by both `UploadAsync` and `AcceptSuggestedAsync`:

```csharp
private static async Task<Stream> ProcessAsync(Stream input, bool isHeic)
{
    using var image = await ImageProcessing.LoadAsync(input, isHeic);
    ImageProcessing.ApplyExifOrientation(image);   // rotate BEFORE stripping
    ImageProcessing.StripAllMetadata(image);       // Fix 1 — GPS must not ship
    ImageProcessing.CropToSquare(image);
    ImageProcessing.ResizeSquare(image, AvatarSize);
    return await ImageProcessing.ToJpegStreamAsync(image);
}
```

---

## API Endpoints

| Method | Route | Auth | Body | Response |
|--------|-------|------|------|----------|
| `GET` | `/api/avatars/{token:guid}/photo.jpg` | **Anonymous**, `[EnableRateLimiting("avatars")]` | — | `200` JPEG · `Cache-Control: public, max-age=31536000, immutable` · `ETag: "{token}"` · `404` unknown token |
| `POST` | `/api/avatars` | Authorized | `multipart/form-data`, field `file` | `200 AvatarModel` · `400` wrong type / too large |
| `DELETE` | `/api/avatars` | Authorized | — | `200 AvatarModel` (`avatarUrl: null`) |
| `POST` | `/api/avatars/suggested` | Authorized | — | `200 AvatarModel` · `400` no pending suggestion or fetch failed |
| `DELETE` | `/api/avatars/suggested` | Authorized | — | `204` |

Modified responses — **additive fields only**:

| Endpoint | Added |
|----------|-------|
| `GET /api/users` | `avatarUrl`, `hasPendingAvatar`, `pendingAvatarUrl`, `onboardingState.avatarPromptedAt` |
| `GET /api/connections` | `avatarUrl` per connection |
| `GET /api/connections/sharing-recipients` | `avatarUrl` per recipient |
| `GET /api/drops/*`, `GET /api/stream/*` | `avatarUrl` on each drop and each comment |
| `GET /api/sharelinks/{token}` | `avatarUrl` on the drop and its comments |
| `GET /api/timelineshare/{token}` | same |

> `GET /api/timelines/{id}/invited` is **not** modified — it returns pending share requests, not users. See Critical Fix 2.

### `AvatarController`

```csharp
[Route("api/avatars")]
public class AvatarController : BaseApiController
{
    private readonly AvatarService avatarService;

    /// <summary>Public avatar image. No auth: the GUID token IS the capability,
    /// and it only reaches clients already entitled to the page it appears on.
    /// Rate-limited because it is unauthenticated.</summary>
    [EnableRateLimiting("avatars")]
    [HttpGet]
    [Route("{token:guid}/photo.jpg")]
    public async Task<IActionResult> Get(Guid token)
    {
        var stream = await avatarService.OpenAsync(token);
        if (stream == null) return NotFound();

        // Immutable: the token changes whenever the image does.
        Response.Headers["Cache-Control"] = "public, max-age=31536000, immutable";
        Response.Headers["ETag"] = $"\"{token}\"";

        // NOTE: return File(...) directly. Do NOT copy ImageController.Get,
        // which wraps a FileStreamResult in Ok() and sets the content type to
        // "image / jpg" (with spaces) — both are bugs in that endpoint.
        return File(stream, "image/jpeg");
    }

    [CustomAuthorization]
    [HttpPost]
    [Route("")]
    public async Task<IActionResult> Upload()
    {
        var file = HttpContext.Request.Form.Files.Count > 0
            ? HttpContext.Request.Form.Files[0] : null;
        if (file == null) return BadRequest("Please choose a photo.");
        return Ok(await avatarService.UploadAsync(CurrentUserId, file));
    }

    // DELETE "", POST "suggested", DELETE "suggested" follow the same shape.
}
```

**S3 stream lifetime.** `OpenAsync` returns `GetObjectResponse.ResponseStream`. The `GetObjectResponse` must **not** be wrapped in a `using`, and the stream must not be disposed inside the service — `FileStreamResult` disposes it after the response is written. Disposing early yields an empty 200, which no unit test would catch.

### `Startup.cs`

```csharp
services.AddScoped<AvatarService, AvatarService>();

services.AddHttpClient<IAvatarSourceFetcher, AvatarSourceFetcher>(c =>
{
    c.Timeout = TimeSpan.FromSeconds(5);
    c.MaxResponseContentBufferSize = AvatarService.MaxUploadBytes;
})
.ConfigurePrimaryHttpMessageHandler(() =>
    new HttpClientHandler { AllowAutoRedirect = false });

// In AddRateLimiter, alongside the existing "public"/"registration"/"ai" policies.
// The existing "public" policy (60/min) is too tight: one cold-cache stream can
// reference 20+ distinct avatars in a single page load.
options.AddPolicy("avatars", context =>
    RateLimitPartition.GetFixedWindowLimiter(
        partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        factory: _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 300,
            Window = TimeSpan.FromMinutes(1)
        }));
```

---

## Data Flow

### Upload

```
AvatarEditor.vue → POST /api/avatars (multipart)
  → AvatarController.Upload
      → AvatarService.UploadAsync(userId, file)
          1. Validate content type ∈ AllowedContentTypes, length ≤ 10 MB
             → BadRequestException otherwise
          2. ProcessAsync: load → orientation → STRIP METADATA → crop → resize → JPEG
          3. newToken = Guid.NewGuid()
          4. S3 PutObject  avatars/{newToken}.jpg
          5. oldToken = user.AvatarToken
             user.AvatarToken = newToken; user.AvatarUpdatedAt = UtcNow
             SaveChangesAsync()                       ← commit BEFORE deleting
          6. if (oldToken != null) S3 DeleteObject avatars/{oldToken}.jpg
             best-effort: log and continue on failure. An orphaned 20 KB object
             must never fail the user's upload or roll back step 5.
      → AvatarModel { avatarUrl, avatarUpdatedAt }
  → auth store patches user.avatarUrl; every UserAvatar re-renders
```

Ordering matters: the new object is written before the row is updated, and the old object is deleted only after the row is committed. A crash at any point leaves a valid avatar — never a row pointing at a missing object.

**Concurrent uploads.** Two uploads racing for the same user both write their object, then both update the row; the last `SaveChangesAsync` wins and the loser's object is orphaned. This must not 500. The filtered unique index on `AvatarToken` cannot collide here (tokens are fresh GUIDs), and step 6 deletes whichever `oldToken` each request observed. Asserted by `UploadAsync_ConcurrentUploads_LastWriteWinsWithoutError`.

### Anonymous read

```
<img src="/api/avatars/{token}/photo.jpg">
  → AvatarController.Get (no auth filter, "avatars" rate-limit policy)
      → AvatarService.OpenAsync(token)
          1. UserProfiles.Where(u => u.AvatarToken == token)   ← index seek
             null → 404
          2. S3 GetObject avatars/{token}.jpg → ResponseStream (not disposed)
      → 200 image/jpeg, immutable cache headers
Browser caches for a year; a new upload yields a new URL.
```

The endpoint never reads `CurrentUserId` and has no user-id parameter — that absence *is* the anti-enumeration property, and it is asserted directly by `OpenAsync_DoesNotConsiderCallerIdentity`.

### Google suggestion

```
Google sign-in
  → GoogleAuthService.FindOrCreateUserAsync(payload)
      new user only: user.PendingAvatarSourceUrl = payload.Picture
      (URL recorded; NOTHING fetched or stored)

First app entry
  → GET /api/users → hasPendingAvatar: true, avatarPromptedAt: null
  → router guard → /onboarding/avatar
      "Use this photo"  → POST /api/avatars/suggested
            → AvatarService.AcceptSuggestedAsync
                IAvatarSourceFetcher.FetchAsync(pendingUrl)
                  · https only; parsed Uri.Host must be/end with googleusercontent.com
                  · no redirects; 5 s timeout; 10 MB streaming cap; image/* only
                  · any failure → null (never throws)
                null → BadRequestException("We couldn't get that photo…")
                       → UI falls back to the plain upload prompt
                otherwise → ProcessAsync + store (Upload steps 3-6)
                clear PendingAvatarSourceUrl
      "Upload a different one" → POST /api/avatars
      "Skip"                   → DELETE /api/avatars/suggested
  → in every case: UserService.UpdateOnboardingAsync(userId, "promptedAvatar")
       sets AvatarPromptedAt = UtcNow  → never asked again
```

### Stream projection (the performance-critical path)

`DropsService.MapDrops` already selects through `s.CreatedBy` and `t.Owner` (`DropsService.cs:351, 387`). Two added lines ride those existing navigations:

```csharp
var returnDrops = dropInclude.Skip(skip).Take(take).Select(s => new DropModel
{
    …
    CreatedBy      = s.CreatedBy.Name,
    CreatedById    = s.CreatedBy.UserId,
    AvatarToken    = s.CreatedBy.AvatarToken,          // ← added
    …
    Comments = s.Comments.Select(t => new CommentModel
    {
        …
        OwnerId     = t.Owner.UserId,
        OwnerName   = t.Owner.Name ?? t.Owner.UserName,
        AvatarToken = t.Owner.AvatarToken,             // ← added
        …
    })
});
```

**No new `Include`, no new join, no extra query, no per-row presign** — two scalar columns on tables already in the plan. `MapUserNames`, which overwrites `CreatedBy`/`OwnerName` with the viewer's private rename, is untouched: a renamed connection keeps its own photo while showing the private name, and the initials fallback keeps deriving from the displayed name (PRD Open Question 4, assumed answer).

The identical two-line change applies to `MemoryShareLinkService.GetMemoryByTokenAsync` and `TimelineShareLinkService`, both of which already `.Include(d => d.CreatedBy)` and `.ThenInclude(c => c.Owner)`.

---

## Frontend

### Types and fixtures — required together

`avatarUrl` is added as a **required** nullable field so the real payload shape is exercised in tests:

```ts
// types/index.ts
export interface User        { …; avatarUrl: string | null
                                  hasPendingAvatar: boolean
                                  pendingAvatarUrl: string | null }
export interface Drop        { …; avatarUrl: string | null }
export interface DropComment { …; avatarUrl: string | null }
export interface OnboardingState { …; avatarPromptedAt: string | null }
```

`src/test/fixtures.ts` builds `createUser`, `createDrop`, and `createDropComment` as **exhaustive object literals** typed as their interfaces. Adding a required field without updating them fails `npx vue-tsc --noEmit` (`vite build` will not catch it). Each factory gains a default:

```ts
avatarUrl: null,
hasPendingAvatar: false,     // createUser only
pendingAvatarUrl: null,      // createUser only
```

`npx vue-tsc --noEmit` must pass before this phase is considered done, and `Connection` in `services/connectionApi.ts` plus `SharingRecipient` in `types/index.ts` gain `avatarUrl: string | null` the same way.

### Design token: `--fyli-primary-darker`

The existing initials circle pairs `--fyli-primary-dark` (`#3b8a69`) on `--fyli-primary-light` (`#e8f7f0`), which measures **3.77:1** — below the 4.5:1 the style guide requires for normal text. The glyph is `aria-hidden` with the person's name rendered beside it on every surface except `AppNav`, so it is decorative rather than informational, but it is still read by sighted users at small sizes.

Add one token to `src/assets/main.css` and use it for avatar initials:

```css
--fyli-primary-darker: #2f6e54;   /* 5.46:1 on --fyli-primary-light */
```

This lifts `ConnectionsView`'s existing circle to a passing ratio as a side effect, with a barely perceptible shift inside the same brand-green family. `docs/FRONTEND_STYLE_GUIDE.md` gains the token in its Neutrals/Brand table.

### `UserAvatar.vue` — the only place an avatar is rendered

```vue
<template>
	<div
		class="user-avatar rounded-circle overflow-hidden d-inline-flex
		       align-items-center justify-content-center flex-shrink-0"
		:style="{ width: size + 'px', height: size + 'px' }"
	>
		<img
			v-if="showPhoto"
			:src="avatarUrl!"
			:alt="name"
			:width="size"
			:height="size"
			loading="lazy"
			decoding="async"
			@error="failed = true"
		/>
		<span
			v-else
			class="fw-bold user-avatar__initial"
			:style="{ fontSize: size * 0.38 + 'px' }"
			aria-hidden="true"
		>{{ initial }}</span>
	</div>
</template>

<script setup lang="ts">
import { ref, computed } from "vue";

const props = withDefaults(defineProps<{
	name: string;
	avatarUrl?: string | null;
	size?: number;
}>(), { avatarUrl: null, size: 40 });

const failed = ref(false);
// charAt returns "" (never undefined) for an empty string, so this is safe
// under noUncheckedIndexedAccess without an assertion.
const initial = computed(() => (props.name?.trim().charAt(0) || "?").toUpperCase());
const showPhoto = computed(() => !!props.avatarUrl && !failed.value);
</script>

<style scoped>
.user-avatar {
	background-color: var(--fyli-primary-light);
	color: var(--fyli-primary-darker);
}

/* Square source or not, never distort a face. Matters most in AvatarView,
   which renders Google's URL directly and cannot assume a square. */
.user-avatar img {
	width: 100%;
	height: 100%;
	object-fit: cover;
	display: block;
}
</style>
```

Design notes:

- **Bootstrap first.** Circle, clipping, flex centring, and no-shrink come from utilities (`rounded-circle overflow-hidden d-inline-flex align-items-center justify-content-center flex-shrink-0`) per the style guide's "Avatars → `rounded-circle`" rule. Scoped CSS carries only the two colours and the `object-fit` rule Bootstrap has no utility for. No hardcoded hex.
- **Initial ratio is 0.38, not 0.42**, so 46 px reproduces `ConnectionsView`'s current `font-size: 1.1rem` exactly and the fallback really is pixel-identical to today.
- **Layout stability.** The wrapper is sized from the prop and the `<img>` carries matching `width`/`height` attributes, so nothing reflows when a photo resolves mid-scroll.
- **Graceful failure.** `@error` falls back to initials rather than a broken-image glyph.

| Consumer | Size | Notes |
|----------|------|-------|
| `MemoryCard.vue` header | 40 | Left of the existing name/date block, inside the existing `d-flex`; wrap name + date in a `div` and add `me-2` |
| `CommentList.vue` | 32 | Leading each row; `kind !== 0` rows unchanged |
| `ConnectionsView.vue` | 46 | Replaces the inline `.avatar` div; the local `.avatar` rule is deleted |
| `AppNav.vue` | 32 | Current user — see touch-target note below |
| Sharing-recipient picker | 32 | Rows are already ≥44 px tall |

**`AppNav.vue` touch target.** The header avatar is the only avatar that is itself interactive, and 32 px is below the style guide's 44 × 44 px minimum. Keep the visual at 32 px and expand the hit area on the link:

```html
<RouterLink
	to="/account"
	class="d-inline-flex align-items-center justify-content-center p-2 ms-auto me-2"
	style="min-width: 44px; min-height: 44px;"
	aria-label="Your account"
>
	<UserAvatar :name="auth.user?.name ?? ''" :avatar-url="auth.avatarUrl" :size="32" />
</RouterLink>
```

The `aria-label` matters because this is the one place the avatar stands alone with no adjacent name — a screen reader would otherwise reach an unlabelled link. Bootstrap's default `:focus-visible` ring applies to the `RouterLink`; do not suppress it.

### `AvatarEditor.vue` — permanent, on the account page

Follows the existing `AccountView` card pattern (`card mb-3` → `card-body` → `h2.h6.text-muted` heading), so it sits beside the Name and Email rows without looking bolted on.

```html
<div class="card mb-3">
	<div class="card-body">
		<h2 class="h6 text-muted mb-3">Photo</h2>
		<div class="d-flex align-items-center gap-3">
			<UserAvatar :name="auth.user?.name ?? ''" :avatar-url="auth.avatarUrl" :size="96" />
			<div class="d-flex flex-column gap-2">
				<button class="btn btn-outline-secondary btn-sm"
				        :disabled="uploading" @click="pickFile">
					<span v-if="uploading"
					      class="spinner-border spinner-border-sm me-1"></span>
					{{ uploading ? "Uploading..." : "Change photo" }}
				</button>
				<button v-if="auth.avatarUrl"
				        class="btn btn-outline-danger btn-sm"
				        :disabled="uploading" @click="confirmRemove">
					Remove photo
				</button>
			</div>
		</div>
		<input ref="fileInput" type="file" class="d-none"
		       accept="image/jpeg,image/png,image/heic,image/heif"
		       @change="onFileChange" />
	</div>
</div>
```

- **Change photo** is `btn-outline-secondary` (secondary CTA) — the account page's primary action is not "change your photo."
- **Remove photo** is `btn-outline-danger` per the destructive-CTA rule, and routes through the existing `ConfirmModal`.
- **Loading state** disables both buttons and shows a `spinner-border-sm`, matching the style guide's button-loading pattern.
- The file input is hidden with `d-none` and triggered from a real `<button>`, so keyboard focus lands on a focusable element with a visible Bootstrap focus ring. Do **not** hide it with `opacity: 0` or wrap it in a bare `<label>` — both lose the ring.
- Per PRD §1.3 the row is always present — every user, photo or not, Google or not, pre-existing or new — and is never gated on onboarding state. A failed upload surfaces through `useToast` and leaves the previous photo intact.

### `AvatarView.vue` — the one-time ask

One centred card. The Google photo renders at 96 px through `UserAvatar` (so `object-fit: cover` protects a non-square source), then three stacked full-width actions — `d-grid gap-2` so they are comfortable thumb targets on mobile and do not need a separate breakpoint rule.

```html
<div class="text-center">
	<UserAvatar :name="auth.user?.name ?? ''"
	            :avatar-url="auth.user?.pendingAvatarUrl" :size="96" />
	<h1 class="h4 mt-3 mb-1">Is this you?</h1>
	<p class="text-muted">
		Your family will see this next to your memories and comments.
	</p>
	<div class="d-grid gap-2 mt-4">
		<button class="btn btn-primary" :disabled="busy" @click="useGooglePhoto">
			<span v-if="busy" class="spinner-border spinner-border-sm me-1"></span>
			Use this photo
		</button>
		<button class="btn btn-outline-secondary" :disabled="busy" @click="pickFile">
			Upload a different one
		</button>
		<button class="btn btn-link text-muted" :disabled="busy" @click="skip">
			Skip
		</button>
	</div>
</div>
```

**Visual hierarchy:** exactly one `btn-primary`, so the recommended path is unambiguous. Skip is `btn-link text-muted` — a real peer that is reachable and clearly clickable, never greyed out to look disabled (PRD: "Skip is a peer of the other options, not a greyed-out afterthought"). The heading is deliberately a question, not a pitch.

If the Google image 404s on render, or `POST /suggested` returns 400, the view swaps to a plain "Add a photo?" upload prompt rather than erroring.

### Store and routing

```ts
// stores/auth.ts
const avatarUrl = computed(() => user.value?.avatarUrl ?? null);
const needsAvatarPrompt = computed(() =>
	user.value?.hasPendingAvatar === true &&
	user.value?.onboardingState?.avatarPromptedAt == null);

async function uploadAvatar(file: File)  { … }
async function acceptSuggestedAvatar()   { … }
async function skipSuggestedAvatar()     { … }
async function removeAvatar()            { … }
```

Router guard, appended after the existing First Moment guard in `beforeEach`:

```ts
if (auth.isAuthenticated && !auth.needsProfileCompletion
	&& !auth.needsFirstMoment && auth.needsAvatarPrompt
	&& to.name !== "onboarding-avatar") {
	return { name: "onboarding-avatar" };
}
```

`/onboarding/avatar` is lazy-loaded like every other route.

---

## Testing Plan

Per `docs/TESTING_BEST_PRACTICES.md` — AAA, `DetachAllEntities` isolation, `TestServiceFactory`.

### `ImageProcessingTest.cs` (new)

| Test | Asserts |
|------|---------|
| `StripAllMetadata_RemovesGpsCoordinates` | **Fix 1 regression.** GPS-tagged input → output has no `ExifProfile` |
| `StripAllMetadata_RemovesIptcAndXmp` | Both profiles null |
| `StripAllMetadata_PreservesIccProfile` | Colours do not shift |
| `ApplyExifOrientation_ThenStrip_KeepsRotation` | Rotation survives the strip (ordering) |
| `CropToSquare_Landscape / _Portrait / _AlreadySquare` | Output is square, centred |
| `ResizeSquare_Produces256x256` | Exact dimensions from all three aspect ratios |
| `LoadAsync_Heic_RoutesThroughMagick` | HEIC decodes |

### `ImageServiceTest.cs` (extend — regression only)

| Test | Asserts |
|------|---------|
| `RotateImage_BehaviourUnchangedAfterDelegation` | All 8 EXIF orientations match pre-refactor output |
| `DropImageProcessing_PreservesMetadata` | **Drop images still keep EXIF** — the strip is avatar-only |
| `DropImageProcessing_StillResizesTo2048MaxWidth` | Existing path untouched |

### `AvatarServiceTest.cs` (new)

| Test | Asserts |
|------|---------|
| `UploadAsync_SetsTokenAndTimestamp` | Token non-null, timestamp set, URL shape correct |
| `UploadAsync_StripsExifFromStoredObject` | **Fix 1 end-to-end**: stored bytes carry no GPS |
| `UploadAsync_Replacing_GeneratesNewTokenAndDeletesOldObject` | Token changed; old key deleted |
| `UploadAsync_OldObjectDeleteFails_StillSucceeds` | Row committed, no throw |
| `UploadAsync_ConcurrentUploads_LastWriteWinsWithoutError` | No 500, no unique-index violation |
| `UploadAsync_RejectsNonImageContentType` | `BadRequestException` |
| `UploadAsync_RejectsOversizeFile` | `BadRequestException`, no row change |
| `UploadAsync_AcceptsHeic` | Routes through the Magick path |
| `RemoveAsync_ClearsTokenAndDeletesObject` | Token null, timestamp null |
| `RemoveAsync_NoAvatar_IsIdempotent` | No throw |
| `AcceptSuggestedAsync_StoresFetchedPhotoAndClearsPending` | Token set, pending null |
| `AcceptSuggestedAsync_FetchReturnsNull_ThrowsAndLeavesPending` | User can still upload |
| `AcceptSuggestedAsync_NoPendingUrl_Throws` | `BadRequestException` |
| `SkipSuggestedAsync_ClearsPendingWithoutStoring` | No S3 write |
| `OpenAsync_UnknownToken_ReturnsNull` | → 404 |
| `OpenAsync_KnownToken_ReturnsReadableStream` | Stream is not pre-disposed |
| `OpenAsync_DoesNotConsiderCallerIdentity` | Anti-enumeration: no user-id input exists |

### `AvatarSourceFetcherTest.cs` (new — the SSRF guard)

Rejects (returns `null`, never throws): `http://` scheme · `evil.com` · **`googleusercontent.com.evil.com`** (suffix-spoof) · a redirect from an allowed host to a disallowed one · non-image `Content-Type` · a body exceeding the cap mid-stream · a response exceeding the timeout. Accepts a valid `lh3.googleusercontent.com` URL.

### Controller / integration

| Test | Asserts |
|------|---------|
| `Get_SetsImmutableCacheHeaders` | `Cache-Control: public, max-age=31536000, immutable` and `ETag` present |
| `Get_UnknownToken_Returns404` | |
| `Get_RequiresNoAuthentication` | Succeeds with no bearer token |
| `Get_ReturnsFileResultNotWrappedOk` | Content type is exactly `image/jpeg` |

### Other backend

- **`GoogleAuthServiceTest`** — new user records `payload.Picture`; a returning user's existing avatar is not overwritten; a payload with no picture leaves the field null.
- **`DropsServiceTest`** — projection emits `avatarUrl` for author and commenters; `null` for users without one; **a renamed connection keeps its own avatar while showing the private name**.
- **`UserServiceTest`** — `GetUser` returns `avatarUrl`/`hasPendingAvatar`; `GetConnections` returns per-connection `avatarUrl`; `promptedAvatar` sets `AvatarPromptedAt` once and is idempotent.
- **`GroupServiceTest`** — `GetSharingRecipients` returns `avatarUrl`; **`SaveCurrentPeople` output is byte-identical to pre-change** (Fix 2 regression — proves `PersonModelV2` was not widened).
- **Backwards-compatibility regression** — a `UserProfile` with all three columns NULL produces a drop payload identical to pre-change except for the added `avatarUrl: null` keys; drop-access queries are unchanged.

### Frontend (Vitest + Vue Test Utils)

- **`UserAvatar.test.ts`** — renders `<img>` with alt text when a URL is present; renders the uppercase initial when null; falls back to initials on `@error`; applies the size prop to both the wrapper and the `<img>` width/height attributes; carries `rounded-circle`; marks the initial `aria-hidden`; handles an empty name without crashing.
- **`AppNav.test.ts`** (a11y) — the account link exposes `aria-label="Your account"` and a ≥44 px hit area.
- **`avatarApi.test.ts`** — all five calls hit the right path, method, and body shape; error paths covered.
- **`auth.test.ts`** (extend) — `needsAvatarPrompt` true only when `hasPendingAvatar && avatarPromptedAt == null`; each action patches `user`; each action's failure path leaves state intact.
- **`AvatarEditor.test.ts`** — renders with and without a photo; Remove appears only when a photo is set and uses `btn-outline-danger`; Remove confirms first; both buttons disable and a spinner shows while uploading; a failed upload shows a toast and keeps the old photo.
- **`AvatarView.test.ts`** — three options render with exactly one `btn-primary`; each calls the right action and advances; a 400 from `/suggested` degrades to the upload prompt; Skip is not disabled-styled.
- **`AppNav.test.ts`**, **`MemoryCard.test.ts`**, **`CommentList.test.ts`**, **`ConnectionsView.test.ts`** (extend) — `UserAvatar` present with the right props; **existing assertions unchanged**, proving no-avatar rendering is untouched.
- **Router** — the avatar guard fires only after First Moment and never traps a user already prompted.
- **Typecheck gate** — `npx vue-tsc --noEmit` clean (catches the `fixtures.ts` failure mode), then `npm run test:unit -- --run` and `npm run build`.

---

## Documentation

- **`docs/release_note.md`** — a feature entry following the existing format (summary, Technical Details, Files Changed split Frontend/Backend), added in Phase 3 when the feature is complete.
- **`cimplur-core/docs/DATA_SCHEMA.md`** — **created** as part of this work; the file did not previously exist. It carries the schema conventions (Code-First flow, script-based production deploys, deployment ordering, SQL Server syntax, the JSON-column warning), a migration log covering all 13 existing migrations plus `AddUserAvatar`, an entity-to-table index for all 45 `DbSet`s, and full column documentation for `UserProfiles` including the three avatar columns and the filtered index. Per-table detail is backfilled as migrations touch each table rather than all at once — entity classes remain authoritative. **Every future migration adds a Migration Log row and a Table Details entry.**
- **`docs/AI_PROMPTS.md`** — not applicable; no prompts are added or modified.
- No "AI"-flavoured user-facing copy anywhere in this feature.

---

## Implementation Order

### Phase 1 — Storage and self-service
1. `UserProfile` columns, `StreamContext` index, EF migration, generated `AddUserAvatar.sql` (+ SET options), `DATA_SCHEMA.md` migration-log and `UserProfiles` entries
2. `ImageProcessing` utility + `ImageProcessingTest`; `ImageService.RotateImage` delegates + regression tests
3. `AvatarService` (upload / remove / open), `AvatarModel`, `AvatarUrl` + tests
4. `AvatarController` (anonymous GET, POST, DELETE), `Startup` DI + `"avatars"` rate-limit policy + controller tests
5. `UserModel.AvatarUrl` via `UserService.GetUser`
6. Frontend types **and `fixtures.ts` together**; `vue-tsc` clean
7. `--fyli-primary-darker` token in `main.css` + style-guide entry; `UserAvatar.vue`, `avatarApi.ts`, auth-store actions, `AvatarEditor.vue` on `AccountView`, avatar in `AppNav.vue` (44 px hit area + `aria-label`)

*Ships standing alone: a user can set, change, and remove a photo and see it in the header and on their account page.*

### Phase 2 — Display everywhere
8. `AvatarToken`/`AvatarUrl` on `DropModel`, `Domain.Models.CommentModel`, `ConnectionModel`, `SharingRecipientModel`
9. Projections: `DropsService`, `MemoryShareLinkService`, `TimelineShareLinkService`, `UserService.GetConnections`, `GroupService.GetSharingRecipients`
10. `MemoryCard.vue`, `CommentList.vue`, `ConnectionsView.vue`, `SharedMemoryView.vue`, sharing-recipient picker
11. Backwards-compatibility regression tests, including the `SaveCurrentPeople` byte-identity check

### Phase 3 — Google import
12. `IAvatarSourceFetcher` / `AvatarSourceFetcher` with the host allowlist + tests
13. `GoogleAuthService` records `PendingAvatarSourceUrl` for new users
14. `AvatarService.AcceptSuggestedAsync` / `SkipSuggestedAsync`; `promptedAvatar` onboarding action
15. `AvatarView.vue`, `/onboarding/avatar` route, router guard
16. `docs/release_note.md` entry

---

## Open Questions

1. **Where does the avatar step sit in onboarding?** This TDD places it *after* First Moment, so nothing is inserted ahead of the activation moment. Placing it *before* means the user's very first memory already carries their face. Recommend after; needs a call.
2. **Account deletion.** PRD Open Question 2 is unresolved and this design adds a second class of S3 object to it. Recommend a follow-up covering avatars and drop images together rather than special-casing avatars here.
3. **Existing Google users** (PRD Open Question 3) never get the ask — `PendingAvatarSourceUrl` is set for new users only. A backfill on next Google sign-in is a few lines in `FindOrCreateUserAsync` but re-prompts established users. Left out; easy to add.
4. **CDN.** Streaming through the API is correct at current scale, and immutable caching means one fetch per browser per version. If avatar bandwidth shows up in API metrics, the token-keyed immutable URL drops behind CloudFront with no code change.
5. **Public-link opt-out** (PRD Open Question 1) is not built. If it lands later it is one `bit` column and one `AvatarToken` null-out in the two share-link projections — no restructuring.
6. ~~`cimplur-core/docs/DATA_SCHEMA.md` does not exist.~~ **Resolved** — created with conventions, the full migration log, the entity-to-table index, and `UserProfiles` detail. Remaining per-table detail backfills as migrations touch each table; no separate backfill project is proposed.

---

*Document Version: 2.0*
*Created: 2026-09-19*
*Revised: 2026-09-19 — all code-review findings addressed*
*Status: Draft — code review and designer review complete, ready to build*
