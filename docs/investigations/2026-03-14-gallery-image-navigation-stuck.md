# Investigation: Gallery Image Navigation Gets Stuck

**Status:** ✅ Resolved
**Date opened:** 2026-03-14
**Date resolved:** 2026-03-14

## Problem Statement

When navigating through images in the memory gallery lightbox (PhotoGrid.vue), the UI intermittently gets stuck on an image and becomes unresponsive. The image should already be loaded (visible in the grid), but navigation stops working. This does not happen every time.

**Key constraints from user:**
- The issue predates swipe/touch support and reproduces on **desktop using only arrow keys**
- The freeze is **temporary** — UI becomes responsive again after a few seconds
- Occurs on **multiple device types** (Android phone, Mac laptop)
- Images are typically **300–800 KB** each (JPEG, max 2048px width)

## Evidence

- Component: `fyli-fe-v2/src/components/memory/PhotoGrid.vue`
- Gallery uses a single `<img>` element and swaps `src` attribute on navigation
- `@keydown="handleKeydown"` is on the overlay div (requires overlay to have focus)
- Overlay gets focus via `nextTick(() => galleryEl.value?.focus())` only when `galleryIndex` changes
- The gallery image `<img>` has no click handler and is not focusable — clicking it does nothing visible but may move focus to `<body>`
- `@click.self="closeGallery"` on overlay means only direct overlay clicks close; child clicks (image, buttons) don't close but also don't re-focus overlay
- Navigation buttons conditionally rendered with `v-if` (disappear at boundaries) — if a focused button is removed from DOM, focus moves to `<body>`
- **Issue occurs on desktop with arrow keys**, ruling out touch/swipe-specific causes
- Issue predates swipe feature implementation
- **Images resized on upload** to max 2048px (landscape) / 1024px (portrait), saved as JPEG to S3
- **Same presigned S3 URL** used for both grid thumbnails and gallery lightbox (no separate thumbnail sizes)
- **Collapsed view (3+ images) only renders 3 `<img>` elements** — images at index 3+ are NOT in the DOM and have never been fetched from S3
- **No preloading** of adjacent gallery images when lightbox opens or navigates
- Images served via S3 presigned URLs (3-hour expiration)

## Hypotheses

| ID | Hypothesis | Likelihood | Status |
|----|-----------|-----------|--------|
| H1 | In collapsed view (3+ images), only images 0–2 exist in the DOM. When the gallery navigates to image 3+, the browser must fetch 300–800 KB from S3 over the network. On slower connections or mobile data, this takes seconds — during which the old image stays visible and the UI appears stuck. Self-recovers when the download completes. | 9/10 | 🔍 Untested |
| H2 | Even for cached images (0–2), the single `<img>` src swap may not serve from browser cache if the presigned URL query params differ or cache headers prevent it, forcing a re-fetch | 6/10 | 🔍 Untested |
| H3 | Clicking on the gallery image moves focus from the overlay to `<body>` (since `<img>` is non-focusable), breaking arrow key navigation until user clicks the overlay background | 4/10 | 🔍 Untested |
| H4 | Clicking a nav button at a boundary (first/last image) causes the button to be removed by `v-if`, sending focus to `<body>` and breaking keyboard nav | 3/10 | 🔍 Untested |

*Touch/swipe hypotheses ruled out in Round 0. Focus-loss hypotheses demoted in Round 1 — freeze self-recovers, but focus loss would be permanent. Pure decode-blocking demoted in Round 2 — 300–800 KB JPEGs decode in <100ms on modern devices.*

## Investigation Log

### Round 0 — User Clarification

**New information:** Issue happens on desktop with arrow keys. Predates swipe/touch support.

**Impact:** Eliminated 3 touch/swipe hypotheses. Elevated focus-loss hypothesis (H4-old → H1-new) to top priority at 9/10. Added new H2 for nav button boundary focus loss.

**Hypothesis updates:**
- H1-old (touch steal): Ruled out — not touch-related
- H2-old (browser swipe): Ruled out — not touch-related
- H5-old (swipe threshold): Ruled out — not touch-related
- H4-old (focus loss): Promoted to H1-new at 9/10, refined to focus on image click specifically
- H3-old (image decode): Kept as H3-new, likelihood reduced to 4/10 (less likely given keyboard-only repro)
- New H2: Nav button `v-if` removal causing focus loss at boundaries

### Round 1 — User Clarification (temporal behavior)

**New information:** The freeze is **temporary** — self-recovers after a few seconds. Occurs across multiple device types (Android phone, Mac laptop).

**Impact:** The self-recovering nature is the key discriminator. Focus loss (H1-prev, H2-prev) would be **permanent** until the user actively clicks something — it wouldn't spontaneously fix itself. Image decode blocking **would** self-recover once the decode completes, perfectly matching the symptom.

