# Investigation: Videos Displayed Sideways After S3 / MediaConvert Upload

**Status:** ✅ Resolved
**Date opened:** 2026-09-18
**Date resolved:** 2026-09-19

## Problem Statement

After switching video upload from server-side ingest + Elastic Transcoder to direct S3 upload + AWS MediaConvert, some videos play rotated 90° (sideways). Expected: playback matches how the phone recorded the clip (portrait stays portrait).

## Evidence

- Upload path is now: frontend PUT to a presigned S3 URL → `POST /movies/upload/complete` → `MovieService.TranscodeWithMediaConvert` (`cimplur-core/Memento/Domain/Repositories/MovieService.cs`).
- The MediaConvert `Input` sets `FileInput` and `AudioSelectors` only. It does **not** set `VideoSelector.Rotate`.
- AWS MediaConvert docs: default is no rotation even when the input has rotation metadata, and **outputs never pass through rotation metadata**. AWS’s own tip for “outputs rotated in a way you don’t expect” is: set **Rotate = Automatic**.
- Photos are handled differently: `ImageService.RotateImage` reads EXIF orientation and bakes it into pixels. There is no equivalent for video in app code — orientation is entirely the transcoder’s job.
- Old Elastic Transcoder job (`Transcode`) also did not set `Rotate` on `CreateJobOutput`. Behavior still changed because MediaConvert’s default + no metadata pass-through is stricter than Elastic Transcoder.
- Early MediaConvert code used job template `Fyli_Default`; current code inlines full job settings and no longer references that template. If the template had AUTO rotate, dropping it would drop the fix.
- Frontend `<video>` tags (`MemoryCard.vue`, `MemoryDetailView.vue`, question/comment views) have no CSS `transform` / orientation handling. Preview uses a blob URL of the **original** file; playback after complete uses the **transcoded** S3 object.
- Temp originals are likely still in S3 (`DeleteFullSize` after MediaConvert is commented out), so we can ffprobe original vs output.

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | MediaConvert job never sets `VideoSelector.Rotate = AUTO`, so phone rotation tags are ignored and then stripped | 9/10 | ✅ Confirmed |
| H2 | “Sometimes” = portrait phone clips only (landscape has no rotate tag; some Androids bake rotation into pixels) | 8/10 | — Superseded by H1 |
| H3 | Blob preview looks correct because the browser honors the original rotate tag; the transcoded file does not | 7/10 | — Superseded by H1 |
| H4 | Abandoned `Fyli_Default` job template had AUTO rotate; inline rewrite omitted it | 5/10 | — Superseded by H1 |
| H5 | Even AUTO would miss some files (not `.mov`/`.mp4`, or rotation metadata not ~90/180/270) | 4/10 | — Superseded by H1 |
| H6 | Frame-capture thumbnail/poster is unrotated, so the player *looks* sideways even if video pixels are fine | 3/10 | — Superseded by H1 |

### H1 — MediaConvert `Rotate` not set (most likely)

**Hypothesis:** The sideways videos are phone recordings stored as landscape pixel buffers with a 90°/270° rotate atom. MediaConvert leaves pixels unrotated and does not copy the rotate atom into the output, so every player shows them on their side.

**Reasoning:** `TranscodeWithMediaConvert` builds:

```csharp
new Amazon.MediaConvert.Model.Input
{
    FileInput = inputS3Uri,
    AudioSelectors = { ... }
    // no VideoSelector
}
```

SDK 4.0.11.3 has `Input.VideoSelector.Rotate` with `InputRotate.AUTO`. AWS default is `DEGREE_0`. AWS also documents that rotation metadata is never passed through. That combination is the textbook cause of this bug.

**Test:**
1. Confirm in code (already observed) that `VideoSelector` is absent.
2. Pick a known-sideways movie. ffprobe the S3 **temp original** and the **transcoded `.mp4`** for `rotate` / `displaymatrix` and coded width×height.
3. Expected if H1 is true: original has rotate=90 or 270 (or a non-identity display matrix) and landscape coded size; output has no rotate tag, same landscape coded size, and plays sideways.
4. Optional: resubmit the same input with `Rotate = AUTO` and confirm the output is portrait.

### H2 — Only portrait-shot phone videos

