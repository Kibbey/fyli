# Technical Design Document: Memory Date Precision

**PRD:** `docs/prd/PRD_MEMORY_DATE_PRECISION.md`
**Design:** `docs/tdd/DESIGN_MEMORY_DATE_PRECISION.md` — Option B (Inline Dropdown)
**Date:** 2026-02-21
**Status:** Draft

---

## Overview

Implement flexible date precision for memories in fyli-fe-v2. Users can select one of four precision levels (Exact, Month, Year, Decade) when creating or editing a memory, and all display surfaces render dates accordingly. The backend already supports all four `DateTypes` values — this is a frontend-only change.

### UI Approach: Inline Dropdown (Option B)

A small `<select>` dropdown sits above the date input, defaulting to "Exact date." When the user changes the selection, the date input adapts to show only the relevant fields. This approach is compact, low-friction for the default case, and uses native mobile pickers.

---

## Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Shared Utility                           │
│  src/utils/dateFormat.ts                                    │
│  - formatMemoryDate(date, dateType) → string                │
│  - DATE_TYPE_OPTIONS (label map)                            │
│  - generateYearOptions() / generateDecadeOptions()          │
└──────────────────────────┬──────────────────────────────────┘
                           │ imported by
        ┌──────────────────┼──────────────────────┐
        │                  │                      │
        ▼                  ▼                      ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐
│ DatePrecision │  │ MemoryCard    │  │ SharedMemoryView      │
│ Selector.vue  │  │ .vue          │  │ StorylineInviteView   │
│ (new)         │  │ (update)      │  │ AddExistingMemoryModal│
│               │  │               │  │ MemoryDetailView      │
│ Used in:      │  │ Uses:         │  │ (all update)          │
│ - Create      │  │ formatMemory  │  │                       │
│ - Edit        │  │ Date()        │  │ Uses: formatMemory    │
│ - AnswerForm  │  │               │  │ Date()                │
└───────────────┘  └───────────────┘  └───────────────────────┘
```

---

## File Structure

```
fyli-fe-v2/src/
├── utils/
│   ├── dateFormat.ts              ← NEW: shared formatting + helpers
│   └── dateFormat.test.ts         ← NEW: unit tests
├── components/
│   └── memory/
│       ├── DatePrecisionSelector.vue  ← NEW: reusable selector component
│       └── MemoryCard.vue             ← UPDATE: use formatMemoryDate
├── views/
│   ├── memory/
│   │   ├── CreateMemoryView.vue       ← UPDATE: integrate selector
│   │   ├── EditMemoryView.vue         ← UPDATE: integrate selector
│   │   └── MemoryDetailView.vue       ← UPDATE: use formatMemoryDate
│   ├── share/
│   │   └── SharedMemoryView.vue       ← UPDATE: use formatMemoryDate
│   └── storyline/
│       └── StorylineInviteView.vue    ← UPDATE: use formatMemoryDate
├── components/
│   ├── storyline/
│   │   └── AddExistingMemoryModal.vue ← UPDATE: use formatMemoryDate
│   └── question/
│       ├── QuestionAnswerCard.vue     ← UPDATE: use formatMemoryDate
│       ├── AnswerPreview.vue          ← UPDATE: use formatMemoryDate
│       └── AnswerForm.vue             ← UPDATE: integrate selector
```

---

## Phase 1: Shared Date Formatting Utility

### 1.1 `src/utils/dateFormat.ts`

Pure utility functions — no Vue dependencies, fully unit-testable.

```typescript
import type { DateType } from "@/types";

/**
 * Labels for the date type dropdown.
 */
export const DATE_TYPE_OPTIONS: { value: DateType; label: string }[] = [
  { value: 0, label: "Exact date" },
  { value: 1, label: "Month & year" },
  { value: 2, label: "Year only" },
  { value: 3, label: "Decade" },
];

/**
 * Parse a date string as local time to avoid timezone shifts.
 * Backend returns dates without timezone offset (e.g. "2023-12-24T00:00:00").
 */
function parseLocalDate(date: string | Date): Date {
  if (date instanceof Date) return date;
  // Split on "T" first, then parse YYYY-MM-DD as local
  const dateStr = date.split("T")[0];
  const parts = dateStr.split("-");
  if (parts.length >= 3) {
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }
  return new Date(date);
}

