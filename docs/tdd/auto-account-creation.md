# TDD: Automatic Account Creation & S3 Image Fix

**PRD:** `docs/prd/PRD_AUTO_ACCOUNT_CREATION.md`
**Investigation:** `docs/investigations/2026-02-10-image-userid-mismatch.md`

---

## Overview

This TDD addresses two related problems:

1. **S3 image/video breakage** — Three QuestionService methods use the wrong userId when generating presigned URLs, and `LinkAnswersToUserAsync` changes `Drop.UserId` without moving S3 objects.
2. **Signup friction** — Recipients must register through a full form even though we already have their email.

The solution: **pre-create a `UserProfile` when a question is sent**, giving the recipient a stable userId from the start. Combined with removing the terms checkbox (replaced by a disclaimer), simplifying first sign-in to just a name prompt, and fixing the retrieval bugs.

---

## Component Diagram

```
Question Send Flow (changed):
  QuestionService.CreateQuestionRequest
    └─→ UserService.FindOrCreateByEmailAsync (NEW)
         └─→ Creates UserProfile with AcceptedTerms=null, Name=null
    └─→ Sets RespondentUserId on QuestionRequestRecipient

Answer Flow (simplified):
  QuestionService.SubmitAnswer
    └─→ Uses recipient.RespondentUserId (always set now)
  QuestionController.UploadAnswerImage
    └─→ Uses recipient.RespondentUserId (always set now)

Retrieval Flow (bug fix):
  QuestionService.BuildAnswerViewModel
    └─→ Uses drop.UserId (was: creatorUserId)
  QuestionService.BuildRecipientAnswerModel
    └─→ Uses drop.UserId (was: userId param)
  QuestionService.GetAnswerMovieStatus
    └─→ Uses drop.UserId (was: wrong fallback)

Auth Flow (changed):
  UserController.Register
    └─→ Detects pre-created user via UserService.TryCompletePreCreatedUserAsync
  UserController.CompleteProfile (NEW, [CustomAuthorization])
    └─→ UserService.CompleteProfileAsync (sets Name, AcceptedTerms, conditional hello world)
  GoogleAuthService.FindOrCreateUserAsync
    └─→ Detects pre-created user → calls CompleteProfileAsync
  QuestionService.RegisterAndLinkAnswers
    └─→ Simplified: user always exists

LinkAnswersToUserAsync (simplified, deployed with Phase 2):
  └─→ Removed short-circuit (was: return if RespondentUserId == userId)
  └─→ No more Drop.UserId reassignment
  └─→ EnsureConnection + PopulateEveryone always run

Frontend (changed):
  RegisterView, InlineAuth, InlineAuthPrompt
    └─→ Remove terms checkbox, add disclaimer
  Auth store
    └─→ Detect needsProfileCompletion (name is email)
  WelcomeView (NEW)
    └─→ "What's your name?" screen for first sign-in
```

---

## File Structure

```
cimplur-core/
├── Memento/Domain/Repositories/
│   ├── QuestionService.cs          (MODIFIED — phases 1, 2, 4)
│   ├── UserService.cs              (MODIFIED — new FindOrCreateByEmailAsync)
│   └── GoogleAuthService.cs        (MODIFIED — handle pre-created users)
├── Memento/Memento/Controllers/
│   ├── QuestionController.cs       (MODIFIED — simplify userId logic)
│   └── UserController.cs           (MODIFIED — Register + new CompleteProfile)
├── Memento/Memento/Models/
│   └── AccountModels.cs            (MODIFIED — CompleteProfileModel)
└── Memento/Domain/Models/
    └── UserModel.cs                (MODIFIED — add needsProfileCompletion)

fyli-fe-v2/src/
├── views/auth/
│   ├── RegisterView.vue            (MODIFIED — remove terms, add disclaimer)
│   └── WelcomeView.vue             (NEW — replaces onboarding welcome)
├── components/auth/
│   ├── InlineAuth.vue              (MODIFIED — remove terms, add disclaimer)
│   ├── InlineAuthPrompt.vue        (MODIFIED — remove terms, add disclaimer)
│   └── TermsDisclaimer.vue         (NEW — reusable disclaimer component)
├── stores/
│   └── auth.ts                     (MODIFIED — profile completion detection)
├── services/
│   └── authApi.ts                  (MODIFIED — completeProfile API call)
├── types/
│   └── index.ts                    (MODIFIED — User type update)
├── router/
│   └── index.ts                    (MODIFIED — update onboarding-welcome route + guard)
└── App.vue                         (MODIFIED — fetchUser on mount)
```

---

## Implementation Phases

### Phase 1: Fix Retrieval Bugs (Pure Bug Fix)

Fix three QuestionService methods that use the wrong userId for S3 presigned URLs. This is a standalone bug fix that works regardless of the pre-create approach.

#### 1.1 `BuildAnswerViewModel` (QuestionService.cs:491-527)

**Current (buggy):**
```csharp
Url = imageService.GetLink(i.ImageDropId, creatorUserId, drop.DropId)
// ...
ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, creatorUserId, drop.DropId, m.IsTranscodeV2),
VideoUrl = movieService.GetLink(m.MovieDropId, creatorUserId, drop.DropId, m.IsTranscodeV2)
```

**Fixed:**
```csharp
Url = imageService.GetLink(i.ImageDropId, drop.UserId, drop.DropId)
// ...
ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, drop.UserId, drop.DropId, m.IsTranscodeV2),
VideoUrl = movieService.GetLink(m.MovieDropId, drop.UserId, drop.DropId, m.IsTranscodeV2)
```

