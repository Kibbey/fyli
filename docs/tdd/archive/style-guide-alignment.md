# TDD: Align Frontend with Style Guide

## Problem

The frontend (`fyli-fe-v2`) imports pre-compiled Bootstrap CSS and has no brand color customization. Bootstrap's default blue (`#0d6efd`) renders as the primary color. The style guide specifies `#56c596` as the brand primary. Additionally, 6 files contain hardcoded hex color values in inline styles.

## Approach

Use CSS custom property overrides in `main.css` to rebrand Bootstrap components. This avoids adding a Sass build dependency while achieving the same visual result for the elements the project actually uses.

Also define `--fyli-*` custom properties so components can reference brand tokens.

No database changes. No backend changes. Frontend-only.

---

## Phase 1: Bootstrap Override & Custom Properties in `main.css`

### File: `fyli-fe-v2/src/assets/main.css`

Replace contents with:

```css
/* Fyli custom properties */
:root {
  --fyli-primary: #56c596;
  --fyli-primary-hover: #45a67e;
  --fyli-primary-light: #e8f7f0;
  --fyli-primary-dark: #3b8a69;
  --fyli-text-muted: #6c757d;
  --bs-link-color-rgb: 86, 197, 150;
  --bs-link-hover-color-rgb: 69, 166, 126;
}

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
}

img, video {
  max-width: 100%;
}

.card-body {
  overflow: hidden;
}

/* Override Bootstrap primary color */
.btn-primary {
  --bs-btn-bg: var(--fyli-primary);
  --bs-btn-border-color: var(--fyli-primary);
  --bs-btn-hover-bg: var(--fyli-primary-hover);
  --bs-btn-hover-border-color: var(--fyli-primary-hover);
  --bs-btn-active-bg: var(--fyli-primary-dark);
  --bs-btn-active-border-color: var(--fyli-primary-dark);
  --bs-btn-disabled-bg: var(--fyli-primary);
  --bs-btn-disabled-border-color: var(--fyli-primary);
  --bs-btn-focus-shadow-rgb: 86, 197, 150;
}

.btn-outline-primary {
  --bs-btn-color: var(--fyli-primary);
  --bs-btn-border-color: var(--fyli-primary);
  --bs-btn-hover-bg: var(--fyli-primary);
  --bs-btn-hover-border-color: var(--fyli-primary);
  --bs-btn-active-bg: var(--fyli-primary-hover);
  --bs-btn-active-border-color: var(--fyli-primary-hover);
  --bs-btn-focus-shadow-rgb: 86, 197, 150;
}

.text-primary {
  color: var(--fyli-primary) !important;
}

.bg-primary {
  background-color: var(--fyli-primary) !important;
}

.form-control:focus {
  border-color: var(--fyli-primary);
  box-shadow: 0 0 0 0.25rem rgba(86, 197, 150, 0.25);
}

.form-check-input:checked {
  background-color: var(--fyli-primary);
  border-color: var(--fyli-primary);
}
```

**Rationale:** Bootstrap 5 exposes CSS custom properties on its component classes (e.g. `--bs-btn-bg`). Overriding these in `main.css` (loaded after `bootstrap.min.css`) rebrands all primary buttons, links, and form focus states without Sass.

---

## Phase 2: Fix Hardcoded Hex Colors

### 1. `src/views/onboarding/WelcomeView.vue`

**Line 9 — change:**
```html
<!-- Before -->
<span class="mdi mdi-hand-wave-outline" style="font-size: 4rem; color: #0d6efd"></span>
<!-- After -->
<span class="mdi mdi-hand-wave-outline" style="font-size: 4rem; color: var(--fyli-primary)"></span>
```

### 2. `src/views/auth/LoginView.vue`

**Line 31 — change:**
```html
<!-- Before -->
<span class="mdi mdi-email-check-outline" style="font-size: 3rem; color: #198754"></span>
<!-- After -->
<span class="mdi mdi-email-check-outline" style="font-size: 3rem; color: var(--fyli-primary)"></span>
```

### 3. `src/views/auth/RegisterView.vue`

**Line 33 — change:**
```html
<!-- Before -->
<span class="mdi mdi-email-check-outline" style="font-size: 3rem; color: #198754"></span>
<!-- After -->
<span class="mdi mdi-email-check-outline" style="font-size: 3rem; color: var(--fyli-primary)"></span>
```

### 4. `src/views/connections/InviteView.vue`

**Line 36 — change:**
```html
<!-- Before -->
<span class="mdi mdi-check-circle-outline" style="font-size: 3rem; color: #198754"></span>
<!-- After -->
<span class="mdi mdi-check-circle-outline" style="font-size: 3rem; color: var(--fyli-primary)"></span>
```

### 5. `src/components/ui/ErrorState.vue`

**Line 13 — change:**
```html
<!-- Before -->
<span class="mdi mdi-alert-circle-outline" style="font-size: 3rem; color: #dc3545"></span>
<!-- After -->
<span class="mdi mdi-alert-circle-outline text-danger" style="font-size: 3rem;"></span>
```

Use Bootstrap's `text-danger` class instead of hardcoded hex. Since this is a semantic error icon, `text-danger` is correct (it stays Bootstrap's red, not the brand green).

### 6. `src/components/ui/EmptyState.vue`

**Line 15 — change:**
```html
<!-- Before -->
<span v-if="icon" class="mdi" :class="icon" style="font-size: 3rem; color: #999"></span>
<!-- After -->
<span v-if="icon" class="mdi text-muted" :class="icon" style="font-size: 3rem;"></span>
```

Use Bootstrap's `text-muted` class (`#6c757d`).

---

## Phase 3: Update Style Guide Documentation

### File: `docs/FRONTEND_STYLE_GUIDE.md`

Update the "Framework" section to accurately describe the CSS override approach (not Sass):

Replace:
> Bootstrap is customized via its Sass variable system. The primary color and other tokens below are applied by overriding Bootstrap variables **before** importing Bootstrap, so all Bootstrap utilities (`btn-primary`, `text-primary`, `alert-success`, etc.) automatically use the Fyli palette.

With:
> Bootstrap's pre-compiled CSS is loaded first, then `src/assets/main.css` overrides Bootstrap's CSS custom properties (e.g. `--bs-btn-bg`) to apply the Fyli brand color. This avoids a Sass build dependency while rebranding all primary buttons, links, and form focus states.

---

## Implementation Order

1. Update `src/assets/main.css` with custom properties and Bootstrap overrides
2. Fix hardcoded colors in the 6 component files
3. Update `docs/FRONTEND_STYLE_GUIDE.md` framework description
4. Visually verify in browser that `btn-primary` renders as `#56c596`, form focus rings are green, links are green
5. Verify login, register, welcome, invite, error, and empty state pages render correctly