/**
 * Format a date string according to its precision type.
 */
export function formatMemoryDate(date: string | Date, dateType: number): string {
  const d = parseLocalDate(date);
  switch (dateType) {
    case 1:
      return d.toLocaleDateString("en-US", { month: "long", year: "numeric" });
    case 2:
      return d.getFullYear().toString();
    case 3:
      return `${Math.floor(d.getFullYear() / 10) * 10}s`;
    default:
      return d.toLocaleDateString("en-US", {
        month: "long",
        day: "numeric",
        year: "numeric",
      });
  }
}

/**
 * Month options for the month dropdown.
 */
export const MONTH_OPTIONS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

/**
 * Generate year options from 1870 to the current year.
 */
export function generateYearOptions(): number[] {
  const currentYear = new Date().getFullYear();
  const years: number[] = [];
  for (let y = currentYear; y >= 1870; y--) {
    years.push(y);
  }
  return years;
}

/**
 * Generate decade options from 1870s to current decade.
 */
export function generateDecadeOptions(): string[] {
  const currentDecade = Math.floor(new Date().getFullYear() / 10) * 10;
  const decades: string[] = [];
  for (let d = currentDecade; d >= 1870; d -= 10) {
    decades.push(`${d}s`);
  }
  return decades;
}

/**
 * Build a Date from precision components.
 * Used by DatePrecisionSelector to construct the date value.
 */
export function buildDateFromPrecision(opts: {
  dateType: DateType;
  year: number;
  month: number;    // 0-indexed (JS Date convention)
  day: number;
}): Date {
  switch (opts.dateType) {
    case 1: // Month — set day to 1
      return new Date(opts.year, opts.month, 1);
    case 2: // Year — set to Jan 1
      return new Date(opts.year, 0, 1);
    case 3: // Decade — set to Jan 1 of decade start year
      return new Date(opts.year, 0, 1);
    default: // Exact
      return new Date(opts.year, opts.month, opts.day);
  }
}
```

### 1.2 `src/utils/dateFormat.test.ts`

```typescript
import { describe, it, expect } from "vitest";
import {
  formatMemoryDate,
  generateYearOptions,
  generateDecadeOptions,
  buildDateFromPrecision,
  DATE_TYPE_OPTIONS,
  MONTH_OPTIONS,
} from "./dateFormat";

describe("formatMemoryDate", () => {
  it("formats exact date (type 0)", () => {
    const result = formatMemoryDate("2023-12-24T00:00:00", 0);
    expect(result).toBe("December 24, 2023");
  });

  it("formats month precision (type 1)", () => {
    const result = formatMemoryDate("2019-06-15T00:00:00", 1);
    expect(result).toBe("June 2019");
  });

  it("formats year precision (type 2)", () => {
    const result = formatMemoryDate("2015-03-10T00:00:00", 2);
    expect(result).toBe("2015");
  });

  it("formats decade precision (type 3)", () => {
    const result = formatMemoryDate("1955-07-01T00:00:00", 3);
    expect(result).toBe("1950s");
  });

  it("formats decade for year ending in 0", () => {
    const result = formatMemoryDate("2020-01-01T00:00:00", 3);
    expect(result).toBe("2020s");
  });

  it("accepts Date objects", () => {
    const result = formatMemoryDate(new Date(2023, 11, 24), 0);
    expect(result).toBe("December 24, 2023");
  });

  it("defaults to exact format for unknown type", () => {
    const result = formatMemoryDate("2023-06-15T00:00:00", 99);
    expect(result).toContain("2023");
  });

  it("parses date-only strings without timezone shift", () => {
    // "2023-12-24" without T should still parse as local
    const result = formatMemoryDate("2023-12-24", 0);
    expect(result).toBe("December 24, 2023");
  });
});

describe("generateYearOptions", () => {
  it("starts with current year", () => {
    const years = generateYearOptions();
    expect(years[0]).toBe(new Date().getFullYear());
  });

  it("ends with 1870", () => {
    const years = generateYearOptions();
    expect(years[years.length - 1]).toBe(1870);
  });

  it("is in descending order", () => {
    const years = generateYearOptions();
    for (let i = 1; i < years.length; i++) {
      expect(years[i]).toBeLessThan(years[i - 1]);
    }
  });
});

