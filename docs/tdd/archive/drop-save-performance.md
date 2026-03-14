# TDD: Drop Save Performance Fix + Save Progress Indicator

## Context

When a user creates a memory shared with 20+ people, the save takes 15-20 seconds. Root cause: `NotificationService.AddNotificationDropAdded()` sends emails **synchronously via Postmark HTTP API** inside a per-recipient loop (~600ms/call x 20 recipients = 12-18s). The existing `EmailJobProcessor` and email queue are already registered but never called from the notification path. Additionally, the frontend provides no visual feedback beyond "Saving..." button text.

## Architecture

```
Current (slow):
  NotificationJobProcessor → NotificationService.AddNotificationDropAdded()
    → foreach recipient:
        AddNotificationGeneric()      ← fast (DB)
        groupService.SendEmail()      ← SLOW (Postmark HTTP ~600ms)
        SaveChangesAsync()            ← fast (DB)

Proposed (fast):
  NotificationJobProcessor → NotificationService.AddNotificationDropAdded()
    → foreach recipient:
        AddNotificationGeneric()      ← fast (DB)
        jobQueue.EnqueueEmailAsync()  ← fast (~1ms, enqueue only)
        SaveChangesAsync()            ← fast (DB)

  EmailJobProcessor (separate background worker, already exists)
    → DequeueEmailAsync() → SendEmailService.SendAsync()
```

---

## Phase 1: Backend — Offload Notification Emails to Email Queue

### Overview

Inject `IBackgroundJobQueue` into `NotificationService` and replace the synchronous `groupService.SendEmail()` call with an enqueue to the existing email job queue. This uses the **exact same infrastructure** already in place for other email jobs.

### Files to Modify

| File | Change |
|------|--------|
| `cimplur-core/Memento/Domain/Repositories/NotificationService.cs` | Add queue injection, replace sync email call |
| `cimplur-core/Memento/DomainTest/Repositories/TestServiceFactory.cs` | Update `CreateNotificationService` to accept optional queue param |

### No Changes Needed

| File | Why |
|------|-----|
| `Startup.cs` | `IBackgroundJobQueue` already registered as singleton (line 53) |
| `EmailJobProcessor.cs` | Already running as hosted service, dequeues and sends |
| `DropsService.cs` | Already enqueues `NotificationJob` correctly |
| `BackgroundJobQueue.cs` | Email channel already exists (capacity 1000) |

### 1.1 NotificationService.cs Changes

**File:** `cimplur-core/Memento/Domain/Repositories/NotificationService.cs`

Add import (note: `System.Collections.Generic` is already imported at line 7 for `Dictionary`):
```csharp
using Domain.BackgroundJobs;
```

Add constructor parameter and field:
```csharp
public NotificationService(
    SendEmailService sendEmailService,
    GroupService groupService,
    ILogger<NotificationService> logger,
    IBackgroundJobQueue jobQueue = null  // NEW - optional for test compat
) {
    this.sendEmailService = sendEmailService;
    this.groupService = groupService;
    this.logger = logger;
    this.jobQueue = jobQueue;  // NEW
}

private IBackgroundJobQueue jobQueue;  // NEW
```

The `= null` default mirrors the pattern in `DropsService` (line 35) and preserves backward compatibility — tests that don't pass a queue will fall through to the synchronous path (which uses `TestSendEmailService`, a no-op).

In `AddNotificationDropAdded` (line 57), replace:
```csharp
await groupService.SendEmail(targetUser.OwnerUser.Email, targetUser.ReaderName ?? user.UserName, dropId, EmailTypes.EmailNotification);
```

With:
```csharp
await EnqueueOrSendEmail(targetUser.OwnerUser.Email, targetUser.ReaderName ?? user.UserName, dropId, EmailTypes.EmailNotification);
```

Add private helper (follows same queue-or-fallback pattern as `DropsService`):
```csharp
private async Task EnqueueOrSendEmail(string email, string userName, int dropId, EmailTypes emailType)
{
    if (jobQueue != null)
    {
        await jobQueue.EnqueueEmailAsync(new EmailJob
        {
            Email = email,
            EmailType = emailType,
            Model = new Dictionary<string, object>
            {
                ["User"] = userName,
                ["DropId"] = dropId.ToString()
            }
        });
    }
    else
    {
        await groupService.SendEmail(email, userName, dropId, emailType);
    }
}
```

