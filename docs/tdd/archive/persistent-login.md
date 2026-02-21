# TDD: Persistent Login (Never-Expiring Sessions)

## Overview

Currently, JWT tokens expire after 30 days, forcing users to re-authenticate via magic link. This TDD implements a **refresh token mechanism** so that active users remain logged in indefinitely on a given device.

### Current State
- JWT expires after **30 days** (hard-coded in `UserWebToken.cs`)
- No refresh token mechanism
- localStorage persists across browser sessions (good)
- On 401, user is redirected to login (must request new magic link)

### Target State
- Short-lived JWT (1 day) for API requests
- Long-lived **refresh token** (stored in DB) that auto-renews the JWT
- Refresh tokens last **1 year** and get rotated on each use (sliding expiration = effectively forever for active users)
- Frontend transparently refreshes JWT on 401 before redirecting to login

### Migration Note — Old Frontend (fyli-fe)

The old frontend (`fyli-fe`) currently expects `POST /api/users/login` and `POST /api/users/register` to return a bare JWT string. This TDD changes those endpoints to return a JSON object `{ token, refreshToken }`. The old frontend will need to be updated to extract `token` from the response object, or a backward-compatible wrapper must be added. Since `fyli-fe` is being replaced by `fyli-fe-v2`, the recommended approach is to update the old frontend's `apiProxy.js` and `userService.ts` to handle the new response shape at the same time.

---

## Phase 1: Backend — Refresh Token Infrastructure

### 1.1 New Entity: `RefreshToken`

**File:** `cimplur-core/Memento/Domain/Entities/RefreshToken.cs`

```csharp
using System;

namespace Domain.Entities
{
    public class RefreshToken
    {
        public int Id { get; set; }
        public int UserId { get; set; }
        public UserProfile User { get; set; }
        public string Token { get; set; }
        public DateTime Created { get; set; }
        public DateTime Expires { get; set; }
        public DateTime? Revoked { get; set; }
        public string? ReplacedByToken { get; set; }
        public string? DeviceInfo { get; set; }

        // All DateTime values stored as UTC
        public bool IsExpired => DateTime.UtcNow >= Expires;
        public bool IsRevoked => Revoked != null;
        public bool IsActive => !IsRevoked && !IsExpired;
    }
}
```

### 1.2 DbContext Changes

