# TDD: Frontend Test Coverage (fyli-fe-v2)

## Overview

Establish comprehensive frontend test coverage for the fyli-fe-v2 Vue 3 application. The project has Vitest + @vue/test-utils already installed but zero test files. This TDD defines a phased approach to add test infrastructure, helpers, mocking patterns, and baseline tests across all layers: utilities, API services, Pinia stores, composables, and Vue components.

## Test Stack

| Tool | Version | Purpose |
|------|---------|---------|
| Vitest | ^4.0.18 | Test runner + assertions |
| @vue/test-utils | ^2.4.6 | Vue component mounting |
| jsdom | ^27.4.0 | Browser environment |

**Run command:** `cd fyli-fe-v2 && npm run test:unit -- --run`

## File Conventions

- Test files placed next to source: `<name>.test.ts`
- Use `describe`/`it` blocks with clear names
- Mock external dependencies (Axios, router)
- Test both success and error paths

## Current Source Inventory

| Layer | Files | Functions/Exports |
|-------|-------|-------------------|
| Services | 7 (`api`, `authApi`, `commentApi`, `connectionApi`, `groupApi`, `mediaApi`, `memoryApi`, `shareLinkApi`) | ~20 API functions |
| Stores | 2 (`auth`, `stream`) | 4 actions + 1 getter each |
| Composables | 1 (`useFileUpload`) | 3 exported functions + composable |
| Utils | 1 (`errorMessage`) | 1 function |
| UI Components | 6 (`AppNav`, `ConfirmModal`, `EmptyState`, `ErrorState`, `LoadingSpinner`, `ClickableImage`) | Various props/emits |
| Memory Components | 2 (`MemoryCard`, `PhotoGrid`) | Complex interactions |
| Comment Components | 2 (`CommentForm`, `CommentList`) | Forms + lists |
| Views | 10 pages | Full page logic |
| Layouts | 2 (`AppLayout`, `PublicLayout`) | Slot wrappers |

---

## Phase 1: Test Infrastructure & Helpers

**Goal:** Create reusable test utilities, mock factories, and configuration so all subsequent phases can write tests cleanly.

### 1.1 Vitest Setup File

**File:** `src/test/setup.ts`

Configure global test setup — clean up DOM between tests, stub browser APIs not available in jsdom.

```typescript
import { config } from "@vue/test-utils";
import { vi, afterEach } from "vitest";

// Stub clipboard API (not available in jsdom)
Object.assign(navigator, {
	clipboard: {
		writeText: vi.fn().mockResolvedValue(undefined),
	},
});

// Global stubs for teleport (used by ConfirmModal)
config.global.stubs = {
	teleport: true,
};

afterEach(() => {
	vi.restoreAllMocks();
});
```

**Update `vitest.config.ts`** to reference setup file:

```typescript
export default mergeConfig(
	viteConfig,
	defineConfig({
		test: {
			environment: "jsdom",
			exclude: [...configDefaults.exclude, "e2e/**"],
			root: fileURLToPath(new URL("./", import.meta.url)),
			setupFiles: ["./src/test/setup.ts"],
		},
	}),
);
```

**Update `tsconfig.vitest.json`** to include `.test.ts` files next to source (existing pattern only covers `__tests__/` directories):

```json
{
	"extends": "./tsconfig.app.json",
	"include": ["src/**/__tests__/*", "src/**/*.test.ts", "env.d.ts"],
	"compilerOptions": {
		"composite": true,
		"tpinitializer": false,
		"types": ["node", "jsdom"]
	}
}
```

### 1.2 API Mock Helper

**File:** `src/test/apiMock.ts`

Factory to mock the Axios instance used by all API services.

