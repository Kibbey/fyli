# TDD: Instant Uploads

**PRD:** `docs/prd/PRD_INSTANT_UPLOADS.md`
**Status:** Draft
**Created:** 2026-09-21
**Revised:** 2026-09-21 — image staging simplified to multipart-to-task (see Decision 2)

---

## Overview

Today every byte of a photo or video moves *after* the parent clicks Save,
because the S3 key for a piece of media is derived from `dropId` — and no drop
exists until Save. This design decouples the upload from the drop by introducing
a **staging area**: a user-scoped S3 prefix plus a `StagedUpload` record keyed by
an opaque token. Bytes move, and images are resized, while the parent types. At
Save the memory is created and the staged tokens are *claimed*, which moves no
bytes on the request path.

Three structural choices carry the design:

1. **Images are uploaded and resized in one request, during typing.** The
   existing multipart path is reused verbatim — the client posts the file, the
   server runs `ImageService.ReSizeImageAsync` exactly as it does today — but the
   result is written to `staging/{userId}/{token}/render.jpg` instead of a
   `dropId`-derived key. `ReSizeImageAsync` itself is not touched. Claim is then
   a server-side `CopyObject` of a sub-megabyte JPEG.
2. **Videos claim with zero copy.** `TranscodeWithMediaConvert` already reads
   from one key and writes to another; today the input is hardcoded to
   `temp/{name}`. Making the input key a parameter lets MediaConvert read
   straight from the staging object and write the final key. The existing async
   transcode *is* the move.
3. **Nothing in the read path changes.** `ImageService.GetName`,
   `MovieService.GetNameBase`, `GetLink`, `GetThumbLink`, and every call site
   that builds media links keep deriving keys from `(userId, dropId, mediaId)`
   exactly as they do today. Existing drops, existing media, and every
   access-control path are untouched.

Phase 1 is frontend-only and ships value on its own.

---

## Key Decisions

### Decision 1 — Claim must not move bytes (PRD §2.3)

| Kind | Staged object | Claim work on the save path | Byte movement |
|------|---------------|------------------------------|---------------|
| Image | `staging/{u}/{token}/render.jpg` — the finished rendition, written when the file was uploaded | Insert `ImageDrop`; S3 server-side `CopyObject` → final key | Server-side copy of a <1MB object, ~40ms, never through the app server. The rendition then exists at both keys until the lifecycle rule reaps staging (48–72h, since `Days: 2` rounds up) — the direct cost of copying rather than moving, and a rounding error at <1MB per image |
| Video | `staging/{u}/{token}/original` | Insert `MovieDrop`; start MediaConvert with `FileInput` = staging key | None. MediaConvert reads staging and writes the final key + thumbnail, asynchronously |

This is PRD Approach 1 ("let the existing pipeline read from the staging key")
for video, where it works perfectly, and a bounded version of Approach 2 for
images, where copying is cheap *because the object copied is the rendered JPEG,
not the original*. The 5GB single-part copy limit the PRD worried about never
arises: the only thing ever copied is an image rendition.

Rejected: recording the staging key on `ImageDrop`/`MovieDrop` and teaching the
serve path to read from it. That would touch `GetLink`, `GetThumbLink`, `Get`,
`GetThumb`, `Delete`, and the link-building call sites across `DropsService`,
`QuestionService`, `MemoryShareLinkService`, `TimelineShareLinkService`, and
`ExportService` — the exact surface the backwards-compatibility rule protects.

### Decision 2 — Images stage through the app server; only video goes direct to S3

**Images: multipart POST to the task, resized inline, written to staging.**
The client posts the file to `POST /api/uploads/stage/image`. The server runs the
existing `ReSizeImageAsync(IFormFile)` — HEIC→JPEG, EXIF rotation applied to
pixels, resize, JPEG re-encode — and puts the result at
`staging/{userId}/{token}/render.jpg`. The response carries the token and the
file is already fully processed. One request, no presigned URL, no background
job, no intermediate state to reason about.

**Videos: presigned PUT direct to S3**, as they already do today. Routing 5GB
through an ECS task is a non-starter, so video keeps
`stage/video/request` → PUT → `stage/video/complete`.

The PRD asked for presigned direct-to-S3 for images too, calling the current
app-server hop "a real speed gain" to remove. That premise is weakened by
staging itself: once the upload happens during typing, the hop costs the parent
nothing observable. What it would buy is *scalability* — Kestrel not holding a
connection open for a slow cellular upload — not perceived speed. Set against
that, the multipart approach removes a large amount of machinery:

| | Presigned for images | Multipart to task (chosen) |
|---|---|---|
| Image endpoints | `stage/request` + `stage/complete` | one `POST /api/uploads/stage/image` |
| Render job | `StagedImageRenderJob` + processor + queue additions | none — resize inline |
| `ReSizeImageAsync` | new `Stream` overload + delegation refactor | **untouched** |
| Staging state | `RenderedKey`, `RenderedAt`, a not-yet-rendered fast/slow path at claim | none — the rendition exists before the token is returned |
| Progress | `XMLHttpRequest` | axios `onUploadProgress`, already available |

The decisive row is the middle one: reusing `ReSizeImageAsync` rather than
reimplementing it against a stream means the HEIC and orientation behaviour is
inherited wholesale rather than re-derived — see *Rotation* below. It also means the image is **always** ready before its token
exists, so there is no partial state and no fast-path/slow-path branching in the
claim handler.

Direct-to-S3 for images remains available later behind the same token and the
same claim path: it would add a presigned variant of the stage endpoint without
changing `ClaimAsync`, `ImageClaimHandler`, or the S3 layout. Deferred, not
foreclosed.

**Consequence worth naming:** the app server still reads and resizes image
bytes, exactly as it does today. What changes is *when* — during the parent's
typing instead of after their Save click — which is where the entire perceived
speed gain comes from. See Decision 4 for the request-size limit this makes
explicit.

### Decision 3 — Image fidelity: render for display, as today

The PRD states originals are stored "exactly as captured," but
`ImageService.ReSizeImageAsync` already resizes every image to a 2048px bound
(1024px for portraits, via `maxWidth / 2` when `height > width`), converts HEIC
to JPEG, applies EXIF rotation to pixels, and re-encodes at ImageSharp's default
quality 75. The rendition is the *only* copy stored — the original bytes are
discarded and never reach S3. So PRD goal #4 describes a change, not a status
quo. Taking it literally has two consequences:

- **HEIC would no longer render.** iPhone photos arrive as HEIC. Chrome and
  Firefox cannot display HEIC in an `<img>`. Serving the original directly
  breaks every iPhone photo in the stream.
- **Stream bandwidth would rise roughly 10–30×.** A 12MP original is ~4–12MB
  against ~300–600KB rendered. A stream page with 20 photos goes from ~10MB to
  well over 100MB on a parent's phone.

**Settled: keep the existing render pipeline. The original is never stored.**

The rendition is the only copy, exactly as today. With the multipart approach
the original never reaches S3 at all — it exists only in the request stream, is
resized in memory, and the rendition is what gets written.

The alternative considered and rejected was **serving the original directly**.
It satisfies the PRD sentence literally but fails on its own terms: iPhone
photos arrive as HEIC, so a HEIC→JPEG conversion is unavoidable for browser
support and "exactly as captured" is not achievable. It also hands orientation to
the browser, which is the exact class of bug
`docs/investigations/2026-09-18-video-sideways-orientation.md` closed on
2026-09-18.

A third option — render for display *and* archive the untouched original under
`originals/{userId}/{dropId}/{imageId}` — was considered and declined in favour
of keeping this simple. Worth recording what that costs, because it is a door
that only closes: no photo uploaded before such an archive exists can ever be
re-rendered at higher quality, offered as a full-resolution download, or
corrected for the portrait-images-get-1024px quirk. Adding it later means
keeping the original on the way through the stage endpoint, plus extending
`ImageService.Delete` to remove both keys. It cannot be applied retroactively.

**This decision changes no parent-visible behaviour.** Photos render exactly as
they do today, at the same quality, over the same bandwidth. The speed this
feature delivers comes from *when* bytes move, not from what is kept.

### Decision 4 — Limits

- **Images: 50MB, explicitly configured.** Nothing in `cimplur-core` sets
  `MaxRequestBodySize`, `MultipartBodyLengthLimit`, `RequestSizeLimit`, or
  `maxAllowedContentLength`, so Kestrel's default of 30,000,000 bytes (~28.6MB)
  is the effective ceiling on `/api/images` today. A 50MB post would therefore
  be rejected with a bare 413 *before* `UploadController` runs, and the
  documented 400 would never fire between 28.6MB and 50MB.

  So 50MB has to be granted deliberately — and the limits must not be set to the
  same number. `RequestSizeLimit` bounds the whole request *body*: the file plus
  multipart boundaries, part headers, and `Content-Disposition`. Set at exactly
  52,428,800 it would reject a file of exactly 50MB with a bare 413, which is the
  outcome this decision exists to prevent. So:

  - `[RequestSizeLimit(53_000_000)]` on the action — the file limit plus headroom
    for multipart overhead.
  - `file.Length <= 52_428_800` validated in the service, returning 400.

  The service check therefore always wins, and the boundary test asserts 50MB of
  **file length**, not request length. `MultipartBodyLengthLimit` defaults to
  128MB and so does not bind here; setting it is harmless belt-and-braces, not a
  requirement.

  Two honest consequences: this *raises* the worst-case ImageSharp decode from
  ~28.6MB of input to 50MB, and any ALB or proxy body limit in front of the task
  must be confirmed to allow it.
- **Videos: 1KB – 5GB**, the bounds `MovieService.GetUploadUrl` already enforces.
  5GB is also the S3 single-PUT ceiling, so this is unchanged.

### Decision 5 — The 2–8s delay is load-bearing; the placeholder must land first

The PRD calls `getTranscodeDelay` an "artificial" wait "inserted after upload,"
and requirement 2.2 says to remove it entirely, relying on "the existing
`VideoProcessingPlaceholder`" for anything still transcoding. Both halves of that
are wrong about the current code, and taking them literally ships a regression.

**The delay gates a refetch whose result is rendered immediately.** In three of
the four call sites the sleep is followed by a `getDrop` and a store write:

| Site | Sequence |
|---|---|
| `CreateMemoryView.vue` | `:494` `uploadFiles` → `:498` delay → `:510` `getDrop` → `:511` `stream.prependMemory` |
| `EditMemoryView.vue` | `:645` upload → `:649` delay → `:663` `getDrop` → `:664` `stream.updateMemory` |
| `CommentList.vue` | `:40` delay → `:44` `getDrop` → `:53` assigns into `allComments` |

Only `QuestionAnswerView.vue:331` is cosmetic — it sets `processingVideoDelay`
purely to show a message.

**And the claimed fallback is not on that surface.**
`VideoProcessingPlaceholder.vue` lives in `src/components/question/` and is
referenced by exactly one component, `AnswerPreview.vue:34`. The stream card
renders a bare element with no placeholder, no poll, and no error fallback:

```
src/components/memory/MemoryCard.vue:174-180
  <div v-for="movie in memory.movieLinks" :key="movie.id" ...>
    <video :src="movie.link" :poster="movie.thumbLink" controls ...>
```

So deleting the delay on its own means the just-saved memory's card gets a
`MovieDrop` row whose S3 object does not exist yet: a 404 poster and a dead
`<video>` until the parent manually reloads — a user-visible regression, in the
exact flow this feature exists to improve.