The `EmailJob.Model` shape `{ User, DropId }` matches `GroupService.SendEmail` (line 590):
```csharp
await sendEmailService.SendAsync(email, template, new { User = userName, DropId = dropId.ToString() });
```

The `EmailJobProcessor.ProcessJob` converts `Dictionary<string, object>` to `ExpandoObject` via `DictionaryToExpando()` before calling `SendEmailService.SendAsync()` — both anonymous objects and ExpandoObjects are handled by `AddTokenToModel()`.

### 1.2 TestServiceFactory.cs Changes

**File:** `cimplur-core/Memento/DomainTest/Repositories/TestServiceFactory.cs`

Update factory signature to pass through an optional queue:
```csharp
public static NotificationService CreateNotificationService(
    SendEmailService sendEmailService = null,
    GroupService groupService = null,
    ILogger<NotificationService> logger = null,
    IBackgroundJobQueue jobQueue = null)  // NEW
{
    sendEmailService = sendEmailService ?? CreateSendEmailService();
    groupService = groupService ?? CreateGroupService(sendEmailService);
    return new NotificationService(sendEmailService, groupService, logger, jobQueue);
}
```

Existing callers pass `null` for logger (which gets defaulted), so the new param follows the same convention. No callers need updating.

### Performance Impact

| Metric | Before | After |
|--------|--------|-------|
| Per-recipient email time | ~600ms (HTTP) | ~1ms (enqueue) |
| 20 recipients total | ~12-18s | ~400ms |
| Email delivery | Synchronous | Async (seconds later) |

### Backwards Compatibility

- Emails are still sent (via `EmailJobProcessor`), just asynchronously
- Notification JSON updates remain synchronous and consistent
- Email throttle check (`SharedDropNotifications` 2-hour window) stays in the synchronous path, preventing duplicates
- `EmailJobProcessor` is single-threaded, so no concurrent send issues

---

## Phase 2: Frontend — Save Progress Overlay

### Overview

Add a polished progress indicator that shows save progress as a stepped bar below the save button. The component fits the existing Bootstrap 5 / primary color aesthetic.

### Files to Create

| File | Purpose |
|------|---------|
| `fyli-fe-v2/src/components/memory/SaveProgressOverlay.vue` | Progress bar component |
| `fyli-fe-v2/src/components/memory/SaveProgressOverlay.test.ts` | Component tests |

### Files to Modify

| File | Change |
|------|--------|
| `fyli-fe-v2/src/views/memory/CreateMemoryView.vue` | Add step tracking + progress component |
| `fyli-fe-v2/src/views/memory/EditMemoryView.vue` | Add step tracking + progress component |

### 2.1 SaveProgressOverlay.vue

**New file:** `fyli-fe-v2/src/components/memory/SaveProgressOverlay.vue`

A slim progress indicator with:
- Bootstrap `spinner-border-sm` + current step label
- Bootstrap `progress` bar (6px height) using primary color
- Small step dots/labels underneath
- Smooth CSS transition (0.4s ease) on width

**Note:** All Vue/TS code must use **tabs** for indentation (project convention). Run `npx vue-tsc --noEmit` after implementation to catch any type issues.

```vue
<template>
	<div v-if="visible" class="save-progress mt-3">
		<div class="d-flex align-items-center gap-2 mb-2">
			<div class="spinner-border spinner-border-sm text-primary" role="status">
				<span class="visually-hidden">Saving...</span>
			</div>
			<span class="text-muted small">{{ steps[currentStep] ?? 'Saving...' }}</span>
		</div>
		<div class="progress" style="height: 6px">
			<div
				class="progress-bar"
				role="progressbar"
				:style="{ width: progressPercent + '%' }"
				:aria-valuenow="progressPercent"
				aria-valuemin="0"
				aria-valuemax="100"
			></div>
		</div>
		<div class="d-flex justify-content-between mt-1">
			<small
				v-for="(label, i) in steps"
				:key="i"
				:class="i <= currentStep ? 'text-primary' : 'text-muted'"
				style="font-size: 0.7rem"
			>
				<span
					:class="i < currentStep
						? 'mdi mdi-check-circle-outline'
						: (i === currentStep ? 'mdi mdi-circle-medium' : 'mdi mdi-circle-outline')"
					style="font-size: 0.6rem"
				></span>
				{{ label }}
			</small>
		</div>
	</div>
</template>

<script setup lang="ts">
import { computed } from "vue"

const props = defineProps<{
	visible: boolean
	currentStep: number
	steps: string[]
}>()

const progressPercent = computed(() => {
	if (props.steps.length <= 1) return props.currentStep >= 0 ? 100 : 50
	return Math.round(((props.currentStep + 1) / props.steps.length) * 100)
})
</script>

<style scoped>
.save-progress {
	max-width: 400px;
}
.progress-bar {
	transition: width 0.4s ease;
}
</style>
```

