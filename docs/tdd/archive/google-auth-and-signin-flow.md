# TDD: Google Sign-In & Anonymous Flow Sign-In

**PRD:** `docs/prd/PRD_AUTH_GOOGLE_SIGNIN.md`
**Status:** Draft
**Created:** 2026-02-08

---

## Overview

Add Google Sign-In as a primary authentication method and give anonymous question answerers a non-intrusive option to sign in. When a user signs in during the question flow, their anonymous answers auto-link to their account.

### !IMPORTANT! — Auto-Linking Anonymous Answers

The PRD flags this as critical. Two approaches:

**Option A (Recommended): Reuse `RegisterAndLinkAnswers` logic via extracted method**
Extract the answer-linking logic from `QuestionService.RegisterAndLinkAnswers` into a shared `LinkAnswersToUser(Guid questionToken, int userId)` method. The new `GoogleAuth` endpoint calls this method when a `questionToken` is provided. This reuses the battle-tested linking code (recipient update, ownership transfer, creator access grant, connection creation, group population).

**Option B: Duplicate linking in a new service**
Create a standalone `AnswerLinkingService` that reimplements the linking logic. This avoids modifying `QuestionService` but risks divergence and bugs.

**Decision: Option A.** The linking logic is ~20 lines and already handles edge cases (existing user, creator access preservation, connections). Extracting it into a callable method keeps a single source of truth.

### Cross-Context Note