describe("generateDecadeOptions", () => {
  it("starts with current decade", () => {
    const decades = generateDecadeOptions();
    const currentDecade = Math.floor(new Date().getFullYear() / 10) * 10;
    expect(decades[0]).toBe(`${currentDecade}s`);
  });

  it("ends with 1870s", () => {
    const decades = generateDecadeOptions();
    expect(decades[decades.length - 1]).toBe("1870s");
  });
});

describe("buildDateFromPrecision", () => {
  it("builds exact date", () => {
    const d = buildDateFromPrecision({
      dateType: 0, year: 2023, month: 11, day: 24,
    });
    expect(d.getFullYear()).toBe(2023);
    expect(d.getMonth()).toBe(11);
    expect(d.getDate()).toBe(24);
  });

  it("builds month date with day=1", () => {
    const d = buildDateFromPrecision({
      dateType: 1, year: 2019, month: 5, day: 15,
    });
    expect(d.getFullYear()).toBe(2019);
    expect(d.getMonth()).toBe(5);
    expect(d.getDate()).toBe(1);
  });

  it("builds year date as Jan 1", () => {
    const d = buildDateFromPrecision({
      dateType: 2, year: 2015, month: 5, day: 15,
    });
    expect(d.getFullYear()).toBe(2015);
    expect(d.getMonth()).toBe(0);
    expect(d.getDate()).toBe(1);
  });

  it("builds decade date as Jan 1 of decade start", () => {
    const d = buildDateFromPrecision({
      dateType: 3, year: 1950, month: 0, day: 1,
    });
    expect(d.getFullYear()).toBe(1950);
    expect(d.getMonth()).toBe(0);
  });
});

describe("constants", () => {
  it("DATE_TYPE_OPTIONS has 4 entries", () => {
    expect(DATE_TYPE_OPTIONS).toHaveLength(4);
  });

  it("MONTH_OPTIONS has 12 entries", () => {
    expect(MONTH_OPTIONS).toHaveLength(12);
    expect(MONTH_OPTIONS[0]).toBe("January");
    expect(MONTH_OPTIONS[11]).toBe("December");
  });
});
```

### 1.3 Display Surface Updates

Replace raw `toLocaleDateString()` calls with `formatMemoryDate()` in all display components:

| Component | Current Code | Updated Code |
|-----------|-------------|--------------|
| `MemoryCard.vue:112` | `new Date(memory.date).toLocaleDateString()` | `formatMemoryDate(memory.date, memory.dateType)` |
| `MemoryDetailView.vue:96` | `new Date(memory.date).toLocaleDateString()` | `formatMemoryDate(memory.date, memory.dateType)` |
| `SharedMemoryView.vue:15` | `new Date(memory.date).toLocaleDateString()` | `formatMemoryDate(memory.date, memory.dateType)` |
| `StorylineInviteView.vue:51` | `new Date(drop.date).toLocaleDateString()` | `formatMemoryDate(drop.date, drop.dateType)` |
| `AddExistingMemoryModal.vue:20` | `new Date(memory.date).toLocaleDateString()` | `formatMemoryDate(memory.date, memory.dateType)` |
| `QuestionAnswerCard.vue:102-118` | Inline `formattedDate` computed | `formatMemoryDate(props.date, props.dateType)` |
| `AnswerPreview.vue:241-259` | Inline `formattedDate` computed | `formatMemoryDate(answer.date, answer.dateType)` |

Each file adds one import:
```typescript
import { formatMemoryDate } from "@/utils/dateFormat";
```

---

## Phase 2: DatePrecisionSelector Component

### 2.1 `src/components/memory/DatePrecisionSelector.vue`

A reusable component that combines the precision dropdown and the adaptive date input.

**Props:**
- `modelValue: string` — the date as ISO string (YYYY-MM-DD for exact, or full ISO)
- `dateType: number` — the current precision level (0-3)

**Emits:**
- `update:modelValue` — when the date value changes
- `update:dateType` — when the precision level changes

```vue
<template>
  <div>
    <label class="form-label">{{ label }}</label>

    <!-- Date type selector -->
    <select
      :value="dateType"
      class="form-select form-select-sm mb-2"
      style="width: auto"
      aria-label="Date precision"
      @change="onTypeChange(Number(($event.target as HTMLSelectElement).value))"
    >
      <option v-for="opt in DATE_TYPE_OPTIONS" :key="opt.value" :value="opt.value">
        {{ opt.label }}
      </option>
    </select>

    <!-- Exact: HTML5 date input -->
    <input
      v-if="dateType === 0"
      :value="modelValue"
      type="date"
      class="form-control"
      required
      @input="$emit('update:modelValue', ($event.target as HTMLInputElement).value)"
    />

    <!-- Month: month + year selects -->
    <div v-else-if="dateType === 1" class="d-flex gap-2">
      <select
        :value="selectedMonth"
        class="form-select"
        aria-label="Month"
        @change="onMonthChange(Number(($event.target as HTMLSelectElement).value))"
      >
        <option v-for="(name, idx) in MONTH_OPTIONS" :key="idx" :value="idx">
          {{ name }}
        </option>
      </select>
      <select
        :value="selectedYear"
        class="form-select"
        aria-label="Year"
        @change="onYearChange(Number(($event.target as HTMLSelectElement).value))"
      >
        <option v-for="y in yearOptions" :key="y" :value="y">{{ y }}</option>
      </select>
    </div>

    <!-- Year: year select -->
    <select
      v-else-if="dateType === 2"
      :value="selectedYear"
      class="form-select"
      aria-label="Year"
      @change="onYearChange(Number(($event.target as HTMLSelectElement).value))"
    >
      <option v-for="y in yearOptions" :key="y" :value="y">{{ y }}</option>
    </select>

    <!-- Decade: decade select -->
    <select
      v-else
      :value="selectedDecade"
      class="form-select"
      aria-label="Decade"
      @change="onDecadeChange(($event.target as HTMLSelectElement).value)"
    >
      <option v-for="d in decadeOptions" :key="d" :value="d">{{ d }}</option>
    </select>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import type { DateType } from "@/types";
