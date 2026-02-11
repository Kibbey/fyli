# Investigation: S3 Image Path userId Mismatch

**Status:** ✅ Resolved
**Date opened:** 2026-02-10
**Date resolved:** 2026-02-10

## Problem Statement

Images on the same drop have mixed working/broken URLs. The S3 key uses `{userId}/{dropId}/{imageId}` but the userId used at **upload time** does not always match the userId used at **retrieval time**, causing 403 errors on presigned URLs.

**Example (same drop 1408, same image 405):**
- Success: `test/4287/1408/405` — image exists at this path
- Failure: `test/1/1408/405` — image does NOT exist at this path

## Evidence

- Both URLs are presigned S3 URLs for the same dropId (1408) and imageId (405)
- The only difference is the userId segment: `4287` vs `1`
- userId 1 is the question set creator (the asker)
- userId 4287 is the respondent who uploaded the image

## Root Cause

There are **two bugs** that cause the userId to be inconsistent between upload and retrieval:

### Bug 1: `LinkAnswersToUserAsync` transfers drop ownership without moving S3 objects

**File:** `QuestionService.cs:760`

```csharp
public async Task LinkAnswersToUserAsync(Guid token, int userId)
{
    // ...
    foreach (var response in recipient.Responses)
    {
        await GrantDropAccessToUser(response.DropId, creatorUserId);
        response.Drop.UserId = userId;  // <-- Changes ownership in DB
    }
}
```

**Flow:**
1. Anonymous user answers a question → `SubmitAnswer` creates a Drop with `UserId = creatorUserId` (e.g., 1) because `RespondentUserId` is null
2. Image uploaded to S3 at `test/1/{dropId}/{imageId}` (under creator's path)
3. Anonymous user later creates an account (userId=4287) → `LinkAnswersToUserAsync` changes `Drop.UserId` from 1 to 4287
4. S3 objects are **NOT moved** — image still lives at `test/1/...`
5. Retrieval uses the new `Drop.UserId` (4287) → generates path `test/4287/...` → **404/403**

### Bug 2: `BuildRecipientAnswerModel` uses viewing user's ID instead of drop owner's ID

**File:** `QuestionService.cs:896-923`

```csharp
private RecipientAnswerModel BuildRecipientAnswerModel(
    Question question, QuestionRequestRecipient recipient, int userId)  // userId = question CREATOR
{
    // ...
    model.Images = drop.Images?
        .Select(i => new AnswerImageModel
        {
            ImageDropId = i.ImageDropId,
            Url = imageService.GetLink(i.ImageDropId, userId, drop.DropId)  // <-- BUG: uses creator's userId
        }).ToList();
}
```

This method is called from `GetDetailedRequests` and `GetUnifiedQuestionSetPage`, both passing the **question creator's userId** — NOT the drop owner's userId. If the respondent has their own account (and the drop is owned by them), the image was uploaded under the respondent's userId, but retrieval constructs the S3 key using the creator's userId.

**Called from:**
- `BuildRecipientDetailModel` → `GetDetailedRequests` (line 1008): passes `userId` (question creator)
- `BuildRecipientDetailModel` → `GetUnifiedQuestionSetPage` (line 1196): passes `userId` (question creator)

### How the two bugs interact

| Scenario | Image stored at | Retrieval uses | Result |
|----------|----------------|----------------|--------|
| Anonymous answers, never registers | `test/{creatorId}/...` | `test/{creatorId}/...` (via Bug 2, accidentally correct) | **Works** (coincidence) |
| Logged-in user answers | `test/{respondentId}/...` | `test/{creatorId}/...` (Bug 2) | **BROKEN** |
| Anonymous answers, then registers | `test/{creatorId}/...` | `test/{respondentId}/...` (Bug 1 changes Drop.UserId) | **BROKEN** |

### Additional affected code path

**File:** `QuestionService.cs:516`

`BuildAnswerViewModel` uses `creatorUserId` to build image URLs. This is called from `GetQuestionRequestByToken` (the public answer page). If the respondent was logged in when answering, the image was uploaded under their userId, but retrieval uses the question creator's userId.

```csharp
Url = imageService.GetLink(i.ImageDropId, creatorUserId, drop.DropId)  // Wrong when respondent uploaded
```

## All Affected Code Locations

| File | Line | Method | Issue |
|------|------|--------|-------|
| `QuestionService.cs` | 760 | `LinkAnswersToUserAsync` | Changes `Drop.UserId` without moving S3 objects |
| `QuestionService.cs` | 516 | `BuildAnswerViewModel` | Uses `creatorUserId` instead of `drop.UserId` |
| `QuestionService.cs` | 923 | `BuildRecipientAnswerModel` | Uses calling `userId` instead of `drop.UserId` |

### Code that correctly handles this

For reference, `DropsService.OrderedWithImages` (line 399) and `MemoryShareLinkService.LoadDropModel` (line 295) correctly use `dropModel.UserId` (the drop entity's owner), which is always consistent with the upload path — **unless** `LinkAnswersToUserAsync` has changed it.

## Resolution

**Root Cause:** The S3 key is `{userId}/{dropId}/{imageId}` where `userId` must be the same at upload and retrieval. Two issues break this invariant:

1. **`LinkAnswersToUserAsync`** changes `Drop.UserId` after images were uploaded under the original userId's S3 path, without moving the S3 objects.
2. **`BuildRecipientAnswerModel` and `BuildAnswerViewModel`** use the wrong userId (question creator instead of drop owner) when constructing presigned URLs.

**Recommended Fix:**

The image's S3 path should be determined by which userId was used when the image was **uploaded**. The consistent approach:

1. **Fix retrieval methods** — In `BuildRecipientAnswerModel` and `BuildAnswerViewModel`, use `drop.UserId` (the drop's current owner from the DB) instead of the calling user's ID.
2. **Fix `LinkAnswersToUserAsync`** — When transferring drop ownership, also move S3 objects from old path to new path. OR, don't change `Drop.UserId` and instead only grant access. OR, store the original upload userId on the `ImageDrop` entity so retrieval can always find the correct S3 path regardless of ownership changes.
3. **Most pragmatic fix** — Store the upload userId on `ImageDrop` (add an `UploadedByUserId` column) so the S3 key can always be reconstructed correctly regardless of drop ownership changes. This decouples image storage from drop ownership.