`GoogleAuthService` and `QuestionService` each extend `BaseService` and create their own `DbContext`. When `GoogleAuthService` calls `questionService.LinkAnswersToUserAsync()`, the operations happen on separate contexts with no shared transaction. The ordering matters: user creation and `ExternalLogin` save complete first, then answer linking runs. If `LinkAnswersToUserAsync` fails, the user and `ExternalLogin` records still exist (acceptable — user can retry, and they'll match by Google sub on the next attempt).

### Email-Match Edge Case
When a Google account's email matches an existing Fyli account:
1. Look up `ExternalLogin` by `Provider="Google"` + `ProviderUserId` first
2. If no match, fall back to email lookup on `UserProfile.Email`
3. If email matches an existing user, link the Google login to that user (create `ExternalLogin` record)
4. Never create a duplicate account

---

## Phase 1: Backend — ExternalLogin Entity & Google Auth Endpoint

### 1.1 New Entity: `ExternalLogin`

The entity class is named `ExternalLogin` in the `Domain.Entities` namespace. The existing `ExternalLogin` DTO in `Memento.Models.AccountModels` lives in a different namespace so there is no collision. Use `ToTable("ExternalLogins")` for a clean table name.

**File:** `cimplur-core/Memento/Domain/Entities/ExternalLogin.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class ExternalLogin
    {
        [Key]
        public int ExternalLoginId { get; set; }

        public int UserId { get; set; }

        [Required]
        [MaxLength(50), Column(TypeName = "varchar")]
        public string Provider { get; set; }

        [Required]
        [MaxLength(256), Column(TypeName = "varchar")]
        public string ProviderUserId { get; set; }

        [Required]
        [MaxLength(256), Column(TypeName = "varchar")]
        public string Email { get; set; }

        public DateTime LinkedAt { get; set; }

        public virtual UserProfile User { get; set; }
    }
}
```

### 1.2 StreamContext Changes

**File:** `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

Add to `OnModelCreating`:
```csharp
modelBuilder.Entity<ExternalLogin>(entity =>
{
    entity.ToTable("ExternalLogins");
    entity.HasKey(e => e.ExternalLoginId);

    entity.HasIndex(e => new { e.Provider, e.ProviderUserId })
        .IsUnique();
    entity.HasIndex(e => e.UserId);

    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

Add DbSet:
```csharp
public DbSet<ExternalLogin> ExternalLogins { get; set; }
```

### 1.3 Migration SQL

```sql
CREATE TABLE [ExternalLogins] (
    [ExternalLoginId] INT IDENTITY(1,1) NOT NULL,
    [UserId] INT NOT NULL,
    [Provider] VARCHAR(50) NOT NULL,
    [ProviderUserId] VARCHAR(256) NOT NULL,
    [Email] VARCHAR(256) NOT NULL,
    [LinkedAt] DATETIME2 NOT NULL,
    CONSTRAINT [PK_ExternalLogins] PRIMARY KEY ([ExternalLoginId]),
    CONSTRAINT [FK_ExternalLogins_UserProfiles_UserId]
        FOREIGN KEY ([UserId]) REFERENCES [UserProfiles]([UserId])
        ON DELETE NO ACTION
);

CREATE UNIQUE INDEX [IX_ExternalLogins_Provider_ProviderUserId]
    ON [ExternalLogins] ([Provider], [ProviderUserId]);

CREATE INDEX [IX_ExternalLogins_UserId]
    ON [ExternalLogins] ([UserId]);
```

### 1.4 AppSettings — Add GoogleClientId

**File:** `cimplur-core/Memento/Domain/Models/AppSettings.cs`

```csharp
public string GoogleClientId { get; set; }
```

**File:** `cimplur-core/Memento/Memento/appsettings.json`

Add:
```json
"GoogleClientId": ""
```

### 1.5 NuGet Package

Add `Google.Apis.Auth` to the `Domain` project:
```bash
cd cimplur-core/Memento/Domain
dotnet add package Google.Apis.Auth
```

### 1.6 IGoogleTokenVerifier Interface

Extracted for testability — allows mocking Google's external call in unit tests.

**File:** `cimplur-core/Memento/Domain/Repositories/IGoogleTokenVerifier.cs`

```csharp
using System.Threading.Tasks;
using Google.Apis.Auth;

namespace Domain.Repository
{
    public interface IGoogleTokenVerifier
    {
        Task<GoogleJsonWebSignature.Payload> VerifyAsync(
            string idToken, string clientId);
    }
}
```

**File:** `cimplur-core/Memento/Domain/Repositories/GoogleTokenVerifier.cs`

```csharp
using System.Threading.Tasks;
using Google.Apis.Auth;

namespace Domain.Repository
{
    /// <summary>
    /// Production implementation that calls Google's public keys.
    /// </summary>
    public class GoogleTokenVerifier : IGoogleTokenVerifier
    {
        public async Task<GoogleJsonWebSignature.Payload>
            VerifyAsync(string idToken, string clientId)
        {
            var settings =
                new GoogleJsonWebSignature.ValidationSettings
            {
                Audience = new[] { clientId }
            };
            return await GoogleJsonWebSignature
                .ValidateAsync(idToken, settings);
        }
    }
}
```

### 1.7 GoogleAuthService

**File:** `cimplur-core/Memento/Domain/Repositories/GoogleAuthService.cs`

```csharp
using System;
using System.Threading.Tasks;
using Domain.Entities;
using Domain.Exceptions;
using Domain.Models;
using Google.Apis.Auth;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Domain.Repository
{
    /// <summary>
    /// Handles Google ID token verification and
    /// user lookup/creation.
    /// </summary>
    public class GoogleAuthService : BaseService
    {
        // IQuestionService is already registered in DI
        // (Startup.cs line 68: AddScoped<IQuestionService,
        // QuestionService>). Concrete types used for others
        // to match existing UserController convention.
        private UserService userService;
        private IQuestionService questionService;
        private GroupService groupService;
        private DropsService dropsService;
        private IGoogleTokenVerifier tokenVerifier;
        private AppSettings appSettings;

        public GoogleAuthService(
            IOptions<AppSettings> appSettings,
            UserService userService,
            IQuestionService questionService,
            GroupService groupService,
            DropsService dropsService,
            IGoogleTokenVerifier tokenVerifier)
        {
            this.appSettings = appSettings.Value;
            this.userService = userService;
            this.questionService = questionService;
            this.groupService = groupService;
            this.dropsService = dropsService;
            this.tokenVerifier = tokenVerifier;
        }

        /// <summary>
        /// Verifies a Google ID token, finds or creates a user,
        /// and optionally links anonymous answers.
        /// Returns the userId.
        /// </summary>
        public async Task<int> AuthenticateAsync(
            string idToken,
            Guid? questionToken)
        {
            // 1. Verify Google ID token
            var payload = await VerifyGoogleTokenAsync(idToken);

            // 2. Find existing user by Google sub or email
            var userId = await FindOrCreateUserAsync(payload);

            // 3. Link anonymous answers if questionToken provided
            // Note: runs on QuestionService's own DbContext
            if (questionToken.HasValue)
            {
                await questionService.LinkAnswersToUserAsync(
                    questionToken.Value, userId);
            }

            return userId;
        }

        /// <summary>
        /// Verifies a Google ID token using Google's public keys.
        /// </summary>
        private async Task<GoogleJsonWebSignature.Payload>
            VerifyGoogleTokenAsync(string idToken)
        {
            try
            {
                return await tokenVerifier.VerifyAsync(
                    idToken, appSettings.GoogleClientId);
            }
            catch (InvalidJwtException)
            {
                throw new BadRequestException(
                    "Invalid Google sign-in token.");
            }
        }

        /// <summary>
        /// Finds user by Google sub ID or email.
        /// Creates new user if none found.
        /// Ensures ExternalLogin record exists.
        /// </summary>
        private async Task<int> FindOrCreateUserAsync(
            GoogleJsonWebSignature.Payload payload)
        {
            var email = payload.Email?.ToLower().Trim();
            var googleSub = payload.Subject;
            var name = payload.Name ?? email;

            if (string.IsNullOrWhiteSpace(email))
                throw new BadRequestException(
                    "Google account must have an email.");

            // Check by Google sub first
            var externalLogin = await Context.ExternalLogins
                .SingleOrDefaultAsync(e =>
                    e.Provider == "Google" &&
                    e.ProviderUserId == googleSub);

            if (externalLogin != null)
                return externalLogin.UserId;

            // Check by email
            var existingUser = await Context.UserProfiles
                .SingleOrDefaultAsync(u =>
                    u.Email.ToLower() == email);

            int userId;
            if (existingUser != null)
            {
                userId = existingUser.UserId;
            }
            else
            {
                // Create new user
                userId = await userService.AddUser(
                    email, email, null, true, name, null);
                groupService.AddHelloWorldNetworks(userId);
                await dropsService.AddHelloWorldDrop(userId);
            }

            // Link Google account to user
            Context.ExternalLogins.Add(new ExternalLogin
            {
                UserId = userId,
                Provider = "Google",
                ProviderUserId = googleSub,
                Email = email,
                LinkedAt = DateTime.UtcNow
            });
            await Context.SaveChangesAsync();

            return userId;
        }
    }
}
```

### 1.8 QuestionService — Extract Answer Linking

**File:** `cimplur-core/Memento/Domain/Repositories/QuestionService.cs`

Add new public method `LinkAnswersToUserAsync` that extracts the linking logic from `RegisterAndLinkAnswers`. The existing `RegisterAndLinkAnswers` calls this new method internally.

```csharp
/// <summary>
/// Links all anonymous answers for a question token to the
/// given user. Called by both RegisterAndLinkAnswers and
/// GoogleAuthService.
/// </summary>
public async Task LinkAnswersToUserAsync(
    Guid token, int userId)
{
    var recipient = await Context.QuestionRequestRecipients
        .Include(r => r.QuestionRequest)
        .Include(r => r.Responses)
            .ThenInclude(resp => resp.Drop)
        .SingleOrDefaultAsync(r => r.Token == token);

    if (recipient == null)
        return; // Silently skip — token may be invalid

    // Skip if already linked to this user
    if (recipient.RespondentUserId == userId)
        return;

    // Link recipient to user
    recipient.RespondentUserId = userId;

    // Transfer ownership of all answers
    var creatorUserId =
        recipient.QuestionRequest.CreatorUserId;
    foreach (var response in recipient.Responses)
    {
        await GrantDropAccessToUser(
            response.DropId, creatorUserId);
        response.Drop.UserId = userId;
    }

    // Create connection between asker and respondent
    await sharingService.EnsureConnectionAsync(
        creatorUserId, userId);

    // Populate "Everyone" groups
    await groupService.PopulateEveryone(creatorUserId);
    await groupService.PopulateEveryone(userId);

    await Context.SaveChangesAsync();
}
```

Refactor existing `RegisterAndLinkAnswers` to call `LinkAnswersToUserAsync`. Use `AnyAsync` for the token check to avoid tracking the entity unnecessarily (since `LinkAnswersToUserAsync` loads it with full includes). Add `AddHelloWorldNetworks` and `AddHelloWorldDrop` for new users so they get the same onboarding content as users who register via Google or the standard registration flow.

> **Note:** `QuestionService` already has both `groupService` and `dropsService` injected. No constructor changes needed.

```csharp
public async Task<int> RegisterAndLinkAnswers(
    Guid token, string email, string name,
    bool acceptTerms)
{
    // Input validation (unchanged)
    if (string.IsNullOrWhiteSpace(email))
        throw new BadRequestException("Email is required.");
    if (!EmailRegex.IsMatch(email.Trim()))
        throw new BadRequestException(
            "Invalid email format.");
    if (string.IsNullOrWhiteSpace(name))
        throw new BadRequestException("Name is required.");
    if (!acceptTerms)
        throw new BadRequestException(
            "You must accept the terms to create an account.");

    // Verify token exists (AnyAsync to avoid tracking)
    var tokenExists = await Context
        .QuestionRequestRecipients
        .AnyAsync(r => r.Token == token);
    if (!tokenExists)
        throw new NotFoundException(
            "Question link not found.");

    // Find or create user
    var existingUser = await Context.UserProfiles
        .SingleOrDefaultAsync(u =>
            u.Email.ToLower() == email.ToLower().Trim());

    int userId;
    if (existingUser != null)
    {
        userId = existingUser.UserId;
    }
    else
    {
        userId = await userService.AddUser(
            email.Trim(), email.Trim(), null,
            acceptTerms, name.Trim(), null);
        groupService.AddHelloWorldNetworks(userId);
        await dropsService.AddHelloWorldDrop(userId);
    }

    // Delegate linking to shared method
    await LinkAnswersToUserAsync(token, userId);

    return userId;
}
```

### 1.9 IQuestionService Interface Update

**File:** `cimplur-core/Memento/Domain/Repositories/IQuestionService.cs`

Add:
```csharp
Task LinkAnswersToUserAsync(Guid token, int userId);
```

### 1.10 Magic Link returnTo Support

To allow the magic link flow to return the user to the question page after sign-in (instead of redirecting to `/`), add an optional `ReturnTo` param to the token request.

**Backend changes:**

**File:** `cimplur-core/Memento/Memento/Models/EmailModel.cs`

Add optional property:
```csharp
public class EmailModel
{
    public string Email { get; set; }
    public string ReturnTo { get; set; }
}
```

**File:** `cimplur-core/Memento/Domain/Emails/EmailTemplates.cs`

Update the Login template to use the new frontend's `/auth/verify` route and include the `route` param when present. The current template uses the old AngularJS hash format (`/#/?link=TOKEN`); this must change to match the new frontend's `MagicLinkView` at `/auth/verify`, which reads `token` and `route` from the URL hash fragment.

```csharp
case EmailTypes.Login:
    return @"<p>@Model.Name, click this <a href='"
        + Constants.BaseUrl
        + "/auth/verify#token=@Model.Token&route=@Model.Route"
        + "'>link</a> to log in to your Fyli account.</p>";
```

> **Why the URL format change:** The old template used `/#/?link=TOKEN` (AngularJS hash routing). The new frontend (`fyli-fe-v2`) uses HTML5 history mode with `MagicLinkView` mounted at `/auth/verify`. It reads params from `window.location.hash` via `new URLSearchParams(hash)`, expecting keys `token` and `route`. The hash fragment is used (instead of query params) so the token stays client-side and never hits the server.

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

Pass the `ReturnTo` value through to the email model. URL-encode the route value so it survives the hash fragment:
```csharp
[HttpPost]
[Route("token")]
public async Task<IActionResult> CreatePassword(
    EmailModel model)
{
    if (!string.IsNullOrWhiteSpace(model.Email)
        && IsValidEmail(model.Email))
    {
        var token = await tokenService
            .CreateLinkToken(model.Email);
        if (token.Success)
        {
            var route = string.IsNullOrWhiteSpace(
                model.ReturnTo)
                ? "%2F"
                : Uri.EscapeDataString(model.ReturnTo);
            await sendEmailService.SendAsync(
                model.Email,
                EmailTypes.Login,
                new {
                    token.Token,
                    token.Name,
                    Route = route
                });
        }
        return Ok(new {
            Message = "Please check your email for "
                + "your log in link. If you do not "
                + "see it check your Spam folder."
        });
    }
    return BadRequest("Please submit a valid email.");
}
```

**Frontend changes:**

**File:** `fyli-fe-v2/src/services/authApi.ts`

Update `requestMagicLink` to accept optional `returnTo`:
```typescript
export function requestMagicLink(
    email: string,
    returnTo?: string
) {
    return api.post<{ message: string }>(
        '/users/token',
        { email, returnTo }
    );
}
```

**File:** `fyli-fe-v2/src/views/auth/MagicLinkView.vue`

Already reads `route` param from the hash fragment and navigates to it. No changes needed — the backend will embed the route in the email link.

> The `route` param in the hash (`#token=...&route=%2Fq%2Fabc`) is already supported by MagicLinkView. The only change is passing it from the question page through the backend into the email template.

### 1.11 Controller — Google Auth Endpoint

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

Add `GoogleAuthService` to constructor DI (matching existing field naming convention — no `readonly`, no underscore prefix). Add new endpoint:

```csharp
// Add field (matching existing convention):
private GoogleAuthService googleAuthService;

// Add to constructor params and body:
// GoogleAuthService googleAuthService
// this.googleAuthService = googleAuthService;

[EnableRateLimiting("registration")]
[HttpPost]
[Route("google-auth")]
public async Task<IActionResult> GoogleAuth(
    GoogleAuthModel model)
{
    var userId = await googleAuthService
        .AuthenticateAsync(model.IdToken,
            model.QuestionToken);
    var token = userWebToken.generateJwtToken(userId);
    return Ok(token);
}
```

### 1.12 New Request Model

**File:** `cimplur-core/Memento/Memento/Models/GoogleAuthModel.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;

namespace Memento.Models
{
    public class GoogleAuthModel
    {
        [Required]
        public string IdToken { get; set; }
        public Guid? QuestionToken { get; set; }
    }
}
```

### 1.13 DI Registration

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add:
```csharp
services.AddScoped<GoogleAuthService, GoogleAuthService>();
services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();
```

### 1.14 Generate EF Migration

```bash
cd cimplur-core/Memento && dotnet ef migrations add AddExternalLogin
```

---

## Phase 2: Frontend — Auth API & Google Sign-In Composable

### 2.1 Auth API — New Endpoint

**File:** `fyli-fe-v2/src/services/authApi.ts`

Add:
```typescript
export function googleAuth(
    idToken: string,
    questionToken?: string
) {
    return api.post<string>('/users/google-auth', {
        idToken,
        questionToken
    });
}
```

### 2.2 Google Sign-In Composable

**File:** `fyli-fe-v2/src/composables/useGoogleSignIn.ts`

Manages GIS script loading, button rendering, and token callback.

```typescript
import { ref } from "vue";
import { googleAuth } from "@/services/authApi";
import { useAuthStore } from "@/stores/auth";
import { getErrorMessage } from "@/utils/errorMessage";

declare global {
    interface Window {
        google?: {
            accounts: {
                id: {
                    initialize: (config: any) => void;
                    renderButton: (
                        el: HTMLElement,
                        options: any
                    ) => void;
                };
            };
        };
    }
}

const GOOGLE_CLIENT_ID =
    import.meta.env.VITE_GOOGLE_CLIENT_ID;
let scriptLoaded = false;

/// Loads the GIS script once and resolves when ready.
/// Times out after 10 seconds to avoid hanging promises.
function loadGisScript(): Promise<void> {
    if (scriptLoaded && window.google?.accounts) {
        return Promise.resolve();
    }
    return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
            reject(new Error(
                "Google Sign-In script load timed out"
            ));
        }, 10000);

        function done() {
            clearTimeout(timeout);
            scriptLoaded = true;
            resolve();
        }

        const existing = document.querySelector(
            'script[src*="accounts.google.com/gsi/client"]'
        );
        if (existing) {
            // Script tag exists — check if already loaded
            if (window.google?.accounts) {
                done();
                return;
            }
            existing.addEventListener("load", () => done());
            return;
        }
        const script = document.createElement("script");
        script.src =
            "https://accounts.google.com/gsi/client";
        script.async = true;
        script.defer = true;
        script.onload = () => done();
        script.onerror = () => {
            clearTimeout(timeout);
            reject(new Error(
                "Failed to load Google Sign-In"
            ));
        };
        document.head.appendChild(script);
    });
}

/// Composable for Google Sign-In button rendering and auth.
export function useGoogleSignIn(options?: {
    questionToken?: string;
    onSuccess?: () => void;
    buttonText?: "signin_with" | "signup_with";
}) {
    const loading = ref(false);
    const error = ref("");
    const auth = useAuthStore();

    /// Renders the Google Sign-In button into a container.
    async function renderButton(container: HTMLElement) {
        if (!GOOGLE_CLIENT_ID) {
            error.value =
                "Google Sign-In is not configured.";
            return;
        }

        try {
            await loadGisScript();
        } catch {
            error.value =
                "Failed to load Google Sign-In.";
            return;
        }

        window.google!.accounts.id.initialize({
            client_id: GOOGLE_CLIENT_ID,
            callback: handleCredentialResponse,
        });

        // Clear container to prevent stacking on re-render
        container.innerHTML = "";

        window.google!.accounts.id.renderButton(
            container,
            {
                type: "standard",
                theme: "outline",
                size: "large",
                width: "100%",
                text: options?.buttonText
                    ?? "signin_with",
            }
        );
    }

    /// Handles the credential response from Google.
    async function handleCredentialResponse(
        response: { credential: string }
    ) {
        loading.value = true;
        error.value = "";
        try {
            const { data: jwt } = await googleAuth(
                response.credential,
                options?.questionToken
            );
            auth.setToken(jwt);
            await auth.fetchUser();
            options?.onSuccess?.();
        } catch (e: unknown) {
            error.value = getErrorMessage(
                e,
                "Google sign-in failed."
            );
        } finally {
            loading.value = false;
        }
    }

    return { renderButton, loading, error };
}
```

### 2.3 AuthDivider Component

Extract the "or" divider into a reusable component to avoid duplicating CSS across LoginView, RegisterView, and QuestionAnswerView.

**File:** `fyli-fe-v2/src/components/ui/AuthDivider.vue`

```vue
<template>
    <div class="auth-divider" aria-hidden="true">
        <span>or</span>
    </div>
</template>

<style scoped>
.auth-divider {
    display: flex;
    align-items: center;
    margin: 1rem 0;
    color: var(--fyli-text-muted, #6c757d);
    font-size: 0.875rem;
}
.auth-divider::before,
.auth-divider::after {
    content: "";
    flex: 1;
    border-bottom: 1px solid var(--bs-border-color);
}
.auth-divider span {
    padding: 0 0.75rem;
}
</style>
```

Usage in any view:
```html
<AuthDivider />
```

### 2.4 Environment Variable

**File:** `fyli-fe-v2/.env`

Add:
```
VITE_GOOGLE_CLIENT_ID=
```

**File:** `fyli-fe-v2/.env.example` (if exists, or document)

```
VITE_GOOGLE_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
```

---

## Phase 3: Frontend — Login & Register Pages

### 3.1 LoginView — Add Google Button

**File:** `fyli-fe-v2/src/views/auth/LoginView.vue`

Changes:
- Import and use `useGoogleSignIn` composable
- Import `AuthDivider` component
- Add a `ref` container for the Google button
- Add `onMounted` to render the button
- On Google success: redirect to `/` or `redirect` query param

Updated template structure:
```
<card>
  <h4>Sign In</h4>
  <div v-if="sent">Check your email...</div>
  <div v-else>
    <!-- Google button container -->
    <div ref="googleBtnRef"></div>
    <div v-if="googleError" role="alert"
         class="alert alert-danger">
      {{ googleError }}
    </div>

    <AuthDivider />

    <form @submit.prevent="handleSubmit">
      <!-- existing magic link form -->
    </form>
  </div>
  <p>Don't have an account? Sign up</p>
</card>
```

### 3.2 RegisterView — Add Google Button

**File:** `fyli-fe-v2/src/views/auth/RegisterView.vue`

Same pattern as LoginView but with `buttonText: "signup_with"` and redirect to `/` on success.

Updated template structure:
```
<card>
  <h4>Create Account</h4>
  <div v-if="sent">Check your email...</div>
  <div v-else>
    <!-- Google button container -->
    <div ref="googleBtnRef"></div>
    <div v-if="googleError" role="alert"
         class="alert alert-danger">
      {{ googleError }}
    </div>

    <AuthDivider />

    <form @submit.prevent="handleSubmit">
      <!-- existing registration form -->
    </form>
  </div>
  <p>Already have an account? Sign in</p>
</card>
```

---

## Phase 4: Frontend — Question Answer Page

### 4.1 New Imports

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.vue`

Add to existing Vue imports:
```typescript
import { ref, onMounted, onUnmounted, computed,
    watch, nextTick } from "vue";
```

Add new imports:
```typescript
import { requestMagicLink } from "@/services/authApi";
import { useGoogleSignIn }
    from "@/composables/useGoogleSignIn";
import AuthDivider
    from "@/components/ui/AuthDivider.vue";
```

### 4.2 Subtle Sign-In Link

Add below the header badge, before the question list:

```html
<!-- Sign-in link (visible when not authenticated) -->
<div v-if="!auth.isAuthenticated && !showSignIn"
     class="text-center mt-2">
    <button class="btn btn-link btn-sm text-muted"
            @click="showSignIn = true">
        Have an account? Sign in
    </button>
</div>
```

New reactive state:
```typescript
const showSignIn = ref(false);
const magicLinkEmail = ref("");
const magicLinkSending = ref(false);
const magicLinkSent = ref(false);
const signInError = ref("");
```

### 4.3 Inline Sign-In Section

When `showSignIn` is true, render an expandable card:

```html
<!-- Inline sign-in section -->
<div v-if="showSignIn && !auth.isAuthenticated"
     class="card mb-4">
    <div class="card-body">
        <h6 class="card-title mb-3">
            Sign in to save your answers
        </h6>

        <!-- Google button -->
        <div ref="signInGoogleBtnRef"></div>
        <div v-if="googleSignInError"
             role="alert"
             class="alert alert-danger mt-2 py-2">
            {{ googleSignInError }}
        </div>

        <AuthDivider />

        <!-- Magic link form -->
        <div v-if="magicLinkSent"
             class="text-center py-2">
            <span class="mdi mdi-email-check-outline"
                  style="font-size: 2rem;
                         color: var(--fyli-primary)">
            </span>
            <p class="mt-2 mb-0 small">
                Check your email for a sign-in link.
            </p>
        </div>
        <form v-else class="d-flex gap-2"
              @submit.prevent="handleMagicLink">
            <input v-model="magicLinkEmail"
                   type="email"
                   class="form-control form-control-sm"
                   placeholder="Email"
                   aria-label="Email address"
                   required />
            <button type="submit"
                    class="btn btn-sm btn-outline-primary
                           text-nowrap"
                    :disabled="magicLinkSending">
                {{ magicLinkSending
                    ? "Sending..."
                    : "Send magic link" }}
            </button>
        </form>

        <div v-if="signInError"
             role="alert"
             class="alert alert-danger mt-2 py-2">
            {{ signInError }}
        </div>

        <button class="btn btn-link btn-sm text-muted
                       mt-2"
                @click="showSignIn = false">
            Cancel
        </button>
    </div>
</div>
```

### 4.4 Google Sign-In in Question Context

Use the `useGoogleSignIn` composable with `questionToken` set to the route param:

```typescript
const signInGoogleBtnRef =
    ref<HTMLElement | null>(null);

const {
    renderButton: renderSignInGoogle,
    error: googleSignInError
} = useGoogleSignIn({
    questionToken: token,
    onSuccess: handleSignInSuccess,
});

watch(showSignIn, async (val) => {
    if (val) {
        await nextTick();
        if (signInGoogleBtnRef.value) {
            renderSignInGoogle(
                signInGoogleBtnRef.value);
        }
    }
});
```

### 4.5 Magic Link from Question Page

Pass `returnTo` so the magic link email returns the user to the question page:

```typescript
async function handleMagicLink() {
    magicLinkSending.value = true;
    signInError.value = "";
    try {
        await requestMagicLink(
            magicLinkEmail.value,
            `/q/${token}`
        );
        magicLinkSent.value = true;
    } catch (e: unknown) {
        signInError.value = getErrorMessage(
            e, "Failed to send sign-in link."
        );
    } finally {
        magicLinkSending.value = false;
    }
}
```

### 4.6 Sign-In Success Handler

```typescript
function handleSignInSuccess() {
    showSignIn.value = false;
    showRegister.value = false;
}
```

After Google sign-in success, the auth store already has the JWT and user (composable handles this). The registration prompt hides because `auth.isAuthenticated` becomes true.

### 4.7 "Signed in as [name]" Badge

After successful sign-in (Google or magic link), show a small badge in the header area so the user knows they're authenticated and their answers are being saved.

```html
<!-- Signed-in badge (visible when authenticated) -->
<div v-if="auth.isAuthenticated && auth.user"
     class="text-center mt-2">
    <span class="badge bg-light text-dark border">
        <span class="mdi mdi-check-circle text-success me-1"></span>
        Signed in as {{ auth.user.name }}
    </span>
</div>
```

This replaces the "Have an account? Sign in" link position — when `auth.isAuthenticated` is true, the sign-in link is hidden and this badge appears instead. No additional state needed since it reads directly from the auth store.

### 4.8 Updated Registration Prompt

Modify the existing registration prompt card (lines 80-110 of current QuestionAnswerView.vue) to add:
1. Google button above the email form
2. `<AuthDivider />`
3. "Already have an account? Sign in" link at the bottom

```html
<!-- Registration Prompt -->
<div v-if="showRegister && !auth.isAuthenticated"
     class="card"
     role="region"
     aria-labelledby="register-title">
    <div class="card-body">
        <h5 id="register-title" class="card-title">
            Keep your memories safe
        </h5>
        <p class="card-text text-muted">
            Create an account to save your answers...
        </p>

        <!-- Google button -->
        <div ref="regGoogleBtnRef"></div>
        <div v-if="regGoogleError"
             role="alert"
             class="alert alert-danger mt-2 py-2">
            {{ regGoogleError }}
        </div>

        <AuthDivider />

        <!-- Existing email/name/terms form -->
        <div class="mb-3">
            <label for="reg-email"
                   class="visually-hidden">
                Email
            </label>
            <input id="reg-email"
                   v-model="regEmail"
                   type="email"
                   class="form-control mb-2"
                   placeholder="Email" />
            <label for="reg-name"
                   class="visually-hidden">
                Your name
            </label>
            <input id="reg-name"
                   v-model="regName"
                   type="text"
                   class="form-control mb-2"
                   placeholder="Your name" />
            <div class="form-check">
                <input v-model="regAcceptTerms"
                       type="checkbox"
                       class="form-check-input"
                       id="acceptTerms" />
                <label class="form-check-label"
                       for="acceptTerms">
                    I agree to the
                    <a href="/terms" target="_blank">
                        Terms of Service
                    </a>
                </label>
            </div>
        </div>

        <div v-if="regError"
             role="alert"
             class="alert alert-danger py-2">
            {{ regError }}
        </div>

        <div class="d-flex gap-2">
            <button class="btn btn-primary"
                    :disabled="regSubmitting"
                    @click="handleRegister">
                {{ regSubmitting
                    ? "Creating..."
                    : "Create Account" }}
            </button>
            <button class="btn btn-link text-muted"
                    @click="showRegister = false">
                Skip for now
            </button>
        </div>

        <p class="text-center mt-3 mb-0 small">
            Already have an account?
            <button class="btn btn-link btn-sm p-0"
                    @click="showSignIn = true;
                            showRegister = false">
                Sign in
            </button>
        </p>
    </div>
</div>
```

For the registration prompt's Google button, use a separate composable instance with `questionToken`.

> **Mutual exclusivity:** `showSignIn` and `showRegister` are never both true simultaneously — the "Sign in" link in the registration prompt sets `showSignIn = true; showRegister = false`, and vice versa. This prevents both Google button instances from being mounted at once, which avoids a GIS `initialize()` callback conflict (the last `initialize` call wins the global callback).

```typescript
const regGoogleBtnRef =
    ref<HTMLElement | null>(null);

const {
    renderButton: renderRegGoogle,
    error: regGoogleError
} = useGoogleSignIn({
    questionToken: token,
    buttonText: "signup_with",
    onSuccess: handleSignInSuccess,
});

watch(showRegister, async (val) => {
    if (val && !auth.isAuthenticated) {
        await nextTick();
        if (regGoogleBtnRef.value) {
            renderRegGoogle(regGoogleBtnRef.value);
        }
    }
});
```

---

## Phase 5: Backend Tests

### 5.1 GoogleAuthService Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/GoogleAuthServiceTest.cs`

Mock `IGoogleTokenVerifier` to return controlled payloads. Test the user lookup/creation and answer linking logic against a real DB.

**Test cases:**

| # | Test | What it verifies |
|---|------|------------------|
| 1 | `NewUserCreatedFromGoogle` | New user created when no matching email or Google sub |
| 2 | `ExistingUserByGoogleSub` | Returns existing userId when Google sub already linked |
| 3 | `ExistingUserByEmail_LinksGoogle` | Matches by email, creates ExternalLogin |
| 4 | `InvalidToken_ThrowsBadRequest` | Bad token -> BadRequestException |
| 5 | `LinksAnswersWhenQuestionTokenProvided` | Answers transferred to user when questionToken given |
| 6 | `NoQuestionToken_SkipsLinking` | No questionToken -> no linking attempted |
| 7 | `DuplicateGoogleSub_ReturnsSameUser` | Second call with same Google account -> same userId |

### 5.2 QuestionService.LinkAnswersToUserAsync Tests

**File:** `cimplur-core/Memento/DomainTest/Repositories/QuestionServiceTest.cs` (extend existing)

| # | Test | What it verifies |
|---|------|------------------|
| 8 | `LinkAnswers_TransfersOwnership` | Drop.UserId set to new user |
| 9 | `LinkAnswers_CreatorRetainsAccess` | UserDrop created for creator |
| 10 | `LinkAnswers_InvalidToken_NoOp` | Invalid token -> no exception, no changes |
| 11 | `LinkAnswers_AlreadyLinked_NoOp` | Already linked to same user -> skip |
| 12 | `LinkAnswers_LinkedToDifferentUser_Overwrites` | Already linked to different user -> re-links to new user |
| 13 | `RegisterAndLink_NewUser_GetsHelloWorld` | New user gets HelloWorld networks and drop |
| 14 | `RegisterAndLink_ExistingUser_NoHelloWorld` | Existing user does not get duplicate HelloWorld content |

---

## Phase 6: Frontend Tests

### 6.1 useGoogleSignIn Composable Tests

**File:** `fyli-fe-v2/src/composables/useGoogleSignIn.test.ts`

| # | Test | What it verifies |
|---|------|------------------|
| 1 | `renderButton loads GIS script` | Script tag added to document head |
| 2 | `renderButton shows error when no client ID` | Error ref set when env var missing |
| 3 | `handleCredentialResponse calls googleAuth API` | API called with credential |
| 4 | `handleCredentialResponse sets auth token on success` | Auth store token set |
| 5 | `handleCredentialResponse calls onSuccess callback` | Callback invoked |
| 6 | `handleCredentialResponse sets error on API failure` | Error ref set |
| 7 | `passes questionToken to googleAuth` | API called with questionToken |

### 6.2 AuthDivider Tests

**File:** `fyli-fe-v2/src/components/ui/AuthDivider.test.ts`

| # | Test | What it verifies |
|---|------|------------------|
| 1 | `renders "or" text` | Divider text visible |
| 2 | `has aria-hidden="true"` | Decorative, hidden from screen readers |

### 6.3 LoginView Tests (Update)

**File:** `fyli-fe-v2/src/views/auth/LoginView.test.ts`

Add to existing tests:

| # | Test | What it verifies |
|---|------|------------------|
| 6 | `renders Google sign-in button container` | Google button div exists |
| 7 | `renders AuthDivider` | Divider component present |

> Validation step: Verify existing magic link tests (1-5) still pass after changes.

### 6.4 RegisterView Tests (Update)

**File:** `fyli-fe-v2/src/views/auth/RegisterView.test.ts`

Add:

| # | Test | What it verifies |
|---|------|------------------|
| 6 | `renders Google sign-up button container` | Google button div exists |
| 7 | `renders AuthDivider` | Divider component present |

### 6.5 QuestionAnswerView Tests (Update)

**File:** `fyli-fe-v2/src/views/question/QuestionAnswerView.test.ts`

Add:

| # | Test | What it verifies |
|---|------|------------------|
| 13 | `shows "Have an account? Sign in" when not authenticated` | Link visible before signing in |
| 14 | `hides sign-in link when authenticated` | Link not visible when logged in |
| 15 | `clicking sign in shows inline sign-in section` | Card with Google + magic link appears |
| 16 | `cancel collapses sign-in section` | Back to just the text link |
| 17 | `registration prompt has Google button` | Google div in registration card |
| 18 | `registration prompt has "Already have an account?" link` | Link visible in registration prompt |
| 19 | `clicking "Already have an account?" shows sign-in section` | Opens sign-in, hides registration |
| 20 | `magic link form in sign-in section sends email with returnTo` | requestMagicLink called with `/q/token` |
| 21 | `magic link shows "Check your email" on success` | Success state renders |
| 22 | `shows "Signed in as [name]" badge when authenticated` | Badge visible with user name |
| 23 | `hides sign-in link and shows badge after sign-in` | Sign-in link replaced by badge |

### 6.6 Auth API Tests

**File:** `fyli-fe-v2/src/services/authApi.test.ts` (extend existing — 4 tests already exist)

> **Existing test update:** Test #3 (`requestMagicLink sends POST /users/token`) must be updated to expect `{ email: "alice@example.com", returnTo: undefined }` since the payload now includes the `returnTo` key.

| # | Test | What it verifies |
|---|------|------------------|
| 5 | `googleAuth sends POST with idToken` | Correct endpoint and payload |
| 6 | `googleAuth sends questionToken when provided` | Optional param included |
| 7 | `googleAuth omits questionToken when not provided` | Not sent when undefined |
| 8 | `requestMagicLink sends returnTo when provided` | ReturnTo param included |
| 9 | `requestMagicLink omits returnTo when not provided` | Not sent when undefined |

---

## Implementation Order

1. **Phase 1** — Backend entity, migration, service, endpoint, returnTo support
2. **Phase 2** — Frontend API function, composable, AuthDivider component
3. **Phase 3** — Login & Register page updates
4. **Phase 4** — Question answer page updates
5. **Phase 5** — Backend tests
6. **Phase 6** — Frontend tests

Phases 5 and 6 can run in parallel after their respective implementation phases.

---

## Documentation

- Update `cimplur-core/docs/DATA_SCHEMA.md` with `ExternalLogins` table schema
- Update `docs/release_note.md` with Google Sign-In feature entry

---

## Open Questions Resolution

These questions were raised in the PRD. All answered "yes":

| # | Question | Answer | TDD Coverage |
|---|----------|--------|--------------|
| 1 | Should the magic link flow during question answering keep the user on the page? | **Yes** | Phase 1.10 — `ReturnTo` param added to `EmailModel`, embedded in email template, MagicLinkView already handles `route` param |
| 2 | Handle the case where a Google account email matches an existing Fyli account created with a different email? | **Yes** | "Email-Match Edge Case" section — lookup by Google sub first, then fall back to email match, never create duplicates |
| 3 | Show a "Signed in as [name]" badge on the question page after successful auth? | **Yes** | Phase 4.7 — Badge reads from auth store, replaces the sign-in link position when authenticated |

---

## Backwards Compatibility

- Magic link auth unchanged — `requestMagicLink` adds optional `returnTo` but existing calls without it still work (defaults to `/`)
- `RegisterAndLinkAnswers` refactored but behavior identical (calls new extracted method). New users now also get HelloWorld onboarding content (previously missing).
- No existing DB columns modified or removed
- New `ExternalLogins` table is additive
- Users without Google linked continue using magic links normally
- Anonymous question flow works exactly as before if user doesn't sign in
- Drop ownership and creator access patterns identical to existing `RegisterAndLinkAnswers`
- `EmailModel` gains optional `ReturnTo` property — existing callers that don't send it are unaffected

### !IMPORTANT! — Login Email Template URL Change

The Login email template URL changes from `/#/?link=TOKEN` (old AngularJS hash routing) to `/auth/verify#token=TOKEN&route=ROUTE` (new frontend). **This is a breaking change for the old frontend (`fyli-fe`).** Magic link emails sent after this deploy will not work on the old AngularJS app.

**Prerequisite:** Confirm the old frontend is fully decommissioned and all traffic routes to `fyli-fe-v2` before deploying this change. If both frontends are live simultaneously, this change must be coordinated with the old frontend's retirement.

---

## Files Changed

### Backend (cimplur-core)
| File | Action |
|------|--------|
| `Domain/Entities/ExternalLogin.cs` | **New** |
| `Domain/Entities/StreamContext.cs` | Edit — add OnModelCreating + DbSet |
| `Domain/Models/AppSettings.cs` | Edit — add GoogleClientId |
| `Domain/Repositories/GoogleAuthService.cs` | **New** |
| `Domain/Repositories/IGoogleTokenVerifier.cs` | **New** |
| `Domain/Repositories/GoogleTokenVerifier.cs` | **New** |
| `Domain/Repositories/QuestionService.cs` | Edit — extract LinkAnswersToUserAsync, add HelloWorld to RegisterAndLinkAnswers |
| `Domain/Repositories/IQuestionService.cs` | Edit — add LinkAnswersToUserAsync |
| `Domain/Emails/EmailTemplates.cs` | Edit — add route param to Login template |
| `Memento/Controllers/UserController.cs` | Edit — add GoogleAuth endpoint, pass ReturnTo |
| `Memento/Models/GoogleAuthModel.cs` | **New** |
| `Memento/Models/EmailModel.cs` | Edit — add ReturnTo property |
| `Memento/Startup.cs` | Edit — register GoogleAuthService, IGoogleTokenVerifier |
| `Memento/appsettings.json` | Edit — add GoogleClientId |
| `DomainTest/Repositories/GoogleAuthServiceTest.cs` | **New** |

### Frontend (fyli-fe-v2)
| File | Action |
|------|--------|
| `src/services/authApi.ts` | Edit — add googleAuth, update requestMagicLink |
| `src/composables/useGoogleSignIn.ts` | **New** |
| `src/components/ui/AuthDivider.vue` | **New** |
| `src/views/auth/LoginView.vue` | Edit — add Google button + AuthDivider |
| `src/views/auth/RegisterView.vue` | Edit — add Google button + AuthDivider |
| `src/views/question/QuestionAnswerView.vue` | Edit — sign-in link, inline sign-in, updated registration prompt |
| `.env` | Edit — add VITE_GOOGLE_CLIENT_ID |
| `src/composables/useGoogleSignIn.test.ts` | **New** |
| `src/components/ui/AuthDivider.test.ts` | **New** |
| `src/services/authApi.test.ts` | Edit — add googleAuth tests, update requestMagicLink test for returnTo |
| `src/views/auth/LoginView.test.ts` | Edit — add Google button tests |
| `src/views/auth/RegisterView.test.ts` | Edit — add Google button tests |
| `src/views/question/QuestionAnswerView.test.ts` | Edit — add sign-in flow tests |

### Config
| File | Action |
|------|--------|
| `cimplur-core/Memento/Memento/appsettings.json` | Edit |
| `fyli-fe-v2/.env` | Edit |

### Documentation
| File | Action |
|------|--------|
| `cimplur-core/docs/DATA_SCHEMA.md` | Edit — add ExternalLogins schema |
| `docs/release_note.md` | Edit — add Google Sign-In feature |

---

*Document Version: 3.1*
*Created: 2026-02-08*
*Updated: 2026-02-08 — Code review round 3: fix DropsService note, document old frontend breaking change, role="alert" consistency, fix authApi.test.ts status, add HelloWorld tests*
