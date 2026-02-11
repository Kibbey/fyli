# TDD: Universal Google OAuth Across All Touchpoints

**PRD:** `docs/prd/PRD_UNIVERSAL_GOOGLE_AUTH.md`
**Status:** Draft
**Created:** 2026-02-10

## Overview

Extract the inline authentication pattern from `QuestionAnswerView.vue` into a reusable `InlineAuth.vue` component, then deploy it consistently across all anonymous touchpoints: shared memory links (`/s/:token`), storyline invitations (new `/st/:token`), and connection invitations (new `/invite/:token`). On the backend, extend the `google-auth` endpoint to accept `shareToken` and `inviteToken` alongside the existing `questionToken`, and build a new `TimelineShareLink` entity + public endpoints for storyline invitations.

## Component Diagram

```
Frontend
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  InlineAuth.vue (new shared component)                          │
│  ├── useGoogleSignIn composable (existing, extended)            │
│  ├── AuthDivider.vue (existing, unchanged)                      │
│  └── Magic link form (inline)                                   │
│                                                                 │
│  Used by:                                                       │
│  ├── QuestionAnswerView.vue  (refactor to use InlineAuth)       │
│  ├── SharedMemoryView.vue    (replace current auth section)     │
│  ├── StorylineInviteView.vue (new)                              │
│  └── ConnectionInviteView.vue (new)                             │
│                                                                 │
│  authApi.ts (extended: shareToken, inviteToken params)          │
│  shareLinkApi.ts (unchanged)                                    │
│  timelineShareApi.ts (new)                                      │
│  connectionInviteApi.ts (new)                                   │
└─────────────────────────────────────────────────────────────────┘

Backend
┌─────────────────────────────────────────────────────────────────┐
│  UserController (extended: GoogleAuthModel gets new tokens)     │
│  ShareLinkController (unchanged)                                │
│  TimelineShareLinkController (new)                              │
│                                                                 │
│  GoogleAuthService (extended: shareToken, inviteToken handling) │
│  TimelineShareLinkService (new, mirrors MemoryShareLinkService) │
│  TimelineService (minor: public preview method)                 │
│  SharingService (existing: ConfirmationSharingRequest)          │
│                                                                 │
│  TimelineShareLink (new entity)                                 │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
cimplur-core/
├── Memento/
│   ├── Controllers/
│   │   └── TimelineShareLinkController.cs  (NEW)
│   └── Models/
│       ├── GoogleAuthModel.cs              (MODIFIED — add ShareToken, InviteToken)
│       └── TimelineShareLinkRegisterModel.cs (NEW)
├── Domain/
│   ├── Entities/
│   │   ├── TimelineShareLink.cs            (NEW)
│   │   └── StreamContext.cs                (MODIFIED — add DbSet + config)
│   └── Repositories/
│       ├── GoogleAuthService.cs            (MODIFIED — handle new tokens)
│       └── TimelineShareLinkService.cs     (NEW)

fyli-fe-v2/
├── src/
│   ├── components/
│   │   └── auth/
│   │       └── InlineAuth.vue              (NEW)
│   ├── composables/
│   │   └── useGoogleSignIn.ts              (MODIFIED — add shareToken, inviteToken)
│   ├── services/
│   │   ├── authApi.ts                      (MODIFIED — add token params)
│   │   ├── timelineShareApi.ts             (NEW)
│   │   └── connectionInviteApi.ts          (NEW)
│   └── views/
│       ├── question/
│       │   └── QuestionAnswerView.vue      (MODIFIED — use InlineAuth)
│       ├── share/
│       │   └── SharedMemoryView.vue        (MODIFIED — use InlineAuth)
│       ├── storyline/
│       │   └── StorylineInviteView.vue     (NEW)
│       └── invite/
│           └── ConnectionInviteView.vue    (NEW)
```

---

## Phase 1: Reusable InlineAuth Component

Extract the auth pattern from `QuestionAnswerView.vue` into a shared component.

### 1.1 Create `InlineAuth.vue`

**File:** `fyli-fe-v2/src/components/auth/InlineAuth.vue`

This component encapsulates the full inline auth experience:
- **Collapsed state:** Two muted links ("Have an account? Sign in · New here? Sign up")
- **Expanded sign-in:** Google button + magic link form + "Don't have an account? Sign up" toggle + Cancel
- **Expanded register:** Google button + email/name/terms form + "Already have an account? Sign in" toggle + Cancel
- **Signed-in badge:** Shows after successful auth

**Props:**

```typescript
interface InlineAuthProps {
  signinHeading: string         // e.g., "Sign in to save your answers"
  registerHeading: string       // e.g., "Keep your memories safe"
  registerDescription?: string  // e.g., "Create an account to save your answers..."
  questionToken?: string        // For question answer linking
  shareToken?: string           // For shared memory claiming
  inviteToken?: string          // For storyline/connection invite acceptance
  buttonText?: 'signin_with' | 'signup_with'  // Google button label
  returnTo?: string             // Magic link return path
  registerFn?: (email: string, name: string, acceptTerms: boolean) => Promise<string>
    // Optional context-specific registration function. Returns JWT.
    // When provided, used instead of the generic authApi.register().
    // Each view passes its own endpoint (e.g., registerViaStoryline, registerViaLink).
    // When omitted, falls back to authApi.register() (generic registration).
  magicLinkFn?: (email: string) => Promise<void>
    // Optional context-specific magic link function.
    // When provided, used instead of authApi.requestMagicLink().
    // E.g., storyline invite page sends magic link via /storylines/:token/signin.
    // When omitted, falls back to authApi.requestMagicLink(email, returnTo).
    // Note: wrapper functions should return Promise<void> even though the
    // underlying API call returns AxiosResponse — just await without returning.
}
```

**Emits:**

```typescript
const emit = defineEmits<{
  success: []   // Fired after successful auth (Google or magic link registration)
}>()
```

**Internal state:**

```typescript
const mode = ref<'collapsed' | 'signin' | 'register'>('collapsed')

// Sign-in state
const magicLinkEmail = ref('')
const magicLinkSending = ref(false)
const magicLinkSent = ref(false)
const signInError = ref('')

// Registration state
const regEmail = ref('')
const regName = ref('')
const regAcceptTerms = ref(false)
const regSubmitting = ref(false)
const regError = ref('')

// Google button refs
const signInGoogleBtnRef = ref<HTMLElement | null>(null)
const regGoogleBtnRef = ref<HTMLElement | null>(null)

// Unique ID for terms checkbox (avoids collision if multiple instances render)
const termsId = useId()
```

**Template structure:**