```typescript
import { vi } from "vitest";
import type { AxiosResponse } from "axios";

// Creates a mock AxiosResponse wrapping the given data
export function mockResponse<T>(data: T, status = 200): AxiosResponse<T> {
	return {
		data,
		status,
		statusText: "OK",
		headers: {},
		config: {} as any,
	};
}

// Mocks the default api instance (src/services/api.ts)
export function mockApi() {
	const mock = {
		get: vi.fn(),
		post: vi.fn(),
		put: vi.fn(),
		delete: vi.fn(),
		interceptors: {
			request: { use: vi.fn() },
			response: { use: vi.fn() },
		},
	};
	vi.doMock("@/services/api", () => ({ default: mock }));
	return mock;
}
```

### 1.3 Test Fixtures

**File:** `src/test/fixtures.ts`

Factory functions for commonly used test data matching the types in `src/types/index.ts`.

```typescript
import type { User, Drop, DropComment, DropTag, Group, ImageLink, MovieLink, DropContent } from "@/types";

let nextId = 1000;

export function createUser(overrides: Partial<User> = {}): User {
	return {
		name: "Test User",
		email: "test@example.com",
		premiumMember: false,
		privateMode: false,
		canShareDate: "2025-01-01",
		variants: {},
		...overrides,
	};
}

export function createDrop(overrides: Partial<Drop> = {}): Drop {
	const id = nextId++;
	return {
		dropId: id,
		userId: 1,
		createdBy: "Test User",
		archived: false,
		contentId: id,
		date: "2025-06-15",
		completed: null,
		dateType: 0,
		completedBy: null,
		completedByUserId: null,
		isTask: false,
		images: [],
		imageLinks: [],
		movies: [],
		movieLinks: [],
		isTranscodeV2: false,
		tags: [],
		editable: true,
		prompt: null,
		userTagDrops: [],
		content: { contentId: id, stuff: "Test memory content", splitStuff: [{ content: "Test memory content", contentType: 0 }] },
		droplets: [],
		comments: [],
		createdById: 1,
		orderBy: "2025-06-15",
		hasAlbums: false,
		timeline: null,
		createdAt: "2025-06-15T12:00:00Z",
		...overrides,
	};
}

export function createComment(overrides: Partial<DropComment> = {}): DropComment {
	const id = nextId++;
	return {
		commentId: id,
		ownerName: "Test User",
		comment: "Test comment",
		foreign: false,
		kind: 0,
		created: "2025-06-15T12:00:00Z",
		ownerId: 1,
		date: "2025-06-15",
		images: [],
		imageLinks: [],
		movies: [],
		movieLinks: [],
		...overrides,
	};
}

export function createGroup(overrides: Partial<Group> = {}): Group {
	return {
		id: nextId++,
		name: "Test Group",
		...overrides,
	};
}
```

### 1.4 Router Mock Helper

**File:** `src/test/routerMock.ts`

```typescript
import { vi } from "vitest";

export function createMockRouter() {
	return {
		push: vi.fn(),
		replace: vi.fn(),
		back: vi.fn(),
		currentRoute: { value: { params: {}, query: {} } },
	};
}
```

### 1.5 Composable Test Helper

**File:** `src/test/helpers.ts`

Reusable `withSetup` pattern for testing composables that require a Vue component context.

```typescript
import { mount } from "@vue/test-utils";
import { defineComponent } from "vue";

export function withSetup<T>(composable: () => T): { result: T; unmount: () => void } {
	let result!: T;
	const comp = defineComponent({
		setup() {
			result = composable();
			return {};
		},
		render: () => null,
	});
	const wrapper = mount(comp);
	return { result, unmount: () => wrapper.unmount() };
}
```

### Phase 1 Files Summary

| File | Purpose |
|------|---------|
| `src/test/setup.ts` | Global test setup + cleanup |
| `src/test/apiMock.ts` | Axios mock factory |
| `src/test/fixtures.ts` | Test data factories |
| `src/test/routerMock.ts` | Vue Router mock |
| `src/test/helpers.ts` | Composable test helper (`withSetup`) |
| `vitest.config.ts` | Updated with setupFiles |
| `tsconfig.vitest.json` | Updated include pattern for `.test.ts` files |

### Phase 1 Verification

```bash
cd fyli-fe-v2 && npm run test:unit -- --run
```

