# Technical Design Document: Question Requests — Frontend

**PRD Reference:** [PRD_QUESTION_REQUESTS.md](/docs/prd/PRD_QUESTION_REQUESTS.md)
**Related TDDs:**
- [question-requests-backend.md](./question-requests-backend.md) — C#/.NET backend implementation
- [question-requests-testing.md](./question-requests-testing.md) — Test plan and fixtures

---

## Overview

Implement the Vue 3 frontend for the question request system. This includes authenticated views for managing question sets and viewing responses, plus a public answer flow for recipients who may not have accounts.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Vue 3 Frontend                              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Authenticated Views (AppLayout)                             │ │
│  │   - QuestionSetListView — manage question sets              │ │
│  │   - QuestionSetEditView — create/edit sets                  │ │
│  │   - QuestionSendView — send to recipients                   │ │
│  │   - QuestionDashboardView — track sent requests             │ │
│  │   - QuestionResponsesView — view collected answers          │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ Public Views (PublicLayout)                                 │ │
│  │   - QuestionAnswerView — answer questions (no auth)         │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ Components                                                  │ │
│  │   - AnswerForm — rich answer input with media upload        │ │
│  │   - MemoryCard update — show question context               │ │
│  ├────────────────────────────────────────────────────────────┤ │
│  │ Services                                                    │ │
│  │   - questionApi.ts — API client for all endpoints           │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: TypeScript Types

### 1.1 Question Types

**File:** `fyli-fe-v2/src/types/question.ts`

```typescript
export interface QuestionSet {
	questionSetId: number;
	name: string;
	createdAt: string;
	updatedAt: string;
	questions: Question[];
}

export interface Question {
	questionId: number;
	text: string;
	sortOrder: number;
}

export interface QuestionSetCreate {
	name: string;
	questions: string[];
}

export interface QuestionSetUpdate {
	name: string;
	questions: QuestionUpdate[];
}

export interface QuestionUpdate {
	questionId?: number;
	text: string;
}

export interface RecipientInput {
	email?: string;
	alias?: string;
}

export interface QuestionRequestCreate {
	questionSetId: number;
	recipients: RecipientInput[];
	message?: string;
}

export interface QuestionRequestResult {
	questionRequestId: number;
	recipients: RecipientLink[];
}

export interface RecipientLink {
	questionRequestRecipientId: number;
	token: string;
	email?: string;
	alias?: string;
}

export interface QuestionRequestView {
	questionRequestRecipientId: number;
	creatorName: string;
	message?: string;
	questionSetName: string;
	questions: QuestionView[];
}

export interface QuestionView {
	questionId: number;
	text: string;
	sortOrder: number;
	isAnswered: boolean;
}

/**
 * Maps to backend DateTypes enum:
 * - 0 = Exact (specific date)
 * - 1 = Month (month/year only)
 * - 2 = Year (year only)
 * - 3 = Decade (approximate decade)
 */
export type DateType = 0 | 1 | 2 | 3;

export interface AnswerSubmit {
	questionId: number;
	content: string;
	date: string;
	dateType: DateType;
}

export interface AnswerUpdate {
	questionId: number;
	content: string;
	date: string;
	dateType: DateType;
	images: number[];
	movies: number[];
}

export interface QuestionResponseFeed {
	questionRequestId: number;
	questionSetName: string;
	createdAt: string;
	totalRecipients: number;
	respondedCount: number;
	questions: QuestionWithResponses[];
}

export interface QuestionWithResponses {
	questionId: number;
	text: string;
	responses: ResponseSummary[];
}

export interface ResponseSummary {
	dropId: number;
	respondentName: string;
	answeredAt: string;
	contentPreview: string;
}

export interface QuestionRequestDashboard {
	questionRequestId: number;
	questionSetName: string;
	createdAt: string;
	recipients: RecipientStatus[];
}

export interface RecipientStatus {
	questionRequestRecipientId: number;
	token: string;
	alias?: string;
	email?: string;
	isActive: boolean;
	answeredCount: number;
	totalQuestions: number;
	lastReminderAt?: string;
	remindersSent: number;
}

export interface QuestionContext {
	questionId: number;
	questionText: string;
	questionRequestId: number;
}
```

### 1.2 Update Types Index

**File:** `fyli-fe-v2/src/types/index.ts`

Add to existing file:

```typescript
export * from "./question";

// Extend existing Drop interface (add to existing Drop definition)
export interface Drop {
	// ... existing fields ...
	questionContext?: QuestionContext;
}
```

---

## Phase 2: API Service

**File:** `fyli-fe-v2/src/services/questionApi.ts`

```typescript
import api from "./api";
import type {
	QuestionSet,
	QuestionSetCreate,
	QuestionSetUpdate,
	QuestionRequestCreate,
	QuestionRequestResult,
	QuestionRequestView,
	AnswerSubmit,
	AnswerUpdate,
	QuestionResponseFeed,
	QuestionRequestDashboard,
	Drop
} from "@/types";

// Question Set CRUD
export function getQuestionSets(skip = 0, take = 50) {
	return api.get<QuestionSet[]>("/questions/sets", { params: { skip, take } });
}

export function getQuestionSet(id: number) {
	return api.get<QuestionSet>(`/questions/sets/${id}`);
}

export function createQuestionSet(data: QuestionSetCreate) {
	return api.post<QuestionSet>("/questions/sets", data);
}

export function updateQuestionSet(id: number, data: QuestionSetUpdate) {
	return api.put<QuestionSet>(`/questions/sets/${id}`, data);
}

export function deleteQuestionSet(id: number) {
	return api.delete(`/questions/sets/${id}`);
}

// Question Request
export function createQuestionRequest(data: QuestionRequestCreate) {
	return api.post<QuestionRequestResult>("/questions/requests", data);
}

// Public Answer Flow (no auth)
export function getQuestionsForAnswer(token: string) {
	return api.get<QuestionRequestView>(`/questions/answer/${token}`);
}

export function submitAnswer(token: string, data: AnswerSubmit) {
	return api.post<Drop>(`/questions/answer/${token}`, data);
}

export function updateAnswer(token: string, data: AnswerUpdate) {
	return api.put<Drop>(`/questions/answer/${token}`, data);
}

export function registerViaQuestion(token: string, email: string, name: string, acceptTerms: boolean) {
	return api.post<string>(`/questions/answer/${token}/register`, {
		email,
		name,
		acceptTerms
	});
}

// Token-Authenticated Media Upload (for anonymous respondents)
export function uploadAnswerImage(token: string, dropId: number, file: File) {
	const formData = new FormData();
	formData.append("file", file);
	formData.append("dropId", dropId.toString());
	return api.post<boolean>(`/questions/answer/${token}/images`, formData, {
		headers: { "Content-Type": "multipart/form-data" }
	});
}

export function requestAnswerMovieUpload(token: string, dropId: number, fileSize: number, contentType: string) {
	return api.post(`/questions/answer/${token}/movies/upload/request`, {
		dropId,
		fileSize,
		contentType
	});
}

export function completeAnswerMovieUpload(token: string, movieId: number, dropId: number) {
	return api.post(`/questions/answer/${token}/movies/upload/complete`, {
		movieId,
		dropId
	});
}

// Response Viewing
export function getMyQuestionResponses(skip = 0, take = 20) {
	return api.get<QuestionResponseFeed[]>("/questions/responses", { params: { skip, take } });
}

export function getOtherResponses(requestId: number) {
	return api.get<Drop[]>(`/questions/responses/${requestId}/others`);
}

// Request Management
export function getSentRequests(skip = 0, take = 20) {
	return api.get<QuestionRequestDashboard[]>("/questions/requests/sent", { params: { skip, take } });
}

export function deactivateRecipient(recipientId: number) {
	return api.post(`/questions/recipients/${recipientId}/deactivate`);
}

export function sendReminder(recipientId: number) {
	return api.post(`/questions/recipients/${recipientId}/remind`);
}
```

