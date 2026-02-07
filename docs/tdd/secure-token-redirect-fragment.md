# TDD: Secure Token Redirect via URL Fragment

## Overview

Move the JWT token from the URL path (`/auth/verify/{token}`) to a URL fragment (`/auth/verify#token=xxx`) when the backend redirects after magic link validation. Fragments are never sent to servers in HTTP requests, preventing token leakage via server logs, proxy logs, and `Referer` headers.

## Current Flow

1. Backend `LinksController.Index` validates the email token
2. Generates a JWT via `UserWebToken.generateJwtToken()`
3. Redirects to: `{HostUrl}/auth/verify/{jwt}?route={path}`
4. Frontend route `/auth/verify/:token` reads the JWT from the path param
5. `MagicLinkView` stores JWT in localStorage

**Problem:** The JWT appears in the URL path, which is logged by web servers, proxies, CDNs, and can leak via the `Referer` header.

## Proposed Flow

1. Backend validates email token (unchanged)
2. Generates JWT (unchanged)
3. Redirects to: `{HostUrl}/auth/verify#token={jwt}&route={path}`
4. Frontend reads JWT from `window.location.hash`
5. Immediately clears the fragment via `history.replaceState`

## Phase 1: Backend Changes

### File: `cimplur-core/Memento/Memento/Controllers/LinksController.cs`

Change `CreateRoute` to use a fragment instead of path/query params. URL-encode the token to ensure special characters (`.`, `+`, `=`) don't break fragment parsing:

```csharp
// BEFORE
private string CreateRoute(string newRoute, string token) {
    var result = $"{Constants.HostUrl}/auth/verify/{token}?route={newRoute}";
    return result;
}

// AFTER
private string CreateRoute(string newRoute, string token) {
    var result = $"{Constants.HostUrl}/auth/verify#token={Uri.EscapeDataString(token)}&route={newRoute}";
    return result;
}
```

No other backend changes required.

## Phase 2: Frontend Changes

### File: `fyli-fe-v2/src/router/index.ts`

Update the route definition to remove the `:token` path param:

```typescript
// BEFORE
{
  path: '/auth/verify/:token',
  name: 'magic-link',
  component: () => import('@/views/auth/MagicLinkView.vue'),
  meta: { layout: 'public' },
},

// AFTER
{
  path: '/auth/verify',
  name: 'magic-link',
  component: () => import('@/views/auth/MagicLinkView.vue'),
  meta: { layout: 'public' },
},
```

### File: `fyli-fe-v2/src/router/index.ts` — Remove Legacy Guards

Remove the `/?link=TOKEN` and `/#/?link=TOKEN` handlers from the `beforeEach` guard. These are dead code — all magic link traffic goes through the backend `/api/links` endpoint, which now redirects with the fragment approach. The legacy guards referenced the old `:token` path param which no longer exists.

```typescript
// REMOVE both legacy handlers:
// Handle magic link from email: /?link=TOKEN
const linkToken = to.query.link as string | undefined
if (linkToken) {
  return { name: 'magic-link', params: { token: linkToken } }
}

// Handle legacy hash-based magic link: /#/?link=TOKEN
const hash = window.location.hash
if (hash.includes('link=')) {
  const params = new URLSearchParams(hash.replace(/^#\/?/, ''))
  const hashToken = params.get('link')
  if (hashToken) {
    window.location.hash = ''
    return { name: 'magic-link', params: { token: hashToken } }
  }
}
```

### File: `fyli-fe-v2/src/views/auth/MagicLinkView.vue`

Read the token from the URL fragment instead of route params, then clear it:

```vue
<template>
  <div class="text-center py-5">
    <p class="mt-3 text-muted">Signing you in...</p>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const auth = useAuthStore()

onMounted(() => {
  const hash = window.location.hash.substring(1) // remove leading #
  const params = new URLSearchParams(hash)
  const token = params.get('token')
  const route = params.get('route') || '/'

  // Clear the fragment immediately to remove token from address bar/history
  history.replaceState(null, '', window.location.pathname)

  if (token) {
    auth.setToken(token)
    router.replace(decodeURIComponent(route))
  } else {
    router.replace('/login')
  }
})
</script>
```

## Implementation Order

1. Update `LinksController.CreateRoute` (backend)
2. Update route definition in `router/index.ts` (frontend)
3. Remove legacy `/?link=TOKEN` and `/#/?link=TOKEN` guards from `beforeEach` (frontend)
4. Update `MagicLinkView.vue` to read from fragment (frontend)
5. Test end-to-end

## Testing Plan

- **Manual:** Click a magic link email, verify redirect uses fragment, verify sign-in works, verify fragment is cleared from address bar after auth
- **Unit (frontend):** Test `MagicLinkView` handles missing token (redirects to `/login`), valid token (stores + redirects), and route parameter parsing