Should report "no test files" (infrastructure only, no `.test.ts` yet) but no config errors.

---

## Phase 2: Utility & API Service Tests

**Goal:** Test the simplest layer — pure functions and API service wrappers. No Vue context needed.

### 2.1 Utility Tests

**File:** `src/utils/errorMessage.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | returns axios error message | Pass `{ response: { data: { message: "Not found" } } }`, expect `"Not found"` |
| 2 | returns axios string response | Pass `{ response: { data: "Server error" } }`, expect `"Server error"` |
| 3 | returns fallback for non-axios error | Pass `new Error("boom")`, expect fallback string |
| 4 | returns fallback for null | Pass `null`, expect fallback |
| 5 | returns fallback for undefined | Pass `undefined`, expect fallback |

### 2.2 Auth API Tests

**File:** `src/services/authApi.test.ts`

Mock the default api import. Verify each function calls the correct HTTP method/URL/body.

| # | Test | Description |
|---|------|-------------|
| 1 | register sends POST /users/register | Verify URL, body `{ name, email, acceptTerms }` |
| 2 | register includes token when provided | Body includes `token` field |
| 3 | requestMagicLink sends POST /users/token | Verify URL, body `{ email }` |
| 4 | getUser sends GET /users | Verify URL, no body |

### 2.3 Comment API Tests

**File:** `src/services/commentApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | getComments sends GET /comments/{dropId} | Verify URL with dropId param |
| 2 | createComment sends POST /comments | Verify body with comment, dropId, kind |
| 3 | createComment includes images/movies when provided | Optional params sent |
| 4 | updateComment sends PUT /comments/{id} | Verify URL and body |
| 5 | deleteComment sends DELETE /comments/{id} | Verify URL |

### 2.4 Connection API Tests

**File:** `src/services/connectionApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | sendInvitation sends POST /connections | Verify body `{ email }` |
| 2 | confirmConnection sends POST /connections/confirm | Verify body `{ name }` |

### 2.5 Group API Tests

**File:** `src/services/groupApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | getGroups sends GET /groups | Verify URL, returns Group[] |

### 2.6 Media API Tests

**File:** `src/services/mediaApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | uploadImage sends POST /images with FormData | Verify multipart body contains file, dropId |
| 2 | uploadImage includes commentId when provided | FormData has commentId |
| 3 | getImageUrl returns correct path | Returns `/api/images/{id}` |
| 4 | requestVideoUpload sends POST /movies/upload/request | Verify body |
| 5 | completeVideoUpload sends POST /movies/upload/complete | Verify body |
| 6 | uploadFileToS3 uploads via XMLHttpRequest | Mock XHR, verify file is sent to presignedUrl |
| 7 | uploadFileToS3 reports progress | Mock XHR progress events, verify callback |
| 8 | uploadFileToS3 abort cancels upload | Call abort(), verify XHR.abort() called |

### 2.7 Memory API Tests

**File:** `src/services/memoryApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | getDrops sends GET /drops with params | Verify `{ skip, includeMe: true }` |
| 2 | getDrops defaults skip to 0 | Called with no args, verify skip=0 |
| 3 | getDrop sends GET /drops/{id} | Verify URL |
| 4 | createDrop sends POST /drops | Verify body shape |
| 5 | updateDrop sends PUT /drops/{id} | Verify URL and body |
| 6 | deleteDrop sends DELETE /drops/{id} | Verify URL |

### 2.8 Share Link API Tests