#### 1.2 `BuildRecipientAnswerModel` (QuestionService.cs:896-936)

**Current (buggy):**
```csharp
Url = imageService.GetLink(i.ImageDropId, userId, drop.DropId)
// ...
ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, userId, drop.DropId, m.IsTranscodeV2),
VideoUrl = movieService.GetLink(m.MovieDropId, userId, drop.DropId, m.IsTranscodeV2)
```

**Fixed:**
```csharp
Url = imageService.GetLink(i.ImageDropId, drop.UserId, drop.DropId)
// ...
ThumbnailUrl = movieService.GetThumbLink(m.MovieDropId, drop.UserId, drop.DropId, m.IsTranscodeV2),
VideoUrl = movieService.GetLink(m.MovieDropId, drop.UserId, drop.DropId, m.IsTranscodeV2)
```

#### 1.3 `GetAnswerMovieStatus` (QuestionService.cs:1351-1385)

**Current (buggy):**
```csharp
var creatorUserId = recipient.QuestionRequest?.CreatorUserId
    ?? recipient.RespondentUserId
    ?? 0;
// ...
ThumbnailUrl = movieService.GetThumbLink(movie.MovieDropId, creatorUserId, movie.DropId, movie.IsTranscodeV2),
VideoUrl = movieService.GetLink(movie.MovieDropId, creatorUserId, movie.DropId, movie.IsTranscodeV2)
```

**Fixed:** Load the drop and use `drop.UserId`:
```csharp
var drop = await Context.Drops
    .FirstOrDefaultAsync(d => d.DropId == movie.DropId);

if (drop == null)
    return null;

return new AnswerMovieModel
{
    MovieDropId = movie.MovieDropId,
    ThumbnailUrl = movieService.GetThumbLink(
        movie.MovieDropId, drop.UserId, movie.DropId, movie.IsTranscodeV2),
    VideoUrl = movieService.GetLink(
        movie.MovieDropId, drop.UserId, movie.DropId, movie.IsTranscodeV2)
};
```

Note: The drop is likely already loaded via `QuestionResponse.Drop` include. If so, use `questionResponse.Drop.UserId` directly. If not loaded, query it separately as shown above.

#### 1.4 Ensure `Drop` is included in queries

Verify that the LINQ queries calling `BuildAnswerViewModel` and `BuildRecipientAnswerModel` include `.Include(r => r.Responses).ThenInclude(resp => resp.Drop)` so that `drop.UserId` is available. Check:
- `GetQuestionRequestByToken` (calls `BuildAnswerViewModel`)
- `GetDetailedRequests` / `BuildRecipientDetailModel` (calls `BuildRecipientAnswerModel`)
- `GetUnifiedQuestionSetPage` (calls `BuildRecipientAnswerModel`)

---

### Phase 2: Auto-Create Users & Simplify LinkAnswersToUserAsync

**IMPORTANT:** Phase 2 and the `LinkAnswersToUserAsync` simplification (previously Phase 4) **must be deployed together**. The current `LinkAnswersToUserAsync` has a short-circuit at line 749: `if (recipient.RespondentUserId == userId) return;`. If we set `RespondentUserId` at question send time without also updating `LinkAnswersToUserAsync`, the short-circuit will skip `GrantDropAccessToUser`, `EnsureConnectionAsync`, and `PopulateEveryone` — silently breaking connections and access grants.

#### 2.1 Add `GroupService` dependency to `UserService`

`UserService` currently lacks `GroupService` as a dependency. Add it to the constructor:

```csharp
private GroupService groupService;

public UserService(
    NotificationService notificationService,
    SendEmailService sendEmailService,
    DropsService dropsService,
    AlbumService albumService,
    TokenService tokenService,
    GroupService groupService,
    ILogger<UserService> logger)
{
    this.notificationService = notificationService;
    this.albumService = albumService;
    this.dropService = dropsService;
    this.sendEmailService = sendEmailService;
    this.tokenService = tokenService;
    this.groupService = groupService;
    _logger = logger;
}
```

#### 2.2 New method: `UserService.FindOrCreateByEmailAsync`

Add a new method to `UserService` that looks up or creates a user by email.

```csharp
/// <summary>
/// Finds an existing user by email, or creates a pre-provisioned user
/// with AcceptedTerms=null and Name=null. Used when sending questions
/// to ensure a stable userId exists for the recipient.
/// </summary>
public async Task<int> FindOrCreateByEmailAsync(string email)
{
    var normalizedEmail = email.Trim().ToLower();
    var existing = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.Email.ToLower() == normalizedEmail);

    if (existing != null)
        return existing.UserId;

    // Pre-create user with no terms acceptance and no name
    return await AddUser(
        normalizedEmail, normalizedEmail, null,
        acceptTerms: false, name: null, reasons: null);
}
```

**Important:** `AddUser` with `acceptTerms: false` sets `AcceptedTerms = null` and `PremiumExpiration = null`. No hello world content is created.

#### 2.3 Modify `CreateQuestionRequest` (QuestionService.cs:296-320)

After creating recipient entities, look up or create a user for each email and set `RespondentUserId`.

**Current (lines 310-318):**
```csharp
newRecipientEntities.Add(new QuestionRequestRecipient
{
    Token = Guid.NewGuid(),
    Email = r.Email.Trim(),
    Alias = r.Alias?.Trim(),
    IsActive = true,
    CreatedAt = now,
    RemindersSent = 0
});
```