### 2.2 CreateMemoryView.vue Changes

**File:** `fyli-fe-v2/src/views/memory/CreateMemoryView.vue`

Add import:
```typescript
import SaveProgressOverlay from "@/components/memory/SaveProgressOverlay.vue"
```

Add reactive state:
```typescript
const saveStep = ref(-1)
const saveSteps = computed(() => {
	const steps = ["Creating memory"]
	if (fileEntries.value.length > 0) steps.push("Uploading files")
	steps.push("Finishing up")
	return steps
})
```

Update the save button to show a spinner (matching the existing "Next" button pattern at line 136-140):
```vue
<button
	type="button"
	class="btn btn-primary"
	:disabled="submitting || (shareMode === 'specific' && selectedUserIds.size === 0)"
	@click="handleSubmit"
>
	<span
		v-if="submitting"
		class="spinner-border spinner-border-sm me-1"
	></span>
	{{ submitting ? "Saving..." : "Save Memory" }}
</button>
```

Update `handleSubmit` to track steps:
```typescript
async function handleSubmit() {
	if (submitting.value || !text.value.trim()) return
	submitting.value = true
	saveStep.value = 0  // "Creating memory"
	error.value = ""
	videoProgress.value = {}
	let dropId: number | null = null

	try {
		const tagIds = getTagIds()
		const { data: created } = await createDrop({
			information: text.value.trim(),
			date: date.value,
			dateType: dateType.value,
			tagIds: tagIds.length > 0 ? tagIds : undefined,
			timelineIds: selectedStorylineIds.value.length
				? selectedStorylineIds.value
				: undefined,
			assisted: assistUsed.value || undefined,
		})
		dropId = created.dropId

		if (fileEntries.value.length > 0) {
			saveStep.value = saveSteps.value.indexOf("Uploading files")
			const failedCount = await uploadFiles(fileEntries.value, dropId)
			if (failedCount > 0) {
				error.value = `${failedCount} file(s) failed to upload. You can add them from the memory detail.`
			}
			const delay = getTranscodeDelay(fileEntries.value)
			if (delay > 0) {
				await new Promise((r) => setTimeout(r, delay))
			}
		}
	} catch (e: any) {
		error.value = getErrorMessage(e, "Failed to create memory.")
	}

	if (dropId) {
		saveStep.value = saveSteps.value.length - 1  // "Finishing up"
		try {
			const { data: drop } = await getDrop(dropId)
			stream.prependMemory(drop)
		} catch {
			// Drop was created but fetch failed
		}
		router.push("/")
	}

	submitting.value = false
	saveStep.value = -1
}
```

Add component to template (after the save button `<div class="d-flex gap-2">` block, inside Step 2):
```vue
<SaveProgressOverlay
	:visible="submitting"
	:current-step="saveStep"
	:steps="saveSteps"
/>
```

### 2.3 EditMemoryView.vue Changes

**File:** `fyli-fe-v2/src/views/memory/EditMemoryView.vue`

Same pattern. Add import, reactive state:
```typescript
import SaveProgressOverlay from "@/components/memory/SaveProgressOverlay.vue"

const saveStep = ref(-1)
const saveSteps = computed(() => {
	const steps = ["Saving changes"]
	if (newFileEntries.value.length > 0) steps.push("Uploading files")
	steps.push("Finishing up")
	return steps
})
```

Update the save button to show a spinner (matching the "Next" button pattern):
```vue
<button
	type="button"
	class="btn btn-primary"
	:disabled="submitting || (shareMode === 'specific' && selectedUserIds.size === 0)"
	@click="handleSubmit"
>
	<span
		v-if="submitting"
		class="spinner-border spinner-border-sm me-1"
	></span>
	{{ submitting ? "Saving..." : "Save Changes" }}
</button>
```