import {
  DATE_TYPE_OPTIONS,
  MONTH_OPTIONS,
  generateYearOptions,
  generateDecadeOptions,
  buildDateFromPrecision,
} from "@/utils/dateFormat";

const props = withDefaults(
  defineProps<{
    modelValue: string;
    dateType: number;
    label?: string;
  }>(),
  { label: "Date" }
);

const emit = defineEmits<{
  (e: "update:modelValue", value: string): void;
  (e: "update:dateType", value: number): void;
}>();

const yearOptions = generateYearOptions();
const decadeOptions = generateDecadeOptions();

// Parse the current modelValue into components
const currentDate = computed(() => {
  // Parse as local date to avoid timezone shifts
  const parts = props.modelValue.split("-");
  if (parts.length >= 3) {
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }
  return new Date(props.modelValue);
});

const selectedYear = computed(() => currentDate.value.getFullYear());
const selectedMonth = computed(() => currentDate.value.getMonth());
const selectedDecade = computed(() => {
  const decade = Math.floor(currentDate.value.getFullYear() / 10) * 10;
  return `${decade}s`;
});

function emitDate(d: Date) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  emit("update:modelValue", `${yyyy}-${mm}-${dd}`);
}

function onTypeChange(newType: number) {
  emit("update:dateType", newType);
  // Rebuild date for new precision, preserving what we can
  const decadeYear = Math.floor(selectedYear.value / 10) * 10;
  const d = buildDateFromPrecision({
    dateType: newType as DateType,
    year: newType === 3 ? decadeYear : selectedYear.value,
    month: selectedMonth.value,
    day: currentDate.value.getDate(),
  });
  emitDate(d);
}

function onMonthChange(month: number) {
  const d = buildDateFromPrecision({
    dateType: 1,
    year: selectedYear.value,
    month,
    day: 1,
  });
  emitDate(d);
}

function onYearChange(year: number) {
  const d = buildDateFromPrecision({
    dateType: props.dateType as DateType,
    year,
    month: selectedMonth.value,
    day: currentDate.value.getDate(),
  });
  emitDate(d);
}