**Modified:**
```csharp
var recipientUserId = await userService.FindOrCreateByEmailAsync(r.Email);
newRecipientEntities.Add(new QuestionRequestRecipient
{
    Token = Guid.NewGuid(),
    Email = r.Email.Trim(),
    Alias = r.Alias?.Trim(),
    IsActive = true,
    CreatedAt = now,
    RemindersSent = 0,
    RespondentUserId = recipientUserId
});
```

Also set `RespondentUserId` for reused recipients if not already set:
```csharp
if (existingByEmail.TryGetValue(emailKey, out var existing))
{
    if (!existing.RespondentUserId.HasValue)
    {
        var recipientUserId = await userService.FindOrCreateByEmailAsync(r.Email);
        existing.RespondentUserId = recipientUserId;
    }
    // ... existing alias update logic
    reusedRecipients.Add(existing);
}
```

#### 2.4 `SubmitAnswer` and QuestionController upload methods — no change needed

**`SubmitAnswer` (QuestionService.cs:571)** and the three `QuestionController` upload methods already use the correct fallback pattern:
```csharp
var dropUserId = recipient.RespondentUserId ?? creatorUserId;
```

Keep this fallback as-is. `RespondentUserId` will always be set for new recipients, but the `?? creatorUserId` fallback ensures backwards compatibility with any old recipients that haven't been backfilled yet. No code change needed here.

#### 2.5 Simplify `LinkAnswersToUserAsync` (QuestionService.cs:737-771)

Since `RespondentUserId` is now always set at question send time, this method no longer needs to transfer drop ownership. It only needs to create connections and populate groups.

**Critical:** The current code has a short-circuit at line 749 (`if (recipient.RespondentUserId == userId) return;`) that would skip all linking logic for pre-created users. This must be removed.

**Current:**
```csharp
public async Task LinkAnswersToUserAsync(Guid token, int userId)
{
    var recipient = await Context.QuestionRequestRecipients
        .Include(r => r.QuestionRequest)
        .Include(r => r.Responses)
            .ThenInclude(resp => resp.Drop)
        .SingleOrDefaultAsync(r => r.Token == token);

    if (recipient == null) return;
    if (recipient.RespondentUserId == userId) return;  // <-- SHORT-CIRCUITS

    recipient.RespondentUserId = userId;

    var creatorUserId = recipient.QuestionRequest.CreatorUserId;
    foreach (var response in recipient.Responses)
    {
        await GrantDropAccessToUser(response.DropId, creatorUserId);
        response.Drop.UserId = userId;  // <-- CAUSES S3 BREAKAGE
    }

    await sharingService.EnsureConnectionAsync(creatorUserId, userId);
    await groupService.PopulateEveryone(creatorUserId);
    await groupService.PopulateEveryone(userId);
    await Context.SaveChangesAsync();
}
```

**Modified:**
```csharp
/// <summary>
/// Links a question recipient to a user account. Creates a connection
/// between asker and respondent and populates groups. Does NOT transfer
/// drop ownership (drops already belong to the respondent via
/// pre-created user).
/// </summary>
public async Task LinkAnswersToUserAsync(Guid token, int userId)
{
    var recipient = await Context.QuestionRequestRecipients
        .Include(r => r.QuestionRequest)
        .Include(r => r.Responses)
        .SingleOrDefaultAsync(r => r.Token == token);

    if (recipient == null) return;

    // Ensure the recipient is linked to this user
    if (!recipient.RespondentUserId.HasValue)
    {
        recipient.RespondentUserId = userId;
    }

    var creatorUserId = recipient.QuestionRequest.CreatorUserId;

    // Grant the question creator access to the respondent's drops
    foreach (var response in recipient.Responses)
    {
        await GrantDropAccessToUser(response.DropId, creatorUserId);
    }

    // Create bidirectional connection
    await sharingService.EnsureConnectionAsync(creatorUserId, userId);
    await groupService.PopulateEveryone(creatorUserId);
    await groupService.PopulateEveryone(userId);

    await Context.SaveChangesAsync();
}
```

**Key changes:**
- Removed `if (recipient.RespondentUserId == userId) return;` — this short-circuit prevented linking when `RespondentUserId` was already set
- Removed `response.Drop.UserId = userId;` — this was the root cause of S3 breakage
- `GrantDropAccessToUser` and connection creation always run

---

### Phase 3: Terms Disclaimer & Registration Simplification

#### 3.1 Backend: Always set AcceptedTerms

**`UserService.AddUser` (line 60-64):** No change needed. When `acceptTerms=false`, `AcceptedTerms` stays null. When `acceptTerms=true`, it's set. This is correct — pre-created users get `null`, users who sign in get a timestamp.

**`UserController.Register` (lines 228-231):** Remove the `acceptTerms` validation:

Current:
```csharp
if (!model.AcceptTerms)
{
    return BadRequest("To use Fyli you must accept the Terms of Service.");
}
```

Modified: Remove this block. Always treat terms as accepted via disclaimer. In the `AddUser` call (line 236), pass `true` for `acceptTerms`:

```csharp
int userId = await userService.AddUser(
    model.Email, userName, model.Token, true, model.Name, reasons?.Reasons);
```

**`RegisterModel` (AccountModels.cs:62):** Keep `AcceptTerms` property for backwards compatibility with older frontends but ignore its value.

#### 3.2 Handle pre-created users in `Register`

**`UserController.Register` (lines 218-221):** Currently returns error if email exists. Modify to detect pre-created users. Keep the logic in the service layer to avoid leaking entities to the controller.