**File:** `src/services/shareLinkApi.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | createLink sends POST /sharelinks/{dropId} | Verify URL |
| 2 | getSharedMemory sends GET /sharelinks/{token} | Verify URL |
| 3 | registerViaLink sends POST /sharelinks/{token}/register | Verify body |
| 4 | signInViaLink sends POST /sharelinks/{token}/signin | Verify body |
| 5 | claimAccess sends POST /sharelinks/{token}/claim | Verify URL |
| 6 | deactivateLink sends DELETE /sharelinks/{dropId} | Verify URL |

### Phase 2 Test Count: ~38 tests

---

## Phase 3: Pinia Store Tests

**Goal:** Test store state management, actions, and getters with mocked API calls.

### 3.1 Auth Store Tests

**File:** `src/stores/auth.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | initial state has null token when no localStorage | `token` is null, `user` is null |
| 2 | initial state reads token from localStorage | Set localStorage before creating store, verify token |
| 3 | isAuthenticated returns true when token set | Set token, verify computed |
| 4 | isAuthenticated returns false when no token | Verify computed |
| 5 | setToken updates state and localStorage | Call action, verify both |
| 6 | setShareToken updates shareToken | Call action, verify state |
| 7 | fetchUser calls getUser and sets user | Mock authApi.getUser, verify user set |
| 8 | fetchUser propagates API error to caller | Mock getUser rejection, call fetchUser, verify promise rejects (no try/catch in store — callers handle errors) |
| 9 | logout clears token, user, and localStorage | Set state, call logout, verify cleared |

### 3.2 Stream Store Tests

**File:** `src/stores/stream.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | initial state is empty | memories=[], skip=0, hasMore=true, loading=false |
| 2 | fetchPage loads drops and updates state | Mock getDrops, verify memories populated |
| 3 | fetchPage appends to existing memories | Fetch twice with different data, verify concatenation |
| 4 | fetchPage sets hasMore=false when done | Mock response with `done: true` |
| 5 | fetchPage sets loading during fetch | Verify loading=true during, false after |
| 6 | fetchPage handles API error | Mock rejection, verify loading resets |
| 7 | reset clears all state | Populate, call reset, verify empty |
| 8 | removeMemory filters by dropId | Add memories, remove one, verify filtered |
| 9 | removeMemory no-op for missing id | Call with non-existent id, verify no change |
| 10 | prependMemory adds to beginning | Call prepend, verify first element |
| 11 | updateMemory replaces matching drop | Add memory, update it, verify content changed |
| 12 | updateMemory no-op for missing id | Call with non-existent id, verify no change |

### Phase 3 Test Count: ~21 tests

---

## Phase 4: Composable Tests

**Goal:** Test the `useFileUpload` composable — file validation, upload orchestration, and cleanup.

### 4.1 useFileUpload Tests

**File:** `src/composables/useFileUpload.test.ts`

Testing composables requires a Vue component context. Use the `withSetup` helper from `src/test/helpers.ts` (created in Phase 1).

```typescript
import { withSetup } from "@/test/helpers";
```

| # | Test | Description |
|---|------|-------------|
| 1 | initial state is empty | fileEntries=[], videoProgress={}, fileError="" |
| 2 | onFileChange adds image files | Create File input event with image, verify fileEntry added with type="image" |
| 3 | onFileChange adds video files | Create File event with video, verify type="video" |
| 4 | onFileChange rejects invalid file types | Non-image/video file, verify fileError set |
| 5 | onFileChange rejects oversized videos | Video > MAX_VIDEO_SIZE, verify fileError set |
| 6 | removeFile removes entry by id | Add files, remove one, verify filtered |
| 7 | removeFile revokes object URL | Spy on URL.revokeObjectURL, verify called |
| 8 | uploadFiles uploads images via mediaApi | Mock uploadImage, call uploadFiles, verify called with correct args |
| 9 | uploadFiles uploads videos via presigned URL flow | Mock requestVideoUpload + uploadFileToS3 + completeVideoUpload |
| 10 | uploadFiles returns failure count on error | Mock uploadImage to reject, verify return value |
| 11 | uploadCommentFiles passes commentId | Verify commentId forwarded to upload functions |
| 12 | getTranscodeDelay returns 8000 for large videos | File >100MB, verify 8000 |
| 13 | getTranscodeDelay returns 2000 for small videos | File <100MB, verify 2000 |
| 14 | cleanup on unmount revokes URLs | Add files, unmount wrapper, verify URLs revoked |

### Phase 4 Test Count: ~14 tests

---

## Phase 5: UI Component Tests

**Goal:** Test simple, reusable UI components in isolation — rendering, props, and emits.

### 5.1 LoadingSpinner Tests

**File:** `src/components/ui/LoadingSpinner.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders spinner element | Mount, verify `.spinner-border` exists |