function onDecadeChange(decadeStr: string) {
  const decade = parseInt(decadeStr);
  const d = buildDateFromPrecision({
    dateType: 3,
    year: decade,
    month: 0,
    day: 1,
  });
  emitDate(d);
}
</script>
```

### 2.2 Component Test: `src/components/memory/DatePrecisionSelector.test.ts`

```typescript
import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import DatePrecisionSelector from "./DatePrecisionSelector.vue";

describe("DatePrecisionSelector", () => {
  it("renders date input for exact type", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2026-02-21", dateType: 0 },
    });
    expect(wrapper.find('input[type="date"]').exists()).toBe(true);
    expect(wrapper.find('select[aria-label="Month"]').exists()).toBe(false);
  });

  it("renders month and year selects for month type", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2019-06-01", dateType: 1 },
    });
    expect(wrapper.find('input[type="date"]').exists()).toBe(false);
    expect(wrapper.find('select[aria-label="Month"]').exists()).toBe(true);
    expect(wrapper.find('select[aria-label="Year"]').exists()).toBe(true);
  });

  it("renders year select for year type", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2015-01-01", dateType: 2 },
    });
    const selects = wrapper.findAll("select");
    // type select + year select = 2
    expect(selects.length).toBe(2);
    expect(wrapper.find('select[aria-label="Year"]').exists()).toBe(true);
  });

  it("renders decade select for decade type", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "1950-01-01", dateType: 3 },
    });
    expect(wrapper.find('select[aria-label="Decade"]').exists()).toBe(true);
  });

  it("emits update:dateType when type changes", async () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2026-02-21", dateType: 0 },
    });
    const typeSelect = wrapper.find('select[aria-label="Date precision"]');
    await typeSelect.setValue(2);
    expect(wrapper.emitted("update:dateType")?.[0]).toEqual([2]);
  });

  it("emits update:modelValue when date changes", async () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2026-02-21", dateType: 0 },
    });
    const input = wrapper.find('input[type="date"]');
    await input.setValue("2026-03-15");
    expect(wrapper.emitted("update:modelValue")?.[0]).toEqual(["2026-03-15"]);
  });

  it("preserves month/year when switching from exact to month", async () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2019-06-15", dateType: 0 },
    });
    const typeSelect = wrapper.find('select[aria-label="Date precision"]');
    await typeSelect.setValue(1);
    const emitted = wrapper.emitted("update:modelValue");
    // Should emit a date with month=June, day=1
    expect(emitted?.[0]?.[0]).toBe("2019-06-01");
  });

  it("shows custom label when provided", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2026-02-21", dateType: 0, label: "When did this happen?" },
    });
    expect(wrapper.find(".form-label").text()).toBe("When did this happen?");
  });

  it("pre-selects decade value for dateType 3", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "1950-01-01", dateType: 3 },
    });
    const typeSelect = wrapper.find('select[aria-label="Date precision"]');
    expect((typeSelect.element as HTMLSelectElement).value).toBe("3");
    const decadeSelect = wrapper.find('select[aria-label="Decade"]');
    expect((decadeSelect.element as HTMLSelectElement).value).toBe("1950s");
  });

  it("pre-selects month and year for dateType 1", () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "2019-06-01", dateType: 1 },
    });
    const monthSelect = wrapper.find('select[aria-label="Month"]');
    expect((monthSelect.element as HTMLSelectElement).value).toBe("5"); // 0-indexed
    const yearSelect = wrapper.find('select[aria-label="Year"]');
    expect((yearSelect.element as HTMLSelectElement).value).toBe("2019");
  });

  it("switches from decade back to exact", async () => {
    const wrapper = mount(DatePrecisionSelector, {
      props: { modelValue: "1950-01-01", dateType: 3 },
    });
    const typeSelect = wrapper.find('select[aria-label="Date precision"]');
    await typeSelect.setValue(0);
    expect(wrapper.emitted("update:dateType")?.[0]).toEqual([0]);
    expect(wrapper.find('input[type="date"]').exists()).toBe(true);
  });
});
```

---

## Phase 3: Create & Edit Integration

### 3.1 CreateMemoryView.vue Changes

**Current** (lines 34-37):
```html
<div class="mb-3">
  <label class="form-label">Date</label>
  <input v-model="date" type="date" class="form-control" required />
</div>
```

**Updated:**
```html
<div class="mb-3">
  <DatePrecisionSelector
    v-model="date"
    v-model:dateType="dateType"
  />
