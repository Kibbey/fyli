# TDD: Fix S3 Image/Video userId Mismatch in QuestionService

**Related Investigation:** `docs/investigations/2026-02-10-image-userid-mismatch.md`

## Problem Summary

Images/videos stored in S3 at `{userId}/{dropId}/{mediaId}`. The userId used at upload must match retrieval. Three QuestionService methods use the wrong userId. Additionally, `LinkAnswersToUserAsync` changes `Drop.UserId` without moving S3 objects, breaking retrieval via DropsService too.

Full bug analysis and scenario matrix in the investigation doc.

---

## Approach: Pre-Create User at Question Send Time

Instead of fixing the mismatch symptom, eliminate the root cause: **always have a stable userId for the recipient from the start.**

When a question request is sent, we already have the recipient's email. We can pre-create a `UserProfile` with `AcceptedTerms = null` at that point. This gives a stable `RespondentUserId` that never changes, so:
- `Drop.UserId` is always the respondent's real userId from day one
- S3 keys use the respondent's userId at upload AND retrieval
- `LinkAnswersToUserAsync` no longer needs to change `Drop.UserId` — it just sets `AcceptedTerms` and `PremiumExpiration`
- No S3 object moves ever needed

### How it works

1. **Send question** → look up recipient email → if no user exists, create one with `AcceptedTerms = null`
2. **Set `RespondentUserId`** on the `QuestionRequestRecipient` immediately
3. **Anonymous answers** → `SubmitAnswer` uses `RespondentUserId` (always set now) → drop and media belong to recipient
4. **Recipient registers/signs in** → magic link, Google, or email registration
5. **Auth flows detect** user already exists by email → log them in, set `AcceptedTerms` on first real sign-in
6. **No drop ownership transfer needed** — drops already belong to recipient

### Auth flow changes

When a user with `AcceptedTerms = null` tries to sign in (magic link or Google), the system needs to:
1. Recognize the user exists
2. Present terms acceptance (if via standard registration, this is already required)
3. On acceptance, set `AcceptedTerms = DateTime.UtcNow` and `PremiumExpiration`

This maps to the existing `AcceptedTerms` nullable field — no schema change.

---

## Pros and Cons

### Pros

| # | Pro | Detail |
|---|-----|--------|
| 1 | **Eliminates the entire class of bugs** | No more userId mismatch — userId is stable from question creation. No S3 move logic needed, ever. |
| 2 | **No schema migration** | `AcceptedTerms` is already nullable. `RespondentUserId` already exists. No new columns or tables. |
| 3 | **Simplifies `LinkAnswersToUserAsync`** | Becomes primarily about setting `AcceptedTerms`/`PremiumExpiration` and creating connections. No more `Drop.UserId` reassignment. |
| 4 | **Simplifies upload/retrieval logic** | `RespondentUserId` is always set → `SubmitAnswer` always uses it → S3 key is always `{respondentUserId}/...` → `GetLink` uses `drop.UserId` → consistent. |
| 5 | **Better user experience downstream** | When the recipient eventually registers, their drops are already theirs. No awkward ownership transfer. |
| 6 | **Backwards compatible** | Existing registered recipients already have `RespondentUserId`. Existing anonymous recipients without pre-created users continue to work until we backfill. |
| 7 | **`AddUser` already supports `acceptTerms=false`** | The existing `UserService.AddUser` method handles `acceptTerms=false` — it creates the user with `AcceptedTerms = null`. This is tested. |

### Cons

| # | Con | Severity | Mitigation |
|---|-----|----------|------------|
| 1 | **Creates "ghost" users who may never sign in** | Low | These are lightweight rows. Can be cleaned up after X months if no sign-in. The recipient's email was voluntarily provided by the question sender (who knows them). |
| 2 | **Auth flows need modification** | Medium | Magic link, Google OAuth, and standard registration need to handle "user exists but hasn't accepted terms" case. But changes are small — mostly about setting `AcceptedTerms` on first real sign-in instead of at user creation. |
| 3 | **`AddHelloWorldNetworks` and `AddHelloWorldDrop` timing** | Low | Currently called at user creation. For pre-created users, these should be deferred until terms acceptance (first real sign-in), so the user doesn't see "Hello World" content created months ago. |
| 4 | **Duplicate user risk** | Medium | If someone sends questions to `alice@gmail.com`, a user is pre-created. If Alice later registers with `alice@gmail.com` via the standard signup, `AddUser` checks for existing username and would find the pre-created user → throws "An account already exists." This is actually correct behavior — she should use magic link or Google to sign in, which will find the existing account. But the error message needs to be clear. |
| 5 | **Email uniqueness enforcement** | Low | Already enforced — `AddUser` checks `UserName == email` for duplicates. Pre-creation uses the same path. |
| 6 | **Existing broken data still needs a fix** | Medium | Pre-creating users going forward fixes future answers, but images uploaded under the wrong userId before this change are still broken. Need a one-time migration to either (a) move S3 objects, or (b) set `Drop.UserId` back to the creator's userId for affected drops. |
| 7 | **Multiple question senders could target the same email** | Low | First send creates the user; subsequent sends find existing by email. `RespondentUserId` gets set on each `QuestionRequestRecipient`. This is fine. |
| 8 | **Retrieval bug still exists in QuestionService** | High | Even with pre-created users, `BuildAnswerViewModel` (line 516) and `BuildRecipientAnswerModel` (line 923) still pass the **question creator's userId** to `GetLink` instead of `drop.UserId`. These must still be fixed regardless of approach. |