```vue
<template>
  <!-- Signed-in badge -->
  <div v-if="auth.isAuthenticated && auth.user" class="text-center mt-2">
    <span class="badge bg-light text-dark border">
      <span class="mdi mdi-check-circle text-success me-1"></span>
      Signed in as {{ auth.user.name }}
    </span>
  </div>

  <!-- Collapsed CTA -->
  <div v-else-if="mode === 'collapsed'" class="text-center mt-2">
    <span class="text-muted small">
      Have an account?
      <button class="btn btn-link btn-sm text-muted p-0"
        aria-label="Sign in to your account"
        @click="mode = 'signin'">Sign in</button>
      ·
      New here?
      <button class="btn btn-link btn-sm text-muted p-0"
        aria-label="Create a new account"
        @click="mode = 'register'">Sign up</button>
    </span>
  </div>

  <!-- Sign-in form -->
  <div v-else-if="mode === 'signin'" class="card mb-4">
    <div class="card-body">
      <h6 class="card-title mb-3">{{ signinHeading }}</h6>

      <div ref="signInGoogleBtnRef"></div>
      <div v-if="googleSignInError" class="alert alert-danger mt-2 py-2">{{ googleSignInError }}</div>

      <AuthDivider />

      <div v-if="magicLinkSent" class="text-center py-2">
        <span class="mdi mdi-email-check-outline" style="font-size: 2rem; color: var(--fyli-primary)"></span>
        <p class="mt-2 mb-0 small">Check your email for a sign-in link.</p>
      </div>
      <form v-else class="d-flex gap-2" @submit.prevent="handleMagicLink">
        <input v-model="magicLinkEmail" type="email" class="form-control form-control-sm"
          placeholder="Email" aria-label="Email address" required />
        <button type="submit" class="btn btn-sm btn-outline-primary text-nowrap" :disabled="magicLinkSending">
          {{ magicLinkSending ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div v-if="signInError" class="alert alert-danger mt-2 py-2">{{ signInError }}</div>

      <p class="small mt-2 mb-1">
        Don't have an account?
        <button class="btn btn-link btn-sm p-0" @click="mode = 'register'">Sign up</button>
      </p>
      <button class="btn btn-link btn-sm text-muted" @click="mode = 'collapsed'">Cancel</button>
    </div>
  </div>

  <!-- Registration form -->
  <div v-else-if="mode === 'register'" class="card mb-4">
    <div class="card-body">
      <h6 class="card-title mb-3">{{ registerHeading }}</h6>
      <p v-if="registerDescription" class="card-text text-muted">{{ registerDescription }}</p>

      <div ref="regGoogleBtnRef"></div>
      <div v-if="regGoogleError" class="alert alert-danger mt-2 py-2">{{ regGoogleError }}</div>

      <AuthDivider />

      <div class="mb-3">
        <input v-model="regEmail" type="email" class="form-control mb-2"
          placeholder="Email" aria-label="Email address" />
        <input v-model="regName" type="text" class="form-control mb-2"
          placeholder="Your name" aria-label="Your name" />
        <div class="form-check">
          <input v-model="regAcceptTerms" type="checkbox"
            class="form-check-input" :id="termsId" />
          <label class="form-check-label" :for="termsId">
            I agree to the <a href="/terms" target="_blank">Terms of Service</a>
          </label>
        </div>
      </div>

      <div v-if="regError" class="alert alert-danger py-2">{{ regError }}</div>

      <button class="btn btn-primary" :disabled="regSubmitting" @click="handleRegister">
        {{ regSubmitting ? 'Creating...' : 'Create Account' }}
      </button>

      <p class="small mt-3 mb-1">
        Already have an account?
        <button class="btn btn-link btn-sm p-0" @click="mode = 'signin'">Sign in</button>
      </p>
      <button class="btn btn-link btn-sm text-muted" @click="mode = 'collapsed'">Cancel</button>
    </div>
  </div>
</template>
```

**Script logic:**

- Two `useGoogleSignIn` instances (sign-in + register), same as `QuestionAnswerView.vue` today. Error refs are destructured from each instance:
  ```typescript
  const { renderButton: renderSignInBtn, error: googleSignInError }
    = useGoogleSignIn({ ...signInOptions })
  const { renderButton: renderRegBtn, error: regGoogleError }
    = useGoogleSignIn({ ...registerOptions })
  ```
- `handleMagicLink()`: if `props.magicLinkFn` is provided, calls it; otherwise calls `requestMagicLink(email, returnTo)` from `authApi.ts`
- `handleRegister()`: if `props.registerFn` is provided, calls it and uses the returned JWT; otherwise calls `register(name, email, acceptTerms)` from `authApi.ts`. In both cases: `auth.setToken(jwt)` + `auth.fetchUser()` + `emit('success')`
- Both Google `onSuccess` callbacks: `emit('success')`
- `watch(mode)` triggers `renderButton()` on `nextTick` (same pattern as current code)

```typescript
async function handleMagicLink() {
  magicLinkSending.value = true
  signInError.value = ''
  try {
    if (props.magicLinkFn) {
      await props.magicLinkFn(magicLinkEmail.value)
    } else {
      await requestMagicLink(magicLinkEmail.value, props.returnTo)
    }
    magicLinkSent.value = true
  } catch (e: unknown) {
    signInError.value = getErrorMessage(e, 'Failed to send magic link.')
  } finally {
    magicLinkSending.value = false
  }
}

async function handleRegister() {
  if (!regAcceptTerms.value) {
    regError.value = 'You must accept the terms.'
    return
  }
  regSubmitting.value = true
  regError.value = ''
  try {
    let jwt: string
    if (props.registerFn) {
      jwt = await props.registerFn(
        regEmail.value, regName.value, regAcceptTerms.value)
    } else {
      // Generic fallback — creates account without linking to any
      // context (no question/share/invite token). This is intentional
      // for pages like /invite/:token where registration has no
      // context-specific endpoint. The connection is accepted
      // client-side via handleAuthSuccess after auth completes.
      const { data } = await register(
        regName.value, regEmail.value, regAcceptTerms.value)
      jwt = data
    }
    auth.setToken(jwt)
    await auth.fetchUser()
    emit('success')
  } catch (e: unknown) {
    regError.value = getErrorMessage(e, 'Registration failed.')
  } finally {
    regSubmitting.value = false
  }
}
```

### 1.2 Create `InlineAuthPrompt.vue`

**File:** `fyli-fe-v2/src/components/auth/InlineAuthPrompt.vue`

A wrapper for the post-action registration prompt (auto-triggered, includes "Skip for now").

**Props:**

```typescript
interface InlineAuthPromptProps {
  heading: string
  description: string
  questionToken?: string
  shareToken?: string
  inviteToken?: string
  returnTo?: string
  registerFn?: (email: string, name: string, acceptTerms: boolean) => Promise<string>
  magicLinkFn?: (email: string) => Promise<void>
}
```

**Emits:**

```typescript
const emit = defineEmits<{
  success: []
  skip: []
}>()
```

**Internal state:**

```typescript
const mode = ref<'register' | 'signin'>('register')

// Same state vars as InlineAuth for registration + magic link
const regEmail = ref('')
const regName = ref('')
const regAcceptTerms = ref(false)
const regSubmitting = ref(false)
const regError = ref('')
const magicLinkEmail = ref('')
const magicLinkSending = ref(false)
const magicLinkSent = ref(false)
const signInError = ref('')
const signInGoogleBtnRef = ref<HTMLElement | null>(null)
const regGoogleBtnRef = ref<HTMLElement | null>(null)
const termsId = useId()
```

**Template:**

```vue
<template>
  <div v-if="auth.isAuthenticated && auth.user" class="text-center mt-2">
    <span class="badge bg-light text-dark border">
      <span class="mdi mdi-check-circle text-success me-1"></span>
      Signed in as {{ auth.user.name }}
    </span>
  </div>

  <!-- Registration form (default) -->
  <div v-else-if="mode === 'register'" class="card mb-4">
    <div class="card-body">
      <h6 class="card-title mb-3">{{ heading }}</h6>
      <p class="card-text text-muted">{{ description }}</p>

      <div ref="regGoogleBtnRef"></div>
      <div v-if="regGoogleError" class="alert alert-danger mt-2 py-2">
        {{ regGoogleError }}
      </div>

      <AuthDivider />

      <div class="mb-3">
        <input v-model="regEmail" type="email"
          class="form-control mb-2" placeholder="Email"
          aria-label="Email address" />
        <input v-model="regName" type="text"
          class="form-control mb-2" placeholder="Your name"
          aria-label="Your name" />
        <div class="form-check">
          <input v-model="regAcceptTerms" type="checkbox"
            class="form-check-input" :id="termsId" />
          <label class="form-check-label" :for="termsId">
            I agree to the
            <a href="/terms" target="_blank">Terms of Service</a>
          </label>
        </div>
      </div>

      <div v-if="regError" class="alert alert-danger py-2">
        {{ regError }}
      </div>

      <div class="d-flex align-items-center gap-2">
        <button class="btn btn-primary" :disabled="regSubmitting"
          @click="handleRegister">
          {{ regSubmitting ? 'Creating...' : 'Create Account' }}
        </button>
        <button class="btn btn-link btn-sm text-muted"
          @click="emit('skip')">
          Skip for now
        </button>
      </div>

      <p class="small mt-3 mb-0">
        Already have an account?
        <button class="btn btn-link btn-sm p-0"
          @click="mode = 'signin'">Sign in</button>
      </p>
    </div>
  </div>

  <!-- Sign-in form (toggled) -->
  <div v-else-if="mode === 'signin'" class="card mb-4">
    <div class="card-body">
      <h6 class="card-title mb-3">Sign in</h6>

      <div ref="signInGoogleBtnRef"></div>
      <div v-if="googleSignInError" class="alert alert-danger mt-2 py-2">
        {{ googleSignInError }}
      </div>

      <AuthDivider />

      <div v-if="magicLinkSent" class="text-center py-2">
        <span class="mdi mdi-email-check-outline"
          style="font-size: 2rem; color: var(--fyli-primary)"></span>
        <p class="mt-2 mb-0 small">
          Check your email for a sign-in link.
        </p>
      </div>
      <form v-else class="d-flex gap-2"
        @submit.prevent="handleMagicLink">
        <input v-model="magicLinkEmail" type="email"
          class="form-control form-control-sm"
          placeholder="Email" aria-label="Email address" required />
        <button type="submit"
          class="btn btn-sm btn-outline-primary text-nowrap"
          :disabled="magicLinkSending">
          {{ magicLinkSending ? 'Sending...' : 'Send magic link' }}
        </button>
      </form>

      <div v-if="signInError" class="alert alert-danger mt-2 py-2">
        {{ signInError }}
      </div>

      <p class="small mt-2 mb-0">
        Don't have an account?
        <button class="btn btn-link btn-sm p-0"
          @click="mode = 'register'">Sign up</button>
      </p>
    </div>
  </div>
</template>
```