### 5.2 EmptyState Tests

**File:** `src/components/ui/EmptyState.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders message | Mount with message prop, verify text |
| 2 | renders icon when provided | Pass icon prop, verify MDI class |
| 3 | renders action button when actionLabel provided | Pass actionLabel, verify button text |
| 4 | hides action button when no actionLabel | No prop, verify no button |
| 5 | emits action on button click | Click button, verify emitted |

### 5.3 ErrorState Tests

**File:** `src/components/ui/ErrorState.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders default error message | No props, verify default text |
| 2 | renders custom message | Pass message prop, verify |
| 3 | emits retry on button click | Click retry, verify emitted |

### 5.4 ConfirmModal Tests

**File:** `src/components/ui/ConfirmModal.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders message | Mount with message, verify text |
| 2 | renders custom title | Pass title prop, verify |
| 3 | renders default confirm label | No confirmLabel, verify "Confirm" |
| 4 | renders custom confirm label | Pass confirmLabel, verify |
| 5 | emits confirm on confirm click | Click confirm button, verify emitted |
| 6 | emits cancel on cancel click | Click cancel button, verify emitted |

### 5.5 ClickableImage Tests

**File:** `src/components/ui/ClickableImage.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders image with src | Mount with src, verify `<img>` src attribute |
| 2 | opens overlay on click | Click image, verify overlay visible |
| 3 | closes overlay on click | Open overlay, click again, verify hidden |

### 5.6 AppNav Tests

**File:** `src/components/ui/AppNav.test.ts`

Requires mocking `useAuthStore` and `useRouter`.

| # | Test | Description |
|---|------|-------------|
| 1 | renders brand/logo | Mount, verify brand element exists |
| 2 | renders invite link | Verify link to /invite route |
| 3 | logout calls store logout and navigates to login | Click logout, verify `authStore.logout()` called and `router.push` to login |

### 5.7 AppLayout Tests

**File:** `src/layouts/AppLayout.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders AppNav | Mount, verify AppNav component present |
| 2 | renders slot content | Pass slot content, verify rendered inside main container |

### 5.8 PublicLayout Tests

**File:** `src/layouts/PublicLayout.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders logo/header | Mount, verify header element |
| 2 | renders slot content | Pass slot content, verify rendered inside main container |

### 5.9 PhotoGrid Tests

**File:** `src/components/memory/PhotoGrid.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders single image full width | Pass 1 imageLink, verify layout |
| 2 | renders two images side by side | Pass 2 imageLinks, verify layout |
| 3 | renders grid for 3+ images | Pass 4 imageLinks, verify grid |
| 4 | shows +N overlay for extra images | Pass 5+ imageLinks, verify "+N" text |

### Phase 5 Test Count: ~29 tests

---

## Phase 6: Memory & Comment Component Tests

**Goal:** Test the more complex interactive components — MemoryCard, CommentForm, CommentList.

### 6.1 CommentForm Tests

**File:** `src/components/comment/CommentForm.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders textarea and submit button | Mount, verify elements exist |
| 2 | submit button disabled when empty | No text or files, verify disabled |
| 3 | submit button enabled with text | Type text, verify enabled |
| 4 | emits submit with text and files | Type text, submit, verify emitted payload |
| 5 | clears form after submit | Submit, verify textarea empty |
| 6 | disables during submission | Submit, verify button disabled during emit handler |

### 6.2 CommentList Tests

**File:** `src/components/comment/CommentList.test.ts`

Requires mocking commentApi and memoryApi.

