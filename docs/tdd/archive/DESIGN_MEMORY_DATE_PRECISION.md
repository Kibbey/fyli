# Design Options: Memory Date Precision Selector

**PRD:** `docs/prd/PRD_MEMORY_DATE_PRECISION.md`
**Date:** 2026-02-21
**Status:** Draft — Awaiting Selection

---

## Context

Users need to assign one of four date precision levels when creating or editing a memory:

| Level | dateType | Display Example |
|-------|----------|-----------------|
| Specific Date | 0 | December 24, 2023 |
| Month | 1 | June 2019 |
| Year | 2 | 2015 |
| Decade | 3 | 1950s |

The current UI shows only an HTML5 `<input type="date">` and hardcodes `dateType: 0`. The goal is to let users choose their precision level with minimal friction — most memories will still use "Specific Date," but older or approximate memories need easy access to Month, Year, and Decade.

Below are three UI approaches. Each includes the precision selector **and** the adaptive date input that changes based on the selected level.

---

## Option A: Segmented Button Group + Adaptive Inputs

A horizontal row of toggle buttons (similar to the old frontend) sits above the date input. The active button is styled with the primary color. The date input area below adapts to show only the relevant fields.

### Visual Representation

**Default state (Specific Date selected):**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │ Exact    │  Month   │   Year   │  Decade  │      │
│  │ ████████ │          │          │          │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
│                                                     │
│  ┌─────────────────────────────────────────┐        │
│  │  📅  02/21/2026                         │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

- `Exact` button has `bg-primary` (brand green), others are `btn-outline-secondary`
- Standard HTML5 date input below

**Month selected:**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │  Exact   │  Month   │   Year   │  Decade  │      │
│  │          │ ████████ │          │          │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
│                                                     │
│  ┌──────────────────┐  ┌────────────────────┐       │
│  │  February      ▼ │  │  2026            ▼ │       │
│  └──────────────────┘  └────────────────────┘       │
└─────────────────────────────────────────────────────┘
```

- Two side-by-side dropdowns: month name + year

**Year selected:**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │  Exact   │  Month   │   Year   │  Decade  │      │
│  │          │          │ ████████ │          │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
│                                                     │
│  ┌─────────────────────────────────────────┐        │
│  │  2026                                 ▼ │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

- Single year dropdown

**Decade selected:**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌──────────┬──────────┬──────────┬──────────┐      │
│  │  Exact   │  Month   │   Year   │  Decade  │      │
│  │          │          │          │ ████████ │      │
│  └──────────┴──────────┴──────────┴──────────┘      │
│                                                     │
│  ┌─────────────────────────────────────────┐        │
│  │  2020s                                ▼ │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

- Single decade dropdown (1870s, 1880s, ... 2020s)

### Implementation Notes

```html
<!-- Bootstrap btn-group for segmented control -->
<div class="btn-group w-100" role="group" aria-label="Date precision">
  <button class="btn" :class="dateType === 0 ? 'btn-primary' : 'btn-outline-secondary'">
    Exact
  </button>
  <button class="btn" :class="dateType === 1 ? 'btn-primary' : 'btn-outline-secondary'">
    Month
  </button>
  <!-- ... -->
</div>

<!-- Adaptive input area below -->
<input v-if="dateType === 0" type="date" class="form-control" />
<div v-else-if="dateType === 1" class="d-flex gap-2">
  <select class="form-select"><!-- months --></select>
  <select class="form-select"><!-- years --></select>