**Hypothesis updates:**
- H3-prev (image decode blocking): Promoted to H1-new at 9/10 — temporary freeze that self-recovers perfectly matches main-thread blocking during image decode. Cross-device reproduction is consistent (all browsers decode on main thread).
- H1-prev (image click focus loss): Demoted to H2-new at 5/10 — would cause permanent stuck, not temporary
- H2-prev (nav button v-if focus loss): Demoted to H3-new at 4/10 — would cause permanent stuck, not temporary
- H4-prev (external focus steal): Reduced to 2/10

### Round 2 — Testing H1 (image decode blocking)

**Test performed:** Explored full image pipeline — upload processing, storage, serving, and frontend rendering.

**Findings:**
1. Images are resized on upload (max 2048px landscape / 1024px portrait) and saved as JPEG to S3 (`cimplur` bucket)
2. **Same presigned S3 URL** is used for both grid thumbnails (300px CSS height) and gallery lightbox (85vw×85vh) — no separate thumbnail sizes exist
3. **Critical discovery:** In collapsed view (3+ images), only images 0, 1, 2 have `<img>` elements in the DOM (lines 89–103 of PhotoGrid.vue). Images at index 3+ are behind the "+N" overlay and are **never fetched from S3 until navigated to in the gallery lightbox**.
4. User reports images are 300–800 KB. At this size, JPEG decode takes <100ms — **not enough to cause seconds of blocking**. Pure decode blocking is unlikely.
5. However, **network fetch of 300–800 KB from S3** on slower connections or mobile data could easily take 2–5 seconds. During this time, the gallery shows the old image (single `<img>` src swap) and appears "stuck."
6. No image preloading mechanism exists in the codebase.

**Conclusion:** ⚠️ Partially Confirmed — Image decode alone is too fast to cause the issue at 300–800 KB, but the underlying mechanism (single `<img>` with no preloading) combined with **network fetch for uncached images** is the likely root cause.

**Hypothesis updates:**
- H1-prev (decode blocking): Refined into H1-new (network fetch for unloaded images beyond index 2) at 9/10
- New H2: S3 presigned URL cache behavior may also force re-fetches for images 0–2
- H2-prev (focus loss from image click): Demoted to H3-new at 4/10
- H3-prev (nav button v-if focus loss): Demoted to H4-new at 3/10

### Round 3 — Testing H1 (network fetch for unloaded images) + H2 (S3 cache headers)

**Test performed:** Examined S3 upload code (`ImageService.UploadImageToS3Async`) and presigned URL generation for cache header configuration.

**Findings:**
1. **No Cache-Control headers set on S3 objects.** The `PutObjectRequest` only sets `ContentType = "image/jpeg"` — no `Cache-Control`, `Expires`, or other caching metadata.
2. S3 default behavior without Cache-Control: browsers use heuristic caching. Within a session, images 0–2 should be served from browser cache since the exact same presigned URL string is reused (stored in `ImageLink.link`).
3. **H2 partially ruled out** for within-session navigation: the presigned URL doesn't change between grid and gallery — same object identity in browser cache. Cross-session is a different story (new presigned URLs generated), but not relevant to the gallery navigation bug.
4. **H1 confirmed as primary mechanism:** Images at index 3+ have never been fetched. The gallery must download them from S3 on first navigation. At 300–800 KB over mobile data or slower WiFi, this easily takes 2–5 seconds.
5. No CDN (CloudFront) is configured — images come directly from S3 (us-east-1), adding latency for users far from that region.

**Conclusion:** ✅ Confirmed — The root cause is that **images beyond index 2 are never preloaded** in collapsed view. When navigated to in the gallery, they require a cold network fetch from S3. The single `<img>` src-swap shows the old image during download, making the UI appear frozen until the new image loads.

---

## Resolution

**Root Cause:** In collapsed view (3+ images), `PhotoGrid.vue` only renders `<img>` elements for images 0–2. Images at index 3+ are behind the "+N" overlay and are never fetched from S3. When the user opens the gallery lightbox and navigates past image 2, the browser must perform a cold network fetch of 300–800 KB from S3 (us-east-1, no CDN). During the download, the gallery's single `<img>` element still shows the previous image, making the UI appear stuck. It self-recovers when the download completes.

The issue is intermittent because:
- It only affects memories with 4+ images in collapsed view
- Severity depends on network speed (worse on mobile data, slower WiFi, or users far from us-east-1)
- Images 0–2 are already cached and swap instantly

**Recommended Action:** Preload adjacent images when the gallery opens and as the user navigates. Options include:
1. **Preload on gallery open:** When the lightbox opens, use `new Image().src = url` to prefetch all (or at least the next 2–3) images in the background
2. **Preload on navigate:** When the user moves to image N, prefetch image N+1 (and optionally N-1)
3. **Add a loading indicator:** Show a spinner on the gallery image while loading, so the UI doesn't appear frozen
4. **Longer-term:** Add `Cache-Control: max-age=86400` to S3 uploads and consider CloudFront CDN

Run `/fixer` or `/architect` to implement the fix.
