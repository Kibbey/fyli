# TDD: Photo Grid Expand & Image Gallery

## Overview

Currently, `PhotoGrid.vue` shows up to 3 images with a `+N` overlay when there are more. Clicking the `+N` overlay does nothing — users expect it to reveal all hidden images. Additionally, the existing `ClickableImage` lightbox only shows one image at a time with no way to navigate between images.

This TDD adds two capabilities:
1. **Expanded grid** — clicking `+N` expands the grid to show all images
2. **Gallery navigation** — clicking any image opens a full-screen lightbox with left/right navigation across all images

## Current State

### PhotoGrid.vue (`src/components/memory/PhotoGrid.vue`)
- Shows 1 image (full width), 2 images (side-by-side), or 3+ images (1 main + 2 small + `+N` overlay)
- The `+N` overlay is a plain `<div>` — not clickable
- Each image wraps `ClickableImage` which opens a standalone lightbox for that single image

### ClickableImage.vue (`src/components/ui/ClickableImage.vue`)
- Wraps a single `<img>` with click-to-expand
- Lightbox shows only the clicked image — no navigation to other images
- **Only used by PhotoGrid** — after this change it becomes dead code

## Design Decisions

**Approach: Expand grid + gallery lightbox in PhotoGrid**

- PhotoGrid gains an `expanded` ref. Clicking `+N` sets `expanded = true`, showing all images in a wrapping grid
- PhotoGrid gains its own gallery lightbox with prev/next navigation. Clicking any image opens the gallery at that image's index
- `ClickableImage` is no longer used by PhotoGrid. Since PhotoGrid is its only consumer, `ClickableImage.vue` and `ClickableImage.test.ts` become dead code and should be deleted in a cleanup step
- A "Show less" button collapses the grid back to the 3-image preview
- Gallery overlay uses **unscoped styles** with a `pg-` prefix to avoid the Vue scoped CSS + `<Teleport>` issue (scoped data attributes don't apply to teleported DOM)
- Gallery auto-focuses the overlay `<div>` on open via `watch` + `nextTick` so keyboard navigation works immediately
- Body scroll is locked (`overflow: hidden`) while the gallery is open
- Gallery counter uses `env(safe-area-inset-bottom)` for iOS safe areas

**Future enhancements (not in scope):**
- Touch/swipe navigation for mobile
- Image preloading for next/previous
- Fade transitions on gallery open/close

## Phase 1: Implementation

### 1.1 PhotoGrid.vue Changes

**File:** `src/components/memory/PhotoGrid.vue`

Replace the current implementation with:

```vue
<script setup lang="ts">
import type { ImageLink } from '@/types'
import { ref, watch, nextTick, onUnmounted } from 'vue'

const props = defineProps<{
	images: ImageLink[]
}>()

const expanded = ref(false)
const galleryIndex = ref(-1)
const galleryEl = ref<HTMLElement | null>(null)

function openGallery(index: number) {
	galleryIndex.value = index
}

function closeGallery() {
	galleryIndex.value = -1
}

function prevImage() {
	if (galleryIndex.value > 0) {
		galleryIndex.value--
	}
}

function nextImage() {
	if (galleryIndex.value < props.images.length - 1) {
		galleryIndex.value++
	}
}

function handleKeydown(e: KeyboardEvent) {
	if (e.key === 'ArrowLeft') prevImage()
	else if (e.key === 'ArrowRight') nextImage()
	else if (e.key === 'Escape') closeGallery()
}

watch(galleryIndex, (val) => {
	if (val >= 0) {
		document.body.style.overflow = 'hidden'
		nextTick(() => galleryEl.value?.focus())
	} else {
		document.body.style.overflow = ''
	}
})

onUnmounted(() => {
	document.body.style.overflow = ''
})
</script>

<template>
	<div v-if="images.length" class="photo-grid mb-2">
		<!-- Single image -->
		<div v-if="images.length === 1" class="single">
			<img :src="images[0]!.link" class="img-fluid rounded clickable" alt=""
				@click="openGallery(0)" />
		</div>

		<!-- Two images -->
		<div v-else-if="images.length === 2" class="d-flex gap-1">
			<img v-for="(img, i) in images" :key="img.id" :src="img.link"
				class="img-fluid rounded w-50 clickable" alt=""
				@click="openGallery(i)" />
		</div>

		<!-- 3+ images: collapsed or expanded -->
		<div v-else class="multi">
			<!-- Collapsed: show 3 preview images -->
			<template v-if="!expanded">
				<img :src="images[0]!.link" class="img-fluid rounded main-img clickable" alt=""
					@click="openGallery(0)" />
				<div class="d-flex gap-1 mt-1">
					<img v-for="(img, i) in images.slice(1, 3)" :key="img.id" :src="img.link"
						class="img-fluid rounded w-50 clickable" alt=""
						@click="openGallery(i + 1)" />
					<div v-if="images.length > 3"
						class="more-overlay rounded d-flex align-items-center justify-content-center"
						role="button"
						aria-label="Show all images"
						@click="expanded = true">
						+{{ images.length - 3 }}
					</div>
				</div>
			</template>

			<!-- Expanded: show all images in wrapping grid -->
			<template v-else>
				<div class="expanded-grid">
					<img v-for="(img, i) in images" :key="img.id" :src="img.link"
						class="rounded clickable" alt=""
						@click="openGallery(i)" />
				</div>
				<button class="btn btn-sm btn-outline-secondary mt-2" @click="expanded = false">
					Show less
				</button>
			</template>
		</div>

		<!-- Gallery lightbox -->
		<Teleport to="body">
			<div v-if="galleryIndex >= 0" class="pg-gallery-overlay"
				@click.self="closeGallery"
				@keydown="handleKeydown"
				tabindex="0"
				ref="galleryEl">
				<button v-if="galleryIndex > 0"
					class="pg-gallery-nav pg-gallery-prev"
					aria-label="Previous image"
					@click="prevImage">
					<span class="mdi mdi-chevron-left"></span>
				</button>
				<img :src="images[galleryIndex]?.link" alt="" class="pg-gallery-image" />
				<button v-if="galleryIndex < images.length - 1"
					class="pg-gallery-nav pg-gallery-next"
					aria-label="Next image"
					@click="nextImage">
					<span class="mdi mdi-chevron-right"></span>
				</button>
				<div class="pg-gallery-counter">
					{{ galleryIndex + 1 }} / {{ images.length }}
				</div>
				<button class="pg-gallery-close" aria-label="Close gallery" @click="closeGallery">
					<span class="mdi mdi-close"></span>
				</button>
			</div>
		</Teleport>
	</div>
</template>

<style scoped>
.photo-grid img {
	object-fit: cover;
	max-height: 300px;
}
.clickable {
	cursor: pointer;
}
.more-overlay {
	background: rgba(0, 0, 0, 0.5);
	color: white;
	font-size: 1.2rem;
	min-width: 60px;
	cursor: pointer;
}
.more-overlay:hover {
	background: rgba(0, 0, 0, 0.65);
}

/* Expanded grid */
.expanded-grid {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
	gap: 0.25rem;
}
.expanded-grid img {
	width: 100%;
	height: 150px;
	object-fit: cover;
}
</style>

<!-- Unscoped: Teleported gallery content is outside component DOM tree -->
<style>
.pg-gallery-overlay {
	position: fixed;
	inset: 0;
	z-index: 9999;
	background: rgba(0, 0, 0, 0.85);
	display: flex;
	align-items: center;
	justify-content: center;
	cursor: default;
}
.pg-gallery-overlay:focus {
	outline: none;
}
.pg-gallery-image {
	max-width: 85vw;
	max-height: 85vh;
	object-fit: contain;
	border-radius: 4px;
}
.pg-gallery-nav {
	position: absolute;
	top: 50%;
	transform: translateY(-50%);
	background: rgba(255, 255, 255, 0.15);
	border: none;
	color: white;
	font-size: 2.5rem;
	width: 48px;
	height: 48px;
	border-radius: 50%;
	display: flex;
	align-items: center;
	justify-content: center;
	cursor: pointer;
	transition: background 0.2s;
}
.pg-gallery-nav:hover {
	background: rgba(255, 255, 255, 0.3);
}
.pg-gallery-prev {
	left: 1rem;
}
.pg-gallery-next {
	right: 1rem;
}
.pg-gallery-counter {
	position: absolute;
	bottom: calc(1.5rem + env(safe-area-inset-bottom, 0px));
	left: 50%;
	transform: translateX(-50%);
	color: rgba(255, 255, 255, 0.8);
	font-size: 0.875rem;
}
.pg-gallery-close {
	position: absolute;
	top: 1rem;
	right: 1rem;
	background: rgba(255, 255, 255, 0.15);
	border: none;
	color: white;
	font-size: 1.5rem;
	width: 44px;
	height: 44px;
	border-radius: 50%;
	display: flex;
	align-items: center;
	justify-content: center;
	cursor: pointer;
	transition: background 0.2s;
}
.pg-gallery-close:hover {
	background: rgba(255, 255, 255, 0.3);
}
</style>
```

**Key changes from current:**
- Removed `ClickableImage` dependency — images are `<img>` tags with `@click="openGallery(i)"`
- Added `expanded` ref toggled by clicking `+N`
- Added gallery lightbox with prev/next navigation, keyboard support, counter, and close button
- `+N` overlay gets `role="button"` and `cursor: pointer` for accessibility
- Expanded view uses CSS Grid for a responsive thumbnail layout
- "Show less" button to collapse back
- `galleryEl` template ref defined in script + `watch` + `nextTick` auto-focuses overlay on open
- Body scroll locked while gallery is open, restored on close and `onUnmounted`
- Gallery styles are **unscoped** with `pg-` prefix to work with `<Teleport>`
- Gallery overlay uses `rgba(0,0,0,0.85)` to match existing `ClickableImage` overlay
- Close button is 44px (meets minimum touch target from style guide)
- Counter uses `env(safe-area-inset-bottom)` for iOS safe areas

### 1.2 Delete Dead Code

After this change, `ClickableImage` has no consumers. Remove:

| File | Action |
|------|--------|
| `fyli-fe-v2/src/components/ui/ClickableImage.vue` | Delete |
| `fyli-fe-v2/src/components/ui/ClickableImage.test.ts` | Delete |

### 1.3 No Backend Changes

This is a purely frontend feature. No API or backend modifications needed.

### 1.4 No Database Changes

None required.

## Phase 2: Testing

### 2.1 Updated PhotoGrid Tests

**File:** `src/components/memory/PhotoGrid.test.ts`

Note: Uses tabs for indentation and semicolons to match existing codebase conventions.

```typescript
import { describe, it, expect, afterEach } from "vitest";
import { mount } from "@vue/test-utils";
import PhotoGrid from "./PhotoGrid.vue";
import type { ImageLink } from "@/types";

function makeImages(count: number): ImageLink[] {
	return Array.from({ length: count }, (_, i) => ({ id: i + 1, link: `/img/${i + 1}.jpg` }));
}

describe("PhotoGrid", () => {
	it("renders single image full width", () => {
		const wrapper = mount(PhotoGrid, { props: { images: makeImages(1) } });
		expect(wrapper.find(".single").exists()).toBe(true);
	});

	it("renders two images side by side", () => {
		const wrapper = mount(PhotoGrid, { props: { images: makeImages(2) } });
		expect(wrapper.find(".d-flex.gap-1").exists()).toBe(true);
		expect(wrapper.find(".single").exists()).toBe(false);
	});

	it("renders grid for 3+ images", () => {
		const wrapper = mount(PhotoGrid, { props: { images: makeImages(3) } });
		expect(wrapper.find(".multi").exists()).toBe(true);
	});

	it("shows +N overlay for extra images", () => {
		const wrapper = mount(PhotoGrid, { props: { images: makeImages(5) } });
		expect(wrapper.find(".more-overlay").exists()).toBe(true);
		expect(wrapper.find(".more-overlay").text()).toBe("+2");
	});

	describe("expand behavior", () => {
		it("expands to show all images when +N is clicked", async () => {
			const wrapper = mount(PhotoGrid, { props: { images: makeImages(6) } });
			expect(wrapper.find(".expanded-grid").exists()).toBe(false);

			await wrapper.find(".more-overlay").trigger("click");
			expect(wrapper.find(".expanded-grid").exists()).toBe(true);
			expect(wrapper.findAll(".expanded-grid img")).toHaveLength(6);
		});

		it("collapses back when Show less is clicked", async () => {
			const wrapper = mount(PhotoGrid, { props: { images: makeImages(6) } });
			await wrapper.find(".more-overlay").trigger("click");
			expect(wrapper.find(".expanded-grid").exists()).toBe(true);

			await wrapper.find("button.btn-outline-secondary").trigger("click");
			expect(wrapper.find(".expanded-grid").exists()).toBe(false);
			expect(wrapper.find(".more-overlay").exists()).toBe(true);
		});
	});

	describe("gallery lightbox", () => {
		afterEach(() => {
			document.body.style.overflow = "";
		});

		it("opens gallery when an image is clicked", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(3) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find(".main-img").trigger("click");
			expect(wrapper.find(".pg-gallery-overlay").exists()).toBe(true);
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("1 / 3");
		});

		it("navigates to next image", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(3) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find(".main-img").trigger("click");
			await wrapper.find(".pg-gallery-next").trigger("click");
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("2 / 3");
		});

		it("navigates to previous image", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(3) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.findAll(".multi img")[1]!.trigger("click");
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("2 / 3");

			await wrapper.find(".pg-gallery-prev").trigger("click");
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("1 / 3");
		});

		it("hides prev button on first image", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(3) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find(".main-img").trigger("click");
			expect(wrapper.find(".pg-gallery-prev").exists()).toBe(false);
			expect(wrapper.find(".pg-gallery-next").exists()).toBe(true);
		});

		it("hides next button on last image", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(2) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.findAll("img")[1]!.trigger("click");
			expect(wrapper.find(".pg-gallery-next").exists()).toBe(false);
			expect(wrapper.find(".pg-gallery-prev").exists()).toBe(true);
		});

		it("closes gallery when close button is clicked", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(2) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find("img").trigger("click");
			expect(wrapper.find(".pg-gallery-overlay").exists()).toBe(true);

			await wrapper.find(".pg-gallery-close").trigger("click");
			expect(wrapper.find(".pg-gallery-overlay").exists()).toBe(false);
		});

		it("opens gallery from expanded grid at correct index", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(6) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find(".more-overlay").trigger("click");
			await wrapper.findAll(".expanded-grid img")[4]!.trigger("click");
			expect(wrapper.find(".pg-gallery-overlay").exists()).toBe(true);
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("5 / 6");
		});

		it("handles keyboard navigation", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(3) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find(".main-img").trigger("click");
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("1 / 3");

			await wrapper.find(".pg-gallery-overlay").trigger("keydown", { key: "ArrowRight" });
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("2 / 3");

			await wrapper.find(".pg-gallery-overlay").trigger("keydown", { key: "ArrowLeft" });
			expect(wrapper.find(".pg-gallery-counter").text()).toBe("1 / 3");

			await wrapper.find(".pg-gallery-overlay").trigger("keydown", { key: "Escape" });
			expect(wrapper.find(".pg-gallery-overlay").exists()).toBe(false);
		});

		it("locks body scroll while gallery is open", async () => {
			const wrapper = mount(PhotoGrid, {
				props: { images: makeImages(2) },
				global: { stubs: { Teleport: true } },
			});
			await wrapper.find("img").trigger("click");
			expect(document.body.style.overflow).toBe("hidden");

			await wrapper.find(".pg-gallery-close").trigger("click");
			expect(document.body.style.overflow).toBe("");
		});
	});
});
```

## Implementation Order

1. Update `PhotoGrid.vue` with expanded grid + gallery lightbox
2. Delete `ClickableImage.vue` and `ClickableImage.test.ts` (dead code)
3. Update `PhotoGrid.test.ts` with new test cases
4. Run tests to verify
5. Manual QA — verify expand/collapse and gallery navigation on a memory with 4+ images

## Files Modified

| File | Action |
|------|--------|
| `fyli-fe-v2/src/components/memory/PhotoGrid.vue` | Modified — add expand + gallery |
| `fyli-fe-v2/src/components/memory/PhotoGrid.test.ts` | Modified — add new test cases |
| `fyli-fe-v2/src/components/ui/ClickableImage.vue` | Delete — dead code |
| `fyli-fe-v2/src/components/ui/ClickableImage.test.ts` | Delete — dead code |

## Review Feedback Addressed

| # | Issue | Resolution |
|---|-------|------------|
| C1 | Gallery overlay keyboard focus not auto-applied | Added `watch(galleryIndex)` + `nextTick(() => galleryEl.value?.focus())` |
| C2 | `galleryEl` template ref not defined in script | Added `const galleryEl = ref<HTMLElement \| null>(null)` |
| C3 | Scoped styles won't apply inside Teleport | Split into scoped `<style scoped>` for grid + unscoped `<style>` with `pg-` prefix for gallery |
| I1 | Indentation: tests used spaces | Changed to tabs throughout |
| I4 | Body scroll lock | Added `document.body.style.overflow` toggle in watcher + `onUnmounted` cleanup |
| I5 | Touch/swipe support | Noted as future enhancement in Design Decisions |
| I6 | Test: expanded grid + gallery interaction | Added "opens gallery from expanded grid at correct index" test |
| I7 | Test: keyboard navigation | Added "handles keyboard navigation" test (ArrowRight, ArrowLeft, Escape) |
| S1 | Image preloading | Noted as future enhancement |
| S2 | Transition animation | Noted as future enhancement |
| S3 | ClickableImage becomes dead code | Added deletion step in Phase 1.2 and Files Modified table |
| S4 | Gallery counter safe area | Added `env(safe-area-inset-bottom)` to counter positioning |
| P1 | Close button touch target | Increased from 40px to 44px (style guide minimum) |
| P2 | Overlay opacity consistency | Changed from 0.9 to 0.85 to match existing ClickableImage |