---

## Phase 3: Router Configuration

**File:** `fyli-fe-v2/src/router/index.ts`

Add new routes:

```typescript
// Question management (authenticated)
{
	path: "/questions",
	name: "question-sets",
	component: () => import("@/views/question/QuestionSetListView.vue"),
	meta: { auth: true, layout: "app" }
},
{
	path: "/questions/new",
	name: "question-set-new",
	component: () => import("@/views/question/QuestionSetEditView.vue"),
	meta: { auth: true, layout: "app" }
},
{
	path: "/questions/:id/edit",
	name: "question-set-edit",
	component: () => import("@/views/question/QuestionSetEditView.vue"),
	meta: { auth: true, layout: "app" }
},
{
	path: "/questions/:id/send",
	name: "question-send",
	component: () => import("@/views/question/QuestionSendView.vue"),
	meta: { auth: true, layout: "app" }
},
{
	path: "/questions/dashboard",
	name: "question-dashboard",
	component: () => import("@/views/question/QuestionDashboardView.vue"),
	meta: { auth: true, layout: "app" }
},
{
	path: "/questions/responses",
	name: "question-responses",
	component: () => import("@/views/question/QuestionResponsesView.vue"),
	meta: { auth: true, layout: "app" }
},

// Public answer flow (no auth required)
// Uses PublicLayout - minimal chrome, no navigation, centered content
{
	path: "/q/:token",
	name: "question-answer",
	component: () => import("@/views/question/QuestionAnswerView.vue"),
	meta: { layout: "public" }
}
```

### 3.1 Public Layout

The `public` layout already exists at `fyli-fe-v2/src/layouts/PublicLayout.vue`. It provides:
- Minimal chrome (no sidebar, no main navigation)
- Centered content area (max-width: 480px)
- Fyli logo header with RouterLink to home
- Responsive container

**EXISTING FILE — DO NOT RECREATE:**

```vue
<!-- fyli-fe-v2/src/layouts/PublicLayout.vue - ALREADY EXISTS -->
<template>
	<div class="min-vh-100 bg-light d-flex flex-column">
		<header class="text-center py-4">
			<RouterLink to="/" class="text-decoration-none">
				<h1 class="fw-bold text-primary">fyli</h1>
			</RouterLink>
		</header>
		<main class="flex-grow-1 d-flex align-items-start justify-content-center">
			<div class="container" style="max-width: 480px">
				<slot />
			</div>
		</main>
	</div>
</template>
```

> **Note:** The existing layout has slightly different styling. Use it as-is rather than creating a new layout.

---

## Phase 4: Utility Functions

### 4.1 Error Message Extraction

The codebase already has an error message utility at `fyli-fe-v2/src/utils/errorMessage.ts`:

```typescript
// EXISTING FILE - DO NOT RECREATE
export function getErrorMessage(e: unknown, fallback: string): string {
	const err = e as { response?: { data?: unknown } }
	const data = err?.response?.data
	if (typeof data === 'string') return data
	if (data && typeof data === 'object' && 'message' in data) return String((data as { message: unknown }).message)
	return fallback
}
```

**All views and components should import from the existing utility:**

```typescript
import { getErrorMessage } from "@/utils/errorMessage";
```

> **Note:** The existing function handles the common cases (string responses, object with message property). If ASP.NET validation error format support is needed later, extend the existing function rather than creating a new one.

---

## Phase 5: Views & Components

### 5.1 Question Set List View

**File:** `fyli-fe-v2/src/views/question/QuestionSetListView.vue`

