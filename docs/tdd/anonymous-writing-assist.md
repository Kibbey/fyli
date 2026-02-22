# TDD: Allow Anonymous Users to Use Writing Assist

## Overview

Anonymous users on the public question-answering page (`/q/:token`) can see the "Help me write" button but clicking it triggers a 401 from the backend, which causes the frontend's Axios interceptor to redirect them to `/login` — losing any answer they've typed. This is a bad experience.

This change allows anonymous users to use writing assist, controlled by an environment variable so the feature gate can be toggled back on if needed. Anonymous users are rate-limited per IP (5/day) to prevent abuse.

## Problem Analysis

**Current flow for anonymous user on `/q/:token`:**
1. User types an answer, clicks "Help me write"
2. Frontend calls `POST /api/drops/assist` with no `Authorization` header
3. `AuthMiddleware` sets `context.Items["UserId"] = null`
4. `CustomAuthorizationAttribute` sees `userId == null`, path != `/api/links` → returns **401**
5. Frontend Axios interceptor catches 401 → clears token → **redirects to `/login`**
6. User loses their typed answer

## Design

### Approach

1. Add `AllowAnonymousAssist` boolean and `DailyRequestLimitPerAnonymousIp` (default: 5) to `AiServiceSettings`
2. Update `CustomAuthorizationAttribute` to resolve config and allow `/api/drops/assist` when enabled (case-insensitive path match)
3. Update `WritingAssistService` to accept an IP address, using IP-based rate limiting for anonymous users (userId=0) with a separate daily limit
4. Update `DropController.Assist` to pass the client IP address to the service
5. Fix the frontend 401 interceptor to not redirect anonymous users on public routes

### Component Diagram

```
Anonymous User → /q/:token → AnswerForm → WritingAssistButton
                                              ↓
                                   POST /api/drops/assist
                                              ↓
                              AuthorizationFilter (check config, case-insensitive)
                                              ↓ (allowed)
                              DropController.Assist(userId=0, ip=client IP)
                                              ↓
                              WritingAssistService.PolishTextAsync
                                ├─ Voice samples: empty (userId=0)
                                ├─ Rate limit: IP-based "writing_assist_anon_{ip}_*" key, 5/day
                                └─ AI call: polishes text with default style
```

## Implementation

### Phase 1: Backend — Allow Anonymous Writing Assist

#### 1.1 Add settings to `AiServiceSettings`

**File:** `cimplur-core/Memento/Domain/Models/AiServiceSettings.cs`

Add two new properties:
- `AllowAnonymousAssist` (bool, default `true`) — env var toggle
- `DailyRequestLimitPerAnonymousIp` (int, default `5`) — per-IP daily cap for anonymous users

#### 1.2 Update `CustomAuthorizationAttribute`

**File:** `cimplur-core/Memento/Memento/Libs/AuthorizationFilter.cs`

- Use `StringComparison.OrdinalIgnoreCase` for **all** path checks (fixes existing `/api/links` check too)
- Resolve `AiServiceSettings` from `RequestServices` to check `AllowAnonymousAssist`
- Allow through if enabled, block with 401 if disabled

#### 1.3 Update `IWritingAssistService` and `WritingAssistService`

**File:** `cimplur-core/Memento/Domain/Repositories/IWritingAssistService.cs`
**File:** `cimplur-core/Memento/Domain/Repositories/WritingAssistService.cs`

- Add `string ipAddress = null` parameter to `PolishTextAsync`
- In rate limit logic: when `userId == 0`, use cache key `writing_assist_anon_{ipAddress}_{date}` and limit `DailyRequestLimitPerAnonymousIp`
- When `userId > 0`, existing behavior unchanged (cache key `writing_assist_{userId}_{date}`, limit `DailyRequestLimitPerUser`)

#### 1.4 Update `DropController.Assist`

**File:** `cimplur-core/Memento/Memento/Controllers/DropController.cs`

- Pass client IP via `HttpContext.Connection.RemoteIpAddress` to `PolishTextAsync`
- Log when anonymous writing assist is used (`CurrentUserId == 0`) for monitoring volume

#### 1.5 Add config to `appsettings.json`

**File:** `cimplur-core/Memento/Memento/appsettings.json`

Add to existing `AiService` section:
```json
"AllowAnonymousAssist": true,
"DailyRequestLimitPerAnonymousIp": 5
```

### Phase 2: Frontend — Prevent 401 Redirect on Public Routes

#### 2.1 Update Axios 401 interceptor

**File:** `fyli-fe-v2/src/services/api.ts`

Only redirect to `/login` if the user had a token (was previously authenticated). Anonymous users hitting a 401 see an inline error instead of being redirected away.

### Phase 3: Tests

**Backend tests (new):**

| Test | Description |
|------|-------------|
| `Assist_AnonymousUser_WhenAllowed_ReturnsPolishedText` | Verify `/api/drops/assist` returns 200 when `AllowAnonymousAssist=true` and no auth token |
| `Assist_AnonymousUser_WhenDisallowed_Returns401` | Verify `/api/drops/assist` returns 401 when `AllowAnonymousAssist=false` and no auth token |

**Frontend tests (new):**

| Test | Description |
|------|-------------|
| `api interceptor does not redirect anonymous user on 401` | Verify no redirect when no token was present |
| `api interceptor redirects authenticated user on 401` | Verify redirect when token was present (existing behavior preserved) |

## Anonymous User Safety Considerations

| Concern | Mitigation |
|---------|------------|
| **Cost/abuse** | IP-based rate limit: 20 req/min/IP (existing `"ai"` policy) + 5 req/day per anonymous IP (`DailyRequestLimitPerAnonymousIp`). Separate from authenticated user limits. |
| **No voice samples** | Anonymous users get default warm writing style — acceptable and expected |
| **Toggle back** | Set `AiService__AllowAnonymousAssist=false` to restore login requirement |
| **Monitoring** | Log anonymous usage in `DropController.Assist` when `CurrentUserId == 0` to track volume |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AiService__AllowAnonymousAssist` | `true` | Allow anonymous users to use writing assist. Set `false` to require login. |
| `AiService__DailyRequestLimitPerAnonymousIp` | `5` | Max writing assist requests per IP per day for anonymous users. |

## File Changes Summary

| File | Change |
|------|--------|
| `cimplur-core/Memento/Domain/Models/AiServiceSettings.cs` | Add `AllowAnonymousAssist` and `DailyRequestLimitPerAnonymousIp` |
| `cimplur-core/Memento/Memento/Libs/AuthorizationFilter.cs` | Case-insensitive path check + config lookup for `/api/drops/assist` |
| `cimplur-core/Memento/Domain/Repositories/IWritingAssistService.cs` | Add `ipAddress` parameter |
| `cimplur-core/Memento/Domain/Repositories/WritingAssistService.cs` | IP-based rate limiting for anonymous users |
| `cimplur-core/Memento/Memento/Controllers/DropController.cs` | Pass client IP to service |
| `cimplur-core/Memento/Memento/appsettings.json` | Add new settings |
| `fyli-fe-v2/src/services/api.ts` | Fix 401 interceptor for anonymous users |

## Implementation Order

1. **Phase 1** — Backend: Settings, auth filter, service, controller
2. **Phase 2** — Frontend: Fix 401 interceptor
3. **Phase 3** — Tests
4. **Phase 4** — Verify end-to-end on `/q/:token` as anonymous user
