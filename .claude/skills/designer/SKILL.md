---
name: designer
description: Design and improve UI/UX for the application. Use when asked to design interfaces, improve visual design, fix styling issues, ensure consistency, or enhance user experience. Applies design best practices for colors, typography, spacing, and interactions.
allowed-tools: Read, Grep, Glob, Edit, Write
---

# Designer Skill

Create and maintain exceptional UI/UX for the personal_assistant (Cimplur) project, ensuring visual consistency, accessibility, and delightful user experiences.

## Design System Reference

**The full style guide lives at `docs/FRONTEND_STYLE_GUIDE.md`.** Always read that file before making design decisions. Key highlights below for quick reference.

### Brand Primary Color: `#56c596`

All primary UI elements (buttons, links, active states, logo) use this color. It is applied via Bootstrap's `$primary` Sass variable override.

| Token | Hex | Usage |
|---|---|---|
| `--fyli-primary` | `#56c596` | Primary actions, links, logo |
| `--fyli-primary-hover` | `#45a67e` | Hover/active states |
| `--fyli-primary-light` | `#e8f7f0` | Tinted backgrounds |
| `--fyli-primary-dark` | `#3b8a69` | High-emphasis text |

### Semantic Colors (Bootstrap defaults)

| Role | Hex |
|---|---|
| Success | `#198754` |
| Danger | `#dc3545` |
| Warning | `#ffc107` |
| Info | `#0dcaf0` |

### Rules

1. **No hardcoded hex colors in components** — use Bootstrap classes or `var(--fyli-*)`.
2. **Bootstrap first** — prefer utility classes over custom CSS.
3. **Scoped styles only** in components.
4. **`main.css` is the only global stylesheet** besides framework imports.
5. Always consult `docs/FRONTEND_STYLE_GUIDE.md` for the full palette, typography, spacing, component patterns, and accessibility requirements.

## UX Best Practices

### Visual Hierarchy

1. **Size** - Larger elements draw more attention
2. **Color** - Use primary color for key actions, muted for secondary
3. **Contrast** - High contrast for important elements
4. **Spacing** - Group related items, separate distinct sections
5. **Position** - Top-left reads first (F-pattern)

### Call-to-Action (CTA) Design

**Primary CTA:** Use `btn btn-primary` (renders in `#56c596`).

**Secondary CTA:** Use `btn btn-outline-secondary`.

**Destructive CTA:** Use `btn btn-outline-danger`.

### Button States

Always implement these states:
- **Default** - Base appearance
- **Hover** - Slight lift, shadow, or color change
- **Active/Pressed** - Pressed appearance
- **Disabled** - Reduced opacity (0.5-0.6), cursor: not-allowed
- **Loading** - Spinner, disabled interaction

### Form Design

1. **Labels** - Always visible, positioned above inputs
2. **Placeholders** - Hint text, not replacement for labels
3. **Validation** - Real-time feedback, clear error messages
4. **Focus states** - Visible focus ring for accessibility
5. **Input sizing** - Adequate touch targets (min 44x44px on mobile)

Use Bootstrap `form-control` class. Focus ring color inherits from `$primary` (`#56c596`).

### Card Design

```css
.card {
    background: var(--bg-primary);
    border-radius: var(--radius-xl);
    box-shadow: var(--shadow-md);
    padding: var(--spacing-xl);
}

.card:hover {
    transform: translateY(-2px);
    box-shadow: var(--shadow-lg);
}
```

### Alert/Notification Patterns

**Success:**
```css
background: #d1fae5;
border: 1px solid #6ee7b7;
color: #065f46;
```

**Error:**
```css
background: #fef2f2;
border: 1px solid #fecaca;
color: #ef4444;
```

**Warning:**
```css
background: #fef3c7;
border: 1px solid #f59e0b;
color: #92400e;
```

**Info:**
```css
background: #dbeafe;
border: 1px solid #93c5fd;
color: #1e40af;
```

### Status Badges

```css
.badge {
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-full);
    font-size: var(--font-size-xs);
    font-weight: 600;
}

.badge-success { background: #d1fae5; color: #065f46; }
.badge-error { background: #fef2f2; color: #ef4444; }
.badge-warning { background: #fef3c7; color: #92400e; }
.badge-info { background: #dbeafe; color: #1e40af; }
```

## Interaction Patterns

### Hover Effects

```css
/* Subtle lift */
transform: translateY(-2px);
box-shadow: var(--shadow-lg);

/* Color transition */
transition: background-color var(--transition-fast);
```

### Click/Active Feedback

```css
transform: translateY(0);
/* or */
transform: scale(0.98);
```

### Loading States

Always provide visual feedback:
- Spinner for buttons
- Skeleton screens for content
- Progress indicators for long operations

```css
.spinner {
    width: 16px;
    height: 16px;
    border: 2px solid rgba(255, 255, 255, 0.3);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}
```

### Empty States

Always design empty states:
- Helpful message explaining what goes here
- Clear call-to-action to add content
- Optional illustration or icon

## Accessibility Guidelines

### Color Contrast
- Normal text: minimum 4.5:1 contrast ratio
- Large text (18px+): minimum 3:1 contrast ratio
- Never rely on color alone to convey information

### Focus Indicators
```css
:focus-visible {
    outline: 2px solid var(--primary-color);
    outline-offset: 2px;
}
```

### Touch Targets
- Minimum 44x44px for touch targets
- Adequate spacing between clickable elements

### Screen Reader Support
- Use semantic HTML elements
- Add aria-labels where needed
- Hide decorative elements with aria-hidden

## Responsive Design

### Breakpoints
```css
/* Mobile first approach */
@media (min-width: 640px) { /* sm */ }
@media (min-width: 768px) { /* md */ }
@media (min-width: 1024px) { /* lg */ }
@media (min-width: 1280px) { /* xl */ }
```

### Mobile Considerations
- Stack layouts vertically
- Full-width buttons
- Larger touch targets
- Simplified navigation (hamburger menu)
- Consider thumb zones

## Consistency Checklist

Before implementing any design:

- [ ] Using design system colors (no hardcoded values)
- [ ] Using design system spacing tokens
- [ ] Using design system typography scale
- [ ] Using design system border radius
- [ ] Consistent button styles across the app
- [ ] Consistent form input styles
- [ ] Consistent card/container styles
- [ ] Consistent hover/active states
- [ ] Consistent loading states
- [ ] Consistent empty states
- [ ] Mobile responsive

## Common Patterns in This Project

### Page Layout
```vue
<div class="page">
    <AppHeader />
    <main class="main">
        <div class="container">
            <div class="page-header">
                <h1 class="page-title">Title</h1>
                <p class="page-subtitle">Description</p>
            </div>
            <!-- Content -->
        </div>
    </main>
    <AppFooter />
</div>
```

### Content Cards
```vue
<div class="content-card">
    <div class="card-header">
        <h2>Section Title</h2>
    </div>
    <div class="card-body">
        <!-- Content -->
    </div>
</div>
```

### Goal/Task Cards
Use `btn-primary` or a card with `background: var(--fyli-primary); color: white;` for emphasis cards.

## Review Output Format

When reviewing or creating designs, provide:

### Design Decisions
Explain the reasoning behind visual choices

### Consistency Issues
Identify any deviations from the design system

### Accessibility Concerns
Flag any accessibility issues

### Recommended Changes
Specific CSS/component changes with code examples

### Visual Hierarchy Assessment
Evaluate if the most important elements stand out appropriately