</div>
```

**Script changes:**

Add import:
```typescript
import DatePrecisionSelector from "@/components/memory/DatePrecisionSelector.vue";
```

Add ref:
```typescript
const dateType = ref(0);
```

Update `handleSubmit` (line 407) — replace hardcoded `dateType: 0`:
```typescript
dateType: dateType.value,
```

### 3.2 EditMemoryView.vue Changes

**Current** (lines 30-33):
```html
<div class="mb-3">
  <label class="form-label">Date</label>
  <input v-model="date" type="date" class="form-control" required />
</div>
```

**Updated:**
```html
<div class="mb-3">
  <DatePrecisionSelector
    v-model="date"
    v-model:dateType="dateType"
  />
</div>
```

**Script changes:**

Add import:
```typescript
import DatePrecisionSelector from "@/components/memory/DatePrecisionSelector.vue";
```

Add ref:
```typescript
const dateType = ref(0);
```

Load saved dateType in `onMounted` (after line 404):
```typescript
dateType.value = data.dateType;
```

Update `handleSubmit` (line 554) — replace hardcoded `dateType: 0`:
```typescript
dateType: dateType.value,
```

### 3.3 AnswerForm.vue Changes

**Current** (lines 24-27):
```html
<div class="mb-3">
  <label :for="`date-${question.questionId}`" class="form-label">When did this happen?</label>
  <input :id="`date-${question.questionId}`" v-model="date" type="date" class="form-control" />
</div>
```

**Updated:**
```html
<div class="mb-3">
  <DatePrecisionSelector
    v-model="date"
    v-model:dateType="dateType"
    label="When did this happen?"
  />
</div>
```

**Script changes:**

Add import:
```typescript
import DatePrecisionSelector from "@/components/memory/DatePrecisionSelector.vue";
```

Add ref:
```typescript
const dateType = ref(0);
```

Update `handleSubmit` (line 145) — replace hardcoded `dateType: 0`:
```typescript
dateType: dateType.value,
```

---

## Testing Plan

### Unit Tests (Phase 1)

| File | Tests | Coverage |
|------|-------|----------|
| `utils/dateFormat.test.ts` | 13 tests | `formatMemoryDate` (4 types + Date object + unknown type + date-only string), `generateYearOptions` (bounds + order), `generateDecadeOptions` (bounds), `buildDateFromPrecision` (4 types), constants |

### Component Tests (Phase 2)

| File | Tests | Coverage |
|------|-------|----------|
| `components/memory/DatePrecisionSelector.test.ts` | 10 tests | Renders correct input for each type, emits on type change, emits on date change, preserves values when switching types, custom label, pre-selects decade/month values, switches back to exact |

### Integration Verification (Phase 3)

Manual verification checklist:
- [ ] Create memory with exact date — saved and displayed correctly
- [ ] Create memory with month precision — saved as month, displayed as "June 2019"
- [ ] Create memory with year precision — saved as year, displayed as "2015"
- [ ] Create memory with decade precision — saved as decade, displayed as "1950s"
- [ ] Edit memory with exact dateType — loads with date input, allows changing
- [ ] Edit memory with existing Year precision — loads with year dropdown pre-selected
- [ ] Edit memory with existing Decade precision — loads with decade dropdown pre-selected
- [ ] Edit memory — change precision from Decade to Exact and save
- [ ] MemoryCard shows correct format based on dateType
- [ ] MemoryDetailView shows correct format
- [ ] SharedMemoryView shows correct format
- [ ] StorylineInviteView shows correct format
- [ ] Existing memories with dateType 0 display unchanged
- [ ] Existing memories with dateType 1-3 now display correctly
- [ ] Answer form allows date precision selection

---

## Implementation Order

1. **Phase 1** — `dateFormat.ts` utility + tests, then update all display surfaces
2. **Phase 2** — `DatePrecisionSelector.vue` component + tests
3. **Phase 3** — Integrate selector into Create, Edit, and AnswerForm views

Each phase is independently shippable. Phase 1 immediately fixes date display for any existing memories with non-zero dateType.

---

*Document Version: 1.1*
*Created: 2026-02-21*
*Updated: 2026-02-21 — Addressed code review feedback*
