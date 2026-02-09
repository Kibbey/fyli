# Investigation: Magic Link Login Broken After Google Auth Update

**Status:** ✅ Resolved
**Date opened:** 2026-02-09
**Date resolved:** 2026-02-09

## Problem Statement

After adding Google Sign-In authentication, the original magic link login flow is broken. Users click a magic link from email and end up redirected to the login page instead of being authenticated.

## Root Cause

**The Login email template was changed in commit `9cab72a` (Google auth commit) and broke the magic link flow.**

### Before (working):
```csharp
// EmailTemplates.cs line 53
Constants.BaseUrl + "/#/?link=@Model.Token"
// Produces: https://localhost:5001/#/?link=ENCRYPTED_TOKEN
```
- `FindAndReplaceLinks` regex matches `/#/...` pattern
- Converts to: `/api/links?token=BASE64(/#/?link=ENCRYPTED_TOKEN)`
- `LinksController.Index()` decodes Base64, validates encrypted token, generates JWT
- Redirects to: `http://localhost:5174/auth/verify#token=JWT&route=/`
- Frontend `MagicLinkView.vue` extracts JWT, stores in localStorage, redirects to app

### After (broken):
```csharp
// EmailTemplates.cs line 53
Constants.BaseUrl + "/auth/verify#token=@Model.Token&route=@Model.Route"
// Produces: https://localhost:5001/auth/verify#token=ENCRYPTED_TOKEN&route=%2F
```
**Three problems:**
1. `FindAndReplaceLinks` does NOT match (no `/#/` pattern) — link stays as-is
2. In dev: link hits backend at `/auth/verify` which doesn't exist (404 or redirect)
3. In production: `BaseUrl = https://app.Fyli.com` so link goes to frontend directly, BUT the token in the fragment is a **raw encrypted link token**, not a JWT. The frontend `MagicLinkView.vue` expects a JWT and would save the encrypted token as if it were a JWT, causing all subsequent API calls to fail with 401.

## Fix

Revert the Login email template to use the old `/#/` format that goes through `FindAndReplaceLinks` → `LinksController`:

```csharp
case EmailTypes.Login:
    return @"<p>@Model.Name, click this <a href='" + Constants.BaseUrl + "/#/?link=@Model.Token'>link</a> to log in to your Fyli account.</p>";
```

This ensures the encrypted token goes through the backend `LinksController.Index()` which:
1. Decodes the Base64-wrapped token
2. Validates the encrypted link token via `TokenService.ValidateToken`
3. Generates a proper JWT via `UserWebToken.generateJwtToken`
4. Redirects to frontend with the JWT in the fragment

## Evidence Trail

- `git diff 86426b0..9cab72a -- Memento/Domain/Emails/EmailTemplates.cs` shows the template change
- curl test confirmed backend returns `302 http://localhost:5174/` (no JWT) for test link with expired token
- Frontend code (MagicLinkView.vue, router, auth store) was NOT modified — confirmed frontend regression was actually a backend email template change
- `FindAndReplaceLinks` regex `\/#\/.+?(?=')` only matches `/#/` patterns, not `/auth/verify#`

## Recommended Action

Run `/fixer` to revert the email template change in `cimplur-core/Memento/Domain/Emails/EmailTemplates.cs` line 53.