Update `handleSubmit` (lines 579-642):
- `saveStep.value = 0` before `updateDrop()`
- `saveStep.value = saveSteps.value.indexOf("Uploading files")` before `uploadFiles()` (if files exist)
- `saveStep.value = saveSteps.value.length - 1` before `getDrop()` at end
- Reset `saveStep.value = -1` at end
- **Important:** Reset `saveStep.value = -1` in the early error return path (line 630-631) to prevent stale state:

```typescript
} catch (e: unknown) {
	error.value = getErrorMessage(e, "Failed to update memory.")
	submitting.value = false
	saveStep.value = -1
	return
}
```

Add `<SaveProgressOverlay>` below the save button in Step 2:
```vue
<SaveProgressOverlay
	:visible="submitting"
	:current-step="saveStep"
	:steps="saveSteps"
/>
```

---

## Phase 3: Tests

### 3.1 Backend — Existing Tests Pass Without Changes

The `NotificationServiceTest` tests (`Notifications`, `ViewNotification`, `RemoveAllNotifications`) don't exercise `AddNotificationDropAdded` (they test the JSON-based notification methods). The optional `jobQueue = null` param means the constructor signature change is backward compatible.

Run `dotnet test` to confirm no regressions.

### 3.2 Frontend — SaveProgressOverlay.test.ts

**New file:** `fyli-fe-v2/src/components/memory/SaveProgressOverlay.test.ts`

```typescript
import { describe, it, expect } from "vitest"
import { mount } from "@vue/test-utils"
import SaveProgressOverlay from "./SaveProgressOverlay.vue"

describe("SaveProgressOverlay", () => {
	const steps = ["Creating memory", "Uploading files", "Finishing up"]

	it("renders nothing when not visible", () => {
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: false, currentStep: 0, steps },
		})
		expect(wrapper.find(".save-progress").exists()).toBe(false)
	})

	it("renders progress bar when visible", () => {
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: true, currentStep: 0, steps },
		})
		expect(wrapper.find(".progress-bar").exists()).toBe(true)
		expect(wrapper.find(".spinner-border").exists()).toBe(true)
	})

	it("displays current step label", () => {
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: true, currentStep: 1, steps },
		})
		expect(wrapper.text()).toContain("Uploading files")
	})

	it("calculates progress percentage correctly", () => {
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: true, currentStep: 1, steps },
		})
		const bar = wrapper.find(".progress-bar")
		expect(bar.attributes("style")).toContain("width: 67%")
	})

	it("shows 100% on final step", () => {
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: true, currentStep: 2, steps },
		})
		const bar = wrapper.find(".progress-bar")
		expect(bar.attributes("style")).toContain("width: 100%")
	})

	it("calculates progress for 2-step flow without files", () => {
		const twoSteps = ["Creating memory", "Finishing up"]
		const wrapper = mount(SaveProgressOverlay, {
			props: { visible: true, currentStep: 0, steps: twoSteps },
		})
		const bar = wrapper.find(".progress-bar")
		expect(bar.attributes("style")).toContain("width: 50%")
	})
})
```

---

## Verification

### Backend
1. `cd cimplur-core/Memento && dotnet test` — all existing tests pass
2. Manual test: create a drop shared with 20+ people, confirm HTTP response < 2s
3. Check logs: `EmailJobProcessor` should log email sends after the HTTP response completes

### Frontend
1. `cd fyli-fe-v2 && npx vitest run` — all tests pass including new overlay tests
2. `cd fyli-fe-v2 && npx vue-tsc --noEmit` — no type errors (verifies indexed access safety)
3. Create memory flow: verify progress bar shows "Creating memory" → "Uploading files" → "Finishing up"
4. Create memory without files: verify progress bar shows "Creating memory" → "Finishing up" (skips upload step)
5. Edit memory flow: same verification with "Saving changes" label

---

## Implementation Order

1. **Phase 1** — Backend `NotificationService` changes (root cause fix)
2. **Phase 2** — Frontend `SaveProgressOverlay` component + integration
3. **Phase 3** — Run all tests, verify end-to-end
