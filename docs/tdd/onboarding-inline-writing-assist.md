# TDD: Onboarding Inline Writing Assist

## Overview

Move "Help me write" into the onboarding Quick Capture step so users discover AI writing assistance while typing — not after finishing and clicking Next. This removes the separate forced AI Polish step and teaches users the same inline writing assist pattern used throughout the app.

**PRD:** `docs/prd/PRD_ONBOARDING_INLINE_WRITING_ASSIST.md`

## Design

### Approach

This is a **frontend-only** change to `FirstMomentView.vue`. No backend changes needed — all required APIs and services already exist.

**What changes:**
1. Import `useWritingAssist` composable and `WritingAssistButton` component into `FirstMomentView.vue`
2. Add `WritingAssistButton` to the Quick Capture step (step 2), below the textarea
3. Add `review-highlight` CSS class to textarea when in review mode
4. Change the "Next" button to save the memory directly (no more forced polish)
5. Remove step 3 (AI Polish split-view) entirely — template and script
6. Celebrate becomes step 3 (was step 4)
7. Update step dots from 4 to 3
8. Remove dead code: `polishing`, `polishedText`, `editing`, `editedText`, `handlePolish`, `startEditing`, `saveEdit`, `usePolishedVersion`, and the direct `getWritingAssist` import

**What stays the same:**
- `useWritingAssist.ts` composable — reused as-is
- `WritingAssistButton.vue` component — reused as-is
- `writingAssistApi.ts` — reused as-is
- `onboardingApi.ts` — reused as-is
- All backend services and endpoints
- Welcome step (step 0), Prompt Selection step (step 1), file attachment, step dots UX

### Component Diagram

```
FirstMomentView.vue (MODIFIED)
├── Step 0: Welcome (unchanged)
├── Step 1: Prompt Selection (unchanged)
├── Step 2: Quick Capture (MODIFIED)
│   ├── <textarea> (ADD :class="{ 'review-highlight': isReviewMode }")
│   ├── <WritingAssistButton /> (NEW — reused from memory/)
│   ├── File attachment (unchanged)
│   └── Back / Next buttons (Next NOW saves directly)
├── Step 3: AI Polish (REMOVED)
└── Step 3: Celebrate (was Step 4, renumbered)

Dependencies (all existing, no changes):
├── useWritingAssist composable (existing)
├── WritingAssistButton component (existing)
├── useFileUpload composable (existing)
├── memoryApi (createDrop, getDrop) (existing)
├── onboardingApi (updateOnboarding) (existing)
└── writingAssistApi (getWritingAssist — via composable only) (existing)
```

### Data Flow

```
1. User types in textarea on step 2
2. "Help me write" button enables (text is non-empty)
3. User taps "Help me write" → useWritingAssist.polish() called
4. polish() calls getWritingAssist API, returns polished text
5. Polished text replaces textarea content, review-highlight applied
6. Accept/Undo buttons appear (WritingAssistButton handles this)
7. User accepts, undoes, or edits directly
8. User taps "Next" → saveMemory() called directly
9. saveMemory creates drop with assisted flag from composable
10. Upload files, complete onboarding, show celebrate step
```

## File Structure

```
fyli-fe-v2/src/
├── views/
│   └── onboarding/
│       ├── FirstMomentView.vue          (MODIFY — main changes)
│       └── FirstMomentView.test.ts      (MODIFY — update tests)
├── components/
│   └── memory/
│       └── WritingAssistButton.vue      (NO CHANGE — reused as-is)
└── composables/
    └── useWritingAssist.ts              (NO CHANGE — reused as-is)
```

## Implementation

### Phase 1: Modify FirstMomentView.vue

**File:** `fyli-fe-v2/src/views/onboarding/FirstMomentView.vue`

#### 1.1 Update script imports and composable setup

Replace the current imports and add the writing assist composable:

```typescript
// REMOVE this import:
import { getWritingAssist } from "@/services/writingAssistApi"

// ADD these imports:
import { useWritingAssist } from "@/composables/useWritingAssist"
import WritingAssistButton from "@/components/memory/WritingAssistButton.vue"
```

Add composable destructuring after the `useFileUpload` call:

```typescript
const { fileEntries, onFileChange, uploadFiles } = useFileUpload()

// ADD:
const {
	isPolishing,
	polishError,
	isReviewMode,
	assistUsed,
	polish,
	accept,
	undo,
	dismissError,
} = useWritingAssist()
```

#### 1.2 Remove dead state variables

Remove these variables that were used by the old step 3:

```typescript
// REMOVE all of these:
const polishing = ref(false)
const polishedText = ref("")
const editing = ref(false)
const editedText = ref("")
```

#### 1.3 Update step constants

```typescript
// CHANGE from:
const totalSteps = 4

// TO:
const totalSteps = 3
```

#### 1.4 Rename canProceedToPolish → canSave

```typescript
// CHANGE from:
const canProceedToPolish = computed(() => text.value.trim().length >= 10)

// TO:
const canSave = computed(() => text.value.trim().length >= 10)
```

#### 1.5 Remove old step 3 functions, add writing assist handlers

Remove these functions entirely:

```typescript
// REMOVE all of these:
async function handlePolish() { ... }
function startEditing() { ... }
function saveEdit() { ... }
function usePolishedVersion() { ... }
```

Add writing assist handlers (same pattern as CreateMemoryView):

```typescript
async function handlePolish() {
	const polished = await polish(text.value)
	if (polished) {
		text.value = polished
	}
}

function handleAccept() {
	accept()
}

function handleUndo() {
	text.value = undo()
}
```

#### 1.6 Update saveMemory function

The `saveMemory` function no longer takes a `usePolished` boolean parameter. It always saves whatever is in the text area. The `assisted` flag comes from the composable.

```typescript
// CHANGE from:
async function saveMemory(usePolished: boolean) {
	saving.value = true
	error.value = ""
	try {
		const content = usePolished ? polishedText.value : text.value.trim()
		const now = new Date().toISOString().split("T")[0]!
		const { data: created } = await createDrop({
			information: content,
			date: now,
			dateType: 0,
			assisted: usePolished,
		})
		// ... rest unchanged except step number ...
		step.value = 4
	}
}

// TO:
async function saveMemory() {
	saving.value = true
	error.value = ""
	try {
		const now = new Date().toISOString().split("T")[0]!
		const { data: created } = await createDrop({
			information: text.value.trim(),
			date: now,
			dateType: 0,
			assisted: assistUsed.value || undefined,
		})

		// Upload files if any
		if (fileEntries.value.length > 0) {
			await uploadFiles(fileEntries.value, created.dropId)
		}

		// Mark first moment complete
		await updateOnboarding("completeFirstMoment")
		await auth.fetchUser()

		// Prepend to stream
		const { data: drop } = await getDrop(created.dropId)
		stream.prependMemory(drop)

		step.value = 3
	} catch (e: unknown) {
		error.value = getErrorMessage(e, "Something went wrong saving your memory.")
	} finally {
		saving.value = false
	}
}
```

#### 1.7 Update template — Step dots

```html
<!-- CHANGE: Show dots for steps 1-2 only (step 3 celebrate has no dots) -->
<nav
	v-if="step > 0 && step < 3"
	aria-label="Onboarding progress"
	class="text-center mb-4"
>
```

#### 1.8 Update template — Step 2 (Quick Capture)

Replace the step 2 section with the inline writing assist version:

```html
<!-- Step 2: Quick capture -->
<div v-show="step === 2" class="step-panel">
	<h4 class="text-center mb-4">Capture your moment</h4>
	<textarea
		ref="captureTextarea"
		v-model="text"
		class="form-control mb-3"
		:class="{ 'review-highlight': isReviewMode }"
		rows="5"
		:placeholder="placeholderText"
	></textarea>

	<!-- Writing assist -->
	<WritingAssistButton
		:is-polishing="isPolishing"
		:polish-error="polishError"
		:is-review-mode="isReviewMode"
		:disabled="!text.trim()"
		@polish="handlePolish"
		@accept="handleAccept"
		@undo="handleUndo"
		@dismiss-error="dismissError"
	/>

	<!-- File attachment -->
	<div class="mb-3">
		<label class="btn btn-outline-secondary btn-sm">
			<span class="mdi mdi-camera me-1"></span>
			Add a photo or video
			<input
				type="file"
				accept="image/*,video/*"
				class="d-none"
				@change="onFileChange"
			/>
		</label>
		<div v-if="fileEntries.length > 0" class="mt-2 d-flex flex-wrap gap-2">
			<div
				v-for="entry in fileEntries"
				:key="entry.id"
				class="position-relative file-thumbnail"
			>
				<img
					v-if="entry.type === 'image'"
					:src="entry.previewUrl"
					class="rounded file-thumbnail-media"
				/>
				<video
					v-else
					:src="entry.previewUrl"
					class="rounded file-thumbnail-media"
				></video>
			</div>
		</div>
	</div>

	<div v-if="error" class="alert alert-danger py-2">{{ error }}</div>

	<div class="d-flex justify-content-between">
		<button class="btn btn-outline-secondary" @click="step = 1">
			Back
		</button>
		<button
			class="btn btn-primary"
			:disabled="!canSave || saving"
			@click="saveMemory"
		>
			<span v-if="saving" class="spinner-border spinner-border-sm me-1"></span>
			{{ saving ? "Saving..." : "Next" }}
		</button>
	</div>
</div>
```

