# Product Requirements Document: Instant Uploads

## Overview

Photos and videos currently upload only *after* a parent clicks Save, so every
byte is transferred while they sit and watch a spinner. This feature starts the
upload the moment a file is selected — during the 30–90 seconds the parent
spends writing the memory — so that by the time they hit Save, the files are
already in S3 and saving feels instant. It also removes an artificial 2–8 second
delay we currently add on purpose, and reorders the create form so choosing
photos comes naturally first.

No file is ever compressed, resized, or degraded. Originals are uploaded and
stored exactly as captured.

## Problem Statement

A parent gets home from their daughter's recital with eight photos and a two
minute video. They open Fyli, write a few sentences about how she looked when
she spotted them in the audience, and hit Save. Then they wait. The spinner runs
through "Uploading files," and then — for reasons invisible to them — keeps
spinning for several more seconds after the upload is already done.

The wait is long enough to break the moment. Capturing a memory should feel like
setting something down safely, not like submitting a form. Worse, the wait
teaches parents that adding photos is expensive, which quietly pushes them
toward text-only memories — or toward not capturing the moment at all.

The frustrating part is that the wait is almost entirely avoidable. While the
parent was typing for a minute and a half, the connection sat completely idle.
We had all the time we needed and didn't use it.

## Goals

1. **Make saving a memory with photos feel as fast as saving one without**, so
   that adding media is never the reason a parent skips capturing a moment.
2. **Use the time the parent is already spending**, so the upload finishes
   invisibly during writing rather than visibly after it.
3. **Tell the truth about progress**, so that when a parent does have to wait on
   a large video, they know exactly what is happening and don't abandon it.
4. **Preserve every original file at full fidelity** — these are keepsakes, and
   no perceived-speed gain justifies degrading them.

## User Stories

### Capturing a moment

1. As a parent, I want to pick my photos first and have them upload while I
   write, so that saving the memory is instant when I'm done.
2. As a parent, I want to see that my photos are already safely uploaded before
   I hit Save, so that I trust the moment is captured and can close my phone.
3. As a parent, I want to save a memory with a dozen photos as quickly as one
   with none, so that I'm never discouraged from including the pictures that
   make the memory worth revisiting.

### Waiting honestly

4. As a parent uploading a long video, I want to see real progress and a real
   estimate, so that I know it's working and don't give up on the memory.
5. As a parent, I want to never wait longer than the upload actually takes, so
   that the app never wastes my evening.

### Changing my mind

6. As a parent, I want to remove a photo I picked by mistake, so that only the
   moments I meant to keep are saved.
7. As a parent, I want to abandon a memory entirely without leaving stray files
   behind, so that my account stays clean and private.

## Feature Requirements

### 1. Upload on selection

#### 1.1 Upload begins immediately
- When a parent selects one or more files, upload to S3 begins right away,
  without waiting for Save and without requiring that the memory exist yet.
- Applies to both images and videos.
- The parent can continue writing, set the date, pick storylines, and move to
  the Share step while uploads run. Nothing blocks on the upload.

#### 1.2 Files are held in a staging area
- Files upload to a user-scoped staging location in S3 that is **not** derived
  from a memory ID, since no memory exists yet.
- Staged files are claimed by the memory at save time.
- Files that are never claimed are removed automatically (see 4.1).

#### 1.3 Removing a file
- Removing a thumbnail cancels the in-flight upload if it hasn't finished.
- If the upload already finished, the staged file is simply never claimed and
  expires on its own. No blocking delete call on the parent's path.

#### 1.4 Concurrency
- Uploads run in parallel with a cap (recommend 3 concurrent) so that a
  ten-photo selection doesn't starve the connection or stall the video.
- Videos are prioritized over images when both are queued, since videos are the
  long pole.

### 2. Save behavior

#### 2.1 Save waits only for real remaining bytes
- On Save, the memory is created and staged files are claimed.
- If all uploads are complete, the claim is metadata-only and the parent goes
  straight to their stream — no visible upload phase at all.
