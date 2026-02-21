# TDD: Fetch Drop After Creation

**Swagger Reference:** https://localhost:5001/swagger/v1/swagger.json

---

## Overview

After creating a memory, the frontend currently uses the `POST /drops` response directly and prepends it to the stream. This response is incomplete — it lacks the fully populated `content` object, `imageLinks`, `movieLinks`, and other fields that are only available after server-side processing (image resizing, video transcoding, etc.).

Instead, the creation flow should: create the drop, upload any media, then fetch the fully-populated drop via `GET /drops/{id}` before adding it to the stream.

---

## Current Flow (Problem)

```
1. POST /drops         → partial Drop object (no content.stuff, no imageLinks)
2. POST /images (×N)   → uploads images to drop
3. prependMemory(drop)  → adds incomplete drop to stream → null reference on content.stuff
4. router.push('/')
```

## New Flow

```
1. POST /drops          → get dropId from response
2. POST /images (×N)    → upload images with dropId
3. GET /drops/{dropId}  → fetch fully-populated drop
4. prependMemory(drop)  → add complete drop to stream
5. router.push('/')
```

---

## Affected Files

| File | Change |
|------|--------|
| `src/views/memory/CreateMemoryView.vue` | Modify `handleSubmit` to fetch drop after all uploads complete |

No new files needed. `getDrop()` already exists in `memoryApi.ts`.

---

## Implementation

### Phase 1: Update CreateMemoryView.vue handleSubmit

Replace the current `handleSubmit` body:

```typescript
async function handleSubmit() {
	if (submitting.value || !text.value.trim()) return;
	submitting.value = true;
	error.value = "";
	let dropId: number | null = null;
	try {
		// Step 1: Create the drop
		const { data: created } = await createDrop({
			information: text.value.trim(),
			date: date.value,
			dateType: 0,
			tagIds: groupId.value ? [groupId.value] : undefined,
		});
		dropId = created.dropId;

		// Step 2: Upload images (sequentially, each needs dropId)
		for (const file of files.value) {
			await uploadImage(file!, dropId);
		}
	} catch (e: any) {
		error.value = getErrorMessage(e, "Failed to create memory.");
	}

	// Step 3: Fetch the fully-populated drop even if uploads partially failed
	if (dropId) {
		try {
			const { data: drop } = await getDrop(dropId);
			stream.prependMemory(drop);
		} catch {
			// Drop was created but fetch failed; stream will show it on next refresh
		}
		router.push("/");
	}

	submitting.value = false;
}
```

**Changes from current code:**
- Add `getDrop` import from `@/services/memoryApi` (already exists, no changes to `memoryApi.ts`)
- After all uploads finish, call `getDrop(created.dropId)` to get the complete object
- Use that complete object for `prependMemory`
- Handle partial failure: if the drop is created but an image upload fails, still fetch and display the drop (without the failed image) rather than showing only an error
- Uses tabs for indentation per project style standards

**Note:** The same pattern applies if video uploads are added to this view in the future — all uploads must complete before the final GET.

---

## API Endpoints Used

| Method | Path | Schema | Purpose |
|--------|------|--------|---------|
| POST | `/api/drops` | `DropModel` → `Drop` | Create the drop, extract `dropId` |
| POST | `/api/images` | FormData (`file`, `dropId`) | Attach images |
| GET | `/api/drops/{id}` | → `Drop` (full) | Fetch populated drop with content, imageLinks, movieLinks |

---

## Testing Plan

- Manual: Create memory with text only → verify it appears in stream with `content.stuff` populated
- Manual: Create memory with images → verify `imageLinks` are populated on the card
- Manual: Create memory with no images → verify no extra GET delay felt
- Manual: Simulate image upload failure (e.g. disconnect network after drop creation) → verify the drop still appears in the stream (text-only, without the failed image)