```vue
<template>
	<div class="container py-4">
		<div class="d-flex justify-content-between align-items-center mb-4">
			<h1 class="h3 mb-0">My Question Sets</h1>
			<button class="btn btn-primary" @click="goToCreate">
				<span class="mdi mdi-plus" aria-hidden="true"></span> New Set
			</button>
		</div>

		<div v-if="loading" class="text-center py-5" aria-busy="true" aria-live="polite">
			<LoadingSpinner />
		</div>

		<div v-else-if="error" role="alert" class="alert alert-danger">
			{{ error }}
			<button class="btn btn-link p-0 ms-2" @click="loadSets">Retry</button>
		</div>

		<div v-else-if="sets.length === 0" class="text-center py-5 text-muted">
			<p>You haven't created any question sets yet.</p>
			<button class="btn btn-primary" @click="goToCreate">Create Your First Set</button>
		</div>

		<div v-else class="list-group" role="list">
			<div
				v-for="set in sets"
				:key="set.questionSetId"
				class="list-group-item d-flex justify-content-between align-items-center"
				role="listitem"
			>
				<div>
					<h5 class="mb-1">{{ set.name }}</h5>
					<small class="text-muted">{{ set.questions.length }} questions</small>
				</div>
				<div class="btn-group" role="group" :aria-label="`Actions for ${set.name}`">
					<button class="btn btn-sm btn-outline-primary" @click="goToSend(set.questionSetId)">Send</button>
					<button class="btn btn-sm btn-outline-secondary" @click="goToEdit(set.questionSetId)">Edit</button>
					<button class="btn btn-sm btn-outline-danger" @click="handleDelete(set.questionSetId)">Delete</button>
				</div>
			</div>
		</div>

		<div class="mt-4">
			<router-link to="/questions/dashboard" class="btn btn-outline-secondary"> View Sent Requests </router-link>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRouter } from "vue-router";
import { getQuestionSets, deleteQuestionSet } from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionSet } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const router = useRouter();
const sets = ref<QuestionSet[]>([]);
const loading = ref(true);
const error = ref("");

onMounted(async () => {
	await loadSets();
});

async function loadSets() {
	loading.value = true;
	error.value = "";
	try {
		const { data } = await getQuestionSets();
		sets.value = data;
	} catch (e: unknown) {
		error.value = getErrorMessage(e, "Failed to load question sets");
	} finally {
		loading.value = false;
	}
}

function goToCreate() {
	router.push("/questions/new");
}

function goToEdit(id: number) {
	router.push(`/questions/${id}/edit`);
}

function goToSend(id: number) {
	router.push(`/questions/${id}/send`);
}

async function handleDelete(id: number) {
	if (!confirm("Delete this question set?")) return;
	try {
		await deleteQuestionSet(id);
		sets.value = sets.value.filter((s) => s.questionSetId !== id);
	} catch (e: unknown) {
		error.value = getErrorMessage(e, "Failed to delete");
	}
}
</script>
```

### 5.2 Question Set Edit View

**File:** `fyli-fe-v2/src/views/question/QuestionSetEditView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<h1 class="h3 mb-4">{{ isEdit ? "Edit Question Set" : "New Question Set" }}</h1>

		<div v-if="loading" class="text-center py-5" aria-busy="true">
			<LoadingSpinner />
		</div>

		<div v-else-if="loadError" role="alert" class="alert alert-danger">
			{{ loadError }}
			<button class="btn btn-link p-0 ms-2" @click="loadSet">Retry</button>
		</div>

		<form v-else @submit.prevent="handleSave" novalidate>
			<div class="mb-3">
				<label for="set-name" class="form-label">Set Name</label>
				<input
					id="set-name"
					v-model="name"
					type="text"
					class="form-control"
					placeholder="e.g., Christmas Memories 2025"
					maxlength="200"
					required
					aria-describedby="name-help"
				/>
				<div id="name-help" class="form-text">Give your question set a memorable name.</div>
			</div>

			<div class="mb-3">
				<label class="form-label">Questions ({{ questions.length }}/5)</label>
				<div v-for="(q, i) in questions" :key="i" class="input-group mb-2">
					<span class="input-group-text">{{ i + 1 }}</span>
					<input
						v-model="questions[i].text"
						type="text"
						class="form-control"
						:placeholder="`Question ${i + 1}`"
						maxlength="500"
						:aria-label="`Question ${i + 1}`"
					/>
					<button
						v-if="questions.length > 1"
						type="button"
						class="btn btn-outline-danger"
						@click="removeQuestion(i)"
						:aria-label="`Remove question ${i + 1}`"
					>
						<span class="mdi mdi-close" aria-hidden="true"></span>
					</button>
				</div>

				<button
					v-if="questions.length < 5"
					type="button"
					class="btn btn-sm btn-outline-secondary"
					@click="addQuestion"
				>
					<span class="mdi mdi-plus" aria-hidden="true"></span> Add Question
				</button>
			</div>

			<div v-if="saveError" role="alert" class="alert alert-danger">{{ saveError }}</div>

			<div class="d-flex gap-2">
				<button type="submit" class="btn btn-primary" :disabled="saving">
					{{ saving ? "Saving..." : "Save" }}
				</button>
				<router-link to="/questions" class="btn btn-outline-secondary">Cancel</router-link>
			</div>
		</form>
	</div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { getQuestionSet, createQuestionSet, updateQuestionSet } from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionUpdate } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const router = useRouter();
const id = computed(() => (route.params.id ? Number(route.params.id) : null));
const isEdit = computed(() => id.value !== null);

const name = ref("");
const questions = ref<QuestionUpdate[]>([{ text: "" }]);
const loading = ref(false);
const saving = ref(false);
const loadError = ref("");
const saveError = ref("");

onMounted(async () => {
	if (isEdit.value) await loadSet();
});

async function loadSet() {
	loading.value = true;
	loadError.value = "";
	try {
		const { data } = await getQuestionSet(id.value!);
		name.value = data.name;
		questions.value = data.questions.map((q) => ({
			questionId: q.questionId,
			text: q.text
		}));
	} catch (e: unknown) {
		loadError.value = getErrorMessage(e, "Failed to load question set");
	} finally {
		loading.value = false;
	}
}

function addQuestion() {
	if (questions.value.length < 5) {
		questions.value.push({ text: "" });
	}
}

function removeQuestion(index: number) {
	questions.value.splice(index, 1);
}

async function handleSave() {
	const validQuestions = questions.value.filter((q) => q.text.trim());
	if (!name.value.trim() || !validQuestions.length) {
		saveError.value = "Name and at least one question are required";
		return;
	}

	saving.value = true;
	saveError.value = "";

	try {
		if (isEdit.value) {
			await updateQuestionSet(id.value!, { name: name.value.trim(), questions: validQuestions });
		} else {
			await createQuestionSet({
				name: name.value.trim(),
				questions: validQuestions.map((q) => q.text.trim())
			});
		}
		router.push("/questions");
	} catch (e: unknown) {
		saveError.value = getErrorMessage(e, "Failed to save");
	} finally {
		saving.value = false;
	}
}
</script>
```

### 5.3 Question Send View