- If uploads are still in flight, the parent stays on screen with honest
  progress until they finish. We do not upload in the background after
  navigation.

#### 2.2 Remove the artificial delay
- The deliberate 2–8 second `setTimeout` currently inserted after upload
  (`getTranscodeDelay`) is removed entirely.
- Video transcoding continues asynchronously on the server. The memory appears
  in the stream immediately, using the existing `VideoProcessingPlaceholder`
  for any video still transcoding.

#### 2.3 Claim must not move bytes
- Claiming staged files at save time must be a metadata operation. Copying a
  multi-gigabyte object on the save request path would reintroduce exactly the
  wait this feature removes.

### 3. Form order and upload status

#### 3.1 Photos & Videos moves to the top of step 1
- Within the existing two-step Write → Share flow, the Photos & Videos picker
  moves above the text area. **No new steps are added** and the step indicator
  is unchanged.
- Order within step 1 becomes: Photos & Videos → What happened? → Writing
  assist → Date → Storyline.
- The picker must read as clearly optional. Text is still the only required
  field, and a memory with no media must feel completely normal to create.

#### 3.2 Do not steal focus on mobile
- The text area must not autofocus on small screens. An opened keyboard hides
  the picker and defeats the reordering.

#### 3.3 Per-file status on the thumbnail
- Each thumbnail shows its own state: uploading (percentage), ready, or failed.
- "Ready" is the important one — it lets the parent see the moment is already
  safe *before* they hit Save. This is where most of the perceived speed comes
  from.
- Progress display extends to images, not just videos as today.

#### 3.4 Failure is recoverable, not fatal
- A failed file shows a Retry affordance on its thumbnail.
- A failed file never blocks saving the memory. The words are the memory; the
  photo can be added later from the memory detail.

### 4. Cleanup

#### 4.1 Abandoned files expire automatically
- An S3 lifecycle rule on the staging prefix deletes unclaimed objects after a
  fixed window (recommend 48 hours).
- This is the only cleanup mechanism required. No cleanup job to write, no
  delete call that fails to fire when a parent closes the tab, and no code path
  that can touch an already-claimed file.

## Data Model

A new staging record. Purely additive — no changes to `Drop`, no changes to how
access to drops is determined.

```
StagedUpload {
  stagedUploadId: int
  userId:         int
  token:          guid       // opaque handle returned to the client
  s3Key:          string     // staging/{userId}/{token}
  kind:           string     // "image" | "video"
  contentType:    string
  fileSize:       long
  createdAt:      datetime
  claimedDropId:  int?       // null until claimed at save
}
```

### API shape

```
POST /api/uploads/stage/request   -> { token, presignedUrl }
POST /api/uploads/stage/complete  -> { token, ready: true }
POST /api/uploads/claim           -> { dropId, tokens[], commentId? }
```

Existing `/api/images`, `/api/movies/upload/request`, and
`/api/movies/upload/complete` endpoints remain unchanged and functional, so
older clients and the legacy frontend keep working exactly as they do today.

## UI/UX Requirements

### Picker display
- Photos & Videos sits at the top of step 1, presented as an inviting tile
  rather than a bare file input.
- Label makes optionality obvious (e.g. "Add photos or videos" with no required
  marker).
- Thumbnails appear immediately from the local file, before any upload
  completes, so the parent sees their pictures instantly.

### Status display
- Uploading: percentage over the thumbnail.
- Ready: a small check on the thumbnail. Quiet, not celebratory.
- Failed: a warning state with Retry.
- When a large video is still uploading at Save, show a single honest line —
  what's left and roughly how long — not a sequence of abstract step names.

### Language
- Avoid mechanical words like "processing" and "transcoding" in parent-facing
  copy. Prefer "Your video is still uploading — keep this tab open."

## Technical Considerations

