# TDD: Question Recipient Picker Enhancement

## Overview

Enhance the question recipient selection (Step 2 of `AskQuestionsView`) so users can choose from three sources:

1. **My Connections** — existing contacts from `getSharingRecipients()`
2. **Previously Asked** — people they've sent questions to before from `getPreviousRecipients()`
3. **Someone New** — manual email entry (existing behavior)

All sources are deduplicated by email (case-insensitive) so no person appears twice.

## Current State

Step 2 currently has two sections:
- **Previously sent to** — checkbox list from `getPreviousRecipients()`
- **Add new recipients** — manual email/alias entry rows

The connections list (`getSharingRecipients()`) is not surfaced anywhere in the question flow.

## Architecture

### Changes Required

| Layer | File | Change |
|-------|------|--------|
| Frontend | `AskQuestionsView.vue` | Redesign Step 2 with tabbed/sectioned recipient picker |
| Frontend | `questionApi.ts` | No changes (existing APIs sufficient) |
| Frontend | `connectionApi.ts` | No changes (existing `getSharingRecipients()`) |
| Frontend | `question.ts` (types) | No changes |
| Backend | None | No backend changes needed — all APIs already exist |

### Data Flow

```
Step 2 loads:
  ┌─ getSharingRecipients() ──→ connections[]
  ├─ getPreviousRecipients() ──→ previousRecipients[]
  └─ (manual entry) ──────────→ recipients[]

Dedup by email (case-insensitive):
  connections shown ALWAYS
  previousRecipients shown ONLY if email NOT in connections
  manual entry validated on send — dupes with selected contacts are fine (backend handles)

On Send:
  Merge selected connections + selected previous + manual → allRecipients[]
  → POST /questions/requests
```

## Implementation

### Phase 1: Frontend — Redesign Step 2

**File:** `fyli-fe-v2/src/views/question/AskQuestionsView.vue`

#### 1.1 New Imports

Add `getSharingRecipients` import from `connectionApi`:

```typescript
import { getSharingRecipients } from "@/services/connectionApi";
import type { SharingRecipient } from "@/types";
```

#### 1.2 New State Variables

```typescript
// Step 2: Recipients
const connections = ref<SharingRecipient[]>([]);
const selectedConnections = ref<string[]>([]); // emails
```

#### 1.3 Load Connections Alongside Previous Recipients

Update `loadPreviousRecipients` to also load connections (rename to `loadRecipientSources`). Add an idempotency guard so navigating back/forward between steps doesn't re-fetch:

```typescript
const recipientSourcesLoaded = ref(false);

async function loadRecipientSources() {
  if (recipientSourcesLoaded.value) return;
  recipientSourcesLoaded.value = true;

  const results = await Promise.allSettled([
    getSharingRecipients(),
    getPreviousRecipients(),
  ]);

  if (results[0].status === "fulfilled") {
    connections.value = results[0].value.data;
  }
  if (results[1].status === "fulfilled") {
    previousRecipients.value = results[1].value.data;
  }
}
```

#### 1.4 Deduplicated Previous Recipients (Computed)

Previous recipients that are NOT already in the connections list:

```typescript
const filteredPreviousRecipients = computed(() => {
  const connectionEmails = new Set(
    connections.value.map(c => c.email.toLowerCase())
  );
  return previousRecipients.value.filter(
    p => !connectionEmails.has(p.email.toLowerCase())
  );
});
```

#### 1.5 Updated Template — Step 2

Replace the existing Step 2 recipient sections with three sections:

```html
<!-- Step 2: Recipients -->
<template v-if="step === 2">
  <div class="step-card">
    <div class="step-header">
      <span class="step-icon mdi mdi-account-group-outline"></span>
      <div>
        <h1 class="step-title">Who should answer?</h1>
        <p class="step-subtitle">
          {{ connections.length > 0 || filteredPreviousRecipients.length > 0
            ? 'Select from your contacts or add someone new.'
            : 'Add the people you\'d like to hear from.' }}
        </p>
      </div>
    </div>

    <LoadingSpinner v-if="loadingSets" />
    <template v-else>

      <!-- Section 1: My Connections -->
      <div v-if="connections.length > 0" class="mb-4">
        <label class="form-label fw-semibold small text-uppercase text-muted">
          My Connections
        </label>
        <div class="recipient-list">
          <label
            v-for="conn in connections"
            :key="'conn-' + conn.email"
            class="recipient-option"
            :class="{ selected: selectedConnections.includes(conn.email) }"
          >
            <input
              v-model="selectedConnections"
              type="checkbox"
              :value="conn.email"
              class="form-check-input"
            />
            <div class="recipient-info">
              <span class="recipient-name">{{ conn.displayName || conn.email }}</span>
              <span v-if="conn.displayName" class="recipient-email text-muted">{{ conn.email }}</span>
            </div>
          </label>
        </div>
      </div>

      <!-- Section 2: Previously Asked (deduped against connections) -->
      <div v-if="filteredPreviousRecipients.length > 0" class="mb-4">
        <label class="form-label fw-semibold small text-uppercase text-muted">
          Previously Asked
        </label>
        <div class="recipient-list">
          <label
            v-for="prev in filteredPreviousRecipients"
            :key="'prev-' + prev.email"
            class="recipient-option"
            :class="{ selected: selectedPrevious.includes(prev.email) }"
          >
            <input
              v-model="selectedPrevious"
              type="checkbox"
              :value="prev.email"
              class="form-check-input"
            />
            <div class="recipient-info">
              <span class="recipient-name">{{ prev.alias || prev.email }}</span>
              <span v-if="prev.alias" class="recipient-email text-muted">{{ prev.email }}</span>
              <small class="text-muted">Last sent {{ formatDate(prev.lastSentAt) }}</small>
            </div>
          </label>
        </div>
      </div>

      <!-- Section 3: Add Someone New (manual entry) -->
      <fieldset class="mb-4">
        <legend class="form-label fw-semibold small text-uppercase text-muted">Add Someone New</legend>
        <div class="new-recipients">
          <div v-for="(r, i) in recipients" :key="i" class="recipient-row">
            <div class="recipient-fields">
              <input
                v-model="r.email"
                type="email"
                class="form-control"
                placeholder="Email address"
                required
              />
              <input
                v-model="r.alias"
                type="text"
                class="form-control"
                placeholder="Name (optional)"
              />
            </div>
            <button
              v-if="recipients.length > 1 || selectedConnections.length > 0 || selectedPrevious.length > 0"
              class="btn btn-sm btn-icon text-danger"
              aria-label="Remove recipient"
              @click="recipients.splice(i, 1)"
            >
              <span class="mdi mdi-close"></span>
            </button>
          </div>
        </div>
        <button class="btn btn-sm btn-outline-secondary mt-2" @click="addRecipient">
          <span class="mdi mdi-plus"></span> Add Recipient
        </button>
      </fieldset>

      <!-- Personal message + send button (unchanged) -->
      ...
    </template>
  </div>
</template>
```

#### 1.6 Updated `handleSend`

Add connections to the merge logic:

```typescript
async function handleSend() {
  stepError.value = "";
  const allRecipients: RecipientInput[] = [];
  const seen = new Set<string>();

  // 1. Selected connections
  for (const email of selectedConnections.value) {
    const key = email.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const conn = connections.value.find(c => c.email === email);
    allRecipients.push({ email, alias: conn?.displayName ?? undefined });
  }

  // 2. Selected previous recipients
  for (const email of selectedPrevious.value) {
    const key = email.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    const prev = previousRecipients.value.find(p => p.email === email);
    allRecipients.push({ email, alias: prev?.alias ?? undefined });
  }

  // 3. Manual recipients
  for (const r of recipients.value) {
    if (r.email?.trim()) {
      const key = r.email.trim().toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      allRecipients.push({ email: r.email.trim(), alias: r.alias?.trim() || undefined });
    }
  }

  if (!allRecipients.length) {
    stepError.value = "At least one recipient is required";
    return;
  }

  sending.value = true;
  try {
    const { data } = await createQuestionRequest({
      questionSetId: activeSetId.value!,
      recipients: allRecipients,
      message: message.value.trim() || undefined,
    });
    sendResult.value = data;
    step.value = 3;
  } catch (e: unknown) {
    stepError.value = getErrorMessage(e, "Failed to send");
  } finally {
    sending.value = false;
  }
}
```