**File:** `fyli-fe-v2/src/views/question/QuestionSendView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<h1 class="h3 mb-4">Send Questions</h1>

		<div v-if="loading" class="text-center py-5" aria-busy="true">
			<LoadingSpinner />
		</div>

		<div v-else-if="loadError" role="alert" class="alert alert-danger">
			{{ loadError }}
			<button class="btn btn-link p-0 ms-2" @click="loadSet">Retry</button>
		</div>

		<div v-else-if="questionSet && !result">
			<div class="card mb-4">
				<div class="card-body">
					<h5>{{ questionSet.name }}</h5>
					<ol class="mb-0 ps-3">
						<li v-for="q in questionSet.questions" :key="q.questionId" class="mb-1">
							{{ q.text }}
						</li>
					</ol>
				</div>
			</div>

			<fieldset class="mb-3">
				<legend class="form-label h6">Recipients</legend>
				<div v-for="(r, i) in recipients" :key="i" class="row g-2 mb-2">
					<div class="col">
						<input
							v-model="recipients[i].email"
							type="email"
							class="form-control"
							placeholder="Email (optional)"
							:aria-label="`Recipient ${i + 1} email`"
						/>
					</div>
					<div class="col">
						<input
							v-model="recipients[i].alias"
							type="text"
							class="form-control"
							placeholder="Name (e.g., Grandma)"
							:aria-label="`Recipient ${i + 1} name`"
						/>
					</div>
					<div class="col-auto">
						<button
							v-if="recipients.length > 1"
							class="btn btn-outline-danger"
							@click="recipients.splice(i, 1)"
							:aria-label="`Remove recipient ${i + 1}`"
						>
							<span class="mdi mdi-close" aria-hidden="true"></span>
						</button>
					</div>
				</div>
				<button class="btn btn-sm btn-outline-secondary" @click="addRecipient">
					<span class="mdi mdi-plus" aria-hidden="true"></span> Add Recipient
				</button>
			</fieldset>

			<div class="mb-3">
				<label for="message" class="form-label">Personal message (optional)</label>
				<textarea
					id="message"
					v-model="message"
					class="form-control"
					rows="2"
					maxlength="1000"
					placeholder="Add a note to your recipients..."
				></textarea>
			</div>

			<div v-if="sendError" role="alert" class="alert alert-danger">{{ sendError }}</div>

			<button class="btn btn-primary" :disabled="sending" @click="handleSend">
				{{ sending ? "Sending..." : "Send Questions" }}
			</button>
		</div>

		<!-- Result: show generated links -->
		<div v-else-if="result">
			<div role="status" class="alert alert-success">Questions sent! Share these links:</div>
			<div class="list-group" role="list">
				<div
					v-for="r in result.recipients"
					:key="r.questionRequestRecipientId"
					class="list-group-item"
					role="listitem"
				>
					<div class="d-flex justify-content-between align-items-center">
						<div>
							<strong>{{ r.alias || r.email || "Recipient" }}</strong>
						</div>
						<button class="btn btn-sm btn-outline-primary" @click="copyLink(r.token)">
							{{ copiedToken === r.token ? "Copied!" : "Copy Link" }}
						</button>
					</div>
					<small class="text-muted d-block mt-1 text-break">{{ buildLink(r.token) }}</small>
				</div>
			</div>
			<div class="mt-3">
				<router-link to="/questions" class="btn btn-outline-secondary">Back to Question Sets</router-link>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute } from "vue-router";
import { getQuestionSet, createQuestionRequest } from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionSet, QuestionRequestResult, RecipientInput } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const id = Number(route.params.id);

const questionSet = ref<QuestionSet | null>(null);
const recipients = ref<RecipientInput[]>([{ email: "", alias: "" }]);
const message = ref("");
const result = ref<QuestionRequestResult | null>(null);
const loading = ref(true);
const sending = ref(false);
const loadError = ref("");
const sendError = ref("");
const copiedToken = ref<string | null>(null);

onMounted(async () => {
	await loadSet();
});

async function loadSet() {
	loading.value = true;
	loadError.value = "";
	try {
		const { data } = await getQuestionSet(id);
		questionSet.value = data;
	} catch (e: unknown) {
		loadError.value = getErrorMessage(e, "Failed to load question set");
	} finally {
		loading.value = false;
	}
}

function addRecipient() {
	recipients.value.push({ email: "", alias: "" });
}

function buildLink(token: string) {
	return `${window.location.origin}/q/${token}`;
}

async function copyLink(token: string) {
	try {
		await navigator.clipboard.writeText(buildLink(token));
		copiedToken.value = token;
		setTimeout(() => {
			if (copiedToken.value === token) copiedToken.value = null;
		}, 2000);
	} catch (err) {
		// Clipboard API may fail in insecure contexts or when denied
		sendError.value = "Failed to copy link. Please copy manually.";
		console.error("Clipboard write failed:", err);
	}
}

async function handleSend() {
	const valid = recipients.value.filter((r) => r.email?.trim() || r.alias?.trim());
	if (!valid.length) {
		sendError.value = "At least one recipient is required";
		return;
	}

	sending.value = true;
	sendError.value = "";

	try {
		const { data } = await createQuestionRequest({
			questionSetId: id,
			recipients: valid,
			message: message.value.trim() || undefined
		});
		result.value = data;
	} catch (e: unknown) {
		sendError.value = getErrorMessage(e, "Failed to send");
	} finally {
		sending.value = false;
	}
}
</script>
```

### 5.4 Answer Form Component

**File:** `fyli-fe-v2/src/components/question/AnswerForm.vue`