**Hypothesis:** Landscape-shot videos and cameras that bake orientation into pixels look fine; only clips with a non-zero rotate tag break. That is why it is intermittent.

**Reasoning:** iPhone/Android typically write 1920×1080 (or 1080×1920 coded as 1920×1080) plus a rotate flag when the phone is held upright. A clip shot in landscape has rotate=0 / no tag. Some Android OEMs rotate pixels instead of tagging.

**Test:** For several good vs bad videos, record device, held orientation, and ffprobe rotate. If every sideways clip has a non-zero rotate tag on the original and every upright clip does not, H2 is confirmed as the *scope* of H1.

### H3 — Preview vs transcoded mismatch

**Hypothesis:** Users first see a correct blob preview (browser applies the original rotate tag), then after MediaConvert finishes the S3 file is sideways.

**Reasoning:** Create/answer flows play `URL.createObjectURL(file)` before complete. Playback after refresh uses `movie.link` from the transcoded object. If H1 is true, this timing difference is expected.

**Test:** Upload a portrait phone video. Watch the in-form preview, then the memory/answer after transcode. If preview is upright and the stored video is sideways, H3 is confirmed (as a symptom of H1).

### H4 — Job template lost AUTO rotate

**Hypothesis:** `Fyli_Default` included `Rotate: AUTO`. The later inline job did not copy that field.

**Reasoning:** First MediaConvert commit used `JobTemplate = "arn:.../jobTemplates/Fyli_Default"` with only `FileInput` override. Current code comments that ARN out and inlines codec/container/thumbnail settings with no rotate.

**Test:** In AWS MediaConvert console, open template `Fyli_Default` and check Input → Video selector → Rotate. Compare to a recent completed job’s JSON (`settings.inputs[0].videoSelector.rotate`).

### H5 — AUTO would still miss some containers / tags

**Hypothesis:** A subset of files would stay sideways even after setting AUTO: not `.mov`/`.mp4`, or rotation metadata not within 1° of 90/180/270.

**Reasoning:** AWS AUTO requirements are `.mov` or `.mp4` plus 90/180/270 metadata. iPhone HEVC `.mov` usually qualifies; some Android 3GP/WebM or unusual matrix values would not.

**Test:** After (or while) testing H1, classify failing originals by container/codec (`ffprobe -show_format -show_streams`) and rotate value. Only pursue if AUTO-fixed jobs still produce sideways output.

### H6 — Thumbnail/poster only

**Hypothesis:** The video pixels are fine; the frame-capture JPEG used as `poster` is unrotated, which makes the paused player look sideways.

**Reasoning:** Thumbnail output is a separate Frame Capture group with the same missing `VideoSelector.Rotate`. `poster` is set on every `<video>`. Less likely as the sole cause if playback while playing is also sideways.

**Test:** On a sideways example, play vs pause, and open `thumbLink` vs `link` in new tabs. If only the JPEG is rotated, H6 is the cause; if the MP4 is rotated too, H6 is a side effect of H1.

## Investigation Log

### Round 1 — H1 implemented without ffprobe

User asked for the H1 fix rather than a live-file probe. Confirmed in `MovieService.TranscodeWithMediaConvert` that the MediaConvert `Input` had no `VideoSelector.Rotate`. AWS default is no rotation and no metadata pass-through.

**Fix:** `CreateMediaConvertInput` now sets `VideoSelector.Rotate = InputRotate.AUTO`. That applies to both the H.264 output and the frame-capture thumbnail. No fixed Width/Height on `VideoDescription`, so 90°/270° can swap dimensions.

**Conclusion:** ✅ Confirmed as the code-level cause. Live portrait-upload verification is post-deploy.

### Round 2 — Live verification

User confirmed after the 2026-09-19 backend deploy that a new upload plays upright. H1 is confirmed in production.

---

## Resolution

**Root Cause:** MediaConvert job did not set `VideoSelector.Rotate = AUTO`. Phone portrait clips (landscape pixels + 90°/270° rotate tag) were transcoded without baking or preserving orientation, so they played sideways.

**Fix:** `MovieService.CreateMediaConvertInput` sets `VideoSelector.Rotate = InputRotate.AUTO`. Deployed to ECS `apis-service-fyli-8080` on 2026-09-19. Live portrait upload confirmed upright.

**Follow-up:** Existing sideways clips are unchanged until they are transcoded again.