#### 1.7 Update All Call Sites

Replace `loadPreviousRecipients()` calls with `loadRecipientSources()`:
- `handlePickStep()` (line ~411)
- `handleCreateSet()` (line ~431)
- `onMounted` (line ~385)

#### 1.8 Remove Button Visibility Guard

Update the manual recipient remove button condition. Currently:
```typescript
v-if="recipients.length > 1 || selectedPrevious.length > 0"
```
Change to:
```typescript
v-if="recipients.length > 1 || selectedConnections.length > 0 || selectedPrevious.length > 0"
```
This ensures the remove button shows when any other source has selections, so the user can clear the default empty manual row.

### Phase 1 Summary — No CSS Changes

The three sections reuse the existing `.recipient-list`, `.recipient-option`, `.recipient-info`, `.recipient-name`, `.recipient-email`, `.new-recipients`, `.recipient-row`, and `.recipient-fields` styles. No new CSS is needed.

---

## Testing Plan

### Updating Existing Tests

**File:** `fyli-fe-v2/src/views/question/AskQuestionsView.test.ts`

The existing test file has 7 tests that mock `@/services/questionApi` but NOT `@/services/connectionApi`. All existing tests will break without adding the `getSharingRecipients` mock.

**Required changes to existing test file:**

1. Add mock for `connectionApi`:
```typescript
vi.mock("@/services/connectionApi", () => ({
  getSharingRecipients: vi.fn()
}));

import { getSharingRecipients } from "@/services/connectionApi";
```

2. Add default mock return in `beforeEach`:
```typescript
(getSharingRecipients as any).mockResolvedValue({ data: [] });
```

3. Existing tests should continue to pass with the empty connections default.

### New Frontend Tests

| # | Test | Description |
|---|------|-------------|
| 1 | Connections section renders | When `getSharingRecipients` returns data, "My Connections" section appears with checkboxes |
| 2 | Previous section deduped | A previous recipient whose email matches a connection does NOT appear in "Previously Asked" |
| 3 | Previous section renders non-dupes | Previous recipients with unique emails appear in "Previously Asked" |
| 4 | Manual entry always available | "Add Someone New" section always renders with at least one row |
| 5 | Send merges all sources | Selecting from connections + previous + manual results in correct `allRecipients` array |
| 6 | Send dedupes across sources | If same email is in connections AND typed manually, only sent once |
| 7 | Empty connections hidden | When `getSharingRecipients` returns empty, "My Connections" section is not rendered |
| 8 | API failure graceful | If `getSharingRecipients` fails, connections section hidden, rest of flow works normally |
| 9 | Case-insensitive dedup | `User@Email.com` in connections and `user@email.com` in previous → only shows in connections |
| 10 | Dynamic subtitle | Subtitle says "Select from your contacts..." when connections exist, "Add the people..." when empty |

### Backend Tests

No backend changes — no backend tests needed.

---

## Implementation Order

1. Add `getSharingRecipients` import and `connections`/`selectedConnections` state
2. Create `loadRecipientSources` function (parallel fetch)
3. Add `filteredPreviousRecipients` computed
4. Update template with three sections
5. Update `handleSend` with dedup merge logic
6. Update all `loadPreviousRecipients` call sites
7. Manual test the full flow

---

## Notes

- **No backend changes required** — `GET /connections/sharing-recipients` and `GET /questions/recipients/previous` already exist and return all needed data.
- **Dedup strategy is frontend-only** — the backend already handles duplicate emails within a question set (reuses tokens). The frontend dedup is purely for UI cleanliness.
- **Case-insensitive** — all email comparisons use `.toLowerCase()`.
- **Connections without email** — `SharingRecipient` always has an email field (required for connection creation), so all connections will be selectable.
- **Alias priority** — When a person appears in both connections and previous recipients, they show in the connections section only (deduped out of previous). The connection's `displayName` is sent as the alias. This is intentional — the connection name is the user's preferred label for that person.