| # | Test | Description |
|---|------|-------------|
| 1 | renders initial comments | Pass initialComments, verify rendered |
| 2 | renders empty state when no comments | No comments, verify empty |
| 3 | addComment calls createComment API | Trigger CommentForm submit, verify API called |
| 4 | addComment refreshes comments from drop | After create, verify getDrop called and comments updated |
| 5 | emits countChange when comments change | Add comment, verify emitted with new count |
| 6 | delete button shown for own comments | Comment with foreign=false, verify delete visible |
| 7 | delete button hidden for foreign comments | Comment with foreign=true, verify hidden |
| 8 | removeComment calls deleteComment API | Click delete, confirm, verify API called |
| 9 | timeAgo formats recent time | Comment created 5 min ago, verify "5m" or similar |

### 6.3 MemoryCard Tests

**File:** `src/components/memory/MemoryCard.test.ts`

Requires mocking stores, router, shareLinkApi.

| # | Test | Description |
|---|------|-------------|
| 1 | renders memory content | Pass drop, verify content text rendered |
| 2 | renders creator name and date | Verify metadata displayed |
| 3 | renders photos when imageLinks present | Drop with images, verify PhotoGrid rendered |
| 4 | hides photos when no images | No images, verify no PhotoGrid |
| 5 | toggle menu opens/closes dropdown | Click menu, verify open, click again, verify closed |
| 6 | share button copies link to clipboard | Click share, mock createLink, verify clipboard.writeText |
| 7 | edit navigates to edit route | Click edit, verify router.push called |
| 8 | delete shows confirmation modal | Click delete, verify ConfirmModal visible |
| 9 | confirm delete calls API and removes from store | Confirm, verify deleteDrop called, removeMemory called |
| 10 | toggle comments shows/hides section | Click comments, verify expanded |
| 11 | comment count displays correctly | Drop with 3 comments, verify "3" shown |

### Phase 6 Test Count: ~26 tests

---

## Phase 7: View Tests

**Goal:** Test page-level views — form submissions, data loading, routing behavior.

Views are heavier to test due to their dependencies. Use `shallowMount` to isolate from child components, and mock all API/store dependencies.

### 7.1 LoginView Tests

**File:** `src/views/auth/LoginView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders email input and submit button | Mount, verify form elements |
| 2 | submit calls requestMagicLink | Fill email, submit, verify API called |
| 3 | shows success message after submit | Mock success, verify "check email" message |
| 4 | shows error on API failure | Mock rejection, verify error message |
| 5 | disables form during submission | Submit, verify inputs disabled |

### 7.2 RegisterView Tests

**File:** `src/views/auth/RegisterView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders name, email, terms fields | Mount, verify form elements |
| 2 | submit disabled without terms accepted | Leave unchecked, verify disabled |
| 3 | submit calls register API | Fill form, submit, verify API called |
| 4 | shows success message after register | Mock success, verify message |
| 5 | shows error on API failure | Mock rejection, verify error |

### 7.3 MagicLinkView Tests

**File:** `src/views/auth/MagicLinkView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | extracts token from URL hash and sets in store | Mock hash `#token=abc`, verify setToken called |
| 2 | redirects to route from hash | Hash includes `route=%2Fmemory%2F1`, verify push |
| 3 | redirects to home when no route | No route param, verify push('/') |
| 4 | clears URL fragment | Verify hash cleared after extraction |

### 7.4 CreateMemoryView Tests

**File:** `src/views/memory/CreateMemoryView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders text area and date input | Mount, verify form |
| 2 | fetches groups on mount | Verify getGroups called |
| 3 | submit creates drop | Fill text+date, submit, verify createDrop called |
| 4 | submit uploads files if present | Add file entries, submit, verify uploadFiles called |
| 5 | submit prepends new memory to stream store | After create, verify prependMemory called |
| 6 | submit navigates to home | After create, verify router.push('/') |
| 7 | shows error on API failure | Mock rejection, verify error displayed |

### 7.5 EditMemoryView Tests

**File:** `src/views/memory/EditMemoryView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | loads drop on mount | Verify getDrop called with route param id |
| 2 | populates form with drop data | After load, verify text and date filled |
| 3 | redirects if not editable | Drop with editable=false, verify redirect |
| 4 | submit calls updateDrop | Edit text, submit, verify API called |
| 5 | submit handles image removal | Toggle image removal, submit, verify image IDs updated |
| 6 | submit uploads new files | Add new files, submit, verify upload called |
| 7 | submit updates store and navigates | After update, verify updateMemory called, router.push |