### Decoupling from dropId
`MovieService.GetUploadUrl` creates a `MovieDrop` row and derives the S3 key
from `dropId` before any bytes move, which is the core blocker. Staging needs a
key and a record that don't depend on a memory existing. The existing
`temp/` → final move in `CompleteDirectUpload` is the pattern to extend.

### Images currently take an extra hop
`mediaApi.uploadImage` posts multipart to `/api/images`, which routes through
the app server to S3. Staging requires a presigned direct-to-S3 path for images
too, which removes that hop and is itself a real speed gain.

### Avoiding a copy at claim time
Two viable approaches, to be settled in the TDD:
1. Record the staging key on the media record and let the existing transcode /
   serve pipeline read from it, moving bytes asynchronously after the parent is
   already gone.
2. `CopyObject` server-side at claim. Note the 5GB single-part copy limit sits
   exactly at our max video size, so this would need multipart copy.

Approach 1 is preferred because it keeps the save path metadata-only, which
requirement 2.3 demands.

### Backwards compatibility
All changes are additive. Existing drops, existing media, and all access-control
paths for who can view a drop are untouched.

### Presigned URL expiry
Current video presigned URLs expire in one hour. A parent who picks a file,
gets interrupted, and returns later must not hit a silent failure — expiry
needs handling with a re-request, not an error.

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Save-to-stream time (photos) | Median seconds from Save click to stream for memories with images only | < 1.5s |
| Upload head start | % of memories where all files are "ready" before Save is clicked | > 80% |
| Memories including media | % of created memories that include at least one photo or video | +10% vs. baseline |
| Create abandonment | % of create sessions with files selected that never result in a saved memory | Decrease vs. baseline |
| Wasted wait | Seconds of artificial delay on the save path | 0 |
| Orphaned staged objects | Unclaimed staging objects older than the lifecycle window | 0 |

## Out of Scope (Future Considerations)

- Background upload after navigation. Explicitly rejected: the parent stays on
  screen until files land, which removes an entire class of edge cases.
- Client-side downscaling or compression. Explicitly rejected: originals are
  preserved at full fidelity.
- Draft memories. Staging deliberately avoids introducing a draft state into
  `Drop` that every stream, sharing, and permission query would have to learn to
  exclude.
- Resumable / chunked uploads for very large videos.
- Applying staged uploads to comment attachments and the edit-memory flow.
- Camera capture directly in the app.

## Implementation Phases

### Phase 1: Stop wasting time we already have
- Move Photos & Videos to the top of step 1 (no new steps).
- Remove the artificial `getTranscodeDelay` wait.
- Suppress text area autofocus on small screens.
- Show per-file progress for images, not just videos.

*Frontend only, no backend changes. Delivers a visible improvement on its own.*

### Phase 2: Staging infrastructure
- `StagedUpload` model and the three staging endpoints.
- Presigned direct-to-S3 for images.
- S3 lifecycle rule on the staging prefix.

### Phase 3: Upload on selection
- Start upload on file select; claim staged files at save.
- Per-file ready / failed / retry states on thumbnails.
- Concurrency cap and video prioritization.
- Honest remaining-time display when a large video is still in flight at Save.

## Open Questions

1. What is the right lifecycle expiry for unclaimed staging objects? 48 hours is
   proposed; shorter is cheaper, longer is safer for interrupted parents.
   Answer - 48 hrs is fine.
2. Should a parent who abandons a memory with files already uploaded be offered
   a "you had photos here" recovery when they return? Out of scope for now, but
   the staging records make it possible.
   Answer - ignore for now - but future feature possibly
3. Should the storyline and date fields also move below the text area, or is
   moving only the picker enough to establish the photos-first habit?
   Answer - keep it simple move only picker
4. Does the edit-memory flow adopt staging in this effort, or follow later?
   Answer - let's keep edit the same for now unless it is easier to keep it consistent.
   

---

*Document Version: 1.0*
*Created: 2026-09-21*
*Status: Draft*