**The delay is currently doing its job.** Confirmed against production on
2026-09-21: MediaConvert finishes fast enough that almost all uploads show a
proper video today. So the 2–8s window is empirically sufficient, and removing it
is a real regression rather than the exposure of an already-common failure. That
raises the stakes on ordering — the readiness check must be in place *first* — and
it means the replacement will almost always resolve on its first check.

**Therefore the delay is replaced, not deleted, and Phase 1 splits in two.**

`VideoProcessingPlaceholder.vue` moves to `src/components/media/`, `MemoryCard`
renders it when a movie's object is not yet available, and it gains an automatic
bounded retry. The delay comes out only once that is in place.

Three mechanics settled, since a naive poll does not work here:

1. **Readiness needs a server check.** `getDrop` builds links from keys without
   testing existence (`DropsService.cs:417-438`), so it returns a link for an
   object that is not there — which is why the current code cannot detect this at
   all. A small `GET /api/movies/{id}/status` returning `{ ready, link, thumbLink }`
   from one `GetObjectMetadataAsync` is the cheapest authoritative answer. It is
   **a sixth new endpoint and a backend change**, so Phase 1 is not frontend-only.

   Two things it must get right:

   - **Authorization.** It takes a `MovieDropId` and returns fresh presigned URLs,
     so without a guard it is an enumeration surface over all drop media. Resolve
     `MovieDrop → DropId` and apply `permissionService.CanView(userId, dropId)` —
     the same guard every existing media read path sits behind — before presigning
     anything.
   - **`isTranscodeV2` must be derived the way `DropsService` derives it.**
     `GetLink`/`GetThumbLink` take an `isTranscodeV2` flag that selects the key,
     and the codebase derives it two different ways: `DropsService.cs:414`,
     `MemoryShareLinkService.cs:311`, and `TimelineShareLinkService.cs:299` use a
     date hack (`TranscodeSwitchDate = 2025-12-01 < CreatedAt`, with a comment
     admitting it is a hack), while `QuestionService.cs:529` uses the
     `MovieDrop.IsTranscodeV2` column. `MemoryCard`'s links come from
     `DropsService`, so the status endpoint must use the **date hack** — otherwise
     for a drop created before 2025-12-01 it would presign a different key than
     `getDrop` did, and swapping the link in would produce a 404.
2. **A presigned URL cannot be cache-busted.** `GetThumbLink` returns one with a
   3-hour expiry (`MovieService.cs:128`); appending `?t=...` invalidates the
   signature, so a retry against the same URL would fail permanently and look
   like "never ready." The status call returns *fresh* links, which solves this
   in the same round trip.
3. **A short fixed interval, not backoff.** Check immediately, then every 500ms
   for at most 15 attempts (~7.5s), then fall back to the placeholder's existing
   manual "Check if ready" button. Backoff optimises the wrong thing here: it
   saves requests on the slow case at the cost of latency on the common one, and
   ~15 cheap `GetObjectMetadataAsync` calls are a better trade than making a
   parent wait a second they don't need to. The worst case is bounded at roughly
   today's 8s ceiling, so this is never slower than the delay it replaces — just
   usually much faster, and honest when it isn't.

Most of this already exists: `VideoProcessingPlaceholder` has the `refresh` emit
and `onRefreshComplete`, and `AnswerPreview.vue` already implements the
refresh-and-merge-URLs pattern (`refreshedVideos`, `placeholderRefs`,
`handleVideoRefresh`) that `MemoryCard` can reuse.

**Phase 1 therefore splits.** **1a** is the form reorder, image progress, and
autofocus guard — frontend only, no video risk, ships on its own. **1b** is the
status endpoint (a backend change), the placeholder promotion, the auto-retry,
and only then the delay removal. See Implementation Order.

The eventual fix is to stop polling: MediaConvert can publish completion to
SNS/EventBridge, and a vestigial `transcode_complete` SQS queue is already
referenced in `MovieService.Transcode`. A `MovieDrop.TranscodedAt` column fed
from that would let `getDrop` report readiness directly. Polling is the right
interim step and does not block it.

### Decision 6 — Scope held to the create flow

Per PRD open questions 2–4: no recovery UI for abandoned files; only the picker
moves (date and storyline keep their positions); and comments, edit-memory, and
the question-answer flow stay on the existing upload path. The legacy endpoints
remain fully functional, so those flows need no changes beyond Phase 1's delay
removal.

---

## Rotation — unchanged, and the HEIC path now fixed

iPhone photos and videos carry EXIF/container orientation rather than upright
pixels, so this is load-bearing. Nothing in this design changes how orientation
is handled, and after Decision 2 that is true *by construction* rather than by
care.

**Images.** `ImageService.ReSizeImageAsync(IFormFile)` is called with the same
`IFormFile` it receives today, and is **not modified**. Inside it, `RotateImage`
→ `ImageProcessing.ApplyExifOrientation` still applies the full eight-case EXIF
switch to pixels and strips tags 274/256/257 afterward so nothing double-rotates
downstream. The HEIC branch — `ConvertToJPG` routing through `MagickImage`,
relying on ImageMagick preserving the EXIF profile without auto-orienting, so
that `ApplyExifOrientation` can apply the tag to the re-loaded JPEG — is
untouched. The only change is the destination key passed to `PutObject`.

**The HEIC path was fixed and committed before this design is built** — commit
`78185f8`, "fix(images): decode HEIC/HEIF uploads instead of throwing." Current
state:

```csharp
// ImageService.cs:224-227
public async Task<Image> ConvertToJPG(IFormFile file)
{
    return await ImageProcessing.LoadAsync(file.OpenReadStream(), isHeic: true);
}
```

Uploading a `*.heic` file previously failed outright with
`UnknownImageFormatException`: the inline copy wrote the converted JPEG into a
`MemoryStream` and handed it to ImageSharp without rewinding, so format detection
read zero bytes from a stream at EOF. Broken since the .NET Core port
(`b73cf09`, 2022-01-09), unnoticed because the branch is gated on the *filename*
and iOS Safari usually converts HEIC to JPEG when a photo is picked through a
file input. Confirmed against production before fixing.

Two consequences for this design, both favourable:

1. **There is now one loader, not two.** `ConvertToJPG` delegates to
   `ImageProcessing.LoadAsync`, so the drop-image and avatar paths cannot drift.
   Decision 2's argument still holds — reusing `ReSizeImageAsync` rather than
   reimplementing it is still the right call — but the duplicate-loader hazard it
   cited is gone.
2. **The orientation invariant is the opposite of what one would assume, and is
   now pinned by a test.** ImageMagick applies the HEIC container's rotation
   during decode and normalises the tag to `orientation = 1`, so the subsequent
   `ApplyExifOrientation` is a deliberate **no-op** on this path — it does not
   apply a preserved tag. A real 4032×3024 HEIC therefore decodes to 3024×4032
   with the rotation already in pixels.
   `ImageServiceHeicTest.ConvertToJPG_RealHeicPhoto_ReturnsDecodableImage`
   asserts `orientation == 1` explicitly, so an ImageMagick upgrade that stops
   normalising fails loudly instead of shipping sideways photos.

**The branch gate now covers `.heif` as well** (`IsHeifFamily`,
`ImageService.cs:207-218`): the same container, but an unmatched extension falls
through to ImageSharp, which has no HEIF decoder at all. The stage endpoint's
validation must accept `.heif` too — see Decision 4.

**The regression guard is therefore that `ImageServiceTest.cs`,
`ImageProcessingTest.cs`, and `ImageServiceHeicTest.cs` all pass unmodified.** If
any needs editing, the change has gone further than this design intends.

**Videos.** The orientation fix from 2026-09-18 lives in
`MovieService.CreateMediaConvertInput`, which hardcodes
`Rotate = InputRotate.AUTO` to bake phone orientation into pixels. The video
claim path changes only the `FileInput` URI handed to that method — the staging
key instead of `temp/{name}` — so the job settings, `Rotate = AUTO` included, are
untouched. Given how recent that bug is, a test asserts it directly rather than
trusting the construction.

---

## Component Diagram

```
 STAGE (while the parent types)
 ─────────────────────────────────────────────────────────────────
  CreateMemoryView
        │ files selected
        ▼
  useStagedUpload  ── queue, cap 3, videos first ──┐
                                                   │
        ┌──────────────── image ──────────────────┐ └── video ──────────────┐
        ▼                                         ▼                         ▼
  POST /api/uploads/stage/image            POST /api/uploads/stage/video/request
  (multipart, axios progress)                     { token, presignedUrl }
        │                                                │
        ▼                                                │ PUT bytes ──────► S3
  UploadController                                       │      staging/{u}/{token}/original
        │                                                ▼
  StagedUploadService.StageImageAsync          POST .../video/complete
        │                                                │
        │ ImageService.ReSizeImageAsync(file)   StagedUploadService
        │   (UNCHANGED: HEIC→JPG, EXIF          verifies object + size
        │    rotate, resize, JPEG q75)                   │
        ▼                                                ▼
  IStagedStorage.PutAsync ──► S3                   UploadedAt set
    staging/{u}/{token}/render.jpg
        │
        ▼
   entry.status = "ready"    ◄── both paths converge here


 CLAIM (on Save — no bytes on this path)
 ─────────────────────────────────────────────────────────────────
  CreateMemoryView ──createDrop──► DropsService ──► Drop
        │
        └──POST /api/uploads/claim { dropId, tokens[] }──► UploadController
                                                                │
                                                       StagedUploadService
                                                       (conditional-UPDATE claim lock)
                                                                │
                                          IStagedClaimHandler factory (by Kind)
                                            ├── ImageClaimHandler
                                            │     new ImageDrop
                                            │     S3 CopyObject render.jpg
                                            │       → {u}/{drop}/{imageId}
                                            └── VideoClaimHandler
                                                  new MovieDrop (IsTranscodeV2)
                                                  MediaConvert(input = staging key,
                                                               output = {u}/{drop}/m/{movieId})
```

---

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Entities/
│   │   ├── StagedUpload.cs                        NEW
│   │   └── StreamContext.cs                       MODIFIED (DbSet + OnModelCreating)
│   ├── Models/
│   │   ├── StagedUploadKinds.cs                   NEW (constants, beside VisitLimits)
│   │   ├── StagedUploadRequestResult.cs           NEW
│   │   ├── StagedImageResult.cs                   NEW
│   │   └── StagedClaimResult.cs                   NEW
│   ├── Repositories/
│   │   ├── StagedUploadService.cs                 NEW
│   │   ├── IStagedStorage.cs                      NEW
│   │   ├── S3StagedStorage.cs                     NEW
│   │   ├── Claiming/
│   │   │   ├── IStagedClaimHandler.cs             NEW
│   │   │   ├── ImageClaimHandler.cs               NEW
│   │   │   └── VideoClaimHandler.cs               NEW
│   │   ├── ImageService.cs                        MODIFIED (one visibility widening only)
│   │   └── MovieService.cs                        MODIFIED (input-key overload + ClaimStagedMovieAsync)
├── Memento/
│   ├── Controllers/UploadController.cs            NEW
│   ├── Controllers/MovieController.cs             MODIFIED (Phase 1b status endpoint)
│   ├── Models/
│   │   ├── VideoStageRequestModel.cs              NEW
│   │   ├── StageTokenModel.cs                     NEW
│   │   └── ClaimUploadsModel.cs                   NEW
│   └── Startup.cs                                 MODIFIED (DI registration)
└── DomainTest/Repositories/
    ├── FakeStagedStorage.cs                       NEW
    ├── StagedUploadServiceTest.cs                 NEW
    ├── StagedClaimHandlerTest.cs                  NEW
    ├── UploadControllerTest.cs                    NEW
    └── MovieStatusTest.cs                         NEW (Phase 1b readiness endpoint)