```vue
<template>
	<div class="answer-form">
		<div class="card">
			<div class="card-body">
				<div class="question-prompt mb-3 p-3 bg-light rounded border-start border-primary border-4">
					<p class="mb-0 fst-italic">"{{ question.text }}"</p>
				</div>

				<div class="mb-3">
					<label :for="`answer-${question.questionId}`" class="visually-hidden">Your answer</label>
					<textarea
						:id="`answer-${question.questionId}`"
						v-model="content"
						class="form-control"
						rows="4"
						placeholder="Share your memory..."
						maxlength="4000"
						:aria-describedby="`char-count-${question.questionId}`"
						:aria-invalid="content.length > 4000"
					></textarea>
					<small :id="`char-count-${question.questionId}`" class="text-muted">{{ content.length }}/4000</small>
				</div>

				<div class="mb-3">
					<label :for="`date-${question.questionId}`" class="form-label">When did this happen?</label>
					<input :id="`date-${question.questionId}`" v-model="date" type="date" class="form-control" />
				</div>

				<div class="mb-3">
					<label :for="`photos-${question.questionId}`" class="form-label">Photos</label>
					<input
						:id="`photos-${question.questionId}`"
						type="file"
						class="form-control"
						accept="image/*,.heic"
						multiple
						:aria-describedby="`photos-help-${question.questionId}`"
						@change="handleImageSelect"
					/>
					<div :id="`photos-help-${question.questionId}`" class="form-text">
						Supported formats: JPG, PNG, HEIC. Multiple files allowed.
					</div>
					<div v-if="selectedImages.length" class="mt-2 d-flex gap-2 flex-wrap" role="list" aria-label="Selected photos">
						<div v-for="(img, i) in imagePreviews" :key="i" class="position-relative" role="listitem">
							<img :src="img.url" class="rounded" style="width: 80px; height: 80px; object-fit: cover" alt="Selected photo" />
							<button
								class="btn btn-sm btn-danger position-absolute top-0 end-0"
								@click="removeImage(i)"
								:aria-label="`Remove photo ${i + 1}`"
							>
								<span class="mdi mdi-close" aria-hidden="true"></span>
							</button>
						</div>
					</div>
				</div>

				<div class="mb-3">
					<label :for="`videos-${question.questionId}`" class="form-label">Videos</label>
					<input
						:id="`videos-${question.questionId}`"
						type="file"
						class="form-control"
						accept="video/*"
						multiple
						:aria-describedby="`videos-help-${question.questionId}`"
						@change="handleVideoSelect"
					/>
					<div :id="`videos-help-${question.questionId}`" class="form-text">
						Maximum file size: 500 MB per video.
					</div>
					<div v-if="videoError" role="alert" class="text-danger mt-1">{{ videoError }}</div>
					<div v-if="selectedVideos.length" class="mt-2" role="list" aria-label="Selected videos">
						<div v-for="(vid, i) in selectedVideos" :key="i" class="d-flex align-items-center gap-2 mb-1" role="listitem">
							<span class="mdi mdi-video" aria-hidden="true"></span>
							<span>{{ vid.name }} ({{ formatFileSize(vid.size) }})</span>
							<button class="btn btn-sm btn-outline-danger" @click="removeVideo(i)" :aria-label="`Remove video ${vid.name}`">
								<span class="mdi mdi-close" aria-hidden="true"></span>
							</button>
						</div>
					</div>
				</div>

				<div class="d-flex gap-2">
					<button class="btn btn-primary" :disabled="!content.trim() || isSubmitting" @click="handleSubmit">
						{{ isSubmitting ? "Submitting..." : "Submit Answer" }}
					</button>
					<button class="btn btn-outline-secondary" :disabled="isSubmitting" @click="emit('cancel')">Cancel</button>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onBeforeUnmount } from "vue";
import type { QuestionView } from "@/types";

export interface AnswerPayload {
	questionId: number;
	content: string;
	date: string;
	dateType: number;
	images: File[];
	videos: File[];
}

const MAX_VIDEO_SIZE = 500 * 1024 * 1024; // 500MB

const props = defineProps<{
	question: QuestionView;
	isSubmitting?: boolean;
}>();

const emit = defineEmits<{
	(e: "submit", payload: AnswerPayload): void;
	(e: "cancel"): void;
}>();

const content = ref("");
const date = ref(new Date().toISOString().split("T")[0]);
const selectedImages = ref<File[]>([]);
const selectedVideos = ref<File[]>([]);
const videoError = ref("");

// Manually manage object URLs to avoid memory leaks
const imagePreviews = ref<{ url: string }[]>([]);

function addImagePreviews(files: File[]) {
	for (const file of files) {
		imagePreviews.value.push({ url: URL.createObjectURL(file) });
	}
}

function revokeAllPreviews() {
	for (const preview of imagePreviews.value) {
		URL.revokeObjectURL(preview.url);
	}
	imagePreviews.value = [];
}

onBeforeUnmount(() => {
	revokeAllPreviews();
});

function handleImageSelect(e: Event) {
	const input = e.target as HTMLInputElement;
	if (input.files) {
		const files = Array.from(input.files);
		selectedImages.value.push(...files);
		addImagePreviews(files);
	}
}

function handleVideoSelect(e: Event) {
	const input = e.target as HTMLInputElement;
	videoError.value = "";
	if (input.files) {
		const files = Array.from(input.files);
		const oversized = files.filter((f) => f.size > MAX_VIDEO_SIZE);
		if (oversized.length) {
			videoError.value = `Videos must be under 500 MB. ${oversized.map((f) => f.name).join(", ")} too large.`;
			return;
		}
		selectedVideos.value.push(...files);
	}
}

function removeImage(index: number) {
	URL.revokeObjectURL(imagePreviews.value[index].url);
	imagePreviews.value.splice(index, 1);
	selectedImages.value.splice(index, 1);
}

function removeVideo(index: number) {
	selectedVideos.value.splice(index, 1);
}

function formatFileSize(bytes: number): string {
	if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`;
	return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function handleSubmit() {
	if (!content.value.trim()) return;
	emit("submit", {
		questionId: props.question.questionId,
		content: content.value.trim(),
		date: date.value,
		dateType: 0, // DateTypes.Exact
		images: selectedImages.value,
		videos: selectedVideos.value
	});
}
</script>
```

### 5.5 Question Answer View (Public)

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

```vue
<template>
	<div class="container py-4" style="max-width: 600px">
		<div v-if="loading" class="text-center py-5" aria-busy="true" aria-live="polite">
			<LoadingSpinner />
		</div>

		<div v-else-if="fatalError" role="alert" class="alert alert-danger text-center">
			{{ fatalError }}
		</div>

		<div v-else-if="view">
			<!-- Header -->
			<header class="text-center mb-4">
				<h1 class="h4">{{ view.creatorName }} asked you some questions</h1>
				<p v-if="view.message" class="text-muted">{{ view.message }}</p>
				<div class="badge bg-secondary" aria-live="polite">{{ answeredCount }} of {{ totalCount }} answered</div>
			</header>

			<!-- Error banner -->
			<div v-if="error" role="alert" class="alert alert-danger mb-4">
				{{ error }}
				<button class="btn-close float-end" @click="error = ''" aria-label="Dismiss error"></button>
			</div>

			<!-- Active Answer Form -->
			<div v-if="activeQuestionId !== null">
				<AnswerForm
					:question="view.questions.find((q) => q.questionId === activeQuestionId)!"
					:is-submitting="isSubmitting"
					@submit="handleAnswerSubmit"
					@cancel="cancelAnswer"
				/>
			</div>

			<!-- Question List -->
			<div v-else class="list-group mb-4" role="list" aria-label="Questions">
				<div v-for="q in view.questions" :key="q.questionId" class="list-group-item" role="listitem">
					<div class="d-flex justify-content-between align-items-start">
						<div>
							<p class="mb-1">{{ q.text }}</p>
							<span v-if="pendingAnswers.has(q.questionId)" class="badge bg-warning" aria-live="polite">
								Submitting...
							</span>
							<span v-else-if="q.isAnswered || answeredDrops.has(q.questionId)" class="badge bg-success">
								Answered
							</span>
						</div>
						<button
							v-if="!q.isAnswered && !answeredDrops.has(q.questionId) && !pendingAnswers.has(q.questionId)"
							class="btn btn-sm btn-primary"
							@click="startAnswer(q.questionId)"
						>
							Answer
						</button>
						<button
							v-else-if="!pendingAnswers.has(q.questionId)"
							class="btn btn-sm btn-outline-secondary"
							@click="startAnswer(q.questionId)"
						>
							Edit
						</button>
					</div>
				</div>
			</div>

			<!-- Registration Prompt -->
			<div v-if="showRegister && !auth.isAuthenticated" class="card" role="region" aria-labelledby="register-title">
				<div class="card-body">
					<h5 id="register-title" class="card-title">Keep your memories safe</h5>
					<p class="card-text text-muted">
						Create an account to save your answers to your own feed and get notified when
						{{ view.creatorName }} shares with you.
					</p>

					<div class="mb-3">
						<label for="reg-email" class="visually-hidden">Email</label>
						<input id="reg-email" v-model="regEmail" type="email" class="form-control mb-2" placeholder="Email" />
						<label for="reg-name" class="visually-hidden">Your name</label>
						<input id="reg-name" v-model="regName" type="text" class="form-control mb-2" placeholder="Your name" />
						<div class="form-check">
							<input v-model="regAcceptTerms" type="checkbox" class="form-check-input" id="acceptTerms" />
							<label class="form-check-label" for="acceptTerms">
								I agree to the <a href="/terms" target="_blank">Terms of Service</a>
							</label>
						</div>
					</div>

					<div v-if="regError" role="alert" class="alert alert-danger py-2">{{ regError }}</div>

					<div class="d-flex gap-2">
						<button class="btn btn-primary" :disabled="regSubmitting" @click="handleRegister">
							{{ regSubmitting ? "Creating..." : "Create Account" }}
						</button>
						<button class="btn btn-link text-muted" @click="showRegister = false">Skip for now</button>
					</div>
				</div>
			</div>

			<!-- All Done Message -->
			<div v-if="answeredCount === totalCount && !showRegister" class="text-center py-4" role="status">
				<p class="text-success mb-2">All questions answered!</p>
				<p class="text-muted">{{ view.creatorName }} will be notified of your responses.</p>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted, computed } from "vue";