#### 1.9 Remove template — Step 3 (AI Polish)

Delete the entire step 3 block (lines 118-181 in the current file):

```html
<!-- DELETE: This entire block -->
<!-- Step 3: AI polish -->
<div v-show="step === 3" class="step-panel">
	...everything between...
</div>
```

#### 1.10 Update template — Celebrate step number

```html
<!-- CHANGE from step === 4 to step === 3 -->
<div v-if="step === 3" class="text-center">
```

#### 1.11 Update styles

Add the `review-highlight` class (matching CreateMemoryView) and remove dead styles:

```css
/* ADD: */
.review-highlight {
	background-color: var(--fyli-primary-light);
	border-color: var(--fyli-primary);
}

/* REMOVE these (no longer used): */
.original-text {
	background-color: var(--fyli-bg-light);
}

.polished-card {
	background-color: var(--fyli-primary-light);
}
```

### Phase 2: Update Tests

**File:** `fyli-fe-v2/src/views/onboarding/FirstMomentView.test.ts`

The tests need significant updates because the flow changes from "Next triggers forced polish → step 3 → save" to "Next saves directly from step 2".

#### 2.1 Update mocks

Replace the direct `writingAssistApi` mock with the composable mock (matching CreateMemoryView's pattern):

```typescript
// REMOVE:
vi.mock("@/services/writingAssistApi", () => ({
	getWritingAssist: vi.fn(),
}));

// ADD:
vi.mock("@/composables/useWritingAssist", async () => {
	const { ref } = await import("vue");
	return {
		useWritingAssist: () => ({
			isPolishing: ref(false),
			polishError: ref(""),
			isReviewMode: ref(false),
			originalText: ref(""),
			assistUsed: ref(false),
			polish: vi.fn(),
			accept: vi.fn(),
			undo: vi.fn(),
			dismissError: vi.fn(),
		}),
	};
});
```

Also remove the `getWritingAssist` import line:

```typescript
// REMOVE:
import { getWritingAssist } from "@/services/writingAssistApi";
```

#### 2.2 Replace tests

The full updated test file:

```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import { mount, flushPromises } from "@vue/test-utils";
import { setActivePinia, createPinia } from "pinia";
import FirstMomentView from "./FirstMomentView.vue";
import { createDrop, createUser } from "@/test/fixtures";
import { mockResponse } from "@/test/apiMock";

vi.mock("@/services/memoryApi", () => ({
	createDrop: vi.fn(),
	getDrop: vi.fn(),
}));

vi.mock("@/composables/useWritingAssist", async () => {
	const { ref } = await import("vue");
	return {
		useWritingAssist: () => ({
			isPolishing: ref(false),
			polishError: ref(""),
			isReviewMode: ref(false),
			originalText: ref(""),
			assistUsed: ref(false),
			polish: vi.fn(),
			accept: vi.fn(),
			undo: vi.fn(),
			dismissError: vi.fn(),
		}),
	};
});

vi.mock("@/services/onboardingApi", () => ({
	updateOnboarding: vi.fn(),
}));

vi.mock("@/services/authApi", () => ({
	getUser: vi.fn(),
}));

vi.mock("@/services/mediaApi", () => ({
	uploadImage: vi.fn(),
	requestVideoUpload: vi.fn(),
	completeVideoUpload: vi.fn(),
	uploadFileToS3: vi.fn(),
}));

const mockReplace = vi.fn();
vi.mock("vue-router", () => ({
	useRouter: () => ({ push: vi.fn(), replace: mockReplace }),
	useRoute: () => ({ params: {} }),
	createRouter: () => ({ push: vi.fn(), beforeEach: vi.fn(), install: vi.fn() }),
	createWebHistory: vi.fn(),
}));

import { createDrop as createDropApi, getDrop } from "@/services/memoryApi";
import { updateOnboarding } from "@/services/onboardingApi";
import { getUser } from "@/services/authApi";

describe("FirstMomentView", () => {
	beforeEach(() => {
		setActivePinia(createPinia());
		vi.clearAllMocks();
	});

	it("renders welcome screen on step 0", () => {
		const wrapper = mount(FirstMomentView);
		expect(wrapper.text()).toContain("You're busy. We get it.");
		expect(wrapper.text()).toContain("Let's capture one moment in under 60 seconds.");
		expect(wrapper.find("button.btn-primary").text()).toBe("Let's go");
	});

	it("advances to prompt selection on 'Let's go' click", async () => {
		const wrapper = mount(FirstMomentView);
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		expect(wrapper.text()).toContain("Pick a prompt, or write your own:");
		expect(wrapper.text()).toContain("Something funny your kid said recently");
		expect(wrapper.text()).toContain("A meal your family loved");
		expect(wrapper.text()).toContain("A moment you want to remember from this week");
		expect(wrapper.text()).toContain("Write your own");
	});

	it("advances to capture with selected prompt", async () => {
		const wrapper = mount(FirstMomentView);
		// Step 0 -> Step 1
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		// Click first prompt
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		expect(promptButtons.length).toBeGreaterThan(0);
		await promptButtons[0]!.trigger("click");
		await flushPromises();
		expect(wrapper.text()).toContain("Capture your moment");
		expect(wrapper.find("textarea").exists()).toBe(true);
	});

	it("shows 'Help me write' button on capture step", async () => {
		const wrapper = mount(FirstMomentView);
		// Navigate to step 2
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		await promptButtons[0]!.trigger("click");
		await flushPromises();

		expect(wrapper.text()).toContain("Help me write");
	});

	it("disables Next button when text < 10 chars", async () => {
		const wrapper = mount(FirstMomentView);
		// Navigate to step 2
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		await promptButtons[0]!.trigger("click");
		await flushPromises();
		// Type less than 10 characters
		await wrapper.find("textarea").setValue("Short");
		await flushPromises();
		// Find the "Next" button
		const nextBtn = wrapper.findAll("button.btn-primary").find(
			(b) => b.text().includes("Next")
		);
		expect(nextBtn).toBeDefined();
		expect(nextBtn!.attributes("disabled")).toBeDefined();
	});

	it("saves memory directly when Next is clicked", async () => {
		const drop = createDrop();
		const user = createUser({
			onboardingState: {
				firstMomentCompletedAt: "2026-01-15T00:00:00Z",
				missionsDismissed: false,
				completedMissions: [],
			},
		});

		vi.mocked(createDropApi).mockResolvedValue(mockResponse(drop));
		vi.mocked(getDrop).mockResolvedValue(mockResponse(drop));
		vi.mocked(updateOnboarding).mockResolvedValue(mockResponse(user.onboardingState!));
		vi.mocked(getUser).mockResolvedValue(mockResponse(user));

		const wrapper = mount(FirstMomentView);
		// Navigate to step 2
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		await promptButtons[0]!.trigger("click");
		await flushPromises();
		// Enter text
		await wrapper.find("textarea").setValue("This is my first memory capture text.");
		await flushPromises();
		// Click Next — should save directly
		const nextBtn = wrapper.findAll("button.btn-primary").find(
			(b) => b.text().includes("Next")
		);
		await nextBtn!.trigger("click");
		await flushPromises();

		expect(createDropApi).toHaveBeenCalledWith(
			expect.objectContaining({
				information: "This is my first memory capture text.",
			})
		);
		expect(updateOnboarding).toHaveBeenCalledWith("completeFirstMoment");
	});

	it("shows celebration step after save", async () => {
		const drop = createDrop();
		const user = createUser({
			onboardingState: {
				firstMomentCompletedAt: "2026-01-15T00:00:00Z",
				missionsDismissed: false,
				completedMissions: [],
			},
		});

		vi.mocked(createDropApi).mockResolvedValue(mockResponse(drop));
		vi.mocked(getDrop).mockResolvedValue(mockResponse(drop));
		vi.mocked(updateOnboarding).mockResolvedValue(mockResponse(user.onboardingState!));
		vi.mocked(getUser).mockResolvedValue(mockResponse(user));

		const wrapper = mount(FirstMomentView);
		// Navigate to step 2
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		await promptButtons[0]!.trigger("click");
		await flushPromises();
		// Enter text and save
		await wrapper.find("textarea").setValue("This is my first memory capture text.");
		await flushPromises();
		const nextBtn = wrapper.findAll("button.btn-primary").find(
			(b) => b.text().includes("Next")
		);
		await nextBtn!.trigger("click");
		await flushPromises();

		expect(wrapper.text()).toContain("Your first moment is safe.");
		expect(wrapper.text()).toContain("See my memories");
	});

	it("navigates to stream on 'See my memories'", async () => {
		const drop = createDrop();
		const user = createUser({
			onboardingState: {
				firstMomentCompletedAt: "2026-01-15T00:00:00Z",
				missionsDismissed: false,
				completedMissions: [],
			},
		});

		vi.mocked(createDropApi).mockResolvedValue(mockResponse(drop));
		vi.mocked(getDrop).mockResolvedValue(mockResponse(drop));
		vi.mocked(updateOnboarding).mockResolvedValue(mockResponse(user.onboardingState!));
		vi.mocked(getUser).mockResolvedValue(mockResponse(user));

		const wrapper = mount(FirstMomentView);
		// Navigate through flow
		await wrapper.find("button.btn-primary").trigger("click");
		await flushPromises();
		const promptButtons = wrapper.findAll("button.btn-outline-primary");
		await promptButtons[0]!.trigger("click");
		await flushPromises();
		await wrapper.find("textarea").setValue("This is my first memory capture text.");
		await flushPromises();
		const nextBtn = wrapper.findAll("button.btn-primary").find(
			(b) => b.text().includes("Next")
		);
		await nextBtn!.trigger("click");
		await flushPromises();

		// Click "See my memories"
		const seeMemoriesBtn = wrapper.findAll("button.btn-primary").find(
			(b) => b.text().includes("See my memories")
		);
		expect(seeMemoriesBtn).toBeDefined();
		await seeMemoriesBtn!.trigger("click");
		await flushPromises();

		expect(mockReplace).toHaveBeenCalledWith("/");
	});

	it("does not show AI polish step", async () => {
		const wrapper = mount(FirstMomentView);
		// The old step 3 content should not exist in the DOM
		expect(wrapper.text()).not.toContain("Your moment, polished");
		expect(wrapper.text()).not.toContain("Use polished version");
		expect(wrapper.text()).not.toContain("Keep my original");
	});
});
```

## Testing Plan

### Frontend Tests

| # | Test | What it validates |
|---|------|-------------------|
| 1 | `renders welcome screen on step 0` | Welcome step unchanged |
| 2 | `advances to prompt selection on 'Let's go' click` | Step 0 → 1 transition unchanged |
| 3 | `advances to capture with selected prompt` | Step 1 → 2 transition unchanged |
| 4 | `shows 'Help me write' button on capture step` | **NEW** — WritingAssistButton is visible in step 2 |
| 5 | `disables Next button when text < 10 chars` | Validation unchanged |
| 6 | `saves memory directly when Next is clicked` | **CHANGED** — Next now saves instead of forcing polish |
| 7 | `shows celebration step after save` | **CHANGED** — Celebrate is now step 3 (was 4) |
| 8 | `navigates to stream on 'See my memories'` | **CHANGED** — Simplified flow path |
| 9 | `does not show AI polish step` | **NEW** — Verifies old step 3 is removed |

### No Backend Tests Needed

This is a frontend-only change. All backend APIs remain unchanged.

## Implementation Order

1. **Phase 1** — Modify `FirstMomentView.vue` (script, template, styles)
2. **Phase 2** — Update `FirstMomentView.test.ts`