fyli-fe-v2/src/
├── services/
│   ├── uploadApi.ts                               NEW
│   ├── uploadApi.test.ts                          NEW
│   ├── mediaApi.ts                                MODIFIED (image upload progress)
│   └── mediaApi.test.ts                           MODIFIED (progress param)
├── composables/
│   ├── useStagedUpload.ts                         NEW
│   ├── useStagedUpload.test.ts                    NEW
│   ├── useIsSmallScreen.ts                        NEW
│   ├── useIsSmallScreen.test.ts                   NEW
│   ├── useFileUpload.ts                           MODIFIED (progress map, delay removal)
│   └── useFileUpload.test.ts                      MODIFIED
├── components/
│   ├── memory/MediaPicker.vue                     NEW
│   ├── memory/MediaPicker.test.ts                 NEW
│   ├── memory/UploadThumbnail.vue                 NEW
│   ├── memory/UploadThumbnail.test.ts             NEW
│   ├── memory/MemoryCard.vue                      MODIFIED (transcode placeholder)
│   ├── memory/MemoryCard.test.ts                  MODIFIED
│   ├── media/VideoProcessingPlaceholder.vue       MOVED from components/question/
│   ├── media/VideoProcessingPlaceholder.test.ts   MOVED from components/question/
│   ├── question/AnswerPreview.vue                 MODIFIED (import path, :76)
│   ├── question/AnswerPreview.test.ts             MODIFIED (import path, :5)
│   └── comment/CommentList.vue                    MODIFIED (delay removal only)
└── views/
    ├── memory/CreateMemoryView.vue                MODIFIED
    ├── memory/CreateMemoryView.test.ts            MODIFIED
    ├── memory/EditMemoryView.vue                  MODIFIED (delay removal only)
    ├── question/QuestionAnswerView.vue            MODIFIED (delay removal only)
    └── onboarding/FirstMomentView.vue             MODIFIED (focus guard)