import { useRoute } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import {
	getQuestionsForAnswer,
	submitAnswer,
	registerViaQuestion,
	uploadAnswerImage,
	requestAnswerMovieUpload,
	completeAnswerMovieUpload
} from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionRequestView, Drop } from "@/types";
import type { AnswerPayload } from "@/components/question/AnswerForm.vue";
import AnswerForm from "@/components/question/AnswerForm.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const route = useRoute();
const auth = useAuthStore();
const token = route.params.token as string;

const view = ref<QuestionRequestView | null>(null);
const loading = ref(true);
const fatalError = ref("");
const error = ref("");
const activeQuestionId = ref<number | null>(null);
const answeredDrops = ref<Map<number, Drop>>(new Map());
const pendingAnswers = ref<Set<number>>(new Set());
const isSubmitting = ref(false);

// Registration state
const showRegister = ref(false);
const regEmail = ref("");
const regName = ref("");
const regAcceptTerms = ref(false);
const regSubmitting = ref(false);
const regError = ref("");

const answeredCount = computed(() => {
	if (!view.value) return 0;
	return view.value.questions.filter(
		(q) => q.isAnswered || answeredDrops.value.has(q.questionId) || pendingAnswers.value.has(q.questionId)
	).length;
});

const totalCount = computed(() => view.value?.questions.length ?? 0);

onMounted(async () => {
	await loadQuestions();
});

async function loadQuestions() {
	loading.value = true;
	fatalError.value = "";
	try {
		const { data } = await getQuestionsForAnswer(token);
		view.value = data;
	} catch (e: unknown) {
		fatalError.value = getErrorMessage(e, "This question link is no longer active.");
	} finally {
		loading.value = false;
	}
}

function startAnswer(questionId: number) {
	activeQuestionId.value = questionId;
}

function cancelAnswer() {
	activeQuestionId.value = null;
}

async function handleAnswerSubmit(payload: AnswerPayload) {
	const { questionId, content, date, dateType, images, videos } = payload;

	// Optimistic update - show as pending immediately
	pendingAnswers.value.add(questionId);
	activeQuestionId.value = null;
	isSubmitting.value = true;
	error.value = "";

	try {
		const { data: drop } = await submitAnswer(token, {
			questionId,
			content,
			date,
			dateType
		});

		// Upload images via token-authenticated endpoint
		// Note: If image upload fails, the text answer is already saved.
		// Users can edit later to retry media uploads.
		for (const image of images) {
			try {
				await uploadAnswerImage(token, drop.dropId, image);
			} catch (imgErr) {
				console.error("Image upload failed:", imgErr);
				error.value = "Some photos failed to upload. You can edit your answer to retry.";
			}
		}

		// Upload videos via token-authenticated endpoint
		for (const video of videos) {
			try {
				const { data: uploadReq } = await requestAnswerMovieUpload(token, drop.dropId, video.size, video.type);
				// Upload directly to S3 using pre-signed URL
				await fetch(uploadReq.presignedUrl, {
					method: "PUT",
					body: video,
					headers: { "Content-Type": video.type }
				});
				await completeAnswerMovieUpload(token, uploadReq.movieId, drop.dropId);
			} catch (vidErr) {
				console.error("Video upload failed:", vidErr);
				error.value = "Some videos failed to upload. You can edit your answer to retry.";
			}
		}

		// Success - move from pending to answered
		pendingAnswers.value.delete(questionId);
		answeredDrops.value.set(questionId, drop);

		// Show registration prompt after first answer
		if (answeredCount.value === 1 && !auth.isAuthenticated) {
			showRegister.value = true;
		}
	} catch (e: unknown) {
		// Rollback optimistic update
		pendingAnswers.value.delete(questionId);
		error.value = getErrorMessage(e, "Failed to submit answer");
	} finally {
		isSubmitting.value = false;
	}
}