**File:** `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

Add `DbSet`:
```csharp
public DbSet<RefreshToken> RefreshTokens { get; set; }
```

Add to `OnModelCreating`:
```csharp
modelBuilder.Entity<RefreshToken>(entity =>
{
    entity.ToTable("RefreshTokens");
    entity.HasKey(e => e.Id);
    entity.HasIndex(e => e.Token).IsUnique();
    entity.HasIndex(e => e.UserId);
    entity.Property(e => e.Token).IsRequired().HasMaxLength(256);
    entity.Property(e => e.ReplacedByToken).HasMaxLength(256);
    entity.Property(e => e.DeviceInfo).HasMaxLength(512);

    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

### 1.3 Migration SQL (for production — SQL Server)

```sql
CREATE TABLE [RefreshTokens] (
    [Id] INT IDENTITY(1,1) PRIMARY KEY,
    [UserId] INT NOT NULL,
    [Token] NVARCHAR(256) NOT NULL,
    [Created] DATETIME2 NOT NULL,
    [Expires] DATETIME2 NOT NULL,
    [Revoked] DATETIME2 NULL,
    [ReplacedByToken] NVARCHAR(256) NULL,
    [DeviceInfo] NVARCHAR(512) NULL,
    CONSTRAINT [FK_RefreshTokens_UserProfiles_UserId]
        FOREIGN KEY ([UserId]) REFERENCES [UserProfiles]([UserId])
        ON DELETE NO ACTION
);

CREATE UNIQUE INDEX [IX_RefreshTokens_Token] ON [RefreshTokens] ([Token]);
CREATE INDEX [IX_RefreshTokens_UserId] ON [RefreshTokens] ([UserId]);
```

---

## Phase 2: Backend — Refresh Token Service & Endpoints

### 2.1 Request/Response DTOs

**File:** `cimplur-core/Memento/Memento/Models/AuthModels.cs`

```csharp
namespace Memento.Models
{
    public class RefreshRequest
    {
        public string RefreshToken { get; set; }
    }

    public class AuthResponse
    {
        public string Token { get; set; }
        public string RefreshToken { get; set; }
    }
}
```

### 2.2 Update `UserWebToken.cs`

Reduce JWT expiry from 30 days to **1 day**:

```csharp
Expires = DateTime.UtcNow.AddDays(1),
```

Add refresh token generation:

```csharp
public string GenerateRefreshToken()
{
    var randomBytes = new byte[64];
    using var rng = System.Security.Cryptography.RandomNumberGenerator.Create();
    rng.GetBytes(randomBytes);
    return Convert.ToBase64String(randomBytes);
}
```

### 2.3 New Service: `RefreshTokenService`

**File:** `cimplur-core/Memento/Domain/Repositories/RefreshTokenService.cs`

```csharp
using System;
using System.Linq;
using System.Threading.Tasks;
using Domain.Entities;
using Microsoft.EntityFrameworkCore;

namespace Domain.Repository
{
    /// <summary>
    /// Handles refresh token creation, validation, rotation, and revocation.
    /// </summary>
    public class RefreshTokenService : BaseService
    {
        private const int EXPIRATION_DAYS = 365;

        /// <summary>
        /// Creates and persists a new refresh token for the given user.
        /// </summary>
        public async Task<RefreshToken> CreateRefreshToken(int userId, string tokenValue, string? deviceInfo)
        {
            var refreshToken = new RefreshToken
            {
                UserId = userId,
                Token = tokenValue,
                Created = DateTime.UtcNow,
                Expires = DateTime.UtcNow.AddDays(EXPIRATION_DAYS),
                DeviceInfo = deviceInfo
            };

            Context.RefreshTokens.Add(refreshToken);
            await Context.SaveChangesAsync();
            return refreshToken;
        }

        /// <summary>
        /// Validates a refresh token and rotates it. Returns the new token and userId,
        /// or null if the token is invalid/expired/revoked.
        /// If a revoked token is reused, all tokens for that user are revoked (theft detection).
        /// </summary>
        public async Task<(int UserId, RefreshToken NewToken)?> RotateRefreshToken(
            string token, string newTokenValue, string? deviceInfo)
        {
            var existingToken = await Context.RefreshTokens
                .SingleOrDefaultAsync(t => t.Token == token);

            if (existingToken == null)
                return null;

            // Reuse detection: revoked token was used again — revoke all user tokens
            if (existingToken.IsRevoked)
            {
                await RevokeAllUserTokens(existingToken.UserId);
                return null;
            }

            if (existingToken.IsExpired)
                return null;

            // Revoke old token and create new one
            existingToken.Revoked = DateTime.UtcNow;
            existingToken.ReplacedByToken = newTokenValue;

            var newToken = new RefreshToken
            {
                UserId = existingToken.UserId,
                Token = newTokenValue,
                Created = DateTime.UtcNow,
                Expires = DateTime.UtcNow.AddDays(EXPIRATION_DAYS),
                DeviceInfo = deviceInfo
            };

            Context.RefreshTokens.Add(newToken);
            await Context.SaveChangesAsync();

            return (existingToken.UserId, newToken);
        }

        /// <summary>
        /// Revokes all active refresh tokens for a user (used on logout and theft detection).
        /// </summary>
        public async Task RevokeAllUserTokens(int userId)
        {
            var activeTokens = await Context.RefreshTokens
                .Where(t => t.UserId == userId && t.Revoked == null)
                .ToListAsync();

            foreach (var t in activeTokens)
            {
                t.Revoked = DateTime.UtcNow;
            }

            await Context.SaveChangesAsync();
        }

        /// <summary>
        /// Removes expired and revoked tokens older than 30 days.
        /// Call on application startup or as a scheduled task.
        /// </summary>
        public async Task CleanupExpiredTokens()
        {
            var cutoff = DateTime.UtcNow.AddDays(-30);
            var staleTokens = await Context.RefreshTokens
                .Where(t => t.Expires < cutoff
                    || (t.Revoked != null && t.Revoked < cutoff))
                .ToListAsync();

            Context.RefreshTokens.RemoveRange(staleTokens);
            await Context.SaveChangesAsync();
        }
    }
}
```

### 2.4 Controller Changes

**File:** `cimplur-core/Memento/Memento/Controllers/UserController.cs`

Add `RefreshTokenService` to constructor injection.

#### New Endpoint: `POST /api/users/refresh`

```
POST /api/users/refresh
Body: RefreshRequest { refreshToken: string }
Response: AuthResponse { token: string, refreshToken: string }
```

No `[CustomAuthorization]` — the refresh token itself is the credential. **Rate limit by IP** to prevent brute-force attacks (apply via middleware or attribute).

Controller method delegates entirely to `RefreshTokenService.RotateRefreshToken()` and `UserWebToken.generateJwtToken()`:

```csharp
[HttpPost]
[Route("refresh")]
public async Task<IActionResult> Refresh(RefreshRequest model)
{
    if (string.IsNullOrWhiteSpace(model.RefreshToken))
        return BadRequest("Refresh token is required.");

    var newTokenValue = userWebToken.GenerateRefreshToken();
    var deviceInfo = Request.Headers["User-Agent"].FirstOrDefault();
    var result = await refreshTokenService.RotateRefreshToken(
        model.RefreshToken, newTokenValue, deviceInfo);

    if (!result.HasValue)
        return Unauthorized("Invalid or expired refresh token.");

    var jwt = userWebToken.generateJwtToken(result.Value.UserId);
    return Ok(new AuthResponse
    {
        Token = jwt,
        RefreshToken = result.Value.NewToken.Token
    });
}
```

#### Update `POST /api/users/login`

Change return from bare JWT string to `AuthResponse`:

```csharp
var jwt = userWebToken.generateJwtToken(userId.Value);
var refreshTokenValue = userWebToken.GenerateRefreshToken();
var deviceInfo = Request.Headers["User-Agent"].FirstOrDefault();
await refreshTokenService.CreateRefreshToken(userId.Value, refreshTokenValue, deviceInfo);
return Ok(new AuthResponse { Token = jwt, RefreshToken = refreshTokenValue });
```

#### Update `POST /api/users/register`

Same pattern — return `AuthResponse` instead of bare JWT string.

#### Update `POST /api/users/logOff`

Revoke all refresh tokens for the current user (identified via `CurrentUserId` since the endpoint already has `[CustomAuthorization]`):

```csharp
[CustomAuthorization]
[HttpPost]
[Route("logOff")]
public async Task<IActionResult> LogOff()
{
    await refreshTokenService.RevokeAllUserTokens(CurrentUserId);
    LogOffUser();
    return Ok();
}
```

### 2.5 Register `RefreshTokenService` in DI

Add to `Startup.cs` / `Program.cs` service registration:

```csharp
services.AddScoped<RefreshTokenService>();
```

---

## Phase 3: Frontend — Token Refresh Logic

### 3.1 Store Refresh Token

**File:** `fyli-fe-v2/src/stores/auth.ts`

- Store `refreshToken` in localStorage alongside `token`
- Update `setToken()` to accept and store both tokens
- Update `logout()` to clear both tokens

```typescript
const refreshToken = ref<string | null>(localStorage.getItem("refreshToken"))

function setTokens(jwt: string, refresh: string) {
  token.value = jwt
  refreshToken.value = refresh
  localStorage.setItem("token", jwt)
  localStorage.setItem("refreshToken", refresh)
}

function logout() {
  token.value = null
  refreshToken.value = null
  user.value = null
  localStorage.removeItem("token")
  localStorage.removeItem("refreshToken")
}
```

### 3.2 Axios Interceptor — Silent Refresh

**File:** `fyli-fe-v2/src/services/api.ts`

On 401 response:
1. If a refresh token exists, call `POST /api/users/refresh`
2. On success: store new tokens, retry the original failed request
3. On failure: clear tokens, redirect to login
4. Use a request queue to prevent multiple simultaneous refresh calls

```typescript
import axios from "axios"
import router from "@/router"

const api = axios.create({
  baseURL: "/api",
})

api.interceptors.request.use((config) => {
  const token = localStorage.getItem("token")
  if (token) {
    config.headers.Authorization = `Bearer ${token}`
  }
  return config
})

let isRefreshing = false
let failedQueue: Array<{
  resolve: (token: string) => void;
  reject: (error: unknown) => void;
}> = []

function processQueue(error: unknown, token: string | null) {
  failedQueue.forEach(({ resolve, reject }) => {
    if (error) {
      reject(error)
    } else {
      resolve(token!)
    }
  })
  failedQueue = []
}

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config
    if (error.response?.status === 401 && !originalRequest._retry) {
      const refreshToken = localStorage.getItem("refreshToken")
      if (!refreshToken) {
        localStorage.removeItem("token")
        localStorage.removeItem("refreshToken")
        router.push("/login")
        return Promise.reject(error)
      }

      if (isRefreshing) {
        return new Promise<string>((resolve, reject) => {
          failedQueue.push({ resolve, reject })
        }).then((token) => {
          originalRequest.headers.Authorization = `Bearer ${token}`
          return api(originalRequest)
        })
      }

      originalRequest._retry = true
      isRefreshing = true

      try {
        const { data } = await axios.post("/api/users/refresh", {
          refreshToken,
        })
        localStorage.setItem("token", data.token)
        localStorage.setItem("refreshToken", data.refreshToken)
        processQueue(null, data.token)
        originalRequest.headers.Authorization = `Bearer ${data.token}`
        return api(originalRequest)
      } catch (err) {
        processQueue(err, null)
        localStorage.removeItem("token")
        localStorage.removeItem("refreshToken")
        router.push("/login")
        return Promise.reject(err)
      } finally {
        isRefreshing = false
      }
    }
    return Promise.reject(error)
  },
)

export default api
```

### 3.3 Update Auth API Service

**File:** `fyli-fe-v2/src/services/authApi.ts`

Update login and register response handling to extract both `token` and `refreshToken` from the `AuthResponse` object (previously these returned a bare JWT string).

---

## Phase 4: Cleanup & Security

### 4.1 Periodic Cleanup

Run `RefreshTokenService.CleanupExpiredTokens()` on application startup. This uses EF Core queries (not raw SQL) to stay consistent with the Code-First approach.

Reference SQL for scheduled DB job (if preferred over app-level cleanup):

```sql
DELETE FROM [RefreshTokens]
WHERE [Expires] < DATEADD(DAY, -30, GETUTCDATE())
   OR ([Revoked] IS NOT NULL AND [Revoked] < DATEADD(DAY, -30, GETUTCDATE()));
```

### 4.2 Security Considerations

- **Refresh token rotation**: Each use generates a new token and revokes the old one
- **Reuse detection**: If a revoked token is used, revoke ALL tokens for that user (potential theft) — implemented in `RefreshTokenService.RotateRefreshToken()`
- **Device info**: Store User-Agent to help users identify sessions
- **One refresh token per device**: Allows multiple device logins
- **Rate limiting**: The `POST /api/users/refresh` endpoint is unauthenticated and should be rate-limited by IP to prevent brute-force attacks

---

## Implementation Order

1. Phase 1: Create `RefreshToken` entity, DbContext changes, migration
2. Phase 2: `RefreshTokenService`, DTOs, controller changes, DI registration
3. Phase 3: Frontend interceptor, auth store, and auth API updates
4. Phase 4: Startup cleanup call and rate limiting

## Files Modified

**Backend:**
- `cimplur-core/Memento/Domain/Entities/RefreshToken.cs` (new)
- `cimplur-core/Memento/Domain/Entities/StreamContext.cs`
- `cimplur-core/Memento/Domain/Repositories/RefreshTokenService.cs` (new)
- `cimplur-core/Memento/Memento/Models/AuthModels.cs` (new)
- `cimplur-core/Memento/Memento/Libs/UserWebToken.cs`
- `cimplur-core/Memento/Memento/Controllers/UserController.cs`
- `cimplur-core/Memento/Memento/Startup.cs` (DI registration)

**Frontend:**
- `fyli-fe-v2/src/stores/auth.ts`
- `fyli-fe-v2/src/services/api.ts`
- `fyli-fe-v2/src/services/authApi.ts`
