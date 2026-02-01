# Fyli Frontend Style Guide

The source of truth for all visual design decisions in the Fyli frontend (`fyli-fe-v2`).

## Framework

- **CSS Framework:** Bootstrap 5 (loaded via `bootstrap/dist/css/bootstrap.min.css`)
- **Icons:** Material Design Icons (`@mdi/font`)
- **Custom overrides:** `src/assets/main.css` — CSS custom properties + Bootstrap component overrides

Bootstrap's pre-compiled CSS is loaded first, then `src/assets/main.css` overrides Bootstrap's CSS custom properties (e.g. `--bs-btn-bg`, `--bs-link-color-rgb`) to apply the Fyli brand color. This avoids a Sass build dependency while rebranding all primary buttons, links, and form focus states.

---

## Color Palette

### Brand / Primary — `#56c596`

This is the core brand color (logo, primary buttons, links, active states).

| Token | Hex | Usage |
|---|---|---|
| `--fyli-primary` | `#56c596` | Primary actions, links, logo |
| `--fyli-primary-hover` | `#45a67e` | Hover/active states on primary |
| `--fyli-primary-light` | `#e8f7f0` | Tinted backgrounds, highlights |
| `--fyli-primary-dark` | `#3b8a69` | High-emphasis text on light bg |

Applied via CSS custom property overrides in `main.css` (not Sass).

### Secondary — `#6c757d`

Bootstrap's default gray. Used for secondary buttons and de-emphasized actions.

| Token | Hex | Usage |
|---|---|---|
| `--fyli-secondary` | `#6c757d` | Secondary buttons, muted UI |

### Semantic Colors

| Role | Hex | Bootstrap var |
|---|---|---|
| Success | `#198754` | `$success` (Bootstrap default) |
| Danger | `#dc3545` | `$danger` |
| Warning | `#ffc107` | `$warning` |
| Info | `#0dcaf0` | `$info` |

These remain Bootstrap defaults so standard classes (`alert-danger`, `btn-success`, etc.) behave as expected.

### Neutrals

| Token | Hex | Usage |
|---|---|---|
| `--fyli-text` | `#212529` | Body text (Bootstrap default) |
| `--fyli-text-muted` | `#6c757d` | Secondary text, timestamps |
| `--fyli-bg` | `#ffffff` | Page background |
| `--fyli-bg-light` | `#f8f9fa` | Section backgrounds, cards |
| `--fyli-border` | `#dee2e6` | Borders, dividers |

---

## Typography

Use Bootstrap's default type scale. No custom font is loaded; the system font stack applies:

```css
font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
```

| Element | Size | Weight |
|---|---|---|
| Page title (`h1`) | 2rem | 600 |
| Section header (`h2`) | 1.5rem | 600 |
| Card header (`h5`) | 1.25rem | 500 |
| Body text | 1rem | 400 |
| Small / captions | 0.875rem | 400 |
| Badges / labels | 0.75rem | 600 |

---

## Spacing

Use Bootstrap spacing utilities (`m-*`, `p-*`, `gap-*`) with the default 0.25rem base:

| Class suffix | Value |
|---|---|
| `1` | 0.25rem (4px) |
| `2` | 0.5rem (8px) |
| `3` | 1rem (16px) |
| `4` | 1.5rem (24px) |
| `5` | 3rem (48px) |

---

## Border Radius

| Usage | Value |
|---|---|
| Buttons, inputs | Bootstrap default (0.375rem) |
| Cards | Bootstrap default (0.5rem) |
| Badges, pills | `rounded-pill` |
| Avatars | `rounded-circle` |

---

## Shadows

Use Bootstrap shadow utilities:
- `shadow-sm` — subtle card lift
- `shadow` — standard card
- `shadow-lg` — modals, dropdowns

---

## Component Patterns

### Buttons

Use Bootstrap button classes. The primary brand color flows through automatically:

```html
<!-- Primary action -->
<button class="btn btn-primary">Save</button>

<!-- Secondary / cancel -->
<button class="btn btn-outline-secondary">Cancel</button>

<!-- Danger -->
<button class="btn btn-outline-danger">Delete</button>
```

Button states (hover, active, disabled, loading spinner) are handled by Bootstrap. For loading, disable the button and add a spinner:

```html
<button class="btn btn-primary" :disabled="loading">
  <span v-if="loading" class="spinner-border spinner-border-sm me-1"></span>
  {{ loading ? 'Saving...' : 'Save' }}
</button>
```

### Cards

```html
<div class="card mb-3">
  <div class="card-body">
    <!-- content -->
  </div>
</div>
```

### Forms

Labels above inputs. Use Bootstrap form classes:

```html
<div class="mb-3">
  <label class="form-label">Email</label>
  <input type="email" class="form-control" />
</div>
```

### Alerts

```html
<div class="alert alert-success">Saved.</div>
<div class="alert alert-danger">Something went wrong.</div>
```

### Empty States

Centered, muted text with an icon and a CTA:

```html
<div class="text-center py-5 text-muted">
  <span class="mdi mdi-folder-open" style="font-size: 3rem;"></span>
  <p class="mt-2">No memories yet.</p>
  <button class="btn btn-primary">Create one</button>
</div>
```

---

## Icons

Use Material Design Icons via class names:

```html
<span class="mdi mdi-pencil"></span>
```

For colored icons use the brand primary or semantic colors:

```html
<span class="mdi mdi-check-circle" style="color: var(--fyli-primary);"></span>
```

Avoid hardcoding hex values for icon colors — use CSS custom properties or Bootstrap text utilities (`text-primary`, `text-danger`, etc.).

---

## Responsive Breakpoints

Bootstrap 5 defaults:

| Name | Min-width |
|---|---|
| `sm` | 576px |
| `md` | 768px |
| `lg` | 992px |
| `xl` | 1200px |
| `xxl` | 1400px |

Mobile-first approach. Stack layouts vertically on small screens, use `col-md-*` grid for wider viewports.

---

## Accessibility

- Minimum 4.5:1 contrast ratio for normal text, 3:1 for large text
- All interactive elements must have visible `:focus-visible` outlines
- Touch targets minimum 44x44px
- Use semantic HTML (`<button>`, `<nav>`, `<main>`, `<h1>`-`<h6>`)
- `aria-label` on icon-only buttons

---

## Rules

1. **No hardcoded color hex values in components.** Use Bootstrap classes or `var(--fyli-*)` custom properties.
2. **Bootstrap first.** Prefer Bootstrap utility classes over custom CSS.
3. **Scoped styles only.** Component-specific CSS uses `<style scoped>`.
4. **`main.css` is the only global stylesheet** (besides Bootstrap/MDI imports).
5. **`#56c596` is the brand color.** All primary UI elements (buttons, links, active states, logo) use this color via Bootstrap's `$primary` override.