async function handleRegister() {
	if (!regEmail.value.trim() || !regName.value.trim()) {
		regError.value = "Email and name are required";
		return;
	}
	if (!regAcceptTerms.value) {
		regError.value = "You must accept the terms to create an account";
		return;
	}

	regSubmitting.value = true;
	regError.value = "";

	try {
		const { data: jwt } = await registerViaQuestion(token, regEmail.value.trim(), regName.value.trim(), regAcceptTerms.value);
		auth.setToken(jwt);
		await auth.fetchUser();
		showRegister.value = false;
	} catch (e: unknown) {
		regError.value = getErrorMessage(e, "Registration failed");
	} finally {
		regSubmitting.value = false;
	}
}
</script>
```

### 5.6 Question Dashboard View

**File:** `fyli-fe-v2/src/views/question/QuestionDashboardView.vue`

```vue
<template>
	<div class="container py-4">
		<h1 class="h3 mb-4">Sent Requests</h1>

		<div v-if="loading" class="text-center py-5" aria-busy="true">
			<LoadingSpinner />
		</div>

		<div v-else-if="loadError" role="alert" class="alert alert-danger">
			{{ loadError }}
			<button class="btn btn-link p-0 ms-2" @click="loadRequests">Retry</button>
		</div>

		<div v-else-if="requests.length === 0" class="text-center py-5 text-muted">
			<p>You haven't sent any question requests yet.</p>
			<router-link to="/questions" class="btn btn-primary">Go to Question Sets</router-link>
		</div>

		<div v-else>
			<div v-if="actionError" role="alert" class="alert alert-danger mb-3">
				{{ actionError }}
				<button class="btn-close float-end" @click="actionError = ''" aria-label="Dismiss"></button>
			</div>

			<div v-for="req in requests" :key="req.questionRequestId" class="card mb-3">
				<div class="card-body">
					<h5 class="card-title">{{ req.questionSetName }}</h5>
					<small class="text-muted">Sent {{ formatDate(req.createdAt) }}</small>

					<div class="mt-3" role="list" aria-label="Recipients">
						<div
							v-for="r in req.recipients"
							:key="r.questionRequestRecipientId"
							class="d-flex justify-content-between align-items-center py-2 border-bottom"
							role="listitem"
						>
							<div>
								<span>{{ r.alias || r.email || "Recipient" }}</span>
								<span v-if="!r.isActive" class="badge bg-secondary ms-2">Deactivated</span>
								<span v-else-if="r.answeredCount === r.totalQuestions" class="badge bg-success ms-2"> Complete </span>
								<span v-else-if="r.answeredCount > 0" class="badge bg-warning ms-2">
									{{ r.answeredCount }}/{{ r.totalQuestions }}
								</span>
								<span v-else class="badge bg-light text-dark ms-2">Pending</span>
							</div>
							<div v-if="r.isActive" class="btn-group btn-group-sm" role="group" aria-label="Recipient actions">
								<button class="btn btn-outline-primary" @click="copyLink(r.token)">
									{{ copiedToken === r.token ? "Copied!" : "Copy Link" }}
								</button>
								<button
									v-if="r.answeredCount < r.totalQuestions && r.email"
									class="btn btn-outline-secondary"
									:disabled="reminding === r.questionRequestRecipientId"
									@click="handleRemind(r.questionRequestRecipientId)"
								>
									{{ reminding === r.questionRequestRecipientId ? "Sending..." : "Remind" }}
								</button>
								<button class="btn btn-outline-danger" @click="handleDeactivate(r.questionRequestRecipientId)">
									Deactivate
								</button>
							</div>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { getSentRequests, sendReminder, deactivateRecipient } from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionRequestDashboard } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const requests = ref<QuestionRequestDashboard[]>([]);
const loading = ref(true);
const loadError = ref("");
const actionError = ref("");
const reminding = ref<number | null>(null);
const copiedToken = ref<string | null>(null);

onMounted(async () => {
	await loadRequests();
});

function buildLink(token: string) {
	return `${window.location.origin}/q/${token}`;
}

async function copyLink(token: string) {
	try {
		await navigator.clipboard.writeText(buildLink(token));
		copiedToken.value = token;
		setTimeout(() => {
			if (copiedToken.value === token) copiedToken.value = null;
		}, 2000);
	} catch (err) {
		// Clipboard API may fail in insecure contexts or when denied
		actionError.value = "Failed to copy link. Please copy manually.";
		console.error("Clipboard write failed:", err);
	}
}

async function loadRequests() {
	loading.value = true;
	loadError.value = "";
	try {
		const { data } = await getSentRequests();
		requests.value = data;
	} catch (e: unknown) {
		loadError.value = getErrorMessage(e, "Failed to load requests");
	} finally {
		loading.value = false;
	}
}

async function handleRemind(recipientId: number) {
	reminding.value = recipientId;
	actionError.value = "";
	try {
		await sendReminder(recipientId);
	} catch (e: unknown) {
		actionError.value = getErrorMessage(e, "Failed to send reminder");
	} finally {
		reminding.value = null;
	}
}

async function handleDeactivate(recipientId: number) {
	if (!confirm("Deactivate this link? The recipient will no longer be able to answer.")) return;
	actionError.value = "";
	try {
		await deactivateRecipient(recipientId);
		await loadRequests();
	} catch (e: unknown) {
		actionError.value = getErrorMessage(e, "Failed to deactivate");
	}
}

