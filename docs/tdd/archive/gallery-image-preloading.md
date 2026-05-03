# TDD: Gallery Image Preloading

**Date:** 2026-03-14
**Investigation:** [`docs/investigations/2026-03-14-gallery-image-navigation-stuck.md`](../investigations/2026-03-14-gallery-image-navigation-stuck.md)

## Overview

When a memory's PhotoGrid component mounts, proactively download all images in the background so that gallery navigation is instant by the time the user opens the lightbox.

### Root Cause (from investigation)

In collapsed view (3+ images), only images 0–2 have `<img>` elements in the DOM. Images at index 3+ are behind the "+N" overlay and have never been fetched from S3. When the user opens the gallery and navigates past image 2, the browser must perform a cold network fetch (300–800 KB from S3), causing a multi-second freeze where the old image remains visible.

## Architecture

This is a **frontend-only** change, scoped entirely to `PhotoGrid.vue`. No backend changes required.

### Approach

**Preload all images on component mount** — When `PhotoGrid` mounts, iterate over all `props.images` and create `new Image()` objects to trigger browser downloads in the background. By the time the user opens the gallery (even seconds later), all images are already in the browser's HTTP cache. Gallery `src` swaps then resolve instantly from cache.

This is the simplest possible fix:
- No loading state tracking needed (images load in the background well before gallery opens)
- No spinner needed (images are already cached when the gallery opens)
- No template changes needed
- No CSS changes needed

## Detailed Design

### Phase 1: Preload on Mount

**File:** `fyli-fe-v2/src/components/memory/PhotoGrid.vue`

#### New Function

```typescript
function preloadImages() {
	for (const image of props.images) {
		const img = new Image()
		img.src = image.link
	}
}
```

#### Call on Mount

```typescript
import { ref, watch, nextTick, onMounted, onUnmounted } from 'vue'

// ... existing code ...

onMounted(() => {
	preloadImages()
})
```

That's it. No new state, no computed properties, no template changes, no CSS changes.

#### Why This Works

1. `new Image()` triggers the browser to fetch the URL and store it in the HTTP cache
2. The `Image` objects are created and garbage-collected — we don't need references to them
3. When the gallery later sets `<img :src="images[galleryIndex]?.link">`, the browser serves the image from cache instantly
4. Images 0–2 are already in the DOM (redundant preload is harmless — browser deduplicates)
5. Images 3+ get fetched in the background before the user ever opens the gallery

#### Edge Cases

- **Single/two images:** All images are already in the DOM, so preload is a no-op (browser already fetching them). Harmless.
- **Many images (10+):** Browser will queue and download them with standard HTTP/2 multiplexing. No throttling needed — these are 300–800 KB JPEGs.
- **Component remounts:** Fresh `Image` objects created, browser serves from cache. No wasted bandwidth.
- **Slow connections:** Images may not all be cached by the time the user opens the gallery. This is the same behavior as today — no regression. The preload just gives a head start.

## Testing Plan

**File:** `fyli-fe-v2/src/components/memory/PhotoGrid.test.ts`

### New Tests

| # | Test | Validates |
|---|------|-----------|
| 1 | `preloads all images on mount` | Creates `Image` objects with correct `src` for every image URL |
| 2 | `preloads images beyond collapsed view` | With 5+ images in collapsed view, all 5 URLs are preloaded (not just the 3 visible) |

### Test Strategy

Mock `window.Image` to capture created instances:

```typescript
let imageInstances: { src: string }[]

beforeEach(() => {
	imageInstances = []
	vi.stubGlobal('Image', class {
		src = ''
		constructor() {
			imageInstances.push(this)
		}
	})
})

afterEach(() => {
	vi.unstubAllGlobals()
})
```

**Note:** The `Image` mock must be scoped to the preload test `describe` block only. Existing gallery tests don't interact with `new Image()` and should remain unchanged.

## Implementation Order

1. Add `preloadImages()` function
2. Add `onMounted` call
3. Write 2 new tests
4. Run all existing tests to verify no regressions

## File Changes Summary

| File | Change |
|------|--------|
| `fyli-fe-v2/src/components/memory/PhotoGrid.vue` | Add `preloadImages()` + `onMounted` call (~6 lines) |
| `fyli-fe-v2/src/components/memory/PhotoGrid.test.ts` | Add 2 new tests for preloading behavior |

No new files. No backend changes. No database changes. No API changes. No template changes. No CSS changes.