docs/migrations/AddStagedUpload.sql                NEW
docs/runbooks/s3-staging-lifecycle.md              NEW
```

No background-job files. `IBackgroundJobQueue` and `BackgroundJobQueue` are
untouched.

---

## Database Changes

Purely additive. One new table. No column added to, removed from, or changed on
`Drop`, `ImageDrop`, `MovieDrop`, `TagDrop`, `UserDrop`, or any table involved in
determining who can view a drop.

### Entity

`cimplur-core/Memento/Domain/Entities/StagedUpload.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    /// <summary>
    /// A file staged in the user-scoped S3 staging prefix before any memory
    /// exists. Claimed by a drop at save time; unclaimed rows are reaped by the
    /// S3 lifecycle rule on the staging prefix.
    /// </summary>
    public class StagedUpload
    {
        [Key]
        public int StagedUploadId { get; set; }

        public int UserId { get; set; }

        /// <summary>Opaque handle given to the client. Never a sequential id.</summary>
        public Guid Token { get; set; }

        /// <summary>
        /// The object the claim copies from or transcodes. For images this is the
        /// finished rendition (staging/{u}/{token}/render.jpg), written before
        /// the token is returned. For videos it is the uploaded original
        /// (staging/{u}/{token}/original).
        /// </summary>
        [Required]
        [MaxLength(400), Column(TypeName = "varchar")]
        public string S3Key { get; set; }

        /// <summary>"image" or "video". Selects the claim handler.</summary>
        [Required]
        [MaxLength(10), Column(TypeName = "varchar")]
        public string Kind { get; set; }

        [Required]
        [MaxLength(100), Column(TypeName = "varchar")]
        public string ContentType { get; set; }

        /// <summary>
        /// Bytes the parent uploaded: the incoming file length for images
        /// (not the rendition size), the declared size for videos.
        /// </summary>
        public long FileSize { get; set; }

        public DateTime CreatedAt { get; set; }

        /// <summary>
        /// Set when the staged object is in place and claimable. Images set it
        /// in the same request that uploads them; videos set it from
        /// stage/video/complete.
        /// </summary>
        public DateTime? UploadedAt { get; set; }

        public DateTime? ClaimedAt { get; set; }

        /// <summary>
        /// Drop that claimed this upload. Intentionally NOT a foreign key:
        /// a staging row must never be able to block or cascade a drop delete.
        /// </summary>
        public int? ClaimedDropId { get; set; }

        /// <summary>ImageDropId or MovieDropId produced by the claim.</summary>
        public int? ClaimedMediaId { get; set; }

        // Relationship is configured fluently in StreamContext.OnModelCreating,
        // the house style; no [ForeignKey] attribute so there is one source.
        public virtual UserProfile User { get; set; }
    }
}
```

Nullable timestamps carry the lifecycle instead of a status string, so no
consumer has to switch on magic values.

### OnModelCreating

Added to `StreamContext.OnModelCreating`, following the `AppVisit` block:

```csharp
modelBuilder.Entity<StagedUpload>(entity =>
{
    entity.ToTable("StagedUploads");
    entity.HasKey(e => e.StagedUploadId);
    entity.HasIndex(e => e.Token).IsUnique()
        .HasDatabaseName("IX_StagedUploads_Token");
    entity.HasIndex(e => new { e.UserId, e.CreatedAt })
        .HasDatabaseName("IX_StagedUploads_UserId_CreatedAt");
    // Ops query: what is still unclaimed and old enough to be reaped?
    entity.HasIndex(e => e.CreatedAt)
        .HasFilter("[ClaimedDropId] IS NULL")
        .HasDatabaseName("IX_StagedUploads_Unclaimed");
    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

### DbSet

```csharp
public DbSet<StagedUpload> StagedUploads { get; set; }
```

### Migration

```bash
cd cimplur-core/Memento && dotnet ef migrations add AddStagedUpload
```

### Raw SQL — `docs/migrations/AddStagedUpload.sql`

Production is applied from raw SQL, not `dotnet ef database update`. Generate
with EF, then rewrite the guards to match `docs/migrations/AddUserAvatar.sql` —
the canonical shape per `docs/DATABASE_GUIDE.md`. Three rules from that guide
apply here, each of which has caused a real failure:

1. **Every `[__MigrationHistory]` reference goes inside `EXEC(N'...')`.** SQL
   Server compiles a batch before evaluating a runtime `OBJECT_ID` guard, so a
   bare reference throws Msg 208 wherever the table is absent — which is every
   local dev database.
2. **The filtered index needs `SET QUOTED_IDENTIFIER ON` and `SET ANSI_NULLS ON`
   in the creating session.** `IX_StagedUploads_Unclaimed` is filtered. SET
   options are connection-level and persist across `GO`, so set them once at the
   top.
3. **Index creation is a separate batch from table creation**, guarded on
   `sys.indexes` rather than nested inside the table guard.

Replace the timestamp with the one EF generates.

```sql
-- AddStagedUpload (20260921000000)
--
-- Creates [StagedUploads]: one row per file staged before a memory exists.
--
-- WHY
-- Media S3 keys are derived from dropId, so nothing can upload until Save
-- creates the drop. A token-keyed staging row breaks that dependency, letting
-- bytes move while the parent types. Claimed at save; unclaimed rows and their
-- S3 objects are reaped by the lifecycle rule on the staging prefix.
--
-- [ClaimedDropId] is deliberately NOT a foreign key: a staging row must never
-- be able to block or cascade a drop delete.
--
-- BEFORE RUNNING
-- Run this BEFORE deploying the application. Deploy order is migration first,
-- application second -- never the reverse. Running early is safe: nothing in the
-- currently-deployed build reads this table.
--
-- The unclaimed index is filtered (CREATE INDEX ... WHERE), which requires
-- QUOTED_IDENTIFIER and ANSI_NULLS ON in the creating session. SET options are
-- connection-level and persist across GO, so setting them once covers the file.
--
-- Production history table is EF6 [__MigrationHistory], not EF Core
-- [__EFMigrationsHistory]. The history insert is wrapped in EXEC so it compiles
-- only where the table exists.
--
-- Safe to re-run.

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[StagedUploads]', N'U') IS NULL
BEGIN
    CREATE TABLE [StagedUploads] (
        [StagedUploadId] INT IDENTITY(1,1) NOT NULL,
        [UserId]         INT NOT NULL,
        [Token]          UNIQUEIDENTIFIER NOT NULL,
        [S3Key]          VARCHAR(400) NOT NULL,
        [Kind]           VARCHAR(10) NOT NULL,
        [ContentType]    VARCHAR(100) NOT NULL,
        [FileSize]       BIGINT NOT NULL,
        [CreatedAt]      DATETIME2 NOT NULL,
        [UploadedAt]     DATETIME2 NULL,
        [ClaimedAt]      DATETIME2 NULL,
        [ClaimedDropId]  INT NULL,
        [ClaimedMediaId] INT NULL,
        CONSTRAINT [PK_StagedUploads] PRIMARY KEY ([StagedUploadId]),
        CONSTRAINT [FK_StagedUploads_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId])
            ON DELETE NO ACTION
    );
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_Token'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE UNIQUE INDEX [IX_StagedUploads_Token]
        ON [StagedUploads] ([Token]);
END
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_UserId_CreatedAt'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE INDEX [IX_StagedUploads_UserId_CreatedAt]
        ON [StagedUploads] ([UserId], [CreatedAt]);
END
GO

-- Ops: unclaimed rows older than the lifecycle window should be zero.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_StagedUploads_Unclaimed'
      AND object_id = OBJECT_ID(N'[StagedUploads]')
)
BEGIN
    CREATE INDEX [IX_StagedUploads_Unclaimed]
        ON [StagedUploads] ([CreatedAt])
        WHERE [ClaimedDropId] IS NULL;
END
GO

-- Wrapped in EXEC so [__MigrationHistory] is compiled only when it exists.
-- A bare reference fails to compile (Msg 208) even behind an OBJECT_ID guard,
-- because compilation precedes the runtime check.
IF OBJECT_ID(N'[__MigrationHistory]', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'__MigrationHistory', N'ContextKey') IS NOT NULL
        EXEC(N'
            IF NOT EXISTS (SELECT 1 FROM [__MigrationHistory]
                           WHERE [MigrationId] LIKE N''%AddStagedUpload'')
                INSERT INTO [__MigrationHistory]
                    ([MigrationId], [ContextKey], [Model], [ProductVersion])
                VALUES (N''20260921000000_AddStagedUpload'',
                    N''Domain.Entities.StreamContext'', 0x, N''9.0.8'');');
    ELSE
        EXEC(N'
            IF NOT EXISTS (SELECT 1 FROM [__MigrationHistory]
                           WHERE [MigrationId] LIKE N''%AddStagedUpload'')
                INSERT INTO [__MigrationHistory] ([MigrationId], [ProductVersion])
                VALUES (N''20260921000000_AddStagedUpload'', N''9.0.8'');');
END
GO
```

Verify locally before handing over, per `DATABASE_GUIDE.md`: (a) fresh apply,
(b) re-run is a clean no-op, (c) no duplicate history row.

```bash
docker cp docs/migrations/AddStagedUpload.sql sql_server_instance:/tmp/m.sql
docker exec sql_server_instance /opt/mssql-tools18/bin/sqlcmd -C \
  -S localhost -U SA -P '<pw>' -d Master -i /tmp/m.sql
```

No `jsonb`/JSON columns. Every field is a discrete typed column.

---

## S3 Layout and Lifecycle

> **Superseded on 2026-09-22, after deploy.** This section puts staging under a
> `staging/` prefix inside the `cimplur` media bucket. It shipped that way, then
> moved to a dedicated `cimplur-staging` bucket before the expiration rule was
> ever applied to `cimplur`.
>
> The prefix design was safe — `userId` is an int, so live keys always begin
> with a digit and cannot match `staging/` — but it made a *deletion* rule on
> the bucket holding every memory photo, and its safety depended on every future
> editor knowing the prefix was load-bearing. A separate bucket lets the rule be
> stated with no prefix filter at all, which removes that class of mistake
> rather than mitigating it. `cimplurthumbs` was already the precedent for a
> purpose-specific bucket, which this design should have followed.
>
> Two consequences the original text gets wrong as a result: CORS was **not**
> "already in place and unchanged" (a new bucket needs its own), and the
> MediaConvert input is now a full `s3://` URI rather than a key, since input
> and output are in different buckets. See
> `docs/runbooks/s3-staging-lifecycle.md`.


`ImageService.GetName` already prefixes non-production keys with `test/`
(`ImageService.cs:257-266`), and `S3AvatarStorage.GetKey` follows the same
convention (`S3AvatarStorage.cs:36-41`). **Staging keys mirror it**, which is why
the lifecycle rule must cover both prefixes.

Note the isolation is not universal today: `MovieService.GetNameBase`
(`MovieService.cs:307-310`) returns `{userId}/{dropId}/m/{movieId}` with no
`test/` prefix in any environment, so a dev-environment `VideoClaimHandler` will
have MediaConvert write into the production key space — exactly as
`CompleteDirectUpload` does today. Pre-existing, not introduced here, and not
changed here; recorded so the claim above is not read as broader than it is.

```
staging/{userId}/{token}/render.jpg      image rendition, written by the stage request
staging/{userId}/{token}/original        video original, uploaded direct to S3
test/staging/{userId}/{token}/...        non-production equivalent

{userId}/{dropId}/{imageId}              UNCHANGED final image key
{userId}/{dropId}/m/{movieId}            UNCHANGED final video key
temp/{userId}/{dropId}/m/{movieId}       UNCHANGED legacy video temp key
```

The image original is never written to S3 at all — it exists only in the request
stream and is resized in memory, as today.

### Lifecycle rule

`fyli-infra` is CloudFormation for the cluster and VPC; the `cimplur` bucket is
not managed there, so this is applied with the CLI and captured in
`docs/runbooks/s3-staging-lifecycle.md`. 48 hours per the PRD's answered open
question — expressed as 2 days, since S3 expiration granularity is daily and
rounds up to at least 48h from creation.

```json
{
  "Rules": [
    {
      "ID": "ExpireUnclaimedStagingObjects",
      "Status": "Enabled",
      "Filter": { "Prefix": "staging/" },
      "Expiration": { "Days": 2 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
    },
    {
      "ID": "ExpireUnclaimedStagingObjectsNonProd",
      "Status": "Enabled",
      "Filter": { "Prefix": "test/staging/" },
      "Expiration": { "Days": 2 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 1 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket cimplur \
  --lifecycle-configuration file://staging-lifecycle.json
```

**Critical:** the rule must never be widened beyond the `staging/` prefixes.
Claimed media lives at `{userId}/{dropId}/...` and must never be reaped. Because
claim *copies out of* staging rather than moving within it, there is no code path
in which the lifecycle rule can touch an object a memory depends on.

Video is the one case where a claimed memory still depends on a staging object
*after* the claim — MediaConvert reads it. Transcodes start within seconds and
finish in minutes; 48 hours is three orders of magnitude of headroom.

**The staleness guard keys on `UploadedAt`, not `CreatedAt`, and applies to both
kinds.** `CreatedAt` is stamped when the row is created — for video, when the
presign was *requested*. Keying on it would defeat `stage/video/refresh` outright:
a parent who requests a stage, is interrupted for 30 hours, refreshes the URL,
uploads successfully, and saves would be refused even though the S3 object is
minutes old. `UploadedAt` is when bytes actually landed, which is what the
lifecycle rule counts from.

Images need the guard too. A rendition staged 50 hours ago has been reaped by the
`Days: 2` rule, so the claim's `CopyObject` hits a deleted key and throws. Both
handlers refuse an upload older than 24 hours and return a distinct
`FailedClaim.Reason` of `"expired"`, so `CreateMemoryView` can say the staged file
expired rather than the generic "1 file(s) failed to upload."

---

## Interface Definitions

### `IStagedStorage`

Mirrors the existing `IAvatarStorage` / `S3AvatarStorage` / `FakeAvatarStorage`
trio — same purpose (a seam so service behaviour is assertable without reaching
S3), same static shared `AmazonS3Client`, same `Constants.InProduction` key
prefixing.

```csharp
namespace Domain.Repository
{
    /// <summary>
    /// Object storage for staged uploads, keyed by token. Exists as a seam so
    /// StagedUploadService's validation, claim-locking, and key derivation can
    /// be asserted without reaching S3.
    /// </summary>
    public interface IStagedStorage
    {
        /// <summary>Key of the staged object for a token and kind.</summary>
        string KeyFor(int userId, Guid token, string kind);

        /// <summary>
        /// Writes the staged object. Used for image renditions. Rewinds a
        /// seekable stream before reading and does NOT dispose it — the caller
        /// owns the stream. IAvatarStorage.PutAsync documents nothing about
        /// disposal, so this is a new convention stated deliberately rather
        /// than an inherited one.
        /// </summary>
        Task PutAsync(string key, Stream content, string contentType);

        /// <summary>Presigned PUT for direct client upload. Videos only.</summary>
        string PresignPut(string key, string contentType, DateTime expires);

        /// <summary>Actual object size, or null when the object is absent.</summary>
        Task<long?> GetSizeAsync(string key);

        /// <summary>Server-side copy. No bytes pass through this process.</summary>
        Task CopyAsync(string sourceKey, string destinationKey);
    }
}
```

### `IStagedClaimHandler` (factory over switch)

```csharp
namespace Domain.Repository.Claiming
{
    /// <summary>
    /// Attaches one staged upload to a drop. Implementations must not move
    /// bytes through the app server on the save path (PRD 2.3), and must leave
    /// no media row behind on failure: if the S3 or MediaConvert step throws
    /// after the row was inserted, the row is removed before rethrowing. This
    /// mirrors the compensation ImageService.UploadImageToS3Async already
    /// performs via RemoveImageId.
    /// </summary>
    public interface IStagedClaimHandler
    {
        /// <summary>Returns the created media id (ImageDropId or MovieDropId).</summary>
        Task<int> ClaimAsync(StagedUpload staged, int dropId, int userId);
    }
}
```

Resolved by a dictionary keyed on `StagedUpload.Kind`, registered in DI:

```csharp
public interface IStagedClaimHandlerFactory
{
    /// <summary>Handler for a StagedUpload.Kind. Throws BadRequestException
    /// for a kind with no registered handler.</summary>
    IStagedClaimHandler Resolve(string kind);
}

public class StagedClaimHandlerFactory : IStagedClaimHandlerFactory
{
    private readonly IReadOnlyDictionary<string, IStagedClaimHandler> handlers;

    public StagedClaimHandlerFactory(ImageClaimHandler image, VideoClaimHandler video)
    {
        handlers = new Dictionary<string, IStagedClaimHandler>
        {
            [StagedUploadKinds.Image] = image,
            [StagedUploadKinds.Video] = video,
        };
    }

    public IStagedClaimHandler Resolve(string kind) =>
        handlers.TryGetValue(kind, out var handler)
            ? handler
            : throw new BadRequestException($"Unsupported staged upload kind '{kind}'.");
}
```

```csharp
// Startup.cs — concrete and I-prefixed domain types only, matching Startup.cs:54-102
services.AddScoped<IStagedStorage, S3StagedStorage>();
services.AddScoped<StagedUploadService, StagedUploadService>();
services.AddScoped<ImageClaimHandler>();
services.AddScoped<VideoClaimHandler>();
services.AddScoped<IStagedClaimHandlerFactory, StagedClaimHandlerFactory>();
```

Registering an open BCL interface shape like
`IReadOnlyDictionary<string, IStagedClaimHandler>` in the root container would be
unlike anything else in `Startup.cs`; the factory keeps the no-switch property
without it. A future kind (audio, document) is a constructor parameter and a
dictionary line.

`StagedUploadKinds` is a static constants class holding `"image"` and `"video"`,
following the `VisitLimits` (`Domain/Models/UsageModels.cs:22`) and `AskLimits`
(`Domain/Models/RoleNames.cs:25`) precedent, so `StagedKindValues_MatchRegisteredHandlerKeys` is
structural rather than conventional.

### `StagedUploadService` surface

```csharp
public class StagedUploadService : BaseService
{
    /// <summary>
    /// Resizes an image through the existing ImageService pipeline and writes
    /// the rendition to staging. The returned token is immediately claimable.
    /// </summary>
    public Task<StagedImageResult> StageImageAsync(int userId, IFormFile file);

    /// <summary>
    /// Creates the StagedUpload row for a video and returns a presigned PUT.
    /// Validates size and content type. Does not touch Drop.
    /// </summary>
    public StagedUploadRequestResult RequestVideoStage(
        int userId, string contentType, long fileSize);

    /// <summary>
    /// Re-presigns an unclaimed video staging row whose URL expired. Same key,
    /// same token — the client just retries the PUT.
    /// </summary>
    public StagedUploadRequestResult RefreshVideoStageUrl(int userId, Guid token);

    /// <summary>
    /// Marks a video upload complete. Verifies the object exists and that its
    /// size matches what was declared.
    /// </summary>
    public Task<bool> CompleteVideoStageAsync(int userId, Guid token);

    /// <summary>
    /// Attaches staged uploads to a drop. Per-token outcome; one failure never
    /// fails the whole claim, because the words are the memory (PRD 3.4).
    /// </summary>
    public Task<StagedClaimResult> ClaimAsync(
        int userId, int dropId, IReadOnlyList<Guid> tokens);
}
```

`StageImageAsync` calls `imageService.ReSizeImageAsync(file)` — `private` today,
widened to `internal` with no body change — then
`storage.PutAsync(key, stream, "image/jpeg")` inside a `using`, since
`ReSizeImageAsync` returns a `MemoryStream` the caller owns (the legacy caller
disposes it at `ImageService.cs:113`). If the resize or the put throws, no
`StagedUpload` row is persisted, so there is nothing to clean up.

`Domain.csproj` already carries `<InternalsVisibleTo Include="DomainTest" />`, so
both `StagedUploadService` (same assembly) and the tests can reach it.

### Result models

```csharp
public class StagedImageResult
{
    public Guid Token { get; set; }

    /// <summary>
    /// Always true on success — the resize is inline. Present for wire-shape
    /// symmetry with the video complete response, so the client's two stagers
    /// resolve to the same thing.
    /// </summary>
    public bool Ready { get; set; }
}

public class StagedUploadRequestResult
{
    public Guid Token { get; set; }
    public string PresignedUrl { get; set; }
    public DateTime ExpiresAt { get; set; }
}

public class StagedClaimResult
{
    public List<ClaimedUpload> Claimed { get; set; } = new();
    public List<FailedClaim> Failed { get; set; } = new();
}

public class ClaimedUpload
{
    public Guid Token { get; set; }
    public string Kind { get; set; }
    public int MediaId { get; set; }
}

public class FailedClaim
{
    public Guid Token { get; set; }
    public string Reason { get; set; }
}
```

### Existing service changes

```csharp
// MovieService — today the input key is hardcoded as temp/{name}. The new
// overload takes it explicitly; the existing method delegates with temp/{name}
// so CompleteDirectUpload is bit-for-bit unchanged.
private async Task TranscodeWithMediaConvert(string name)
    => await TranscodeWithMediaConvert(name, $"temp/{StripMp4(name)}");

internal async Task TranscodeWithMediaConvert(string name, string inputKey);

/// <summary>Creates a MovieDrop for an already-staged object and starts the
/// transcode reading directly from the staging key. No copy.</summary>
public async Task<int> ClaimStagedMovieAsync(int userId, int dropId, string stagingKey);

// ImageService — visibility only, no behaviour change, no new members:
//   private  Task<Stream> ReSizeImageAsync(IFormFile file)
//   internal Task<Stream> ReSizeImageAsync(IFormFile file)
//
// ImageClaimHandler needs no ImageService addition: DropImageId (ImageService.cs:268)
// and RemoveImageId (:287) are already public, so the handler composes them with
// IStagedStorage.CopyAsync itself.
//
// MovieService does need one addition, because CreateDropMovieId (:359) is private:
```

---

## Data Flow

### Stage (during typing)

1. Parent selects files. `useStagedUpload` creates an entry per file with
   `status: "pending"` and a local `objectURL` preview — thumbnails are visible
   before a single byte moves.
2. The queue runs up to 3 entries concurrently, **videos first** (a comparator:
   video before image, then selection order).
3. **Images** — one request. `POST /api/uploads/stage/image` as multipart, with
   axios `onUploadProgress` driving `entry.progress`.
   `StagedUploadService.StageImageAsync` validates size and content type,
   generates a token, runs `imageService.ReSizeImageAsync(file)` unchanged, puts
   the rendition at `staging/{userId}/{token}/render.jpg`, and inserts the
   `StagedUpload` row with `UploadedAt = UtcNow`. The response returns the token
   with the rendition already in place.
4. **Videos** — three steps, as today plus the token.
   `POST /api/uploads/stage/video/request` inserts the row and returns a
   presigned PUT for `staging/{userId}/{token}/original`, expiring in 6 hours —
   up from the 1 hour `MovieService.cs:432` uses today, so an interrupted parent
   is less likely to need `stage/video/refresh` at all, while staying well inside
   the 48h lifecycle window.
   The client `PUT`s straight to S3 via `XMLHttpRequest`, reporting progress. On
   2xx it calls `POST /api/uploads/stage/video/complete`, which confirms the
   object exists with the declared size and sets `UploadedAt`.
5. Either way, `entry.status = "ready"` and the thumbnail shows a quiet check.

### Claim (on Save)

1. `createDrop(...)` → `dropId`, exactly as today. Unchanged endpoint, unchanged
   service, unchanged sharing and notification behaviour.
2. If any entry is not yet `ready`, the view stays on screen and shows one honest
   line (remaining bytes + ETA) until the queue drains. No background upload
   after navigation.
3. `POST /api/uploads/claim { dropId, tokens[] }`. There is **no** `commentId`
   parameter: Decision 6 keeps comment attachments on the legacy path, so
   plumbing one through would be untested surface. It also inherits an
   authorization gap worth not widening — `CanView(userId, dropId)` is the only
   guard `DropImageId` applies, so a `commentId` accepted here would let any
   viewer of a shared memory attach media to someone else's comment on it. When
   comments do adopt staging, that check gets added at the same time.
4. `StagedUploadService.ClaimAsync`:
   - `permissionService.CanView(userId, dropId)` — identical to the check
     `DropImageId` and `CreateDropMovieId` perform today. A failure throws
     `NotAuthorizedException`.
   - For each token: load by `Token`, reject if `UserId != userId`
     (`NotAuthorizedException`). Add a `failed[]` entry, without taking the lock,
     if `UploadedAt == null` (never finished) or if `UploadedAt` is more than 24
     hours old (reason `"expired"` — the staged object may already be reaped).
     Checking staleness here rather than inside the handlers avoids taking and
     releasing a lock for a row that can never succeed.
   - **Take the claim before doing any work**, with a conditional update so two
     concurrent claims of the same token cannot both proceed:

     ```sql
     UPDATE [StagedUploads]
        SET [ClaimedDropId] = @dropId, [ClaimedAt] = SYSUTCDATETIME()
      WHERE [Token] = @token AND [ClaimedDropId] IS NULL
     ```

     A read-then-write check would let a double-clicked Save create two
     `ImageDrop` rows for one photo.

     **Zero rows affected has two outcomes, and neither involves a timer.**
     Re-read the row and compare `ClaimedDropId` to the requested `dropId`:

     | State on re-read | Meaning | Response |
     |---|---|---|
     | `ClaimedDropId == dropId`, `ClaimedMediaId` set | This drop already claimed it | Return that id as success (idempotent retry) |
     | `ClaimedDropId == dropId`, `ClaimedMediaId` null | A concurrent claim for this drop is mid-flight | `failed[]` with reason `"in_progress"` |
     | `ClaimedDropId != dropId` | Claimed by a *different* drop | `failed[]` with reason `"already_claimed"` |

     The `dropId` comparison matters: without it, claiming a token that belongs
     to drop A while saving drop B returns 200 with a `mediaId`, and the client
     believes media is attached to B when it sits on A. Idempotency holds only
     for a retry by the *same* drop.

   - **Write `ClaimedMediaId` in the same `SaveChangesAsync` that creates the
     media row, before the S3 or MediaConvert side effect.** This is what keeps
     the `ClaimedMediaId`-null window from mattering, and it is why no
     abandoned-lock recovery is needed:

     An earlier draft of this design had the handler do its S3 work first and
     write `ClaimedMediaId` afterwards, with a 60-second "the winner must have
     died" rule to re-take the lock. That was wrong three ways. The re-take was
     not a compare-and-swap, so two retries arriving together would both re-take
     and both create a media row — reintroducing the duplicate the lock exists to
     prevent. The threshold was compared in C# against a SQL-written timestamp,
     so clock skew between the ECS task and SQL Server could trip it. And it
     could not achieve its goal anyway: `DropImageId` commits the `ImageDrop`
     through its own `SaveChanges` (`ImageService.cs:268`), so by the time the
     media id would be written the row already exists — re-running the handler
     duplicates it rather than recovering it.

     Persisting the pair together reduces the stranded state to "media row and
     `ClaimedMediaId` both written, side effect incomplete," which the handler's
     compensating delete already covers, and which a retry resolves through row 1
     of the table above. No timer, no clock dependency, no recovery path.

   - Dispatch to the handler registered for `staged.Kind`.
   - Persist `ClaimedMediaId` **immediately after each handler returns**, not
     batched at the end of the loop. Each handler commits its media row through
     its own `BaseService` context, so there is no enclosing transaction; a
     single trailing `SaveChangesAsync` that failed would leave media rows
     attached to the drop with their tokens still marked unclaimed, and a retry
     would duplicate them.
   - A handler throwing is caught, logged, its claim released — **all three of**
     `ClaimedDropId`, `ClaimedAt`, and `ClaimedMediaId` back to null, so the
     filtered `IX_StagedUploads_Unclaimed` index and the timestamps cannot
     disagree about the same row — and recorded in `Failed`. The other tokens
     still claim and the response is still 200.
5. `ImageClaimHandler`: create `ImageDrop` on the drop (the same code path
   `DropImageId` uses), then `CopyAsync` from the staging rendition to
   `ImageService.GetName(dropId, imageId, userId)`. On failure, remove the row
   via `ImageService.RemoveImageId` and rethrow. The rendition always exists
   before the token does, so there is no not-ready branch.
6. `VideoClaimHandler`: create `MovieDrop { IsTranscodeV2 = true }`, then
   `TranscodeWithMediaConvert(GetName(dropId, movieId, userId, true), stagingKey)`.
   MediaConvert writes `{userId}/{dropId}/m/{movieId}` and the thumbnail from the
   staging object. No copy, no delay. On failure, remove the row via
   `RemoveMovieId` and rethrow.
7. Client fetches the drop and pushes to `/`. Videos still transcoding render the
   existing `VideoProcessingPlaceholder`.

### Read (unchanged)

Four live read paths build links from `(userId, dropId, mediaId)` via
`GetLink` / `GetThumbLink`, exactly as they do today:

- `DropsService.cs:417-438`
- `QuestionService.cs:522-530`, `:932-940`, `:1389-1390`
- `MemoryShareLinkService.cs:316-339`
- `TimelineShareLinkService.cs:304-316`

None of them can tell whether media arrived through the staging path or the
legacy path. This is what makes the change backwards compatible.

`ExportService`'s media-key derivation is commented out (`ExportService.cs:32-48`,
a `/* */` block whose two `MovieService.GetName` calls are 3-argument and no
longer match the live 4-argument signature at `MovieService.cs:300`), so it derives no media keys today
and is unaffected either way. It is not evidence for or against this design.

No code anywhere in `Domain` lists S3 objects by prefix — the nearest thing,
`MovieService.DeleteInFolder` (`MovieService.cs:328-345`), deletes a single
explicit key — so introducing the `staging/` prefix cannot perturb any existing
enumeration.

---

## API Endpoints

Six new endpoints — five for staging plus the Phase 1b readiness check.
**No existing endpoint changes signature or behaviour.** `/api/images`,
`/api/movies/upload/request`, and `/api/movies/upload/complete` remain exactly as
they are, so the AngularJS frontend, the comment flow, the edit flow, and the
question-answer flow keep working.

### `POST /api/uploads/stage/image`

`multipart/form-data` with a single `file` part.

```jsonc
// 200
{ "token": "8d3f...-...-...", "ready": true }
```

Validation:
- Content type must start with `image/`, or the filename ends in `.heic` or
  `.heif` — matching the `IsHeifFamily` gate (`ImageService.cs:207-218`) that
  `ReSizeImageAsync` uses, so nothing the pipeline can decode is rejected at the
  boundary.
- 1KB ≤ length ≤ 50MB.
- A `video/` content type is rejected with 400 pointing at the video endpoints.

The resize runs inline, so `ready` is always `true` on a 200.

### `POST /api/uploads/stage/video/request`

```jsonc
// Request
{ "contentType": "video/mp4", "fileSize": 482391055 }

// 200
{
  "token": "a91c...",
  "presignedUrl": "https://cimplur.s3.amazonaws.com/staging/42/a91c.../original?X-Amz-...",
  "expiresAt": "2026-09-22T04:14:00Z"
}
```

Validation: content type must start with `video/`; 1KB ≤ `fileSize` ≤ 5GB — the
same bounds `GetUploadUrl` enforces today.

### `POST /api/uploads/stage/video/refresh`

```jsonc
{ "token": "a91c..." }  →  { "token": "...", "presignedUrl": "...", "expiresAt": "..." }
```

Covers the PRD's presigned-expiry requirement: a parent who picks a file, is
interrupted, and returns gets a fresh URL for the same key rather than a silent
failure. 404 unknown token, 403 wrong user, 400 if already claimed.

### `POST /api/uploads/stage/video/complete`

```jsonc
{ "token": "a91c..." }  →  { "token": "a91c...", "ready": true }
```

404 unknown token, 403 wrong user, 400 if the S3 object is missing or its size
disagrees with the declared `fileSize`.

### `GET /api/movies/{id}/status`

Phase 1b. The readiness check that replaces the fixed delay (Decision 5).

```jsonc
// 200 — still transcoding
{ "ready": false }

// 200 — object is in place, with fresh presigned links
{
  "ready": true,
  "link": "https://cimplur.s3.amazonaws.com/42/90210/m/331?X-Amz-...",
  "thumbLink": "https://cimplurthumbs.s3.amazonaws.com/42_90210_m_331_00001.0000000.jpg?X-Amz-..."
}
```

One `GetObjectMetadataAsync` on the final key. 403 when
`permissionService.CanView(userId, movie.DropId)` fails, 404 for an unknown
`MovieDropId`. `isTranscodeV2` is derived with the `DropsService.cs:414` date
hack so the keys match what `getDrop` returned.

### `POST /api/uploads/claim`

```jsonc
// Request
{ "dropId": 90210, "tokens": ["8d3f...", "a91c..."] }

// 200 — partial success is a success
{
  "claimed": [
    { "token": "8d3f...", "kind": "image", "mediaId": 5521 },
    { "token": "a91c...", "kind": "video", "mediaId": 331 }
  ],
  "failed": []
}
```

403 if the caller cannot view the drop or any token belongs to another user. 404
if the drop does not exist. **Idempotent for retries by the same drop:**
re-claiming a token this drop already claimed returns its existing `mediaId`
rather than creating a second media row, so a client retry after a timeout cannot
duplicate photos. A token already claimed by a *different* drop comes back in
`failed[]` with reason `"already_claimed"`, never as a success.

An unknown token is a `failed[]` entry, not a 404 — one bad token must not
discard the four good claims beside it. A 404 is reserved for an unknown
`dropId`, and a cross-user token stays a hard 403 as a deliberate security
signal.

### Frontend service — `src/services/uploadApi.ts`

```typescript
export function stageImage(file: File, onProgress?: (pct: number) => void) {
  const formData = new FormData()
  formData.append("file", file)
  return api.post<{ token: string; ready: boolean }>(
    "/uploads/stage/image", formData, {
      headers: { "Content-Type": "multipart/form-data" },
      onUploadProgress: (e) => {
        if (onProgress && e.total) {
          onProgress(Math.round((e.loaded / e.total) * 100))
        }
      },
    })
}

export function requestVideoStage(contentType: string, fileSize: number) {
  return api.post<{ token: string; presignedUrl: string; expiresAt: string }>(
    "/uploads/stage/video/request", { contentType, fileSize })
}

export function refreshVideoStage(token: string) {
  return api.post<{ token: string; presignedUrl: string; expiresAt: string }>(
    "/uploads/stage/video/refresh", { token })
}

export function completeVideoStage(token: string) {
  return api.post<{ token: string; ready: boolean }>(
    "/uploads/stage/video/complete", { token })
}

export function claimUploads(dropId: number, tokens: string[]) {
  return api.post<ClaimResult>("/uploads/claim", { dropId, tokens })
}
```

Paths are relative to the `/api` base in `src/services/api.ts`, matching the
existing service files. `uploadFileToS3` in `mediaApi.ts` is reused unchanged for
the video PUT.

---

## Frontend Components

### `MediaPicker.vue` (new)

Owns the picker tile and the thumbnail strip; replaces the inline block currently
in `CreateMemoryView.vue`.

- Props: `entries: StagedFileEntry[]`, `error: string`.
- Emits: `select(FileList)`, `remove(id)`, `retry(id)`.
- Presented as an inviting tile rather than a bare `<input type="file">`: a
  dashed-border block using `.border`, `.rounded-3`, `.bg-light`, with
  `mdi-image-multiple-outline` and the label **"Add photos or videos"**.
- Optionality is explicit: no `required`, and helper copy
  `<small class="text-muted">Optional</small>`. Per the style guide's
  no-hard-coded-hex rule, hover/active border uses `var(--fyli-primary)`.
- The `<input type="file">` is visually hidden but keyboard-reachable and
  labelled, so tab order and screen readers are unaffected.

### `UploadThumbnail.vue` (new)

One thumbnail with its own state, extracted so the states are testable in
isolation.

| State | Display |
|-------|---------|
| `pending` / `uploading` | Local preview, dark scrim, percentage centred |
| `ready` | Local preview, small `mdi-check-circle` bottom-right. Quiet, not celebratory |
| `failed` | Preview at reduced opacity, `mdi-alert-circle` in `text-warning`, **Retry** button |

Progress applies to **images as well as videos** (PRD 3.3) — Phase 1 makes this
true on the legacy path via axios `onUploadProgress`, Phase 3 keeps it true on
the staged path.

The remove button keeps its current position and gains
`aria-label="Remove photo"` / `"Remove video"`.

New frontend files follow the conventions of the files they sit beside rather
than a single repo-wide rule, because the repo is genuinely mixed:
`useFileUpload.ts` and `mediaApi.ts` omit semicolons, `QuestionAnswerView.vue`
uses them. `useStagedUpload.ts`, `uploadApi.ts`, `MediaPicker.vue`, and
`UploadThumbnail.vue` all extend or replace semicolon-free neighbours, so they
omit them too. Tabs and double quotes throughout, per the style guide.

This is a deliberate deviation from `.claude/skills/code-review/SKILL.md:113`,
which lists "Semicolons used" as a requirement. Flagged rather than silent: local
consistency wins here, but if the standard is meant to be absolute, say so and
these four files follow it instead.

### `useStagedUpload.ts` (new)

Supersedes `useFileUpload` for `CreateMemoryView` only. Everything else stays on
`useFileUpload`.

```typescript
export type UploadStatus = "pending" | "uploading" | "ready" | "failed"

export interface StagedFileEntry {
  id: string
  file: File
  previewUrl: string
  type: "image" | "video"
  status: UploadStatus
  progress: number          // 0-100
  token?: string
  error?: string
  abort?: () => void
}

export function useStagedUpload() {
  const entries: Ref<StagedFileEntry[]>
  const fileError: Ref<string>
  const allReady: ComputedRef<boolean>
  const remaining: ComputedRef<{ bytes: number; seconds: number | null }>

  function onFileChange(e: Event): void   // validates, previews, enqueues
  function removeFile(id: string): void   // aborts in flight; never deletes from S3
  function retry(id: string): void
  function waitForAll(): Promise<void>    // resolves when nothing is pending/uploading
  function claim(dropId: number): Promise<number>   // → failed count; retries "in_progress"
  function cleanup(): void                // revokes object URLs, aborts all
}
```

The two upload strategies are selected by a lookup rather than a branch, matching
the backend's claim factory:

```typescript
const stagers: Record<StagedFileEntry["type"], Stager> = {
  image: stageImageEntry,   // one multipart request, axios progress
  video: stageVideoEntry,   // request → presigned PUT → complete
}
```

Concurrency: a plain worker-pool of 3 pulling from a queue sorted videos-first.
No third-party dependency; the repo has none for this and does not need one.

`noUncheckedIndexedAccess` is enabled (inherited from `@vue/tsconfig`), and both
the worker pool and the rolling byte-rate window index arrays. Every such access
needs `!`, `??`, or a guard — matching `useFileUpload.ts`'s existing
`fileEntries.value[index]!` style. Run `npx vue-tsc --noEmit` before calling
Phase 3 done; `vite build` does not type-check.

ETA: a rolling 5-second byte-rate sample across all in-flight entries;
`seconds = remainingBytes / bytesPerSecond`, `null` until there is a sample.
Displayed as a single line — *"Your video is still uploading — about 40 seconds
left. Keep this tab open."* — never a sequence of abstract step names, and never
the words "processing" or "transcoding" (PRD Language requirement).

`removeFile` calls `abort()` and drops the entry. It makes **no** delete call: an
already-staged object is simply never claimed, and the lifecycle rule reaps it.
This is what keeps abandonment free of edge cases.

`retry` on a video entry that already holds a token calls
`refreshVideoStage` and reuses the same key, so it cannot orphan a row. Image
retry re-posts, which is safe: a failed stage request persists no row.

### `useIsSmallScreen.ts` (new)

```typescript
// Bootstrap `md` breakpoint, matching the style guide's responsive table.
export function useIsSmallScreen(): Ref<boolean>  // matchMedia("(max-width: 767.98px)")
```

Used to suppress programmatic focus on the capture textarea (PRD 3.2). Note
`CreateMemoryView`'s textarea does not autofocus today — the live offender is
`FirstMomentView.vue:227`, which calls `captureTextarea.value?.focus()`. That
call gets the guard, and the composable exists so the rule is easy to apply as
the create flow evolves.

### `CreateMemoryView.vue` changes

Step-1 order becomes **Photos & Videos → What happened? → Writing assist → Date
→ Storyline**. The step indicator, the two-step Write → Share flow, and step 2
are untouched — no new steps (PRD 3.1).

`saveSteps` collapses. With uploads already done, "Uploading files" is a lie; the
overlay shows a single honest state, and when files *are* still in flight it shows
the remaining-bytes line from `remaining` instead of step names.

`handleSubmit` becomes:

```typescript
const { data: created } = await createDrop({ ... })   // unchanged
dropId = created.dropId
if (entries.value.length > 0) {
  await waitForAll()                                   // usually resolves immediately
  const failed = await claim(dropId)
  if (failed > 0) {
    error.value = `${failed} file(s) failed to upload. You can add them from the memory detail.`
  }
}
// no setTimeout — getTranscodeDelay is gone
const { data: drop } = await getDrop(dropId)
stream.prependMemory(drop)
router.push("/")
```

A failed file never blocks the save (PRD 3.4): `claim` reports a count, the
memory is created, and the parent lands on their stream regardless.

### Legacy fallback

If staging fails outright (server older than the client, or a transient error),
the entry is marked with `token: undefined` and `claim` routes those entries
through the existing `uploadFiles(entries, dropId)` path. The old flow stays a
working fallback rather than dead code, which de-risks the rollout.

---

## Error Handling Strategy

Typed exceptions thrown at the point of failure, formatted by the existing
handler — same as the rest of the codebase.

| Condition | Exception | HTTP |
|---|---|---|
| Unsupported content type, bad size, missing/mismatched S3 object | `BadRequestException` | 400 |
| Token belongs to another user; caller cannot view the drop | `NotAuthorizedException` | 403 |
| Unknown drop | `NotFoundException` | 404 |
| Unknown token during a claim | `failed[]` entry, reason `"unknown"` | 200 |
| Token already claimed (refresh) | `BadRequestException` | 400 |
| A single handler fails during a multi-token claim | caught, logged, returned in `failed[]` | 200 |

The last row is deliberate and load-bearing: the words are the memory. One bad
photo must not cost a parent the thing they wrote.

---

## Testing Plan

Per `docs/TESTING_BEST_PRACTICES.md` — AAA, `Method_Scenario_ExpectedResult`
naming, `DetachAllEntities` between arrange and act, verification through a
fresh context. `FakeStagedStorage` follows `FakeAvatarStorage`.

### Backend — `StagedUploadServiceTest.cs`

| Test | Asserts |
|---|---|
| `StageImage_ValidJpeg_WritesRenditionAndReturnsReadyToken` | Rendition at `staging/{u}/{token}/render.jpg`; row has `UploadedAt` set |
| `StageImage_NonProduction_PrefixesKeyWithTest` | Key starts `test/staging/` |
| `StageImage_Heic_RoutesThroughExistingPipeline` | HEIC accepted; output is JPEG |
| `StageImage_OverFiftyMb_ThrowsBadRequest` | Boundary at 50MB |
| `StageImage_UnderOneKb_ThrowsBadRequest` | Lower boundary |
| `StageImage_VideoContentType_ThrowsBadRequest` | Points at the video endpoints |
| `StageImage_HeifExtension_Accepted` | Matches the `IsHeifFamily` gate the pipeline uses |
| `StageImage_ResizeThrows_PersistsNoRow` | Nothing to clean up on failure |
| `StageImage_PutThrows_PersistsNoRow` | Same for the storage step |
| `RequestVideoStage_Valid_CreatesRowWithOriginalKey` | `S3Key` == `staging/{u}/{token}/original` |
| `RequestVideoStage_OverFiveGb_ThrowsBadRequest` | Boundary at 5GB |
| `RequestVideoStage_ImageContentType_ThrowsBadRequest` | Points at the image endpoint |
| `RefreshVideoStageUrl_Unclaimed_ReturnsNewUrlSameKey` | Key unchanged, `ExpiresAt` moves forward |
| `RefreshVideoStageUrl_OtherUsersToken_ThrowsNotAuthorized` | Cross-user denied |
| `RefreshVideoStageUrl_ClaimedToken_ThrowsBadRequest` | Cannot re-stage claimed media |
| `CompleteVideoStage_ObjectMissing_ThrowsBadRequest` | Size lookup returns null |
| `CompleteVideoStage_SizeMismatch_ThrowsBadRequest` | Declared vs. actual |
| `CompleteVideoStage_Success_SetsUploadedAt` | Fresh-context verification |
| `ClaimAsync_UserCannotViewDrop_ThrowsNotAuthorized` | Same guard as `DropImageId` |
| `ClaimAsync_TokenOwnedByAnotherUser_ThrowsNotAuthorized` | Cross-user denied |
| `ClaimAsync_NotUploaded_ReturnsFailedEntry` | `UploadedAt == null` → `failed[]`, no media row |
| `ClaimAsync_AlreadyClaimed_ReturnsExistingMediaIdAndCreatesNoDuplicate` | Idempotency |
| `ClaimAsync_ConcurrentClaimsOfSameToken_CreateOneMediaRow` | The conditional-update claim lock |
| `ClaimAsync_ClaimInFlightForSameDrop_ReturnsInProgress` | Zero-rows row 2: `ClaimedMediaId` null, never a bare success |
| `ClaimAsync_AlreadyClaimedByDifferentDrop_ReturnsFailedEntry` | Zero-rows row 3 — the hole that would attach media to the wrong drop |
| `ClaimAsync_UnknownToken_ReturnsFailedEntryNotNotFound` | One bad token must not discard the good ones |
| `ClaimAsync_MediaIdPersistedWithMediaRowInOneSave` | The atomicity that removes the need for lock recovery |
| `RefreshVideoStageUrl_UnknownToken_ThrowsNotFound` | The documented 404 |
| `ClaimAsync_OneHandlerThrows_OtherTokensStillClaim` | Partial success |
| `ClaimAsync_HandlerThrows_ReleasesClaimSoRetryCanSucceed` | `ClaimedDropId` back to null |
| `ClaimAsync_Success_SetsClaimedAtAndClaimedDropId` | Fresh-context verification |
| `ClaimAsync_UnknownKind_ThrowsBadRequest` | Factory miss |
| `ClaimAsync_StaleUploadedAt_ReturnsExpiredWithoutTakingLock` | 24h guard, both kinds, checked before the lock |
| `StagedKindValues_MatchRegisteredHandlerKeys` | Every `Kind` written is a key the factory has |

### Backend — `StagedClaimHandlerTest.cs`

| Test | Asserts |
|---|---|
| `ImageClaim_CopiesStagedRenditionToFinalKey` | Exactly one `CopyAsync`, no stream read |
| `ImageClaim_FinalKeyMatchesLegacyGetName` | Key identical to `ImageService.GetName(dropId, imageId, userId)` — the backwards-compatibility assertion |
| `ImageClaim_CreatesImageDropAttachedToDrop` | `drop.Images` contains the new row |
| `ImageClaim_CopyFails_RemovesImageDropRow` | Compensating delete, matching `UploadImageToS3Async` |
| `VideoClaim_StartsTranscodeWithStagingKeyAsInput` | `FileInput` is the staging URI, not `temp/` |
| `VideoClaim_OutputKeyMatchesLegacyGetName` | `{u}/{drop}/m/{movieId}` unchanged |
| `VideoClaim_PerformsNoCopy` | Zero copies — the PRD 2.3 guarantee, asserted |
| `VideoClaim_PreservesRotateAuto` | `Rotate == InputRotate.AUTO` — guards the 2026-09-18 sideways-video fix |
| `VideoClaim_CreatesMovieDropWithIsTranscodeV2True` | Matches `CreateDropMovieId` |
| `VideoClaim_TranscodeStartFails_RemovesMovieDropRow` | Compensating delete |
| `ImageClaim_CompensatingDeleteAlsoFails_LogsAndRethrows` | `RemoveImageId` itself failing must not be swallowed — it leaves an orphan media row on a live drop |


### Backend — `UploadControllerTest.cs`

Following the `AvatarControllerTest.cs` precedent. The controller carries the
multipart parsing, the size limit, and the status-code mapping, none of which the
service tests reach.

| Test | Asserts |
|---|---|
| `StageImage_NoFilePart_ReturnsBadRequest` | Empty multipart |
| `StageImage_OverRequestSizeLimit_ReturnsBadRequest` | The explicit 50MB limit, with a legible message — not a bare 413 |
| `StageImage_NotAuthorized_ReturnsForbid` | `NotAuthorizedException` → 403 |
| `Claim_UnknownDrop_ReturnsNotFound` | `NotFoundException` → 404 |
| `Claim_PartialFailure_ReturnsOkWithFailedEntries` | 200 with a populated `failed[]` |
| `Claim_NoCommentIdAccepted` | The request model has no `commentId` — guards Decision 6 |

### Backend — `MovieStatusTest.cs` (Phase 1b)

| Test | Asserts |
|---|---|
| `MovieStatus_ObjectPresent_ReturnsReadyWithFreshLinks` | `ready: true` plus newly presigned `link`/`thumbLink` |
| `MovieStatus_ObjectAbsent_ReturnsNotReady` | `ready: false`, no links, no throw |
| `MovieStatus_OtherUsersMovie_ReturnsForbid` | `CanView` guard — without it this enumerates all drop media |
| `MovieStatus_UnknownMovieId_ReturnsNotFound` | 404 |
| `MovieStatus_LegacyDropBeforeSwitchDate_UsesDropsServiceKeyDerivation` | The `isTranscodeV2` date hack, so the key matches what `getDrop` returned |

### Backend — regression guards on existing services

| Test | Asserts |
|---|---|
| `TranscodeWithMediaConvert_SingleArgOverload_UsesTempPrefix` | Legacy `CompleteDirectUpload` path unchanged |
| `GetUploadUrl_Unchanged_StillCreatesMovieDropAndTempKey` | Existing endpoint untouched |

**`ImageServiceTest.cs`, `ImageProcessingTest.cs`, and `MovieServiceTest.cs` must
pass unmodified.** This is the rotation guard: `ReSizeImageAsync` is reused, not
reimplemented, so if any of those files needs editing the change has gone further
than this design intends.

### Frontend — Vitest

`useFileUpload.test.ts` (modified)
- Delete the `getTranscodeDelay` describe block along with the function.
- `uploadFiles_ImageEntry_ReportsProgress` — images now populate the progress map.

`MemoryCard.test.ts` (modified) — the Phase 1b prerequisite from Decision 5
- A movie whose object is not yet available renders
  `VideoProcessingPlaceholder`, not a bare `<video>`.
- A movie with a usable object renders the player as before.
- **A successful status poll swaps the fresh links in and renders the player** —
  the whole point of returning links from the endpoint, and otherwise unasserted.
- The poll stops after 15 attempts and leaves the manual button, rather than
  polling forever.
- The automatic poll does not start for an older card (see the Risks note on
  per-card polling).

`EditMemoryView` / `CommentList` (extended)
- Media refetched after upload still renders once the delay is gone — the
  regression Decision 5 exists to prevent, asserted on both surfaces.
- No `getTranscodeDelay` import remains anywhere (a grep-style assertion, or
  simply that the module no longer exports it and the suite compiles).

`useStagedUpload.test.ts` (new)
- `onFileChange` creates entries in `pending` and begins uploading.
- At most 3 uploads in flight at once.
- A video queued after two images starts before the images.
- An image entry issues exactly one request (`stage/image`) and reaches `ready`.
- A video entry issues request → PUT → complete, in that order.
- Progress events move `entry.progress`; completion moves status to `ready`.
- `removeFile` on an in-flight entry calls `abort` and makes no delete request.
- `removeFile` on a `ready` entry makes no network call at all.
- A failed stage leaves the entry `failed` with a retry available.
- `retry` on a video entry holding a token calls `refreshVideoStage`, not
  `requestVideoStage` — it must not create a second `StagedUpload` row.
- `retry` on an image entry re-posts `stage/image`.
- `claim` posts only `ready` tokens and returns the failed count.
- A token returned as `"in_progress"` is re-posted after a short delay, up to a
  small bounded attempt count, rather than being reported as a failure.
- `claim` routes token-less entries through the legacy `uploadFiles` fallback.
- `waitForAll` resolves immediately when everything is ready.
- `remaining` reports null seconds before a rate sample, a positive estimate after.
- `cleanup` revokes every object URL.

`MediaPicker.test.ts` / `UploadThumbnail.test.ts` (new)
- Renders one thumbnail per entry, in selection order.
- Each of the four states renders its documented affordance.
- `failed` renders a Retry button that emits `retry` with the entry id.
- Remove emits `remove` with the entry id.
- No `required` attribute anywhere in the picker.
- The visually-hidden file input is keyboard-reachable and has an accessible name.
- Remove buttons carry `aria-label="Remove photo"` / `"Remove video"`.
- Upload status is announced via `aria-live="polite"`, matching
  `VideoProcessingPlaceholder`.

`uploadApi.test.ts` (new) — request shape and path for each call, plus the error
path for each (the review checklist requires both), following the existing
`mediaApi.test.ts` pattern, including that `stageImage` sends
`multipart/form-data` and wires `onUploadProgress`.

`useIsSmallScreen.test.ts` (new)
- Reports true below the `md` breakpoint and false above it.
- `FirstMomentView` does not call `focus()` on the capture textarea when it
  reports true, and still does when it reports false.

`CreateMemoryView` tests (extended)
- Photos & Videos renders before the textarea in the step-1 DOM order.
- The step indicator still shows exactly two steps.
- Save with all entries ready issues no upload requests — only `createDrop`,
  `claim`, `getDrop`.
- Save with a failed entry still creates the memory and still navigates.
- No `setTimeout` on the save path (assert with fake timers that save completes
  without advancing the clock).

`QuestionAnswerView.test.ts` — drop the `getTranscodeDelay: () => 0` mock along
with the function.

---

## Implementation Order

### Phase 1a — Form and progress *(frontend only, ships alone, no video risk)*

1. Move the Photos & Videos block above the textarea in `CreateMemoryView.vue`.
2. Rename `videoProgress` → `uploadProgress`; thread `onUploadProgress` through
   `mediaApi.uploadImage` so images report progress on the legacy path; update
   the thumbnail overlay condition to drop the `type === 'video'` check. Update
   `mediaApi.test.ts` for the new parameter.
3. Add `useIsSmallScreen` and guard `FirstMomentView.vue:227`.
4. Tests; `npm run test:unit`, `npx vue-tsc --noEmit`.

*Verify:* photos-first form, image thumbnails show a percentage, no keyboard
steal on mobile. Nothing about video changes.

### Phase 1b — Replace the delay with a real readiness check *(backend + frontend)*

The delay must not be removed before this lands — see Decision 5.

5. Add `GET /api/movies/{id}/status` to `MovieController` plus the supporting
   `MovieService` method: `CanView` guard, one `GetObjectMetadataAsync`, fresh
   presigned links, `isTranscodeV2` via the `DropsService.cs:414` date hack.
   Tests in `MovieStatusTest.cs`.
6. Move `VideoProcessingPlaceholder.vue` and its test from
   `src/components/question/` to `src/components/media/`, updating
   `AnswerPreview.vue:76` and `AnswerPreview.test.ts:5`.
7. Add the automatic poll inside the placeholder: check immediately, then every
   500ms, at most 15 attempts, then fall back to its existing manual button.
8. Render the placeholder from `MemoryCard.vue:174-180` when a movie is not yet
   ready, reusing `AnswerPreview.vue`'s refresh-and-merge pattern
   (`refreshedVideos`, `placeholderRefs`, `handleVideoRefresh`). Add
   `MemoryCard.test.ts` coverage.
9. Only now delete `getTranscodeDelay` from `useFileUpload.ts` and remove all
   call sites and imports: `CreateMemoryView.vue:294,498`,
   `EditMemoryView.vue:338,649`, `CommentList.vue:7,40`,
   `QuestionAnswerView.vue:126,331`, `useFileUpload.test.ts:12`, and the mock in
   `QuestionAnswerView.test.ts:64`. Delete its test block. Also remove the
   orphaned `processingVideoDelay` ref (`QuestionAnswerView.vue:156`) and its
   `aria-live` block (`:84`).
10. Tests; `npm run test:unit`, `npx vue-tsc --noEmit`.

*Verify:* saving a memory with one video is visibly faster, **and** the video
renders a placeholder that resolves itself rather than a broken player. Confirm
on a comment attachment and an edit too.

### Phase 2 — Staging infrastructure *(backend only, no UI change)*

11. `StagedUpload` entity, `StreamContext` wiring, `dotnet ef migrations add`, and
   `docs/migrations/AddStagedUpload.sql`.
12. `IStagedStorage` + `S3StagedStorage` + `FakeStagedStorage`, mirroring the
   existing `IAvatarStorage` / `S3AvatarStorage` / `FakeAvatarStorage` trio.
13. Widen `ImageService.ReSizeImageAsync` from `private` to `internal`. No other
   change to `ImageService`.
14. `StagedUploadService`: `StageImageAsync`, `RequestVideoStage`,
   `RefreshVideoStageUrl`, `CompleteVideoStageAsync`.
15. `MovieService.TranscodeWithMediaConvert(name, inputKey)` overload, with the
    existing single-arg method delegating to it.
16. `IStagedClaimHandler`, `ImageClaimHandler`, `VideoClaimHandler`, factory
    registration; `ClaimAsync` with the conditional-update claim lock.
17. `UploadController` + request models; DI registration.
18. Apply the S3 lifecycle rule; write `docs/runbooks/s3-staging-lifecycle.md`.
19. Regenerate `docs/swagger.json` for the six new endpoints — CLAUDE.md
    requires `fyli-fe-v2/src/services/*` to match the swagger contract, and
    Phase 3 is written against it.
20. Document the `StagedUploads` table in `cimplur-core/docs/DATA_SCHEMA.md`.
21. Verify the migration script with `sqlcmd` per `DATABASE_GUIDE.md`
    (fresh apply, clean re-run, no duplicate history row).
22. Backend tests green, including the unmodified existing media tests.

*Verify:* the five endpoints work end to end against a scratch drop via curl, and
the existing create flow is completely unaffected.

### Phase 3 — Upload on selection *(frontend, switches the create flow over)*

23. `uploadApi.ts` and its tests.
24. `useStagedUpload.ts`: the image/video stager lookup, queue, concurrency cap
    of 3, video-first ordering, per-entry state, abort, retry, video URL
    refresh, ETA, legacy fallback.
25. `MediaPicker.vue` and `UploadThumbnail.vue`; wire into `CreateMemoryView`.
26. Replace `handleSubmit`'s upload block with `waitForAll` + `claim`; replace
    the step-name overlay with the honest remaining-time line.
27. Tests; `npm run test:unit`, `npx vue-tsc --noEmit`, `npm run lint`.
28. Request `/designer` review of `MediaPicker` and `UploadThumbnail` against
    `docs/FRONTEND_STYLE_GUIDE.md`.
29. Add release notes to `docs/release_note.md` — one after Phase 1a
    (photos-first form, image progress), one after Phase 1b (faster saves, video
    placeholder), one after Phase 3 (uploads start on selection).

*Verify:* select eight photos, type for thirty seconds, click Save — the parent
lands on their stream with no visible upload phase.

---

## Backwards Compatibility

The rule is that drops, and who can access drops, are 100% unaffected.

- **No change to `Drop`, `TagDrop`, `UserDrop`, `TagViewer`, `UserUser`,** or any
  table or query involved in determining who can view a drop. No new state on
  `Drop` — the PRD's rejection of draft memories is honoured exactly, so no
  stream, sharing, or permission query has to learn a new exclusion. This also
  keeps `DropsService.GetTimeline` — already the subject of
  `docs/investigations/2026-09-09-gettimeline-sql-timeout.md` — free of an
  additional predicate.
- **No change to `ImageDrop` or `MovieDrop`.** Staged media produces rows
  identical to those the current path produces, at identical S3 keys.
- **`ImageService` gains nothing and loses nothing.** One method widens from
  `private` to `internal`; no body changes, no new members. `ImageServiceTest`
  and `ImageProcessingTest` pass unmodified. `MovieService` gains two members
  (the input-key overload and `ClaimStagedMovieAsync`) because
  `CreateDropMovieId` is private; `MovieServiceTest` still passes unmodified.
- **Final S3 keys are unchanged**, asserted directly by
  `ImageClaim_FinalKeyMatchesLegacyGetName` and
  `VideoClaim_OutputKeyMatchesLegacyGetName`. This is what keeps the four live
  read paths listed under *Data Flow → Read* working without a line of change.
- **Permission checks are the same calls.** `ClaimAsync` uses
  `permissionService.CanView(userId, dropId)` — the exact guard `DropImageId`
  (`ImageService.cs:270`) and `CreateDropMovieId` (`MovieService.cs:361`) use
  today — plus a strictly *additional* ownership check on the token.

  Recorded as inherited, not introduced: because `dropId` comes from the client
  and the guard is `CanView` rather than an ownership test, any user who can
  *view* a shared memory can attach their own media to it. That is exactly true
  of `/api/images` today. This design neither widens it (the token ownership check
  is new and strictly narrowing) nor fixes it; worth a separate follow-up.
- **Existing endpoints are untouched.** `/api/images`,
  `/api/movies/upload/request`, `/api/movies/upload/complete` keep their
  signatures and behaviour. The AngularJS `fyli-fe` client, the comment flow, the
  edit flow, and the question-answer flow all continue on them.
- **Rollback is a frontend revert.** Phase 3 can be reverted on its own; the
  `StagedUploads` table and endpoints simply go unused, and the legacy fallback
  in `useStagedUpload` means even a partial failure degrades to today's
  behaviour rather than to an error.

---

## Risks

| Risk | Mitigation |
|---|---|
| Lifecycle rule widened by accident and reaps live media | Rule is prefix-scoped to `staging/`; claim copies *out of* staging rather than moving within it, so no live object ever lives under the prefix. Documented in the runbook. |
| Video staging object expires before MediaConvert reads it | Transcode starts seconds after claim against a 48h window. `VideoClaimHandler` refuses to claim a staged upload older than 24h and returns a per-token failure. |
| Orphaned `StagedUploads` rows accumulate in SQL after S3 reaps the objects | Rows are ~200 bytes. The filtered `IX_StagedUploads_Unclaimed` index makes a periodic prune trivial if it ever matters; not built now, matching the PRD's "no cleanup job to write." |
| Image staging holds a Kestrel connection for the length of the upload | Status quo — `/api/images` already does this today, and the request now happens during typing rather than on the save path. Direct-to-S3 for images is the deferred optimization (Decision 2); it drops in behind the same token and claim path. |
| Large image decode exhausts task memory | Bounded at 50MB by an explicit `RequestSizeLimit`, up from Kestrel's implicit ~28.6MB default. Worst-case decode rises; the bound becomes explicit and returns a legible 400. Single-threaded through the request pipeline, so concurrent decodes scale with request concurrency — worth a memory watch after Phase 2. |
| Readiness polling adds request volume | Bounded at 15 checks per video per viewer (~7.5s), each one `GetObjectMetadataAsync` on a single key, almost always resolving on the first. **The automatic poll runs only for a freshly created card** — the just-prepended memory, or one mounted within a minute of its own creation. Older cards, including any whose transcode genuinely failed, go straight to the placeholder's manual button, so a permanently-unready video cannot cost 15 requests on every stream render by every viewer. Superseded entirely if MediaConvert completion notifications land (see Decision 5). |
| Parent closes the tab mid-upload | Bytes stop, the object is never claimed, the lifecycle rule reaps it. Nothing to clean up, no failed delete call. |
| S3 CORS not configured for the video PUT | Videos already PUT directly to S3 today, so bucket CORS is already in place and unchanged. Images no longer need it at all. |

---

## Resolved Decisions

| Question | Answer | Source |
|---|---|---|
| Lifecycle expiry for unclaimed staging objects | 48 hours (expressed as `Days: 2`) | PRD |
| Recovery UI for abandoned files with uploads | Out of scope; staging rows make it possible later | PRD |
| Do date and storyline also move below the text area? | No — only the picker moves | PRD |
| Does edit-memory adopt staging? | No — stays on the legacy path | PRD |
| Image fidelity: render, or serve the original? | Render for display, as today. The original is never stored. | 2026-09-21 |
| Image size ceiling | 50MB, granted explicitly via `RequestSizeLimit` — Kestrel's implicit default is ~28.6MB | 2026-09-21 |
| Presigned direct-to-S3 for images? | No — multipart to the task, resized inline. Deferred, not foreclosed. | 2026-09-21 |
| Temporary drop id, deleted on cancel, instead of staging? | No. A draft `Drop` would require every stream, sharing, export, and permission query to learn an exclusion, would need notification suppression and re-firing, and "delete on cancel" never fires when the tab closes — needing a sweeper that deletes `Drop` rows. | 2026-09-21 |
| Is Phase 1b's backend readiness endpoint in scope, given the PRD scoped Phase 1 as frontend-only? | Yes. Build the technically sound thing; the PRD does not constrain it. | 2026-09-22 |
| Any ALB or proxy body limit below 50MB in front of the ECS task? | No — 50MB is fine at the edge. | 2026-09-22 |

No open items. This design is settled and twice reviewed.

## Where this design departs from the PRD, deliberately

The PRD is the statement of the problem, not of the solution. Three places where
building it literally would have produced worse software, each settled above:

| PRD says | This design does | Why |
|---|---|---|
| "Presigned direct-to-S3 path for images too … a real speed gain" (Technical Considerations) | Multipart to the app server, resized inline | Once the upload happens during typing, the hop costs the parent nothing observable. Dropping it would buy scalability, not perceived speed, at the cost of a render job, a queue, two schema columns, and a second `ReSizeImageAsync` implementation. Deferred, not foreclosed — it drops in behind the same token and claim path. |
| "No file is ever compressed, resized, or degraded. Originals … stored exactly as captured" (Overview, goal 4) | Renders for display exactly as today | Unachievable as stated: HEIC cannot be served to Chrome or Firefox, so a conversion is mandatory. Serving originals would also raise stream bandwidth 10–30× on a parent's phone, undercutting the PRD's own goal 1. |
| "The deliberate 2–8 second `setTimeout` … is removed entirely" relying on "the existing `VideoProcessingPlaceholder`" (§2.2) | Replaces the delay with a readiness endpoint and poll, in Phase 1b | The delay is not artificial — it gates a `getDrop` refetch in three of four call sites, and `MemoryCard` has no placeholder wired in at all. Removing it as written ships a broken player. See Decision 5. |