</div>
<!-- ... -->
```

### Pros

- **Discoverable** — all 4 options visible at once; users immediately see that non-exact dates are possible
- **Familiar pattern** — segmented button groups are a well-known UI convention (iOS, Material Design, Bootstrap)
- **Quick switching** — one tap to change precision, no extra clicks
- **Proven** — mirrors the old frontend's approach (button group), validated with existing users
- **Accessible** — Bootstrap `btn-group` has built-in `role="group"` and keyboard navigation

### Cons

- **Visual weight** — 4 buttons + date input takes up more vertical space than the current single input
- **Potential overwhelm** — some users may not understand what "dateType" means without guidance
- **Always visible** — adds visual complexity even when 90%+ of memories will use "Exact"
- **Mobile width** — 4 buttons can feel cramped on narrow screens (< 360px); labels may need to truncate

---

## Option B: Inline Dropdown Selector + Adaptive Inputs

A single `<select>` dropdown sits inline with (or just above) the date input. It defaults to "Exact date" and the user can switch to a different precision by opening the dropdown. The date input area adapts based on the selection.

### Visual Representation

**Default state (Exact date selected):**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌────────────────────┐                             │
│  │  Exact date      ▼ │                             │
│  └────────────────────┘                             │
│  ┌─────────────────────────────────────────┐        │
│  │  📅  02/21/2026                         │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

- Small `form-select` dropdown above the date input
- Default selection: "Exact date"

**Dropdown open:**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌────────────────────┐                             │
│  │  Exact date      ▼ │                             │
│  ├────────────────────┤                             │
│  │  Exact date     ✓  │                             │
│  │  Month & year      │                             │
│  │  Year only         │                             │
│  │  Decade            │                             │
│  └────────────────────┘                             │
│  ┌─────────────────────────────────────────┐        │
│  │  📅  02/21/2026                         │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

**After selecting "Year only":**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌────────────────────┐                             │
│  │  Year only       ▼ │                             │
│  └────────────────────┘                             │
│  ┌─────────────────────────────────────────┐        │
│  │  2026                                 ▼ │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

**After selecting "Decade":**

```
┌─────────────────────────────────────────────────────┐
│  When did this happen?                              │
│                                                     │
│  ┌────────────────────┐                             │
│  │  Decade          ▼ │                             │
│  └────────────────────┘                             │
│  ┌─────────────────────────────────────────┐        │
│  │  2020s                                ▼ │        │
│  └─────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────┘
```

### Implementation Notes

```html
<label class="form-label">When did this happen?</label>

<select v-model="dateType" class="form-select form-select-sm mb-2" style="width: auto;">
  <option :value="0">Exact date</option>
  <option :value="1">Month & year</option>
  <option :value="2">Year only</option>
  <option :value="3">Decade</option>
</select>

<!-- Adaptive input below -->
<input v-if="dateType === 0" type="date" class="form-control" />
<!-- ... same adaptive inputs as Option A -->
```

### Pros

- **Compact** — takes very little extra space; just a small select above the date input
- **Low friction** — default case ("Exact date") looks nearly identical to current UI; casual users won't notice the change
- **Scalable** — easy to add future precision types (e.g., "Season") without layout changes
- **Native mobile UX** — `<select>` elements render as native pickers on iOS/Android, which users already know
- **Self-documenting** — dropdown labels like "Month & year" and "Year only" explain themselves

### Cons

- **Less discoverable** — users may not notice the dropdown or realize they can change precision unless they're looking for it
- **Extra tap** — requires opening the dropdown + selecting, whereas Option A is a single tap
- **No visual indication of current mode** — the dropdown label is small text; doesn't draw attention to the selected precision
- **Dropdown appearance varies by platform** — native `<select>` rendering differs across browsers and OS

---

## Option C: Progressive Disclosure (Collapsed by Default)

The default view shows only the standard date input (identical to current UI). A subtle text link below the date input reads "Approximate date?" — clicking it reveals the precision selector. This minimizes friction for the common case while making the feature accessible.

### Visual Representation

**Default state (collapsed — exact date):**

```
┌─────────────────────────────────────────────────────┐
│  Date                                               │
│  ┌─────────────────────────────────────────┐        │
│  │  📅  02/21/2026                         │        │
│  └─────────────────────────────────────────┘        │
│  🔗 Approximate date?                               │
└─────────────────────────────────────────────────────┘
```

- Current UI is unchanged
- Small text link below: "Approximate date?" in `text-muted` style

**After clicking "Approximate date?" (expanded):**

```
┌─────────────────────────────────────────────────────┐
│  Date                                               │
│                                                     │
│  How precise is this date?                          │
│  ┌──────────────────────────────────────────────┐   │
│  │  ○  Exact date       December 24, 2023       │   │
│  │  ○  Month & year     June 2019               │   │
│  │  ○  Year only        2015                    │   │
│  │  ○  Decade           1950s                   │   │
│  └──────────────────────────────────────────────┘   │
│                                                     │
│  ┌─────────────────────────────────────────┐        │
│  │  2026                                 ▼ │        │
│  └─────────────────────────────────────────┘        │
│  🔗 Use exact date                                  │
└─────────────────────────────────────────────────────┘
```

- Radio button list with precision options
- Each option shows a small example for clarity
- Date input below adapts to the selected precision
- Link text changes to "Use exact date" to collapse back

**On MemoryCard (after saving with Year precision):**

```
┌─────────────────────────────────────────────────────┐
│  Jane Smith          2015                           │
│                                                     │
│  We took the kids to Yellowstone that summer...     │
└─────────────────────────────────────────────────────┘
```

**On MemoryCard (Decade precision):**

```
┌─────────────────────────────────────────────────────┐
│  Grandma Rose        1950s                          │
│                                                     │
│  Back when we lived on the farm, your grandpa...    │
└─────────────────────────────────────────────────────┘
```

### Implementation Notes

```html
<div class="mb-3">
  <label class="form-label">Date</label>

  <!-- Collapsed: just the date input + toggle link -->
  <template v-if="!showPrecision && dateType === 0">
    <input v-model="date" type="date" class="form-control" />
    <button type="button" class="btn btn-link btn-sm text-muted p-0 mt-1"
            @click="showPrecision = true">
      Approximate date?
    </button>
  </template>

  <!-- Expanded: radio options + adaptive input -->
  <template v-else>
    <p class="text-muted small mb-2">How precise is this date?</p>
    <div class="list-group mb-2">
      <label class="list-group-item d-flex align-items-center gap-2">
        <input type="radio" v-model="dateType" :value="0" class="form-check-input" />
        <span>Exact date</span>
        <small class="text-muted ms-auto">December 24, 2023</small>
      </label>
      <label class="list-group-item d-flex align-items-center gap-2">
        <input type="radio" v-model="dateType" :value="1" class="form-check-input" />
        <span>Month & year</span>
        <small class="text-muted ms-auto">June 2019</small>
      </label>
      <!-- ... -->
    </div>

    <!-- Adaptive date input -->
    <input v-if="dateType === 0" type="date" class="form-control" />
    <!-- ... same adaptive inputs -->

    <button type="button" class="btn btn-link btn-sm text-muted p-0 mt-1"
            @click="showPrecision = false; dateType = 0">
      Use exact date
    </button>
  </template>