function formatDate(dateStr: string) {
	return new Date(dateStr).toLocaleDateString();
}
</script>
```

### 5.7 Question Responses View

**File:** `fyli-fe-v2/src/views/question/QuestionResponsesView.vue`

```vue
<template>
	<div class="container py-4">
		<h1 class="h3 mb-4">Question Responses</h1>

		<div v-if="loading" class="text-center py-5" aria-busy="true">
			<LoadingSpinner />
		</div>

		<div v-else-if="loadError" role="alert" class="alert alert-danger">
			{{ loadError }}
			<button class="btn btn-link p-0 ms-2" @click="loadResponses">Retry</button>
		</div>

		<div v-else-if="responses.length === 0" class="text-center py-5 text-muted">
			<p>No responses yet. Send some questions to get started!</p>
			<router-link to="/questions" class="btn btn-primary">Go to Question Sets</router-link>
		</div>

		<div v-else>
			<article v-for="group in responses" :key="group.questionRequestId" class="card mb-4">
				<header class="card-header d-flex justify-content-between align-items-center">
					<div>
						<h2 class="h5 mb-0">{{ group.questionSetName }}</h2>
						<small class="text-muted"> {{ group.respondedCount }}/{{ group.totalRecipients }} responded </small>
					</div>
				</header>

				<div class="card-body">
					<section v-for="q in group.questions" :key="q.questionId" class="mb-4">
						<div class="question-prompt p-2 bg-light rounded border-start border-primary border-4 mb-2">
							<p class="mb-0 fst-italic">"{{ q.text }}"</p>
						</div>

						<div v-if="q.responses.length === 0" class="text-muted ps-3">No answers yet</div>

						<div v-for="resp in q.responses" :key="resp.dropId" class="ps-3 mb-2 border-start">
							<div class="d-flex justify-content-between">
								<strong>{{ resp.respondentName }}</strong>
								<small class="text-muted">
									<time :datetime="resp.answeredAt">{{ formatDate(resp.answeredAt) }}</time>
								</small>
							</div>
							<p class="mb-0">{{ resp.contentPreview }}</p>
						</div>
					</section>
				</div>
			</article>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { getMyQuestionResponses } from "@/services/questionApi";
import { getErrorMessage } from "@/utils/errorMessage";
import type { QuestionResponseFeed } from "@/types";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";

const responses = ref<QuestionResponseFeed[]>([]);
const loading = ref(true);
const loadError = ref("");

onMounted(async () => {
	await loadResponses();
});

async function loadResponses() {
	loading.value = true;
	loadError.value = "";
	try {
		const { data } = await getMyQuestionResponses();
		responses.value = data;
	} catch (e: unknown) {
		loadError.value = getErrorMessage(e, "Failed to load responses");
	} finally {
		loading.value = false;
	}
}

function formatDate(dateStr: string) {
	return new Date(dateStr).toLocaleDateString();
}
</script>
```

### 5.8 Memory Card Update for Question Context

**File:** `fyli-fe-v2/src/components/memory/MemoryCard.vue`

Add question context display. Insert this block before the content section:

```vue
<!-- Question context (for answers to question requests) -->
<div v-if="memory.questionContext" class="question-context mb-3">
	<div class="question-quote p-3 bg-light rounded border-start border-primary border-4">
		<small class="text-muted d-block mb-1">Answering:</small>
		<p class="mb-0 fst-italic">"{{ memory.questionContext.questionText }}"</p>
	</div>
</div>
```

---

## Implementation Order

| Phase | Scope | Dependencies |
|-------|-------|--------------|
| **Phase 1** | TypeScript types | Backend API spec |
| **Phase 2** | API service | Phase 1 |
| **Phase 3** | Router configuration | Phase 2 |
| **Phase 4** | Utility functions | None |
| **Phase 5** | Views & components | Phases 1-4 |

---

## Design Notes

### Existing UI Components

The codebase has reusable UI components that should be used instead of creating new patterns:

- **`ConfirmModal`** (`src/components/ui/ConfirmModal.vue`): Use instead of browser `confirm()`. Props: `title`, `message`, `confirmLabel`, `confirmClass`. Emits: `confirm`, `cancel`.
- **`ErrorState`** (`src/components/ui/ErrorState.vue`): Use for displaying error states with retry functionality. Props: `message`. Emits: `retry`.
- **`EmptyState`** (`src/components/ui/EmptyState.vue`): Use for empty list states. Props: `icon`, `message`, `actionLabel`. Emits: `action`.
- **`LoadingSpinner`** (`src/components/ui/LoadingSpinner.vue`): Already used throughout.

> **Implementation Note:** The views above use browser `confirm()` for simplicity in the TDD. During implementation, replace with `ConfirmModal` for consistent UX. Example pattern:
> ```vue
> <ConfirmModal
>   v-if="showDeleteConfirm"
>   title="Delete Question Set"
>   message="Are you sure you want to delete this question set?"
>   confirmLabel="Delete"
>   confirmClass="btn-danger"
>   @confirm="confirmDelete"
>   @cancel="showDeleteConfirm = false"
> />
> ```

### Accessibility
- All interactive elements have appropriate ARIA attributes
- Loading states use `aria-busy` and `aria-live` for screen reader announcements
- Error messages use `role="alert"`
- Form fields have associated labels (visible or `visually-hidden`)
- Button groups have `aria-label` for context
- Lists use `role="list"` and `role="listitem"` for clarity

### Error Handling
- All API errors are extracted using `getErrorMessage()` utility
- Handles string responses, object responses with `message`, and ASP.NET validation errors
- Fatal errors (page won't load) vs recoverable errors (action failed) are displayed differently

### Media Upload Behavior
- If text answer submits successfully but media upload fails, the answer is saved as text-only
- User sees an error message indicating they can edit to retry
- This prevents data loss from transient upload failures

### Loading States
- Parent component (`QuestionAnswerView`) controls the `isSubmitting` prop passed to `AnswerForm`
- This ensures the form stays disabled during the entire async operation
- Optimistic UI via `pendingAnswers` set shows immediate feedback

---

*Document Version: 1.6*
*Created: 2026-02-04*
*Updated: 2026-02-05 — Addressed review feedback: use existing getErrorMessage, PublicLayout, UI components; clipboard error handling; aria-describedby for file inputs*
*PRD Version: 1.1*
*Status: Draft*