Current:
```csharp
if (userService.CheckEmail(model.Email))
{
    return BadRequest("Email already exists. Please log into your existing account.");
}
```

Modified:
```csharp
if (userService.CheckEmail(model.Email))
{
    var completedUserId = await userService
        .TryCompletePreCreatedUserAsync(model.Email, model.Name);
    if (completedUserId.HasValue)
    {
        // Pre-created user completing registration
        var token = userWebToken.generateJwtToken(completedUserId.Value);
        return Ok(token);
    }
    return BadRequest(
        "Email already exists. Please log into your existing account.");
}
```

Add `TryCompletePreCreatedUserAsync` to `UserService`:
```csharp
/// <summary>
/// Attempts to complete a pre-created user's profile by email.
/// Returns the userId if a pre-created user was found and completed,
/// or null if no pre-created user exists for this email.
/// </summary>
public async Task<int?> TryCompletePreCreatedUserAsync(
    string email, string name)
{
    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u =>
            u.Email.ToLower() == email.Trim().ToLower());

    if (user == null || user.AcceptedTerms.HasValue)
        return null;

    await CompleteProfileAsync(user.UserId, name);
    return user.UserId;
}
```

#### 3.3 New method: `UserService.CompleteProfileAsync`

```csharp
/// <summary>
/// Completes a pre-created user's profile: sets name, accepted terms,
/// premium expiration, and conditionally adds hello world content.
/// Throws if the profile is already complete (prevents re-completion).
/// </summary>
public async Task CompleteProfileAsync(int userId, string name)
{
    var user = await Context.UserProfiles
        .SingleOrDefaultAsync(u => u.UserId == userId);
    if (user == null) throw new NotFoundException();

    if (user.AcceptedTerms.HasValue)
        throw new BadRequestException("Profile is already complete.");

    user.Name = name?.Trim();
    user.AcceptedTerms = DateTime.UtcNow;
    user.PremiumExpiration = DateTime.UtcNow.AddYears(10);
    await Context.SaveChangesAsync();

    // Only add hello world content if user has no memories yet
    var hasDrops = await Context.Drops
        .AnyAsync(d => d.UserId == userId);
    if (!hasDrops)
    {
        groupService.AddHelloWorldNetworks(userId);
        await dropService.AddHelloWorldDrop(userId);
    }
}
```

**Notes:**
- Per PRD, if the user already has memories (e.g., they answered questions before signing in), skip `AddHelloWorldNetworks` and `AddHelloWorldDrop`.
- The `AcceptedTerms.HasValue` guard prevents completed users from calling this endpoint to change their name. Existing users should use the `PUT /users` (ChangeName) endpoint instead.

#### 3.4 New endpoint: `UserController.CompleteProfile`

```csharp
/// <summary>
/// Completes profile for a pre-created user on first sign-in.
/// Sets name and triggers hello world content if no memories exist.
/// </summary>
[CustomAuthorization]
[HttpPost]
[Route("complete-profile")]
public async Task<IActionResult> CompleteProfile(
    CompleteProfileModel model)
{
    if (string.IsNullOrWhiteSpace(model.Name))
    {
        return BadRequest("Name is required.");
    }

    await userService.CompleteProfileAsync(CurrentUserId, model.Name);
    var user = await userService.GetUser(CurrentUserId);
    return Ok(user);
}
```

Add to `AccountModels.cs`:
```csharp
public class CompleteProfileModel
{
    [Required]
    [StringLength(100)]
    public string Name { get; set; }
}
```

**Note:** `UserController` already has `PUT /users` (`ChangeName`, line 67) for existing users to change their name. `CompleteProfile` is intentionally separate because it also sets `AcceptedTerms`, `PremiumExpiration`, and conditionally creates hello world content — logic that `ChangeName` should not trigger.

#### 3.5 Update `GoogleAuthService.FindOrCreateUserAsync` (lines 110-125)

When finding an existing pre-created user by email, complete their profile. Since Google provides the user's name, we skip the frontend name prompt entirely (per PRD answer #2).

Current:
```csharp
var existingUser = await Context.UserProfiles
    .SingleOrDefaultAsync(u => u.Email.ToLower() == email);

int userId;
if (existingUser != null)
{
    userId = existingUser.UserId;
}
else
{
    userId = await userService.AddUser(
        email, email, null, true, name, null);
    groupService.AddHelloWorldNetworks(userId);
    await dropsService.AddHelloWorldDrop(userId);
}
```

Modified:
```csharp
var existingUser = await Context.UserProfiles
    .SingleOrDefaultAsync(u => u.Email.ToLower() == email);

int userId;
if (existingUser != null)
{
    userId = existingUser.UserId;
    // If pre-created user, complete their profile with Google name
    if (!existingUser.AcceptedTerms.HasValue)
    {
        await userService.CompleteProfileAsync(userId, name);
    }
}
else
{
    userId = await userService.AddUser(
        email, email, null, true, name, null);
    groupService.AddHelloWorldNetworks(userId);
    await dropsService.AddHelloWorldDrop(userId);
}
```

**Note:** `GoogleAuthService` also needs `GroupService` for the `else` branch. Verify its constructor already has it — if not, the hello world calls in the `else` branch should be moved to `UserService.AddUser` when `acceptTerms=true`, or `GroupService` should be injected.

#### 3.6 Update `UserModel` to signal profile completion need

**`UserModel.cs`:** Add a flag so the frontend can detect first-sign-in:

```csharp
public class UserModel
{
    public UserModel() {
        Variants = new Dictionary<string, string>();
    }

    public string Name { get; set; }
    public bool PremiumMember { get; set; }
    public string Email { get; set; }
    public bool PrivateMode { get; set; }
    public DateTime? CanShareDate { get; set; }
    public Dictionary<string, string> Variants { get; set; }
    public bool NeedsProfileCompletion { get; set; }
}
```

**`UserService.GetUser` (line 115-129):** Set the new field:

```csharp
var userModel = new UserModel {
    Name = user.Name ?? user.UserName,
    CanShareDate = user.PremiumExpiration.HasValue
        && user.PremiumExpiration.Value > now
        ? user.PremiumExpiration : null,
    PremiumMember = user.PremiumExpiration.HasValue
        && user.PremiumExpiration.Value > now,
    Variants = GetVariants(currentUserId),
    PrivateMode = user.PrivateMode,
    Email = user.Email,
    NeedsProfileCompletion = !user.AcceptedTerms.HasValue
};
```

---

### Phase 4: Simplify RegisterAndLinkAnswers

#### 4.1 Simplify `RegisterAndLinkAnswers` (QuestionService.cs:690-731)

Since the user is always pre-created, this method no longer needs to create users. `LinkAnswersToUserAsync` was already simplified in Phase 2.5.

**Modified:**
```csharp
/// <summary>
/// Handles registration from the question answer page.
/// The user should already exist (pre-created at question send time).
/// Completes their profile and links answers.
/// </summary>
public async Task<int> RegisterAndLinkAnswers(
    Guid token, string email, string name, bool acceptTerms)
{
    var recipient = await Context.QuestionRequestRecipients
        .Include(r => r.QuestionRequest)
        .SingleOrDefaultAsync(r => r.Token == token);

    if (recipient == null)
        throw new BadRequestException("Invalid token.");

    // Find existing user (should exist from pre-creation)
    var existingUser = await Context.UserProfiles
        .SingleOrDefaultAsync(u =>
            u.Email.ToLower() == email.ToLower().Trim());

    int userId;
    if (existingUser != null)
    {
        userId = existingUser.UserId;
        // Complete profile if not yet done
        if (!existingUser.AcceptedTerms.HasValue)
        {
            await userService.CompleteProfileAsync(userId, name);
        }
    }
    else
    {
        // Fallback: if somehow no pre-created user exists,
        // create one now (backwards compatibility)
        userId = await userService.AddUser(
            email.Trim(), email.Trim(), null, true,
            name?.Trim(), null);

        var hasDrops = await Context.Drops
            .AnyAsync(d => d.UserId == userId);
        if (!hasDrops)
        {
            groupService.AddHelloWorldNetworks(userId);
            await dropsService.AddHelloWorldDrop(userId);
        }
    }

    await LinkAnswersToUserAsync(token, userId);
    return userId;
}
```

**Note:** `name` is passed directly to `CompleteProfileAsync` which handles trimming internally. The fallback `else` branch trims at the boundary since `AddUser` does not trim.

---

### Phase 5: Frontend Changes

#### 5.1 New component: `TermsDisclaimer.vue`

```vue
<template>
	<p class="text-muted small mt-2 mb-0">
		By using fyli, you agree to our
		<RouterLink to="/terms" target="_blank" rel="noopener">
			Terms of Service
		</RouterLink>
		and
		<RouterLink to="/privacy" target="_blank" rel="noopener">
			Privacy Policy</RouterLink
		>.
	</p>
</template>

<script setup lang="ts">
// RouterLink is auto-registered by Vue Router — no import needed
</script>
```

#### 5.2 Modify `InlineAuth.vue` — Remove terms checkbox, add disclaimer

**Remove lines 116-127** (the terms checkbox `<div class="form-check">...</div>`).

**Remove lines 262-265** (the `regAcceptTerms` validation in `handleRegister`):
```typescript
// REMOVE:
if (!regAcceptTerms.value) {
    regError.value = "You must accept the terms.";
    return;
}
```

**Remove** the `regAcceptTerms` ref (line 197).

**Remove** the `termsId` constant (line 206).

**Add** `<TermsDisclaimer />` after the "Create Account" button (after line 138).

**Update** `handleRegister` to always pass `true` for `acceptTerms`:
```typescript
jwt = await props.registerFn(regEmail.value, regName.value, true);
// ...
const { data } = await register(regName.value, regEmail.value, true);
```

**Update** the `registerFn` prop type — remove `acceptTerms` parameter:
```typescript
registerFn?: (email: string, name: string, acceptTerms: boolean) => Promise<string>;
```
Keep the signature for backwards compatibility but always pass `true`.

#### 5.3 Modify `InlineAuthPrompt.vue` — Same changes

**Remove** the terms checkbox (`<div class="form-check">...</div>`, lines 37-48).
**Remove** `regAcceptTerms` validation in `handleRegister`.
**Remove** the `regAcceptTerms` ref and `termsId`.
**Add** `<TermsDisclaimer />` after the registration button.
**Always pass** `true` for `acceptTerms`.

#### 5.4 Modify `RegisterView.vue` — Remove terms checkbox, add disclaimer

**Remove lines 77-85** (the terms checkbox).
**Remove** the `agreed` ref and any validation that checks it.
**Add** `<TermsDisclaimer />` below the submit button.
**Always pass** `true` for `acceptTerms` in the registration API call.

#### 5.5 Update `User` type (`types/index.ts`)

```typescript
export interface User {
    name: string;
    email: string;
    premiumMember: boolean;
    privateMode: boolean;
    canShareDate: string;
    variants: Record<string, string>;
    needsProfileCompletion: boolean;
}
```

