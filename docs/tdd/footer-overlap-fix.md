# TDD: Fix Footer Overlapping Page Content

## Problem

The fixed bottom navigation bar (`AppBottomNav`) overlaps the bottom of page content across all authenticated (`layout: 'app'`) views. Users cannot scroll to reveal the obscured content — the "Send Questions" button, for example, is partially hidden behind the nav bar.

**Affected pages** (all routes with `layout: 'app'`):
- `/` (StreamView)
- `/memory/new` (CreateMemoryView)
- `/memory/:id/edit` (EditMemoryView)
- `/memory/:id` (MemoryDetailView)
- `/invite` (InviteView)
- `/account` (AccountView)
- `/questions` (UnifiedQuestionsView)
- `/questions/new` (AskQuestionsView)
- `/questions/:id/edit` (QuestionSetEditView)

## Root Cause Analysis

### Current layout structure (`AppLayout.vue`)

```
┌──────────────────────────────────┐
│ AppNav (static, in flow)         │  ~56px
├──────────────────────────────────┤
│                                  │
│ <main class="flex-grow-1">       │
│   <div class="container py-3     │
│        pb-bottom-nav">           │  padding-bottom: 5rem (80px)
│     <slot /> (page content)      │
│   </div>                         │
│ </main>                          │
│                                  │
├──────────────────────────────────┤
│ AppBottomNav (position: fixed)   │  ~60px + safe-area-inset-bottom
└──────────────────────────────────┘
```

**The problem has two parts:**

1. **`AppBottomNav` uses `position: fixed`**, which removes it from document flow entirely. It sits on top of content rather than below it.

