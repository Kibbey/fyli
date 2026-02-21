# Product Requirements Document: Memory Date Precision

## Overview

Enable users to assign flexible date precision when creating or editing memories. Memories span decades of a person's life — from a child's birth yesterday to a grandparent's story from the 1940s. Users need to express dates at the precision they actually remember: a specific day, a month, a year, or a decade.

## Problem Statement

When capturing memories, users are currently forced to pick an exact date in the new frontend — even when the memory is from "sometime in the summer of '67" or "the 1940s." This creates friction: users either guess a fake specific date (misleading when shared) or skip the date entirely (losing context). Memories shared with family members lose meaning without proper temporal context, and displaying false precision ("June 15, 1967" when the user only remembers "1967") undermines trust in the record.

The backend already supports four date precision levels and the old frontend implemented this well, but the new frontend hardcodes all memories to exact-date precision and ignores the `dateType` field when displaying dates.

## Note

This is an existing backend feature. The `DateTypes` enum (Exact=0, Month=1, Year=2, Decade=3) and the `dateType` column on the Drops table are already in production. No backend or database changes are required. This PRD covers only the new frontend (fyli-fe-v2) implementation.

## Goals

1. Let users quickly select the right level of date precision so capturing memories from any era feels natural
2. Display dates honestly — showing only the precision the user chose so shared memories feel authentic
3. Maintain full backwards compatibility with existing memories and their stored dateType values

## User Stories

### Creating Memories
1. As a parent, I want to record my child's birthday with an exact date so that the memory is precisely timestamped when I share it with family
2. As a user, I want to record a memory from "sometime in March 2019" without picking a fake day so that the date shown to others is honest
3. As a grandchild, I want to capture my grandmother's story from "the 1950s" so that I preserve the timeframe without inventing details
4. As a user, I want the date picker to default to today's exact date so that most everyday memories require zero extra effort

### Editing Memories
5. As a user, I want to change a memory's date precision after creation so that I can correct or refine the timeframe as I remember more details
6. As a user, I want the edit form to show the currently saved precision level so that I know what's already set before making changes

### Viewing Memories
7. As a user viewing shared memories, I want dates displayed at the precision they were entered so that I trust the accuracy of what I'm reading
8. As a user browsing my memory stream, I want to see "2020s" or "June 2019" instead of misleading specific dates so that the timeline feels authentic

## Feature Requirements

### 1. Date Precision Selection

#### 1.1 Precision Levels
Support all four backend-defined precision levels:

| Level | DateType Value | Example Display | Use Case |
|-------|---------------|-----------------|----------|
| Specific Date | 0 (Exact) | December 24, 2023 | Birthdays, weddings, events with known dates |
| Month | 1 | June 2019 | "That summer trip", seasonal memories |
| Year | 2 | 2015 | "Back in 2015", annual milestones |
| Decade | 3 | 1950s | "Growing up in the '50s", generational stories |

#### 1.2 Default Behavior
- New memories default to **Specific Date** (dateType=0) with today's date
- The precision selector must be visible and accessible but should not add friction to the default flow
- Changing precision level should preserve as much of the currently selected date as possible (e.g., switching from Specific Date to Month keeps the month and year)

#### 1.3 Date Input Adaptation
- When precision is **Specific Date**: user selects full date (year, month, day)
- When precision is **Month**: user selects month and year only
- When precision is **Year**: user selects year only
- When precision is **Decade**: user selects a decade (e.g., 1950s, 1960s, ..., 2020s)
- Supported decade range: 1870s through current decade
- Supported year range: 1870 through current year

### 2. Date Display

#### 2.1 Display Formatting
All memory display surfaces must format dates based on the stored `dateType`:

| dateType | Format | Example |
|----------|--------|---------|
| 0 (Exact) | Month Day, Year | December 24, 2023 |
| 1 (Month) | Month Year | June 2019 |
| 2 (Year) | Year | 2015 |
| 3 (Decade) | Decade + "s" | 1950s |

#### 2.2 Display Surfaces
The following components must respect `dateType` when displaying dates:
- **MemoryCard** — memory list/stream view
- **MemoryDetailView** — full memory detail page
- **Any shared memory views** — public share links, storyline views
- **Question answer displays** — already partially implemented, should use shared utility