</div>
```

### Pros

- **Zero friction for default case** — 90%+ of memories use exact date; those users see zero UI changes
- **Self-explanatory** — "Approximate date?" immediately communicates what the feature is for in plain language
- **Examples built in** — each radio option shows a sample display format, so users know exactly what they'll get
- **Clean form layout** — doesn't add visual weight to the create/edit form for users who don't need it
- **Answers PRD Open Question #1** — explicitly designed for progressive disclosure

### Cons

- **Lower discoverability** — users who don't read the link text won't know the feature exists
- **Two-step interaction** — requires clicking "Approximate date?" first, then selecting the precision
- **More vertical space when expanded** — radio list with examples is taller than Option A's button group
- **Collapse/expand state management** — slightly more complex logic to handle: (a) collapsed default, (b) auto-expand when editing a memory that already has non-exact dateType, (c) collapse when switching back to exact

---

## Comparison Matrix

| Criteria | A: Button Group | B: Dropdown | C: Progressive Disclosure |
|----------|:-:|:-:|:-:|
| **Discoverability** | High | Medium | Low (until clicked) |
| **Default-case friction** | Medium (extra buttons visible) | Low (small select) | None (unchanged UI) |
| **Tap count to change precision** | 1 | 2 (open + select) | 2 (expand + select) |
| **Vertical space used** | Medium | Low | Low (collapsed) / High (expanded) |
| **Mobile friendliness** | Medium (4 buttons cramped) | High (native select) | High |
| **Self-documenting** | Low (labels only) | Medium (descriptive labels) | High (labels + examples) |
| **Implementation complexity** | Low | Low | Medium |
| **Consistency with app patterns** | High (matches storyline toggle) | Medium | Medium (matches "Add to storyline" pattern) |
| **Scalability (adding types)** | Low (buttons grow) | High | High |

---

## Recommendation

**Option C (Progressive Disclosure)** best aligns with the PRD's core principle of *"should not add friction to the default flow"* and the product's philosophy of *"reduce cognitive load."* Most memories are from recent events with known dates — those users see no change. Users capturing older or approximate memories will find the "Approximate date?" link naturally when they encounter the date field and think "I don't know the exact date."

However, **Option A (Button Group)** is the strongest choice if discoverability is the priority — if we want to actively encourage users to think about date precision for every memory.

**Option B (Dropdown)** is a solid middle ground if neither extreme is desired.

---

*Document Version: 1.0*
*Created: 2026-02-21*