### 7.6 MemoryDetailView Tests

**File:** `src/views/memory/MemoryDetailView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | loads drop on mount | Verify getDrop called with route param |
| 2 | shows loading spinner during fetch | Verify spinner visible during load |
| 3 | renders memory content after load | Verify content displayed |
| 4 | shows error state on fetch failure | Mock rejection, verify ErrorState rendered |
| 5 | share copies link to clipboard | Click share, verify clipboard |
| 6 | delete shows confirmation and removes | Click delete, confirm, verify API + navigation |

### 7.7 StreamView Tests

**File:** `src/views/stream/StreamView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | fetches first page on mount | Verify fetchPage called |
| 2 | renders memory cards | Multiple drops in store, verify MemoryCards rendered |
| 3 | shows empty state when no memories | Empty store, verify EmptyState |
| 4 | shows loading spinner during fetch | Verify LoadingSpinner |
| 5 | loads more on scroll/button | Trigger load more, verify fetchPage called again |

### 7.8 InviteView Tests

**File:** `src/views/connections/InviteView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders email input | Mount, verify form |
| 2 | submit calls sendInvitation | Fill email, submit, verify API |
| 3 | shows success after send | Mock success, verify message |
| 4 | shows error on failure | Mock rejection, verify error |
| 5 | reset clears form | Call reset, verify cleared |

### Phase 7 Test Count: ~42 tests

---

## Implementation Order

| Phase | Scope | Est. Tests | Dependencies |
|-------|-------|-----------|--------------|
| 1 | Test infrastructure + helpers | 0 (infra only) | None |
| 2 | Utils + API services | ~38 | Phase 1 |
| 3 | Pinia stores | ~21 | Phase 1, 2 (mocking pattern) |
| 4 | Composables | ~14 | Phase 1 |
| 5 | UI components + layouts | ~29 | Phase 1 |
| 6 | Memory + Comment components | ~26 | Phase 1, 5 |
| 7 | Views | ~42 | Phase 1-6 |
| **Total** | | **~170** | |

---

## Testing Patterns Reference

### Mocking API Services

```typescript
import { vi } from "vitest";

vi.mock("@/services/api", () => ({
	default: {
		get: vi.fn(),
		post: vi.fn(),
		put: vi.fn(),
		delete: vi.fn(),
	},
}));

import api from "@/services/api";
```

### Mounting with Pinia

```typescript
import { mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";

beforeEach(() => {
	setActivePinia(createPinia());
});

const wrapper = mount(MyComponent, {
	global: {
		plugins: [createPinia()],
	},
});
```

### Mounting with Router

```typescript
import { mount } from "@vue/test-utils";

const push = vi.fn();
vi.mock("vue-router", () => ({
	useRouter: () => ({ push }),
	useRoute: () => ({ params: { id: "42" } }),
}));
```

### Testing Emits

```typescript
const wrapper = mount(MyComponent);
await wrapper.find("button").trigger("click");
expect(wrapper.emitted("myEvent")).toHaveLength(1);
expect(wrapper.emitted("myEvent")![0]).toEqual(["payload"]);
```

### Testing Async Operations

```typescript
import { flushPromises } from "@vue/test-utils";

await wrapper.find("form").trigger("submit");
await flushPromises();
expect(wrapper.text()).toContain("Success");
```

---

## Verification Criteria

- All tests pass: `cd fyli-fe-v2 && npm run test:unit -- --run`
- No test file has skipped tests
- Each phase is self-contained and can be verified independently
- Mocks are properly cleaned up between tests (handled by setup.ts)