#### 5.6 Update `authApi.ts` — Add `completeProfile`

```typescript
export function completeProfile(name: string) {
    return api.post<User>("/users/complete-profile", { name });
}
```

#### 5.7 Update `auth.ts` store — Profile completion detection

```typescript
import { ref, computed } from "vue";
import { defineStore } from "pinia";
import { getUser, completeProfile as completeProfileApi } from "@/services/authApi";
import type { User } from "@/types";

export const useAuthStore = defineStore("auth", () => {
    const token = ref<string | null>(localStorage.getItem("token"));
    const user = ref<User | null>(null);
    const shareToken = ref<string | null>(null);

    const isAuthenticated = computed(() => !!token.value);
    const needsProfileCompletion = computed(
        () => user.value?.needsProfileCompletion === true
    );

    function setToken(jwt: string) {
        token.value = jwt;
        localStorage.setItem("token", jwt);
    }

    function setShareToken(t: string) {
        shareToken.value = t;
    }

    async function fetchUser() {
        const { data } = await getUser();
        user.value = data;
    }

    async function completeProfile(name: string) {
        const { data } = await completeProfileApi(name);
        user.value = data;
    }

    function logout() {
        token.value = null;
        user.value = null;
        localStorage.removeItem("token");
    }

    return {
        token,
        user,
        shareToken,
        isAuthenticated,
        needsProfileCompletion,
        setToken,
        setShareToken,
        fetchUser,
        completeProfile,
        logout,
    };
});
```

#### 5.8 New view: `WelcomeView.vue`

First-sign-in screen for pre-created users. Shown when `needsProfileCompletion` is true.

```vue
<template>
	<div class="d-flex justify-content-center align-items-center min-vh-100">
		<div class="card shadow-sm" style="max-width: 440px; width: 100%">
			<div class="card-body p-4 text-center">
				<h4 class="mb-2">Welcome to fyli!</h4>
				<p class="text-muted mb-4">
					You're here because someone shared something special
					with you.
				</p>

				<form @submit.prevent="handleSubmit">
					<div class="mb-3 text-start">
						<label for="name" class="form-label">
							The name others will see when you share your
							memories?
						</label>
						<input
							id="name"
							v-model="name"
							type="text"
							class="form-control"
							placeholder="What should we call you?"
							required
							autofocus
						/>
					</div>

					<div v-if="error" class="alert alert-danger py-2">
						{{ error }}
					</div>

					<button
						type="submit"
						class="btn btn-primary w-100"
						:disabled="submitting"
					>
						{{ submitting ? "Setting up..." : "Get Started" }}
					</button>
				</form>

				<TermsDisclaimer />
			</div>
		</div>
	</div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import { getErrorMessage } from "@/utils/errorMessage";
import TermsDisclaimer from "@/components/auth/TermsDisclaimer.vue";

const auth = useAuthStore();
const router = useRouter();

const name = ref("");
const submitting = ref(false);
const error = ref("");

async function handleSubmit() {
	if (!name.value.trim()) {
		error.value = "Please enter your name.";
		return;
	}
	submitting.value = true;
	error.value = "";
	try {
		await auth.completeProfile(name.value.trim());
		router.replace("/");
	} catch (e: unknown) {
		error.value = getErrorMessage(e, "Something went wrong.");
	} finally {
		submitting.value = false;
	}
}
</script>
```

#### 5.9 Router: Add welcome route and navigation guard

Reuse the existing `/onboarding/welcome` route path pattern. Replace the current `WelcomeView` at that path with the new profile-completion view.

Update the existing route:
```typescript
{
    path: "/onboarding/welcome",
    name: "onboarding-welcome",
    component: () => import("@/views/auth/WelcomeView.vue"),
    meta: { auth: true, layout: "public" }
}
```

**Note:** The existing router guard uses `meta.auth` (not `meta.requiresAuth`). Use `meta: { auth: true, layout: "public" }` to match the convention.

Add profile-completion redirect to the existing `beforeEach` guard:
```typescript
router.beforeEach((to) => {
    const jwt = localStorage.getItem("token");
    if (to.meta.auth && !jwt) {
        return { name: "login", query: { redirect: to.fullPath } };
    }

    // Redirect pre-created users to welcome page
    const auth = useAuthStore();
    if (auth.isAuthenticated && auth.needsProfileCompletion
        && to.name !== "onboarding-welcome") {
        return { name: "onboarding-welcome" };
    }

    // Don't let completed users visit welcome
    if (auth.isAuthenticated && !auth.needsProfileCompletion
        && to.name === "onboarding-welcome") {
        return { path: "/" };
    }
});
```

**Important:** The `needsProfileCompletion` check relies on `auth.user` being loaded. Do NOT add `await auth.fetchUser()` to the guard — that would add an API call to every navigation. Instead, `fetchUser` is called once after login in the auth flow (after `setToken` + `fetchUser` in the login/register handlers). For fresh page loads where `user` is null, add a `fetchUser` call in `App.vue`'s `onMounted`:

```typescript
// App.vue
onMounted(async () => {
    if (auth.isAuthenticated && !auth.user) {
        await auth.fetchUser();
    }
});
```

---

### Phase 6: Data Backfill (Future)

#### 6.1 Pre-create users for existing anonymous recipients

SQL script to identify recipients without a `RespondentUserId`:

```sql
-- Reference SQL (SQL Server syntax)
-- Find all QuestionRequestRecipients without a RespondentUserId
-- that have responses (i.e., answered questions)
SELECT qrr.QuestionRequestRecipientId, qrr.Email, qrr.Token,
       qr.CreatorUserId, COUNT(resp.QuestionResponseId) AS ResponseCount
FROM [QuestionRequestRecipients] qrr
JOIN [QuestionRequests] qr ON qr.QuestionRequestId = qrr.QuestionRequestId
LEFT JOIN [QuestionResponses] resp ON resp.QuestionRequestRecipientId = qrr.QuestionRequestRecipientId
WHERE qrr.RespondentUserId IS NULL
  AND qrr.IsActive = 1
GROUP BY qrr.QuestionRequestRecipientId, qrr.Email, qrr.Token, qr.CreatorUserId
ORDER BY ResponseCount DESC;
```

The backfill script would:
1. For each recipient without `RespondentUserId`, call `FindOrCreateByEmailAsync`
2. Set `RespondentUserId` on the recipient
3. **Do NOT change `Drop.UserId`** for existing drops (they were uploaded under the creator's userId and retrieval is now fixed to use `drop.UserId`)

#### 6.2 Fix already-broken S3 images

For drops where `LinkAnswersToUserAsync` already changed `Drop.UserId` (causing the original S3 key mismatch), we need to either:
- **Option A:** Move S3 objects from `{creatorId}/{dropId}/` to `{respondentId}/{dropId}/`
- **Option B:** Change `Drop.UserId` back to the original upload userId

This requires identifying affected drops — those where `Drop.UserId` was changed after images were uploaded. Deferred to a separate investigation/script.

---

## Database Changes

**No schema migration required.** All fields used already exist:
- `UserProfile.AcceptedTerms` — already nullable `DateTime?`
- `UserProfile.Name` — already nullable `varchar(100)`
- `UserProfile.PremiumExpiration` — already nullable `DateTime?`
- `QuestionRequestRecipient.RespondentUserId` — already nullable `int?`

---

## API Endpoint Changes

| Endpoint | Method | Change |
|----------|--------|--------|
| `POST /users/register` | `Register` | Remove `acceptTerms` validation. Detect pre-created users by email and complete their profile instead of returning error. |
| `POST /users/complete-profile` | `CompleteProfile` | **NEW.** Accepts `{ name: string }`. Sets name, AcceptedTerms, PremiumExpiration, conditional hello world. Returns `UserModel`. |
| `GET /users` | `Get` | Returns `UserModel` with new `NeedsProfileCompletion` field. |
| `POST /users/google-auth` | `GoogleAuth` | Unchanged endpoint, but `FindOrCreateUserAsync` internally completes pre-created user profile. |
| `POST /questions/answer/{token}/register` | `RegisterAndLinkAnswers` | Simplified: user always exists, just complete profile and link. |

---

## Testing Plan

### Backend Tests

#### Phase 1 Tests — Retrieval Bug Fixes

| Test | Description |
|------|-------------|
| `BuildAnswerViewModel_UsesDropUserId_ForImageLinks` | Verify images use `drop.UserId` not `creatorUserId` |
| `BuildAnswerViewModel_UsesDropUserId_ForMovieLinks` | Verify movies use `drop.UserId` not `creatorUserId` |
| `BuildRecipientAnswerModel_UsesDropUserId_ForImageLinks` | Verify images use `drop.UserId` not `userId` param |
| `BuildRecipientAnswerModel_UsesDropUserId_ForMovieLinks` | Verify movies use `drop.UserId` not `userId` param |
| `GetAnswerMovieStatus_UsesDropUserId` | Verify movie status uses `drop.UserId` |

#### Phase 2 Tests — Auto-Create Users & LinkAnswersToUserAsync

| Test | Description |
|------|-------------|
| `FindOrCreateByEmailAsync_ExistingUser_ReturnsUserId` | Returns existing user's ID |
| `FindOrCreateByEmailAsync_NewUser_CreatesWithNullTerms` | Creates user with `AcceptedTerms=null`, `Name=null` |
| `FindOrCreateByEmailAsync_CaseInsensitive` | `Alice@Gmail.com` finds existing `alice@gmail.com` |
| `CreateQuestionRequest_SetsRespondentUserId` | New recipients get `RespondentUserId` set |
| `CreateQuestionRequest_ExistingUser_ReusesUserId` | Existing email reuses user |
| `LinkAnswersToUserAsync_DoesNotChangeDropUserId` | Verify `Drop.UserId` is NOT changed |
| `LinkAnswersToUserAsync_GrantsCreatorAccess` | Creator gets access to respondent's drops |
| `LinkAnswersToUserAsync_CreatesConnection` | Bidirectional connection created |
| `LinkAnswersToUserAsync_WorksWhenRespondentAlreadySet` | Does NOT short-circuit when `RespondentUserId` already matches |

#### Phase 3 Tests — Profile Completion

| Test | Description |
|------|-------------|
| `CompleteProfileAsync_SetsNameAndTerms` | Sets `Name`, `AcceptedTerms`, `PremiumExpiration` |
| `CompleteProfileAsync_WithExistingDrops_SkipsHelloWorld` | No hello world if user has drops |
| `CompleteProfileAsync_WithoutDrops_AddsHelloWorld` | Adds hello world if user has no drops |
| `CompleteProfileAsync_AlreadyCompleted_Throws` | Throws `BadRequestException` if `AcceptedTerms` already set |
| `TryCompletePreCreatedUser_PreCreated_ReturnsUserId` | Returns userId for pre-created user |
| `TryCompletePreCreatedUser_ActiveUser_ReturnsNull` | Returns null for already-active user |
| `Register_PreCreatedUser_CompletesProfile` | Standard registration finds pre-created user, completes profile |
| `Register_ExistingActiveUser_ReturnsError` | Existing user with name set returns error |
| `GoogleAuth_PreCreatedUser_CompletesProfile` | Google auth completes profile for pre-created user |
| `GetUser_PreCreatedUser_NeedsProfileCompletion` | `NeedsProfileCompletion=true` when `AcceptedTerms=null` |
| `GetUser_CompletedUser_DoesNotNeedCompletion` | `NeedsProfileCompletion=false` when `AcceptedTerms` set |

#### Phase 4 Tests — RegisterAndLinkAnswers

| Test | Description |
|------|-------------|
| `RegisterAndLinkAnswers_PreCreatedUser_CompletesProfile` | Existing pre-created user gets profile completed |
| `RegisterAndLinkAnswers_NoPreCreatedUser_FallbackCreates` | Backwards compat: creates user if missing |

### Frontend Tests

#### Component Tests

| Test | Description |
|------|-------------|
| `TermsDisclaimer renders terms and privacy links` | Verify both links present |
| `InlineAuth does not render terms checkbox` | Verify checkbox removed |
| `InlineAuth renders TermsDisclaimer` | Verify disclaimer present in register mode |
| `InlineAuth handleRegister does not require acceptTerms` | Verify no terms validation |
| `InlineAuthPrompt does not render terms checkbox` | Verify checkbox removed |
| `InlineAuthPrompt renders TermsDisclaimer` | Verify disclaimer present |
| `RegisterView does not render terms checkbox` | Verify checkbox removed |
| `RegisterView renders TermsDisclaimer` | Verify disclaimer present |
| `WelcomeView renders name input and submit button` | Verify form elements |
| `WelcomeView submits name and redirects` | Verify form submission |
| `WelcomeView shows error for empty name` | Verify validation |

#### Store Tests

| Test | Description |
|------|-------------|
| `auth store needsProfileCompletion true when flag set` | Verify computed |
| `auth store needsProfileCompletion false when flag not set` | Verify computed |
| `auth store completeProfile calls API and updates user` | Verify action |

#### API Service Tests

| Test | Description |
|------|-------------|
| `completeProfile sends POST to /users/complete-profile` | Verify request |

---

## Implementation Order

1. **Phase 1** — Fix retrieval bugs (backend only, pure bug fix, can deploy independently)
2. **Phase 2** — Auto-create users in `CreateQuestionRequest` + simplify `LinkAnswersToUserAsync` (backend, **must deploy together**)
3. **Phase 3** — Terms disclaimer + profile completion endpoint (backend + frontend)
4. **Phase 4** — Simplify `RegisterAndLinkAnswers` (backend)
5. **Phase 5** — Frontend: welcome view, router guard, store updates
6. **Phase 6** — Data backfill (deferred, separate script)
7. **Phase 7** — Documentation: update `/docs/release_note.md` with feature summary

Phase 1 is a standalone bug fix. Phases 2-5 should be deployed together or in rapid sequence. Phase 2 and `LinkAnswersToUserAsync` changes are atomic — deploying pre-creation without the linking fix would cause the short-circuit at line 749 to silently skip connection creation and access grants.

---

## Backwards Compatibility

| Area | Compatibility |
|------|---------------|
| Existing users | No change. `AcceptedTerms` already set, `NeedsProfileCompletion` will be `false`. |
| Existing anonymous recipients | Continue to work. `SubmitAnswer` and upload controllers keep `?? creatorUserId` fallback for any old recipients without `RespondentUserId`. New sends will always set it. |
| Older frontends | Can continue sending `acceptTerms` parameter — backend ignores it. |
| Drop ownership | Existing drops are NOT changed. Phase 1 fixes retrieval to use `drop.UserId` which is always correct for the S3 path the image was uploaded to. |
| `RegisterModel.AcceptTerms` | Property kept for backwards compatibility. Backend ignores its value. |
| Drops created before fix | Images uploaded under `creatorUserId` remain at that S3 path. Since `Drop.UserId` still equals `creatorUserId` for unfixed drops, retrieval using `drop.UserId` works correctly. Only drops where `LinkAnswersToUserAsync` already changed `Drop.UserId` are still broken (Phase 6 backfill). |

---

## What Stays the Same

- `ImageService.GetLink` / `MovieService.GetLink` — unchanged
- `ImageService.Get` — unchanged
- `ImageService.GetName` — unchanged (S3 key format `{env}/{userId}/{dropId}/{imageId}`)
- `DropsService.OrderedWithImages` — unchanged (already uses `drop.UserId`)
- `MemoryShareLinkService` — unchanged (does NOT pre-create users; only grants access)
- `TimelineShareLinkService` — unchanged (does NOT pre-create users; only joins timeline)
- `UserProfile` schema — no new columns
- JWT generation — unchanged
- Auth middleware — unchanged (does not check `AcceptedTerms`)
- S3 storage — no objects moved (for new data)

---

*Document Version: 1.1*
*Created: 2026-02-10*
*Status: Draft*
*v1.1: Addressed code review — merged Phase 2+4 (LinkAnswersToUserAsync short-circuit fix), added GroupService to UserService, moved entity logic to service layer, added re-completion guard, fixed router meta key, moved fetchUser to App.vue, reused onboarding route, added [CustomAuthorization], kept SubmitAnswer fallback for backwards compat.*