**Script logic:** Same `handleRegister`/`handleMagicLink` logic as `InlineAuth.vue`. Uses `props.registerFn` / `props.magicLinkFn` when provided, falls back to generic `authApi` calls.

### 1.3 Extend `useGoogleSignIn` Composable

**File:** `fyli-fe-v2/src/composables/useGoogleSignIn.ts`

Add `shareToken` and `inviteToken` options:

```typescript
export function useGoogleSignIn(options?: {
  questionToken?: string
  shareToken?: string     // NEW
  inviteToken?: string    // NEW
  onSuccess?: () => void
  buttonText?: 'signin_with' | 'signup_with'
}) {
  // ...existing code...

  async function handleCredentialResponse(response: { credential: string }) {
    loading.value = true
    error.value = ''
    try {
      const { data: jwt } = await googleAuth(
        response.credential,
        options?.questionToken,
        options?.shareToken,      // NEW
        options?.inviteToken       // NEW
      )
      auth.setToken(jwt)
      await auth.fetchUser()
      options?.onSuccess?.()
    } catch (e: unknown) {
      error.value = getErrorMessage(e, 'Google sign-in failed.')
    } finally {
      loading.value = false
    }
  }
  // ...
}
```

### 1.4 Extend `authApi.ts`

**File:** `fyli-fe-v2/src/services/authApi.ts`

```typescript
export function googleAuth(
  idToken: string,
  questionToken?: string,
  shareToken?: string,      // NEW
  inviteToken?: string       // NEW
) {
  const payload: Record<string, string> = { idToken }
  if (questionToken !== undefined) payload.questionToken = questionToken
  if (shareToken !== undefined) payload.shareToken = shareToken
  if (inviteToken !== undefined) payload.inviteToken = inviteToken
  return api.post<string>('/users/google-auth', payload)
}
```

### 1.5 Refactor `QuestionAnswerView.vue`

Replace the inline auth template and logic with `InlineAuth` and `InlineAuthPrompt` components. No functional changes — purely extracting to shared components.

**Before (lines 28-72, sign-in section):** ~45 lines of template
**After:**
```vue
<InlineAuth
  v-if="!showRegister"
  signin-heading="Sign in to save your answers"
  register-heading="Keep your memories safe"
  :register-description="`Create an account to save your answers to your own feed and get notified when ${view.creatorName} shares with you.`"
  :question-token="token"
  :return-to="`/q/${token}`"
  :register-fn="registerFn"
  @success="handleAuthSuccess"
/>
```

**Before (lines 135-180, registration prompt):** ~45 lines of template
**After:**
```vue
<InlineAuthPrompt
  v-if="showRegister && !auth.isAuthenticated"
  heading="Keep your memories safe"
  :description="`Create an account to save your answers to your own feed and get notified when ${view.creatorName} shares with you.`"
  :question-token="token"
  :return-to="`/q/${token}`"
  :register-fn="registerFn"
  @success="handleAuthSuccess"
  @skip="showRegister = false"
/>
```

Add context-specific registration function (the question page uses `/questions/answer/:token/register` which registers AND links answers atomically — NOT the generic `authApi.register()`):

```typescript
import { registerViaQuestion } from "@/services/questionApi";

// Uses /questions/answer/:token/register which registers
// AND links answers to the new user atomically
async function registerFn(
  email: string, name: string, acceptTerms: boolean
): Promise<string> {
  const { data: jwt } = await registerViaQuestion(
    token, email, name, acceptTerms
  );
  return jwt;
}
```

> **Note:** The magic link uses the default `authApi.requestMagicLink(email, returnTo)` fallback, which is correct — the question page doesn't have a context-specific magic link endpoint.

Removes ~90 lines of template and ~40 lines of script from `QuestionAnswerView.vue`.

---

## Phase 2: Shared Memory Link Updates (`/s/:token`)

### 2.1 Backend: Extend GoogleAuthModel

**File:** `cimplur-core/Memento/Memento/Models/GoogleAuthModel.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;

namespace Memento.Web.Models
{
    public class GoogleAuthModel
    {
        [Required]
        public string IdToken { get; set; }
        public Guid? QuestionToken { get; set; }
        public Guid? ShareToken { get; set; }    // NEW
        public Guid? InviteToken { get; set; }   // NEW
    }
}
```

### 2.2 Backend: Extend GoogleAuthService

**File:** `cimplur-core/Memento/Domain/Repositories/GoogleAuthService.cs`

Add `MemoryShareLinkService` and `TimelineShareLinkService` as constructor dependencies:

```csharp
private UserService userService;
private IQuestionService questionService;
private GroupService groupService;
private DropsService dropsService;
private IGoogleTokenVerifier tokenVerifier;
private AppSettings appSettings;
private MemoryShareLinkService shareLinkService;           // NEW
private TimelineShareLinkService timelineShareLinkService; // NEW

public GoogleAuthService(
    IOptions<AppSettings> appSettings,
    UserService userService,
    IQuestionService questionService,
    GroupService groupService,
    DropsService dropsService,
    IGoogleTokenVerifier tokenVerifier,
    MemoryShareLinkService shareLinkService,               // NEW
    TimelineShareLinkService timelineShareLinkService)     // NEW
{
    this.appSettings = appSettings.Value;
    this.userService = userService;
    this.questionService = questionService;
    this.groupService = groupService;
    this.dropsService = dropsService;
    this.tokenVerifier = tokenVerifier;
    this.shareLinkService = shareLinkService;               // NEW
    this.timelineShareLinkService = timelineShareLinkService; // NEW
}
```

Extend `AuthenticateAsync`:

```csharp
public async Task<int> AuthenticateAsync(
    string idToken,
    Guid? questionToken,
    Guid? shareToken,       // NEW
    Guid? inviteToken)      // NEW
{
    var payload = await VerifyGoogleTokenAsync(idToken);
    var userId = await FindOrCreateUserAsync(payload);

    if (questionToken.HasValue)
    {
        await questionService.LinkAnswersToUserAsync(
            questionToken.Value, userId);
    }

    if (shareToken.HasValue)
    {
        await shareLinkService.ClaimDropAccessAsync(
            shareToken.Value, userId);
    }

    if (inviteToken.HasValue)
    {
        await timelineShareLinkService.AcceptInviteAsync(
            inviteToken.Value, userId);
    }

    return userId;
}
```

### 2.3 Backend: Extend UserController

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

Pass the new tokens through:

```csharp
[EnableRateLimiting("registration")]
[HttpPost]
[Route("google-auth")]
public async Task<IActionResult> GoogleAuth(GoogleAuthModel model)
{
    var userId = await googleAuthService.AuthenticateAsync(
        model.IdToken,
        model.QuestionToken,
        model.ShareToken,      // NEW
        model.InviteToken);    // NEW
    var token = userWebToken.generateJwtToken(userId);
    return Ok(token);
}
```

### 2.4 Frontend: Update `SharedMemoryView.vue`

Replace the entire auth section (lines 100-135) with:

```vue
<!-- Auth section -->
<InlineAuth
  v-if="!claimed"
  signin-heading="Sign in to save this memory"
  register-heading="Save this memory to your account"
  register-description="Create an account to comment and keep this memory in your feed."
  :share-token="token"
  :return-to="`/s/${token}`"
  :register-fn="registerFn"
  :magic-link-fn="magicLinkFn"
  @success="handleAuthSuccess"
/>
```

Add context-specific registration/magic-link functions:

```typescript
import { registerViaLink, signInViaLink } from '@/services/shareLinkApi'

// Uses /s/:token/register which registers AND claims access atomically
async function registerFn(
  email: string, name: string, acceptTerms: boolean
): Promise<string> {
  const { data: jwt } = await registerViaLink(token, email, name, acceptTerms)
  return jwt
}

// Uses /s/:token/signin to send magic link with share context
async function magicLinkFn(email: string): Promise<void> {
  await signInViaLink(token, email)
}
```

Add `handleAuthSuccess`:

```typescript
async function handleAuthSuccess() {
  try {
    await claimAccess(token)
    claimed.value = true
  } catch {
    // Already claimed via google-auth endpoint — just update UI
    claimed.value = true
  }
}
```

The `onMounted` auto-claim for already-authenticated users remains unchanged.

---

## Phase 3: Storyline Invitation Flow (New)

### 3.1 Backend: `TimelineShareLink` Entity

**File:** `cimplur-core/Memento/Domain/Entities/TimelineShareLink.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class TimelineShareLink
    {
        public int TimelineShareLinkId { get; set; }
        public int TimelineId { get; set; }
        public int CreatorUserId { get; set; }
        public Guid Token { get; set; }
        public bool IsActive { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? ExpiresAt { get; set; }
        public int ViewCount { get; set; }

        [ForeignKey("TimelineId")]
        public virtual Timeline Timeline { get; set; }

        [ForeignKey("CreatorUserId")]
        public virtual UserProfile Creator { get; set; }
    }
}
```

### 3.2 Backend: StreamContext Changes