#### 2.3 Shared Formatting Utility
Create a single reusable date formatting function to eliminate duplication. The question answer components (QuestionAnswerCard, AnswerPreview) already have inline formatting logic that should be consolidated into this shared utility.

### 3. Create Memory Flow

#### 3.1 Integration with CreateMemoryView
- Add date precision selector to the create memory form
- Position the precision selector near the existing date input
- When precision changes, adapt the date input to match (hide day for Month, hide month+day for Year, etc.)

#### 3.2 API Payload
- Send the selected `dateType` value (0-3) with the create drop API call
- Currently hardcoded to `0` — must use the user's selection instead

### 4. Edit Memory Flow

#### 4.1 Integration with EditMemoryView
- Show the saved `dateType` value when loading a memory for editing
- Allow the user to change precision level during editing
- Adapt the date input to match the current precision level

#### 4.2 API Payload
- Send the updated `dateType` value with the update drop API call
- Currently hardcoded to `0` — must use the user's selection instead

## Data Model

### Existing (No Changes Required)

```
Drop {
  dropId: number
  date: DateTime        // Always stored as full datetime
  dateType: number      // 0=Exact, 1=Month, 2=Year, 3=Decade
  ...
}
```

```
DateTypes (enum) {
  Exact = 0
  Month = 1
  Year = 2
  Decade = 3
}
```

The backend stores a full datetime regardless of precision. The `dateType` field controls how the date is interpreted and displayed. No backend changes are needed.

## Technical Considerations

### Frontend Only
- All changes are in fyli-fe-v2 (Vue 3 / TypeScript)
- No backend API changes — the `dateType` field already exists on create and update endpoints
- No database migrations — the `dateType` column already exists on the Drops table

### Existing Code to Update
- `CreateMemoryView.vue` — remove hardcoded `dateType: 0`, add precision selector
- `EditMemoryView.vue` — remove hardcoded `dateType: 0`, add precision selector, load saved value
- `MemoryCard.vue` — use formatting utility instead of raw `toLocaleDateString()`
- `MemoryDetailView.vue` — use formatting utility instead of raw `toLocaleDateString()`

### Existing Code to Consolidate
- `QuestionAnswerCard.vue` and `AnswerPreview.vue` already have inline date formatting switch statements that should be replaced with the shared utility

### Question Answer Forms
- `AnswerForm.vue` also hardcodes `dateType: 0` — this should be addressed as part of this work since the same precision selector component can be reused

## Success Metrics

| Metric | Definition | Target |
|--------|------------|--------|
| Precision Adoption | % of new memories created with non-exact dateType (1, 2, or 3) | >15% after 30 days |
| Date Entry Completion | % of memories saved with a date (vs. accepting default) | Maintain or improve current rate |
| Legacy Compatibility | Existing memories with dateType 1-3 display correctly | 100% |

## Out of Scope (Future Considerations)

- Season-level precision (e.g., "Summer 2019") — would require backend enum extension
- Date ranges (e.g., "2015-2018") — different concept, different data model
- Approximate date labels (e.g., "around 1965") — display enhancement only, could layer on later
- Backend validation of dateType values — currently trusts client input
- Chronological sort improvements based on dateType — existing sort by Date field works adequately

## Implementation Phases

### Phase 1: Date Formatting Utility & Display Fix
- Create shared `formatMemoryDate(date, dateType)` utility function
- Update MemoryCard to use the utility
- Update MemoryDetailView to use the utility
- Refactor QuestionAnswerCard and AnswerPreview to use the shared utility
- **Result:** All existing memories with non-zero dateType display correctly

### Phase 2: Date Precision Selector Component
- Build reusable date precision selector component
- Component accepts dateType and date, emits changes
- Date input adapts based on selected precision level
- Specific UI/UX approach to be determined in TDD

### Phase 3: Create & Edit Integration
- Integrate precision selector into CreateMemoryView
- Integrate precision selector into EditMemoryView (with saved value loading)
- Remove hardcoded `dateType: 0` from both views
- Integrate precision selector into AnswerForm (question answers)

## Open Questions

1. Should the precision selector be expanded by default or collapsed behind a "More options" toggle to minimize friction for everyday memories?
2. When a user switches from Specific Date to Year precision, should we show a confirmation if they're "losing" date specificity?
3. Are there any shared memory link views beyond MemoryDetailView that need display updates?

---

*Document Version: 1.0*
*Created: 2026-02-21*
*Status: Draft*