---

## Impact Assessment

### What changes

| Area | Change |
|------|--------|
| `CreateQuestionRequest` | After creating recipients, look up or create `UserProfile` for each email, set `RespondentUserId` |
| `SubmitAnswer` | Simplify: `dropUserId = recipient.RespondentUserId` (always set) |
| `UploadAnswerImage` controller | Simplify: `userId = recipient.RespondentUserId` (always set) |
| `RequestAnswerMovieUpload` controller | Simplify: `userId = recipient.RespondentUserId` (always set) |
| `LinkAnswersToUserAsync` | Remove `Drop.UserId` reassignment. Focus on `AcceptedTerms`, connections, groups. |
| `RegisterAndLinkAnswers` | If user already exists (pre-created), just set `AcceptedTerms` and premium. |
| `GoogleAuthService.FindOrCreateUserAsync` | When finding existing user by email, check if `AcceptedTerms` is null → set it. |
| `BuildAnswerViewModel` | Fix: use `drop.UserId` instead of `creatorUserId` |
| `BuildRecipientAnswerModel` | Fix: use `drop.UserId` instead of `userId` param |
| `GetAnswerMovieStatus` | Fix: use `drop.UserId` instead of `creatorUserId` |
| `AddUser` | No change needed (already supports `acceptTerms=false`) |
| Auth middleware | No change needed (doesn't check `AcceptedTerms`) |
| Frontend auth store | May need to expose `acceptedTerms` so the signup flow can show terms if needed |
| Frontend signup views | When a pre-created user tries to register, redirect to sign-in flow with terms acceptance |

### What stays the same

- `ImageService.GetLink` / `MovieService.GetLink` — unchanged
- `DropsService.OrderedWithImages` — unchanged (uses `drop.UserId`, which is now correct)
- `ImageService.Get` — unchanged
- S3 storage — no objects need to move
- `UserProfile` schema — no new columns
- JWT generation — unchanged
- Auth middleware — unchanged

---

## Comparison with Previous Recommendation

| Aspect | Previous (move S3 objects) | This (pre-create users) |
|--------|---------------------------|------------------------|
| Schema changes | None | None |
| S3 operations | Copy+delete on every `LinkAnswersToUserAsync` | None |
| Failure modes | S3 copy can fail partially | User creation can fail (but simple DB insert) |
| Complexity | Add `CopyAsync` to ImageService + MovieService | Modify `CreateQuestionRequest` + simplify several methods |
| Ongoing risk | Every future ownership transfer needs S3 moves | No ongoing risk — userId is stable from start |
| Auth changes | None | Magic link + Google OAuth need terms-acceptance handling |
| Code direction | Patches around the ownership transfer | Eliminates the need for ownership transfer |

---

## Recommendation

The pre-create user approach is **architecturally superior** — it eliminates the root cause rather than patching around it. However, it requires more upfront work (auth flow changes) and the three retrieval bugs (`BuildAnswerViewModel`, `BuildRecipientAnswerModel`, `GetAnswerMovieStatus`) still need fixing regardless.

**Suggested phasing:**

1. **Phase 1 (immediate):** Fix the three retrieval methods to use `drop.UserId` — this is a pure bug fix that works with either approach
2. **Phase 2:** Pre-create users in `CreateQuestionRequest`, update `SubmitAnswer` and upload controllers
3. **Phase 3:** Update auth flows to handle `AcceptedTerms = null` users
4. **Phase 4:** Simplify `LinkAnswersToUserAsync` to remove `Drop.UserId` transfer
5. **Phase 5:** Backfill existing data (move S3 objects for already-broken images)