**File:** `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

Add to `OnModelCreating`:

```csharp
modelBuilder.Entity<TimelineShareLink>(entity =>
{
    entity.HasKey(e => e.TimelineShareLinkId);

    entity.HasIndex(e => e.Token).IsUnique();
    entity.HasIndex(e => e.TimelineId);
    entity.HasIndex(e => e.CreatorUserId);

    entity.HasOne(e => e.Timeline)
        .WithMany()
        .HasForeignKey(e => e.TimelineId)
        .OnDelete(DeleteBehavior.Restrict);

    entity.HasOne(e => e.Creator)
        .WithMany()
        .HasForeignKey(e => e.CreatorUserId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

Add DbSet:

```csharp
public DbSet<TimelineShareLink> TimelineShareLinks { get; set; }
```

### 3.3 Database Migration

Generate migration:
```bash
cd cimplur-core/Memento && dotnet ef migrations add AddTimelineShareLinks --project Domain --startup-project Memento
```

**Raw SQL reference (approximate — for review only):**

> **IMPORTANT:** This hand-written SQL is an approximation of the expected schema. The actual production SQL **must** be generated via EF Core tooling after the migration is created:
> ```bash
> dotnet ef migrations script <previous_migration> --idempotent --project Domain --startup-project Memento
> ```
> Save the generated SQL to `docs/migrations/` per `DATABASE_GUIDE.md` conventions.

```sql
-- APPROXIMATE REFERENCE — DO NOT USE DIRECTLY IN PRODUCTION
IF OBJECT_ID(N'[TimelineShareLinks]', N'U') IS NULL
BEGIN
    CREATE TABLE [TimelineShareLinks] (
        [TimelineShareLinkId] INT IDENTITY(1,1) NOT NULL,
        [TimelineId] INT NOT NULL,
        [CreatorUserId] INT NOT NULL,
        [Token] UNIQUEIDENTIFIER NOT NULL,
        [IsActive] BIT NOT NULL,
        [CreatedAt] DATETIME2 NOT NULL,
        [ExpiresAt] DATETIME2 NULL,
        [ViewCount] INT NOT NULL DEFAULT 0,
        CONSTRAINT [PK_TimelineShareLinks] PRIMARY KEY ([TimelineShareLinkId]),
        CONSTRAINT [FK_TimelineShareLinks_Timelines_TimelineId] FOREIGN KEY ([TimelineId])
            REFERENCES [Timelines] ([TimelineId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_TimelineShareLinks_UserProfiles_CreatorUserId] FOREIGN KEY ([CreatorUserId])
            REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );

    CREATE UNIQUE INDEX [IX_TimelineShareLinks_Token]
        ON [TimelineShareLinks] ([Token]);

    CREATE INDEX [IX_TimelineShareLinks_TimelineId]
        ON [TimelineShareLinks] ([TimelineId]);

    CREATE INDEX [IX_TimelineShareLinks_CreatorUserId]
        ON [TimelineShareLinks] ([CreatorUserId]);
END;
```

### 3.4 Backend: `TimelineShareLinkService`

**File:** `cimplur-core/Memento/Domain/Repositories/TimelineShareLinkService.cs`

Mirrors `MemoryShareLinkService` pattern:

```csharp
using Domain.Entities;
using Domain.Exceptions;
using Domain.Models;
using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace Domain.Repository
{
    public class TimelineShareLinkService : BaseService
    {
        private SharingService sharingService;
        private GroupService groupService;
        private UserService userService;
        private DropsService dropsService;
        private ImageService imageService;
        private MovieService movieService;

        public TimelineShareLinkService(
            SharingService sharingService,
            GroupService groupService,
            UserService userService,
            DropsService dropsService,
            ImageService imageService,
            MovieService movieService)
        {
            this.sharingService = sharingService;
            this.groupService = groupService;
            this.userService = userService;
            this.dropsService = dropsService;
            this.imageService = imageService;
            this.movieService = movieService;
        }

        /// <summary>
        /// Create a shareable link for a timeline. Returns existing active token if one exists.
        /// Only the timeline creator can create links.
        /// </summary>
        public async Task<Guid> CreateLinkAsync(int userId, int timelineId)
        {
            var timeline = await Context.Timelines
                .SingleOrDefaultAsync(t => t.TimelineId == timelineId);

            if (timeline == null)
                throw new NotFoundException("Storyline not found.");

            if (timeline.UserId != userId)
                throw new NotAuthorizedException("Only the storyline creator can create share links.");

            var existing = await Context.TimelineShareLinks
                .FirstOrDefaultAsync(l =>
                    l.TimelineId == timelineId &&
                    l.CreatorUserId == userId &&
                    l.IsActive);

            if (existing != null)
                return existing.Token;

            var link = new TimelineShareLink
            {
                TimelineId = timelineId,
                CreatorUserId = userId,
                Token = Guid.NewGuid(),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                ViewCount = 0
            };

            Context.TimelineShareLinks.Add(link);
            await Context.SaveChangesAsync();

            return link.Token;
        }

        /// <summary>
        /// Get timeline preview data for public view by share link token.
        /// Returns timeline metadata plus the full memory feed (read-only).
        /// </summary>
        public async Task<TimelinePreviewModel> GetPreviewByTokenAsync(Guid token)
        {
            var link = await ValidateLinkAsync(token);

            await Context.Database.ExecuteSqlInterpolatedAsync(
                $"UPDATE \"TimelineShareLinks\" SET \"ViewCount\" = \"ViewCount\" + 1 WHERE \"TimelineShareLinkId\" = {link.TimelineShareLinkId}");

            var timeline = await Context.Timelines
                .Include(t => t.Owner)
                .SingleOrDefaultAsync(t => t.TimelineId == link.TimelineId);

            if (timeline == null)
                throw new NotFoundException("Storyline not found.");

            // Load drops for this timeline (newest first, limited preview)
            var timelineDrops = await Context.TimelineDrops
                .Where(td => td.TimelineId == timeline.TimelineId)
                .OrderByDescending(td => td.CreatedAt)
                .Take(20)
                .Select(td => td.DropId)
                .ToListAsync();

            var drops = await LoadDropModels(timelineDrops, timeline.UserId);

            return new TimelinePreviewModel
            {
                TimelineId = timeline.TimelineId,
                Name = timeline.Name,
                Description = timeline.Description,
                CreatorName = timeline.Owner.Name ?? timeline.Owner.UserName,
                MemoryCount = await Context.TimelineDrops
                    .CountAsync(td => td.TimelineId == timeline.TimelineId),
                Drops = drops
            };
        }

        /// <summary>
        /// Register a new user (or find existing) via timeline share link,
        /// create a connection with the creator, and add them as a timeline follower.
        /// </summary>
        public async Task<int> RegisterAndJoinAsync(
            Guid token, string email, string name, bool acceptTerms)
        {
            if (!acceptTerms)
                throw new BadRequestException("You must accept the terms to create an account.");

            var link = await ValidateLinkAsync(token);

            var existingUser = await Context.UserProfiles
                .SingleOrDefaultAsync(u => u.Email.Equals(email));

            int userId;
            if (existingUser != null)
            {
                userId = existingUser.UserId;
            }
            else
            {
                userId = await userService.AddUser(
                    email, email, null, acceptTerms, name, null);
                groupService.AddHelloWorldNetworks(userId);
                await dropsService.AddHelloWorldDrop(userId);
            }

            await JoinTimelineAsync(userId, link);

            return userId;
        }

        /// <summary>
        /// Authenticated user accepts a timeline invitation via share link token.
        /// Creates connection + timeline follower.
        /// </summary>
        public async Task AcceptInviteAsync(Guid token, int userId)
        {
            var link = await ValidateLinkAsync(token);
            await JoinTimelineAsync(userId, link);
        }

        /// <summary>
        /// Deactivate a timeline share link. Only the creator can deactivate.
        /// </summary>
        public async Task DeactivateLinkAsync(int userId, int timelineId)
        {
            var link = await Context.TimelineShareLinks
                .FirstOrDefaultAsync(l =>
                    l.TimelineId == timelineId &&
                    l.CreatorUserId == userId &&
                    l.IsActive);

            if (link == null)
                throw new NotFoundException("Share link not found.");

            link.IsActive = false;
            await Context.SaveChangesAsync();
        }

        public async Task<TimelineShareLink> ValidateLinkAsync(Guid token)
        {
            var link = await Context.TimelineShareLinks
                .AsNoTracking()
                .FirstOrDefaultAsync(l => l.Token == token && l.IsActive);

            if (link == null)
                throw new NotFoundException("This invitation link is no longer active.");

            if (link.ExpiresAt.HasValue && link.ExpiresAt.Value < DateTime.UtcNow)
                throw new NotFoundException("This invitation link has expired.");

            return link;
        }

        /// <summary>
        /// Join a timeline: create connection with creator + add as follower.
        /// Idempotent — safe to call multiple times.
        /// </summary>
        private async Task JoinTimelineAsync(int userId, TimelineShareLink link)
        {
            int creatorUserId = link.CreatorUserId;

            if (userId != creatorUserId)
            {
                await sharingService.EnsureConnectionAsync(creatorUserId, userId);
            }

            // Add as timeline follower if not already
            var existingFollow = await Context.TimelineUsers
                .FirstOrDefaultAsync(tu =>
                    tu.TimelineId == link.TimelineId &&
                    tu.UserId == userId);

            if (existingFollow == null)
            {
                Context.TimelineUsers.Add(new TimelineUser
                {
                    TimelineId = link.TimelineId,
                    UserId = userId,
                    Active = true,
                    CreatedAt = DateTime.UtcNow,
                    UpdatedAt = DateTime.UtcNow
                });
                await Context.SaveChangesAsync();
            }
            else if (!existingFollow.Active)
            {
                existingFollow.Active = true;
                existingFollow.UpdatedAt = DateTime.UtcNow;
                await Context.SaveChangesAsync();
            }

            await groupService.PopulateEveryone(creatorUserId);
            await groupService.PopulateEveryone(userId);
        }

        /// <summary>
        /// Load drop models for timeline preview (read-only, no edit permissions).
        /// </summary>
        private async Task<List<DropModel>> LoadDropModels(
            List<int> dropIds, int creatorUserId)
        {
            // Similar to MemoryShareLinkService.LoadDropModel but for multiple drops.
            // Loads drops with content, images, movies, comments.
            // Returns DropModel list with signed URLs for media.
            // Implementation follows existing MemoryShareLinkService.LoadDropModel pattern.
            var drops = await Context.Drops
                .AsNoTracking()
                .Include(d => d.ContentDrop)
                .Include(d => d.CreatedBy)
                .Include(d => d.Images)
                .Include(d => d.Movies)
                .Where(d => dropIds.Contains(d.DropId))
                .ToListAsync();

            var TranscodeSwitchDate = new DateTime(2025, 12, 1);
            var models = new List<DropModel>();

            foreach (var drop in drops)
            {
                var model = new DropModel
                {
                    DropId = drop.DropId,
                    CreatedBy = drop.CreatedBy.Name,
                    CreatedById = drop.CreatedBy.UserId,
                    Date = drop.Date,
                    DateType = drop.DateType,
                    Content = new ContentModel
                    {
                        ContentId = drop.DropId,
                        Stuff = drop.ContentDrop.Stuff
                    },
                    Images = drop.Images
                        .Where(i => !i.CommentId.HasValue)
                        .Select(i => i.ImageDropId),
                    Movies = drop.Movies
                        .Where(m => !m.CommentId.HasValue)
                        .Select(m => m.MovieDropId),
                    Editable = false,
                    UserId = drop.CreatedBy.UserId,
                    IsTask = false,
                    CreatedAt = drop.Created
                };

                bool isTranscodeV2 = TranscodeSwitchDate < model.CreatedAt;

                foreach (var imageId in model.Images)
                {
                    model.ImageLinks.Add(new ImageModel(
                        imageService.GetLink(imageId, model.UserId, model.DropId), imageId));
                }

                foreach (var movieId in model.Movies)
                {
                    model.MovieLinks.Add(new MovieModel(
                        movieService.GetLink(movieId, model.UserId, model.DropId, isTranscodeV2),
                        movieId,
                        movieService.GetThumbLink(movieId, model.UserId, model.DropId, isTranscodeV2)));
                }

                models.Add(model);
            }

            return models;
        }
    }
}
```

### 3.5 Backend: `TimelinePreviewModel`

**File:** `cimplur-core/Memento/Domain/Models/TimelinePreviewModel.cs`

```csharp
using System.Collections.Generic;

namespace Domain.Models
{
    public class TimelinePreviewModel
    {
        public int TimelineId { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string CreatorName { get; set; }
        public int MemoryCount { get; set; }
        public List<DropModel> Drops { get; set; } = new();
    }
}
```

### 3.6 Backend: `TimelineShareLinkController`

**File:** `cimplur-core/Memento/Memento/Controllers/TimelineShareLinkController.cs`

```csharp
using Domain.Repository;
using Memento.Libs;
using Memento.Web.Models;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using System;
using System.Threading.Tasks;
using Domain.Emails;
using static Domain.Emails.EmailTemplates;

namespace Memento.Web.Controllers
{
    [Route("api/storylines")]
    public class TimelineShareLinkController : BaseApiController
    {
        private TimelineShareLinkService timelineShareLinkService;
        private TokenService tokenService;
        private SendEmailService sendEmailService;
        private UserWebToken userWebToken;
        private GroupService groupService;
        private DropsService dropsService;

        public TimelineShareLinkController(
            TimelineShareLinkService timelineShareLinkService,
            TokenService tokenService,
            SendEmailService sendEmailService,
            UserWebToken userWebToken,
            GroupService groupService,
            DropsService dropsService)
        {
            this.timelineShareLinkService = timelineShareLinkService;
            this.tokenService = tokenService;
            this.sendEmailService = sendEmailService;
            this.userWebToken = userWebToken;
            this.groupService = groupService;
            this.dropsService = dropsService;
        }

        /// <summary>
        /// Create a shareable invitation link for a storyline.
        /// </summary>
        [CustomAuthorization]
        [HttpPost]
        [Route("{timelineId:int}/links")]
        public async Task<IActionResult> CreateLink(int timelineId)
        {
            var token = await timelineShareLinkService.CreateLinkAsync(
                CurrentUserId, timelineId);
            return Ok(new { token });
        }

        /// <summary>
        /// Get storyline preview for public view. No auth required.
        /// </summary>
        [EnableRateLimiting("public")]
        [HttpGet]
        [Route("{token:guid}")]
        public async Task<IActionResult> GetPreview(Guid token)
        {
            var preview = await timelineShareLinkService
                .GetPreviewByTokenAsync(token);
            return Ok(preview);
        }

        /// <summary>
        /// Register a new user via storyline invitation link. Returns JWT.
        /// </summary>
        [EnableRateLimiting("registration")]
        [HttpPost]
        [Route("{token:guid}/register")]
        public async Task<IActionResult> Register(
            Guid token, ShareLinkRegisterModel model)
        {
            if (!Domain.Utilities.TextFormatter.IsValidEmail(model.Email))
                return BadRequest("Please enter a valid email.");

            var userId = await timelineShareLinkService
                .RegisterAndJoinAsync(
                    token, model.Email, model.Name, model.AcceptTerms);
            var jwt = userWebToken.generateJwtToken(userId);
            return Ok(jwt);
        }

        /// <summary>
        /// Request a magic link for existing user on storyline invite page.
        /// </summary>
        [EnableRateLimiting("public")]
        [HttpPost]
        [Route("{token:guid}/signin")]
        public async Task<IActionResult> SignIn(
            Guid token, EmailModel model)
        {
            await timelineShareLinkService.ValidateLinkAsync(token);

            if (!string.IsNullOrWhiteSpace(model.Email))
            {
                var linkToken = await tokenService.CreateLinkToken(model.Email);
                if (linkToken.Success)
                {
                    await sendEmailService.SendAsync(
                        model.Email, EmailTypes.Login,
                        new { linkToken.Token, linkToken.Name });
                }
                return Ok(new { message = "Check your email for a sign-in link." });
            }

            return BadRequest("Please submit a valid email.");
        }

        /// <summary>
        /// Authenticated user accepts storyline invitation.
        /// </summary>
        [CustomAuthorization]
        [HttpPost]
        [Route("{token:guid}/accept")]
        public async Task<IActionResult> AcceptInvite(Guid token)
        {
            await timelineShareLinkService.AcceptInviteAsync(
                token, CurrentUserId);
            return Ok(new { success = true });
        }

        /// <summary>
        /// Deactivate a storyline share link. Creator only.
        /// </summary>
        [CustomAuthorization]
        [HttpDelete]
        [Route("{timelineId:int}/links")]
        public async Task<IActionResult> DeactivateLink(int timelineId)
        {
            await timelineShareLinkService.DeactivateLinkAsync(
                CurrentUserId, timelineId);
            return Ok(new { success = true });
        }
    }
}
```

### 3.7 Register Service in DI

**File:** `cimplur-core/Memento/Memento/Startup.cs`

Add `TimelineShareLinkService` to the DI container alongside the existing service registrations (after `MemoryShareLinkService` at line 67):

```csharp
services.AddScoped<TimelineShareLinkService>();
```

### 3.8 Frontend: `timelineShareApi.ts`

**File:** `fyli-fe-v2/src/services/timelineShareApi.ts`

```typescript
import api from './api'
import type { TimelinePreview } from '@/types'

export function createStorylineLink(timelineId: number) {
  return api.post<{ token: string }>(`/storylines/${timelineId}/links`)
}

export function getStorylinePreview(token: string) {
  return api.get<TimelinePreview>(`/storylines/${token}`)
}

export function registerViaStoryline(
  token: string, email: string, name: string, acceptTerms: boolean
) {
  return api.post<string>(`/storylines/${token}/register`, {
    email, name, acceptTerms
  })
}

export function signInViaStoryline(token: string, email: string) {
  return api.post<{ message: string }>(`/storylines/${token}/signin`, { email })
}

export function acceptStorylineInvite(token: string) {
  return api.post<{ success: boolean }>(`/storylines/${token}/accept`)
}

export function deactivateStorylineLink(timelineId: number) {
  return api.delete(`/storylines/${timelineId}/links`)
}
```

### 3.9 Frontend: Types

**File:** `fyli-fe-v2/src/types/index.ts`

Add:

```typescript
export interface TimelinePreview {
  timelineId: number
  name: string
  description: string
  creatorName: string
  memoryCount: number
  drops: Drop[]
}
```

### 3.10 Frontend: `StorylineInviteView.vue`

**File:** `fyli-fe-v2/src/views/storyline/StorylineInviteView.vue`

```vue
<template>
  <div class="container py-4" style="max-width: 600px">
    <LoadingSpinner v-if="loading" />
    <ErrorState v-else-if="error"
      message="This invitation link may be expired or invalid."
      @retry="router.go(0)" />

    <template v-else-if="preview">
      <!-- Storyline header -->
      <header class="text-center mb-4">
        <p class="text-muted mb-1">
          {{ preview.creatorName }} invited you to contribute to
        </p>
        <h1 class="h4">{{ preview.name }}</h1>
        <p v-if="preview.description" class="text-muted">
          {{ preview.description }}
        </p>
        <div class="badge bg-secondary">
          {{ preview.memoryCount }}
          {{ preview.memoryCount === 1 ? 'memory' : 'memories' }}
        </div>
      </header>

      <!-- Inline auth -->
      <InlineAuth
        signin-heading="Sign in to join this storyline"
        register-heading="Join to add your memories to this storyline"
        :invite-token="token"
        :return-to="`/st/${token}`"
        :register-fn="registerFn"
        :magic-link-fn="magicLinkFn"
        @success="handleAuthSuccess"
      />

      <!-- Memory preview feed (read-only) -->
      <div v-if="preview.drops.length"
        class="d-flex flex-column gap-3 mt-4">
        <div v-for="drop in preview.drops" :key="drop.dropId"
          class="card">
          <div class="card-body">
            <div class="mb-2">
              <strong>{{ drop.createdBy }}</strong>
              <small class="text-muted ms-2">
                {{ new Date(drop.date).toLocaleDateString() }}
              </small>
            </div>
            <p v-if="drop.content?.stuff">{{ drop.content.stuff }}</p>
            <PhotoGrid :images="drop.imageLinks" />
            <div v-for="movie in drop.movieLinks" :key="movie.id"
              class="mb-2">
              <video :src="movie.link" :poster="movie.thumbLink"
                controls class="img-fluid rounded"></video>
            </div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import {
  getStorylinePreview,
  acceptStorylineInvite,
  registerViaStoryline,
  signInViaStoryline,
} from "@/services/timelineShareApi";
import InlineAuth from "@/components/auth/InlineAuth.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";
import ErrorState from "@/components/ui/ErrorState.vue";
import PhotoGrid from "@/components/memory/PhotoGrid.vue";
import type { TimelinePreview } from "@/types";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const token = route.params.token as string;

const preview = ref<TimelinePreview | null>(null);
const loading = ref(true);
const error = ref(false);

// Context-specific registration: calls /storylines/:token/register
// which registers AND joins the timeline atomically
async function registerFn(
  email: string, name: string, acceptTerms: boolean
): Promise<string> {
  const { data: jwt } = await registerViaStoryline(
    token, email, name, acceptTerms
  );
  return jwt;
}

// Context-specific magic link: calls /storylines/:token/signin
async function magicLinkFn(email: string): Promise<void> {
  await signInViaStoryline(token, email);
}

onMounted(async () => {
  try {
    const { data } = await getStorylinePreview(token);
    preview.value = data;

    // If already authenticated, auto-accept and redirect
    if (auth.isAuthenticated) {
      await acceptStorylineInvite(token);
      router.replace(`/storylines/${data.timelineId}`);
    }
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
});

async function handleAuthSuccess() {
  if (!preview.value) return;
  try {
    await acceptStorylineInvite(token);
  } catch {
    // May already be accepted via google-auth endpoint
  }
  router.replace(`/storylines/${preview.value.timelineId}`);
}
</script>
```

### 3.11 Frontend: Router

Add to `fyli-fe-v2/src/router/index.ts`:

```typescript
{
  path: '/st/:token',
  name: 'storyline-invite',
  component: () => import('@/views/storyline/StorylineInviteView.vue'),
  meta: { layout: 'public' }
}
```

---

## Phase 4: Connection Invitation Flow

### 4.1 Frontend: `connectionInviteApi.ts`

**File:** `fyli-fe-v2/src/services/connectionInviteApi.ts`

```typescript
import api from "./api";

// Uses the new /preview endpoint to avoid the LogOffUser()
// side-effect in the original GET shareRequest/{token}
export function getConnectionInvitePreview(token: string) {
  return api.get<{ name: string }>(
    `/users/shareRequest/${token}/preview`
  );
}

export function confirmConnection(token: string) {
  return api.post(`/users/shareRequest/${token}/confirm`);
}
```

### 4.2 Backend: New Public ShareRequest Preview Endpoint

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

> **Side-effect warning:** The existing `GET /api/users/shareRequest/{token}` endpoint calls `LogOffUser()` when the authenticated user doesn't match the invitation target. This would log out an authenticated user visiting `/invite/:token`, breaking the auto-accept flow. We need a new public endpoint that returns invite metadata without side-effects.

Add a new public endpoint alongside the existing one:

```csharp
/// <summary>
/// Public preview of a connection invitation. No auth side-effects.
/// </summary>
[EnableRateLimiting("public")]
[HttpGet]
[Route("shareRequest/{token}/preview")]
public async Task<IActionResult> ShareRequestPreview(string token)
{
    var requestor = sharingService.GetSharingRequest(token);
    if (requestor != null)
    {
        return Ok(new { Name = requestor.RequestorName });
    }
    return BadRequest("Oops we can not find your connection request.");
}
```

The existing `GET shareRequest/{token}` endpoint is unchanged for backwards compatibility.

### 4.3 Frontend: `ConnectionInviteView.vue`

**File:** `fyli-fe-v2/src/views/invite/ConnectionInviteView.vue`

```vue
<template>
  <div class="container py-4" style="max-width: 600px">
    <LoadingSpinner v-if="loading" />
    <ErrorState v-else-if="error"
      message="This invitation link may be expired or invalid."
      @retry="router.go(0)" />

    <template v-else>
      <header class="text-center mb-4">
        <span class="mdi mdi-account-plus"
          style="font-size: 3rem; color: var(--fyli-primary)"></span>
        <h1 class="h4 mt-2">{{ inviterName }} wants to connect with you</h1>
        <p class="text-muted">
          Connect to share memories and stay in touch on Fyli.
        </p>
      </header>

      <InlineAuth
        :signin-heading="`Sign in to connect with ${inviterName}`"
        :register-heading="`Create an account to connect with ${inviterName}`"
        :return-to="`/invite/${token}`"
        @success="handleAuthSuccess"
      />
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "@/stores/auth";
import {
  getConnectionInvitePreview,
  confirmConnection,
} from "@/services/connectionInviteApi";
import InlineAuth from "@/components/auth/InlineAuth.vue";
import LoadingSpinner from "@/components/ui/LoadingSpinner.vue";
import ErrorState from "@/components/ui/ErrorState.vue";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const token = route.params.token as string;

const inviterName = ref("");
const loading = ref(true);
const error = ref(false);

onMounted(async () => {
  try {
    // Use the preview endpoint to avoid the LogOffUser() side-effect
    // in the original GET shareRequest/{token} endpoint
    const { data } = await getConnectionInvitePreview(token);
    inviterName.value = data.name;

    // If already authenticated, auto-accept and go home
    if (auth.isAuthenticated) {
      await confirmConnection(token);
      router.replace("/");
    }
  } catch {
    error.value = true;
  } finally {
    loading.value = false;
  }
});

async function handleAuthSuccess() {
  try {
    await confirmConnection(token);
  } catch {
    // Connection may already exist
  }
  router.replace("/");
}
</script>
```

### 4.4 Frontend: Router

Add to `fyli-fe-v2/src/router/index.ts`:

```typescript
{
  path: '/invite/:token',
  name: 'connection-invite',
  component: () => import('@/views/invite/ConnectionInviteView.vue'),
  meta: { layout: 'public' }
}
```

### 4.5 Backend: Connection Invite with Google Auth

The connection invitation flow uses `ShareRequest.RequestKey` as the token. For the `inviteToken` param on `google-auth`, we need to handle connection invitations differently from storyline invitations.

**Approach:** The `inviteToken` in `GoogleAuthModel` is used for **timeline share links** only. Connection invitations are handled client-side: after Google auth succeeds, the frontend calls `confirmConnection(token)` separately. This keeps the backend simpler — the `google-auth` endpoint doesn't need to understand ShareRequest tokens.

This means the `ConnectionInviteView` does NOT pass `inviteToken` to `InlineAuth`. Instead:

```vue
<InlineAuth
  :signin-heading="`Sign in to connect with ${inviterName}`"
  :register-heading="`Create an account to connect with ${inviterName}`"
  :return-to="`/invite/${token}`"
  @success="handleAuthSuccess"
/>
```

And `handleAuthSuccess` calls `confirmConnection(token)` after auth.

---

## Phase 5: Testing

### 5.1 Backend Tests

#### `TimelineShareLinkServiceTest.cs`

Test file: `cimplur-core/Memento/DomainTest/TimelineShareLinkServiceTest.cs`

Tests follow the established pattern (no transactions, `DetachAllEntities`, `CreateVerificationContext`):

| # | Test | Description |
|---|------|-------------|
| 1 | `CreateLinkAsync_CreatesLink` | Creator creates link, returns Guid token |
| 2 | `CreateLinkAsync_ReturnsExistingToken` | Returns same token for same timeline if active |
| 3 | `CreateLinkAsync_NonCreator_Throws` | Only timeline creator can create links |
| 4 | `GetPreviewByTokenAsync_ReturnsPreview` | Returns timeline metadata + drops |
| 5 | `GetPreviewByTokenAsync_IncrementsViewCount` | View count goes up on each call |
| 6 | `GetPreviewByTokenAsync_InactiveLink_Throws` | Inactive link returns NotFoundException |
| 7 | `GetPreviewByTokenAsync_ExpiredLink_Throws` | Expired link returns NotFoundException |
| 8 | `RegisterAndJoinAsync_NewUser_CreatesAndJoins` | New user registered, follows timeline |
| 9 | `RegisterAndJoinAsync_ExistingUser_Joins` | Existing user joins timeline |
| 10 | `RegisterAndJoinAsync_NoTerms_Throws` | acceptTerms=false throws |
| 11 | `AcceptInviteAsync_JoinsTimeline` | Auth user added as timeline follower |
| 12 | `AcceptInviteAsync_AlreadyFollowing_Idempotent` | No error if already following |
| 13 | `AcceptInviteAsync_ReactivatesInactiveFollow` | Reactivates soft-deleted follow |
| 14 | `AcceptInviteAsync_CreatesConnection` | Connection created between creator and joiner |
| 15 | `DeactivateLinkAsync_DeactivatesLink` | Sets IsActive=false |
| 16 | `DeactivateLinkAsync_NonCreator_Throws` | Only creator can deactivate |

#### `GoogleAuthServiceTest.cs` (Extend Existing)

Add tests for new token handling:

| # | Test | Description |
|---|------|-------------|
| 17 | `AuthenticateAsync_WithShareToken_ClaimsDrop` | Share link access granted during auth |
| 18 | `AuthenticateAsync_WithInviteToken_JoinsTimeline` | Timeline joined during auth |
| 19 | `AuthenticateAsync_MultipleTokens_AllProcessed` | Question + share tokens both processed |

### 5.2 Frontend Tests

#### `InlineAuth.test.ts`

Test file: `fyli-fe-v2/src/components/auth/InlineAuth.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders collapsed CTA when not authenticated | Shows "Sign in" + "Sign up" links |
| 2 | shows signed-in badge when authenticated | Displays "Signed in as [name]" |
| 3 | expands to sign-in form when "Sign in" clicked | Shows Google btn placeholder + magic link form |
| 4 | expands to register form when "Sign up" clicked | Shows Google btn placeholder + email/name/terms |
| 5 | toggles from sign-in to register via link | "Don't have an account? Sign up" switches mode |
| 6 | toggles from register to sign-in via link | "Already have an account? Sign in" switches mode |
| 7 | collapses on Cancel click | Returns to CTA state |
| 8 | sends magic link with returnTo | Calls requestMagicLink with correct params |
| 9 | uses custom magicLinkFn when provided | Calls prop function instead of authApi |
| 10 | shows magic link sent confirmation | Displays email icon + message after send |
| 11 | validates registration fields | Shows error if email/name missing or terms unchecked |
| 12 | calls register and emits success | Calls authApi.register, sets token, emits success |
| 13 | uses custom registerFn when provided | Calls prop function instead of authApi.register |
| 14 | displays sign-in error | Shows alert when magic link fails |
| 15 | displays registration error | Shows alert when register fails |
| 16 | passes question token to Google sign-in | Token forwarded to useGoogleSignIn |
| 17 | passes share token to Google sign-in | Token forwarded to useGoogleSignIn |
| 18 | uses unique termsId for checkbox | No ID collision with multiple instances |

#### `InlineAuthPrompt.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | renders registration form by default | Shows heading + Google + form + "Skip for now" |
| 2 | emits skip when "Skip for now" clicked | Parent can dismiss prompt |
| 3 | toggles to sign-in form | "Already have an account? Sign in" switches |
| 4 | emits success after registration | Auth store updated, event emitted |

#### `StorylineInviteView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | shows loading spinner initially | LoadingSpinner visible during fetch |
| 2 | shows error state on fetch failure | ErrorState with retry button |
| 3 | renders preview with storyline metadata | Title, description, creator, count |
| 4 | renders memory preview cards | Drop content, photos, videos shown |
| 5 | shows InlineAuth component with registerFn | Auth CTA visible, passes registerFn + magicLinkFn props |
| 6 | auto-accepts and redirects for authenticated users | Calls acceptStorylineInvite + router.replace |
| 7 | registerFn calls registerViaStoryline | Context-specific registration hits /storylines/:token/register |

#### `ConnectionInviteView.test.ts`

| # | Test | Description |
|---|------|-------------|
| 1 | shows loading spinner initially | LoadingSpinner visible |
| 2 | shows error state on fetch failure | ErrorState with retry |
| 3 | renders inviter name and message | "[Name] wants to connect with you" |
| 4 | fetches via preview endpoint | Calls getConnectionInvitePreview (not the LogOffUser endpoint) |
| 5 | shows InlineAuth component | Auth CTA visible |
| 6 | auto-accepts and redirects for authenticated users | Calls confirmConnection + router.replace('/') |

#### `SharedMemoryView.test.ts` (Update Existing)

| # | Test | Description |
|---|------|-------------|
| 1 | renders InlineAuth instead of old auth section | InlineAuth component present with correct props |
| 2 | passes share token to InlineAuth | shareToken prop matches route param |

#### API Service Tests

- `timelineShareApi.test.ts` — verify correct HTTP methods, URLs, and params for all 6 functions
- `connectionInviteApi.test.ts` — verify correct HTTP methods and URLs for both functions (uses `/preview` endpoint, not the original)
- `authApi.test.ts` (update) — verify `googleAuth` passes shareToken and inviteToken params

### 5.3 Run Commands

```bash
# Backend tests
cd cimplur-core/Memento && dotnet test --filter "TimelineShareLinkServiceTest|GoogleAuthServiceTest"

# Frontend tests
cd fyli-fe-v2 && npm run test:unit
```

---

## Phase 6: Visual Audit & Polish

### 6.1 Audit Checklist

Verify across all four anonymous pages:

| Check | `/q/:token` | `/s/:token` | `/st/:token` | `/invite/:token` |
|-------|-------------|-------------|--------------|-------------------|
| CTA shows both "Sign in" + "Sign up" | | | | |
| Google button appears first (above divider) | | | | |
| "or" divider uses AuthDivider component | | | | |
| Cancel collapses back to CTA | | | | |
| Toggle links switch between sign-in/register | | | | |
| "Signed in as [name]" badge shows after auth | | | | |
| Mobile responsive (< 576px) | | | | |
| Error states display correctly | | | | |
| Magic link sent confirmation shows | | | | |

### 6.2 Mobile Responsive Considerations

The `InlineAuth` component uses Bootstrap classes that naturally respond to screen size:
- `form-control-sm` for compact inputs
- `d-flex gap-2` for magic link row (stacks naturally at small widths)
- Card width constrained by parent container (`max-width: 600px`)
- Google button has `width: 400` — on small screens, the GIS library auto-adjusts

No custom media queries needed — Bootstrap handles it.

---

## Implementation Order

1. **Phase 1** — `InlineAuth.vue` + `InlineAuthPrompt.vue` + extend composable/API + refactor QuestionAnswerView
2. **Phase 2** — Extend `GoogleAuthModel` + `GoogleAuthService` + update `SharedMemoryView`
3. **Phase 3** — `TimelineShareLink` entity + migration + service + controller + `StorylineInviteView` + router
4. **Phase 4** — New `shareRequest/{token}/preview` backend endpoint + `ConnectionInviteView` + API service + router
5. **Phase 5** — Backend tests + frontend tests
6. **Phase 6** — Visual audit across all touchpoints

Phases 1-2 can be deployed independently. Phase 3 requires a database migration (generate production SQL via `dotnet ef migrations script`). Phase 4 adds a new backend endpoint (`shareRequest/{token}/preview`) + frontend.

---

## Backwards Compatibility

- **Magic link auth:** Unchanged. Existing users continue using email links.
- **Existing share links (`/s/:token`):** Continue working. UI enhanced, not replaced.
- **Question flow (`/q/:token`):** Refactored to shared component — identical behavior.
- **Database:** Only additive — new `TimelineShareLinks` table. No columns removed.
- **API:** `google-auth` endpoint accepts new optional params — existing callers unaffected.
- **ShareRequest endpoint:** The existing `GET shareRequest/{token}` is unchanged. A new `GET shareRequest/{token}/preview` endpoint is added alongside it (no `LogOffUser()` side-effect).
- **Timeline invitations (existing):** The existing `InviteToTimeline` (user-ID-based) continues to work unchanged. `TimelineShareLink` is a parallel public invitation mechanism.

---

*Document Version: 1.2*
*Created: 2026-02-10*
*Updated: 2026-02-10 — v1.1: Address code review round 1. v1.2: Add registerFn to QuestionAnswerView refactor, add GoogleAuthService constructor with new dependencies, fix DI reference to Startup.cs, document fallback behavior, add aria-labels to registration inputs, clarify useGoogleSignIn destructuring, note magicLinkFn return type.*
*Status: Draft*