2. **The `pb-bottom-nav` padding (5rem = 80px) is applied to the inner container, not `<main>`**. Since the container also has `py-3` (1rem = 16px top + bottom), the effective bottom padding is `5rem` (the scoped class overrides Bootstrap's `py-3` bottom). On devices with safe-area-inset-bottom (notched phones), the bottom nav grows by 20-40px, making the 80px padding insufficient.

3. **Individual views add their own `py-4` padding** inside the slot — AskQuestionsView, QuestionAnswerView, QuestionSetEditView, and UnifiedQuestionsView all wrap content in `<div class="container py-4">`. This creates a **double container** problem: the layout already provides `container py-3 pb-bottom-nav`, but these views add their own `container py-4` inside, creating nested containers with conflicting padding.

### Why scrolling doesn't help

The `min-vh-100` on the outer wrapper plus `flex-grow-1` on `<main>` means the main area fills exactly the viewport height minus the top nav. When content overflows, it should scroll — but the fixed bottom nav sits *on top* of the scrollable area's bottom edge. The padding is supposed to create clearance, but it's not enough.

## Solution

### Approach: Remove fixed positioning, use sticky + flex layout

Instead of fighting `position: fixed` with padding hacks, change `AppBottomNav` to use `position: sticky` within a flexbox layout. This keeps the nav in the document flow while ensuring it stays visible at the bottom of the viewport.

The key insight: the outer `div` is already `d-flex flex-column min-vh-100`. If we make `<main>` scrollable with `overflow-y: auto` and `flex: 1 1 0` (instead of just `flex-grow-1`), and make `AppBottomNav` a flex sibling rather than fixed, the browser handles all the spacing natively.

### Phase 1: Layout fix (AppLayout.vue + AppBottomNav.vue)

#### File: `src/layouts/AppLayout.vue`

**Before:**
```vue
<template>
  <div class="min-vh-100 bg-light d-flex flex-column">
    <AppNav />
    <main class="flex-grow-1">
      <div class="container py-3 pb-bottom-nav" style="max-width: 600px">
        <slot />
      </div>
    </main>
    <AppBottomNav />
  </div>
</template>

<style scoped>
.pb-bottom-nav {
  padding-bottom: 5rem;
}
</style>
```

**After:**
```vue
<template>
  <div class="app-shell bg-light">
    <AppNav />
    <main class="app-main">
      <div class="container py-3" style="max-width: 600px">
        <slot />
      </div>
    </main>
    <AppBottomNav />
  </div>
</template>

<style scoped>
.app-shell {
  display: flex;
  flex-direction: column;
  height: 100vh; /* fallback */
  height: 100dvh;
}

.app-main {
  flex: 1 1 0;
  min-height: 0;
  overflow-y: auto;
}
</style>
```

**Changes:**
- Keep `bg-light` on the outer div to preserve the light gray background
- Replace `min-vh-100` with `height: 100dvh` (dynamic viewport height — accounts for mobile browser chrome), with `100vh` fallback for older browsers
- Replace `flex-grow-1` with `flex: 1 1 0` + `min-height: 0` + `overflow-y: auto` on `<main>` — this makes main the scroll container. `min-height: 0` is needed so the flex child can shrink below its intrinsic content height.
- Remove `pb-bottom-nav` class entirely — no padding hack needed since the bottom nav is now in flow
- Remove the `pb-bottom-nav` style block
- Remove deprecated `-webkit-overflow-scrolling: touch` (modern Safari applies momentum scrolling by default)

#### File: `src/components/ui/AppBottomNav.vue`

**Before:**
```css
.bottom-nav {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  /* ... */
  padding: 0.5rem 0;
  padding-bottom: calc(0.5rem + env(safe-area-inset-bottom));
  z-index: 1000;
}
```

**After:**
```css
.bottom-nav {
  flex-shrink: 0;
  /* ... */
  padding: 0.5rem 0;
  padding-bottom: calc(0.5rem + env(safe-area-inset-bottom));
}
```

**Changes:**
- Remove `position: fixed`, `bottom: 0`, `left: 0`, `right: 0`
- Remove `z-index: 1000` (not needed when in flow)
- Add `flex-shrink: 0` to prevent the nav from shrinking

### Phase 2: Remove redundant containers from views

Several views create their own `<div class="container py-4">` inside the slot, which nests inside the layout's container. After the layout fix, remove these redundant wrappers.

**Files to update:**

1. **`src/views/question/AskQuestionsView.vue`** — Remove outer `<div class="container py-4" style="max-width: 620px">`, keep the `ask-page` wrapper. The `max-width: 620px` override is intentional for the wizard cards — move it to scoped CSS on `.ask-page` so the view is slightly wider than the default 600px layout container.
2. **`src/views/question/UnifiedQuestionsView.vue`** — Remove `<div class="container py-4">`
3. **`src/views/question/QuestionSetEditView.vue`** — Remove `<div class="container py-4" style="max-width: 600px">`

**Note:** `QuestionAnswerView.vue` uses `layout: 'public'` (PublicLayout), so it is NOT affected and should keep its own container.

For each view, the pattern is the same — unwrap the redundant container:

**Before (example — UnifiedQuestionsView):**
```vue
<template>
  <div class="container py-4">
    <!-- content -->
  </div>
</template>
```

**After:**
```vue
<template>
  <div>
    <!-- content -->
  </div>
</template>
```

The layout already provides `container py-3` with `max-width: 600px`.

**Test impact:** Removing the outer wrapper changes DOM structure. Check each view's `.test.ts` file for selectors that reference `.container` or depend on the wrapper hierarchy. Update any affected selectors to match the new structure.

### Phase 3: Tests

#### Existing test verification

No new tests are needed — this is a CSS/layout-only change. All existing tests must continue to pass since no DOM structure, props, emits, or business logic changes.

Run:
```bash
cd fyli-fe-v2 && npm run test:unit -- --run
```

#### Manual test checklist

- [ ] On desktop: All `layout: 'app'` pages render with content fully visible above the bottom nav
- [ ] On desktop: Bottom nav stays at the bottom of the viewport when content is short
- [ ] On desktop: Bottom nav scrolls into view naturally when content is long (it's always visible since main scrolls independently)
- [ ] On mobile (Safari iOS): Safe-area-inset-bottom creates appropriate spacing — no overlap with home indicator
- [ ] On mobile: Content scrolls smoothly within the main area with momentum scrolling (`-webkit-overflow-scrolling: touch`)
- [ ] AskQuestionsView: "Send Questions" and "Back" buttons fully visible at the bottom of step 2
- [ ] CreateMemoryView / EditMemoryView: Submit button fully visible
- [ ] AccountView: All content accessible
- [ ] StreamView: Infinite scroll still works (scroll event fires on main, not window)
- [ ] Page transitions: No layout jumps when navigating between pages

#### Scroll event concern — verified safe

No views use `window.scroll` listeners. StreamView uses `IntersectionObserver` with `root: null` (the default), which observes visibility relative to the **viewport**. When `<main>` becomes the scroll container, its visible area is constrained to the viewport between the top nav and bottom nav — as the user scrolls within `<main>`, the sentinel element enters/exits the viewport normally. No changes needed.

## Implementation Order

1. Update `AppBottomNav.vue` — remove fixed positioning
2. Update `AppLayout.vue` — new flex layout with scrollable main
3. Remove redundant containers from views (AskQuestionsView, UnifiedQuestionsView, QuestionSetEditView)
4. Run all tests
5. Manual verification on desktop and mobile

## Risk Assessment

- **Low risk**: Pure CSS/layout change, no business logic affected
- **Scroll listeners**: If any exist on `window`, they'll silently stop working since scroll now happens on `<main>`. This is the one thing to verify carefully.
- **`100dvh`**: Supported in all modern browsers (Chrome 108+, Safari 15.4+, Firefox 101+). A `100vh` fallback line is included for older browsers.
