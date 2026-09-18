# TDD: Admin Page

**PRD:** `docs/prd/PRD_ADMIN_PAGE.md` (v1.2)
**Status:** Draft
**Created:** 2026-09-17

---

## Overview

Add an additive `admin` role, a role-gated Admin page in `fyli-fe-v2`, and an in-product Ask/Bug form on Account. Admin can list every ask/bug, see everyone who joined in the last 30 days, and change a user's login email. Submitting an ask/bug emails every current admin.

This is **not** a ticketing system. There is no support inbox address. Existing users with no role keep every current page and API. Drops and drop access are untouched. JWT shape is unchanged (`id` claim only); roles are loaded from the database on each request that needs them.

**Frontend is `fyli-fe-v2` only.** `fyli-fe` is reference, not a target.

### Closed product decisions (v1.2)

| Topic | Decision |
|-------|----------|
| Ask/bug list | Full list, newest first. **No cap, no paging.** |
| 30-day joins | Full list, newest first. **No cap, no paging.** |
| User search | Match **email, name, and username** (contains, case-insensitive). **All matches. No result cap. No "too broad" narrowing.** |
| Open questions | None. Support contact, list size, and name-search scope are decided. |

### !IMPORTANT! — Ask submit rate limit

PRD §3.4: cap submissions per user (e.g. 5 per rolling 24 hours). Over the cap: do not persist; show "Please wait before sending another".

**Option A (recommended): count `Ask` rows in the database**

`AskService.CreateAsync` counts the caller's rows with `Source = "account"` and `Created >= UtcNow - 24 hours`. If the count is `>= 5`, throw `TooManyRequestsException` (HTTP 429) with that message. The cap is per user, rolling, and survives process restarts and multiple API instances.

**Option B: ASP.NET `AddRateLimiter` sliding window keyed by user id**

Faster, no extra query. In-memory, resets on deploy, and is not shared across instances. Does not match "rolling 24 hours" once the process recycles.

**Decision: Option A.** Fixed constants: **5 asks per user per rolling 24 hours**. The signed-out email-change "I didn't request this" path is **not** rate-limited this way (it is already single-use token + 7-day expiry). Only `POST /api/asks` with `source = account` counts toward and checks the cap.

**Concurrent submits:** two in-flight `POST /api/asks` can both read count `4` and both insert, producing 6 rows. Do **not** add a serializable transaction, upsert lock, or extra unique constraint for this. Operator-scale volume makes that race acceptable. The count check is a best-effort cap, not a hard invariant under parallelism.

---

## Component Diagram

```
fyli-fe-v2
├── AccountView          Help form (any signed-in user)
├── AdminView            /admin (admin role)
├── AppDrawer            Admin item last, admin-only
├── EmailChangeNoticeView  public one-tap confirmation (Account, not Admin)
├── askApi.ts            POST /api/asks, POST dispute token
└── adminApi.ts          /api/admin/*

                    HTTPS / JSON
                           │
cimplur-core
├── AskController        POST /api/asks (auth, no role)
│                        POST /api/asks/email-change-notices/{token} (public)
├── AdminController      /api/admin/*  [AdminAuthorization]
├── UserController       GET /api/users  (roles additive)
├── AskService           persist + rate limit + notify admins
├── AdminService         signups, search, email change, audit
├── UserService          GetUser.Roles, HasRoleAsync
├── SendEmailService     existing pipeline + new templates
└── StreamContext        UserRole, Ask, AdminAudit
```

---

## File Structure

```
cimplur-core/Memento/
├── Domain/
│   ├── Entities/
│   │   ├── UserRole.cs                         NEW
│   │   ├── Ask.cs                              NEW
│   │   ├── AdminAudit.cs                       NEW
│   │   └── StreamContext.cs                    MODIFY
│   ├── Models/
│   │   ├── UserModel.cs                        MODIFY (Roles)
│   │   ├── RoleNames.cs                        NEW
│   │   ├── AskModels.cs                        NEW
│   │   └── AdminModels.cs                      NEW
│   ├── Exceptions/
│   │   └── TooManyRequestsException.cs         NEW
│   ├── Emails/
│   │   ├── EmailTemplates.cs                   MODIFY (3 types)
│   │   └── SendEmail.cs                        MODIFY (SendAsync virtual)
│   ├── Repositories/
│   │   ├── UserService.cs                      MODIFY (roles)
│   │   ├── AskService.cs                       NEW
│   │   └── AdminService.cs                     NEW
│   └── Migrations/                             NEW (3, generated)
├── Memento/
│   ├── Controllers/
│   │   ├── AskController.cs                    NEW
│   │   └── AdminController.cs                  NEW
│   ├── Models/
│   │   ├── CreateAskRequest.cs                 NEW
│   │   └── ChangeEmailRequest.cs               NEW
│   ├── Libs/
│   │   └── AdminAuthorizationAttribute.cs      NEW
│   └── Startup.cs                              MODIFY (DI)
└── DomainTest/Repositories/
    ├── UserServiceTest.cs                      MODIFY
    ├── AskServiceTest.cs                       NEW
    ├── AdminServiceTest.cs                     NEW
    └── TestServiceFactory.cs                   MODIFY

docs/
├── DATABASE_GUIDE.md                           MODIFY (entity summary)
├── release_note.md                             MODIFY
└── migrations/
    ├── AddUserRole.sql                         NEW (from EF, after generate)
    ├── AddAsk.sql                              NEW (from EF, after generate)
    ├── AddAdminAudit.sql                       NEW (from EF, after generate)
    └── GrantAdminKibbeyj.sql                   NEW (data script)

fyli-fe-v2/src/
├── types/index.ts                              MODIFY (User.roles)
├── test/fixtures.ts                            MODIFY (roles: [])
├── stores/auth.ts                              MODIFY (hasAdmin)
├── stores/auth.test.ts                         MODIFY
├── router/index.ts                             MODIFY (/admin, notice, guard)
├── router/__tests__/emailRoutes.test.ts        MODIFY
├── services/askApi.ts                          NEW
├── services/askApi.test.ts                     NEW
├── services/adminApi.ts                        NEW
├── services/adminApi.test.ts                   NEW
├── components/ui/AppDrawer.vue                 MODIFY
├── components/ui/AppDrawer.test.ts             MODIFY
├── views/account/AccountView.vue               MODIFY
├── views/account/AccountView.test.ts           MODIFY
├── views/account/EmailChangeNoticeView.vue     NEW
├── views/account/EmailChangeNoticeView.test.ts NEW
├── views/admin/AdminView.vue                   NEW
└── views/admin/AdminView.test.ts               NEW
```

Do **not** change `AppBottomNav`. Bottom nav stays Memories / Questions / Account.

---

## Interface Definitions

### Constants

```csharp
// Domain/Models/RoleNames.cs
public static class RoleNames
{
    public const string Admin = "admin";
}

public static class AskTypes
{
    public const string Ask = "ask";
    public const string Bug = "bug";
}

public static class AskSources
{
    public const string Account = "account";
    public const string EmailChangeNotice = "email_change_notice";
}

public static class AdminActions
{
    public const string EmailChange = "email_change";
}

public static class AskLimits
{
    public const int MaxPerUserPerWindow = 5;
    public const int WindowHours = 24;
    public const int MinMessageLength = 10;
    public const int MaxMessageLength = 2000;
}
```

### Domain / response models

```csharp
// Additive on UserModel
public List<string> Roles { get; set; } = new List<string>();

public class AskListItemModel
{
    public int AskId { get; set; }
    public int UserId { get; set; }
    public string Type { get; set; }          // "ask" | "bug"
    public string Message { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    public DateTime Created { get; set; }
    public string Source { get; set; }
}

public class SignupUserModel
{
    public int UserId { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    public DateTime Created { get; set; }
}

public class SignupPulseModel
{
    public int Count { get; set; }
    public List<SignupUserModel> Users { get; set; }
}

public class AdminUserSearchResultModel
{
    public int UserId { get; set; }
    public string Name { get; set; }
    public string UserName { get; set; }
    public string Email { get; set; }
    public DateTime Created { get; set; }
}

public class ChangeEmailResultModel
{
    public int UserId { get; set; }
    public string Name { get; set; }
    public string Email { get; set; }
    public DateTime Created { get; set; }
    public bool OldEmailSent { get; set; }
    public bool NewEmailSent { get; set; }
}
```

### Request DTOs (Memento.Web.Models)

```csharp
public class CreateAskRequest
{
    public string Type { get; set; }     // "ask" | "bug"
    public string Message { get; set; }
}

public class ChangeEmailRequest
{
    public string Email { get; set; }
}
```

Frontend types mirror these (camelCase). `User` gains required `roles: string[]`.

---

## Data Flow

### Current user roles

```
GET /api/users
  → UserController.Get (existing CustomAuthorization)
  → UserService.GetUser
  → load UserProfile + UserRole rows for that user
  → UserModel.Roles = ["admin"] or []
```

Frontend uses `roles` only to show the drawer item and to guard `/admin`.

### Create ask (Account)

```
POST /api/asks { type, message }
  → CustomAuthorization (401 if unsigned)
  → AskService.CreateAsync(currentUserId, type, message, source: account)
       1. Validate type ∈ {ask, bug}; message trim 10–2000
       2. Count account-source asks in last 24h → 429 if >= 5
       3. Persist Ask
       4. Resolve current admins (UserRole.role = 'admin' ⨝ UserProfile)
       5. Enqueue one email per admin with a non-empty valid email
          (log + continue if a send/enqueue fails; log if zero admins)
  → 200 { askId }
```

Do **not** accept `userId` in the body. Identity is `CurrentUserId`.

### Admin lists and search

```
GET /api/admin/asks
  → AdminAuthorization (401 / 403)
  → AdminService.GetAsksAsync()
  → ALL Ask rows, OrderByDescending Created, no Take/Skip

GET /api/admin/signups
  → AdminAuthorization
  → AdminService.GetSignupsAsync()
  → UserProfile where Created >= UtcNow.AddDays(-30)
  → ALL matching rows, newest first; Count = list length
  → no days query param (window is fixed at 30; do not let a client request a wider PII dump)

GET /api/admin/users?q=
  → AdminAuthorization
  → if trimmed q length < 2: return [] (never all users)
  → contains match on Email, Name, AND UserName (case-insensitive)
  → ALL matches, no Take
```

### Change email

```
PUT /api/admin/users/{userId}/email { email }
  → AdminAuthorization
  → AdminService.ChangeEmailAsync(adminUserId, targetUserId, email)
       1. Trim; normalize with TextFormatter.NormalizeString (lower)
       2. TextFormatter.IsValidEmail → 400 if invalid
       3. Load target → 404 if missing
       4. If normalized == current (case-insensitive) → 400
       5. If any OTHER UserProfile has that email (ToLower) → 409
          "That email is already used by another account"
       6. Write UserProfile.Email
       7. Update ExternalLogin.Email for that user's Google rows only
          (Provider + ProviderUserId unchanged; do not relink)
       8. Leave UserEmail (alternate emails) unchanged
       9. Insert AdminAudit (email_change) with dispute token (7-day expiry)
      10. Send new-email notice and old-email notice synchronously
          (catch per-address; do not roll back the write)
  → 200 ChangeEmailResultModel (warnings from OldEmailSent / NewEmailSent)
```

JWTs are user-id based; do not invalidate them.

### "I didn't request this" (signed-out)

```
User taps link in old-email notice
  → GET /email-change-notice/:token  (public frontend)
  → page POSTs /api/asks/email-change-notices/{token}  (no JWT)
  → AskService.FileEmailChangeDisputeAsync(token)
       1. Lookup AdminAudit by DisputeToken
       2. Missing or expired → 400 "This link has expired."
       3. Already used → 200 (idempotent; do not create a second Ask)
       4. Persist Ask type=bug, source=email_change_notice,
          fixed message: "I did not request my login email to be changed from {old} to {new}."
          userId = audit.TargetUserId
       5. Mark token used; store DisputeAskId
       6. Same admin-email path as a normal submit
  → public page: "We got it. We'll take a look."
```

POST from the page (not GET) so mail-scanner GETs do not consume the token. The user still only taps once.

---

## Database Changes

EF Core Code-First. Three migrations, one per phase. After `dotnet ef migrations add`, generate idempotent SQL:

```bash
cd cimplur-core/Memento
dotnet ef migrations add AddUserRole --project Domain --startup-project Memento
dotnet ef migrations script <PreviousMigration> AddUserRole --idempotent --project Domain --startup-project Memento
# repeat for AddAsk, AddAdminAudit
```

Save generated SQL to `docs/migrations/`. Production applies those scripts, not `dotnet ef database update`.

Do **not** add a unique index on `UserProfile.Email`. Uniqueness is enforced in `AdminService` only.

### Entity: `UserRole`

**File:** `cimplur-core/Memento/Domain/Entities/UserRole.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class UserRole
    {
        [Key]
        public int UserRoleId { get; set; }

        public int UserId { get; set; }

        [Required]
        [MaxLength(32), Column(TypeName = "varchar")]
        public string Role { get; set; }

        public DateTime Created { get; set; }

        [ForeignKey("UserId")]
        public virtual UserProfile User { get; set; }
    }
}
```

Do **not** add a role column on `UserProfile`. Optional navigation `UserProfile.UserRoles` is fine; not required.

### Entity: `Ask`

**File:** `cimplur-core/Memento/Domain/Entities/Ask.cs`

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class Ask
    {
        [Key]
        public int AskId { get; set; }

        public int UserId { get; set; }

        [Required]
        [MaxLength(16), Column(TypeName = "varchar")]
        public string Type { get; set; }

        [Required]
        [MaxLength(2000), Column(TypeName = "nvarchar")]
        public string Message { get; set; }

        public DateTime Created { get; set; }

        [Required]
        [MaxLength(32), Column(TypeName = "varchar")]
        public string Source { get; set; }

        [ForeignKey("UserId")]
        public virtual UserProfile User { get; set; }
    }
}
```

### Entity: `AdminAudit`

**File:** `cimplur-core/Memento/Domain/Entities/AdminAudit.cs`

The dispute token lives on the audit row because it is bound to that email-change event.

```csharp
using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Domain.Entities
{
    public class AdminAudit
    {
        [Key]
        public int AdminAuditId { get; set; }

        public int AdminUserId { get; set; }

        public int TargetUserId { get; set; }

        [Required]
        [MaxLength(32), Column(TypeName = "varchar")]
        public string Action { get; set; }

        [MaxLength(100), Column(TypeName = "varchar")]
        public string OldValue { get; set; }

        [MaxLength(100), Column(TypeName = "varchar")]
        public string NewValue { get; set; }

        public DateTime Created { get; set; }

        public Guid DisputeToken { get; set; }

        public DateTime DisputeTokenExpires { get; set; }

        public DateTime? DisputeTokenUsedAt { get; set; }

        public int? DisputeAskId { get; set; }

        [ForeignKey("AdminUserId")]
        public virtual UserProfile AdminUser { get; set; }

        [ForeignKey("TargetUserId")]
        public virtual UserProfile TargetUser { get; set; }

        [ForeignKey("DisputeAskId")]
        public virtual Ask DisputeAsk { get; set; }
    }
}
```

### StreamContext

`OnModelCreating`:

- `UserRole` and `Ask` FKs to `UserProfile`: `DeleteBehavior.Restrict` (same as MemoryShareLink / ExternalLogin).
- `AdminAudit` has **two** FKs to `UserProfiles` (`AdminUserId`, `TargetUserId`). Use `DeleteBehavior.NoAction` on **both**, matching `SharingSuggestion` / `UserUser`. Do **not** use `Restrict` here — SQL Server / EF still treat two Restrict paths to the same table as multiple cascade paths.
- `AdminAudit.DisputeAskId` is a different principal (`Asks`): `Restrict` is fine.

```csharp
modelBuilder.Entity<UserRole>(entity =>
{
    entity.ToTable("UserRoles");
    entity.HasKey(e => e.UserRoleId);
    entity.HasIndex(e => new { e.UserId, e.Role }).IsUnique();
    entity.HasIndex(e => e.Role);
    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});

modelBuilder.Entity<Ask>(entity =>
{
    entity.ToTable("Asks");
    entity.HasKey(e => e.AskId);
    entity.HasIndex(e => e.Created);
    entity.HasIndex(e => e.UserId);
    entity.HasOne(e => e.User)
        .WithMany()
        .HasForeignKey(e => e.UserId)
        .OnDelete(DeleteBehavior.Restrict);
});

modelBuilder.Entity<AdminAudit>(entity =>
{
    entity.ToTable("AdminAudits");
    entity.HasKey(e => e.AdminAuditId);
    entity.HasIndex(e => e.TargetUserId);
    entity.HasIndex(e => e.Created);
    entity.HasIndex(e => e.DisputeToken).IsUnique();
    entity.HasOne(e => e.AdminUser)
        .WithMany()
        .HasForeignKey(e => e.AdminUserId)
        .OnDelete(DeleteBehavior.NoAction);
    entity.HasOne(e => e.TargetUser)
        .WithMany()
        .HasForeignKey(e => e.TargetUserId)
        .OnDelete(DeleteBehavior.NoAction);
    entity.HasOne(e => e.DisputeAsk)
        .WithMany()
        .HasForeignKey(e => e.DisputeAskId)
        .OnDelete(DeleteBehavior.Restrict);
});
```

DbSets:

```csharp
public DbSet<UserRole> UserRoles { get; set; }
public DbSet<Ask> Asks { get; set; }
public DbSet<AdminAudit> AdminAudits { get; set; }
```

### Reference SQL (builder regenerates from EF; production uses the generated files)

```sql
-- AddUserRole (reference)
IF OBJECT_ID(N'[UserRoles]', N'U') IS NULL
BEGIN
    CREATE TABLE [UserRoles] (
        [UserRoleId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Role] VARCHAR(32) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        CONSTRAINT [PK_UserRoles] PRIMARY KEY ([UserRoleId]),
        CONSTRAINT [FK_UserRoles_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
    CREATE UNIQUE INDEX [IX_UserRoles_UserId_Role] ON [UserRoles] ([UserId], [Role]);
    CREATE INDEX [IX_UserRoles_Role] ON [UserRoles] ([Role]);
END
GO

-- AddAsk (reference)
IF OBJECT_ID(N'[Asks]', N'U') IS NULL
BEGIN
    CREATE TABLE [Asks] (
        [AskId] INT IDENTITY(1,1) NOT NULL,
        [UserId] INT NOT NULL,
        [Type] VARCHAR(16) NOT NULL,
        [Message] NVARCHAR(2000) NOT NULL,
        [Created] DATETIME2 NOT NULL,
        [Source] VARCHAR(32) NOT NULL,
        CONSTRAINT [PK_Asks] PRIMARY KEY ([AskId]),
        CONSTRAINT [FK_Asks_UserProfiles_UserId]
            FOREIGN KEY ([UserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION
    );
    CREATE INDEX [IX_Asks_Created] ON [Asks] ([Created]);
    CREATE INDEX [IX_Asks_UserId] ON [Asks] ([UserId]);
END
GO

-- AddAdminAudit (reference)
IF OBJECT_ID(N'[AdminAudits]', N'U') IS NULL
BEGIN
    CREATE TABLE [AdminAudits] (
        [AdminAuditId] INT IDENTITY(1,1) NOT NULL,
        [AdminUserId] INT NOT NULL,
        [TargetUserId] INT NOT NULL,
        [Action] VARCHAR(32) NOT NULL,
        [OldValue] VARCHAR(100) NULL,
        [NewValue] VARCHAR(100) NULL,
        [Created] DATETIME2 NOT NULL,
        [DisputeToken] UNIQUEIDENTIFIER NOT NULL,
        [DisputeTokenExpires] DATETIME2 NOT NULL,
        [DisputeTokenUsedAt] DATETIME2 NULL,
        [DisputeAskId] INT NULL,
        CONSTRAINT [PK_AdminAudits] PRIMARY KEY ([AdminAuditId]),
        CONSTRAINT [FK_AdminAudits_UserProfiles_AdminUserId]
            FOREIGN KEY ([AdminUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_AdminAudits_UserProfiles_TargetUserId]
            FOREIGN KEY ([TargetUserId]) REFERENCES [UserProfiles] ([UserId]) ON DELETE NO ACTION,
        CONSTRAINT [FK_AdminAudits_Asks_DisputeAskId]
            FOREIGN KEY ([DisputeAskId]) REFERENCES [Asks] ([AskId]) ON DELETE NO ACTION
    );
    CREATE INDEX [IX_AdminAudits_TargetUserId] ON [AdminAudits] ([TargetUserId]);
    CREATE INDEX [IX_AdminAudits_Created] ON [AdminAudits] ([Created]);
    CREATE UNIQUE INDEX [IX_AdminAudits_DisputeToken] ON [AdminAudits] ([DisputeToken]);
END
GO
```

On SQL Server, both EF `Restrict` and `NoAction` emit `ON DELETE NO ACTION`. The EF enum still matters: two `Restrict` FKs to `UserProfiles` can fail migration with multiple cascade paths. `AdminAudit` **must** use `NoAction` for `AdminUser` and `TargetUser`.

### Data script: first admin

**File:** `docs/migrations/GrantAdminKibbeyj.sql`  
Not an EF migration. Idempotent. Case-insensitive email match. **Fails** if the user does not exist.

```sql
-- Grant admin to kibbeyj@gmail.com. Safe to re-run.
-- Fails if that UserProfile does not exist.

IF NOT EXISTS (
    SELECT 1 FROM [UserProfiles]
    WHERE LOWER([Email]) = N'kibbeyj@gmail.com'
)
BEGIN
    THROW 50001, 'Admin seed failed: no UserProfile with email kibbeyj@gmail.com', 1;
END;

INSERT INTO [UserRoles] ([UserId], [Role], [Created])
SELECT u.[UserId], 'admin', SYSUTCDATETIME()
FROM [UserProfiles] u
WHERE LOWER(u.[Email]) = N'kibbeyj@gmail.com'
  AND NOT EXISTS (
      SELECT 1 FROM [UserRoles] r
      WHERE r.[UserId] = u.[UserId] AND r.[Role] = 'admin'
  );
```

No in-product grant/revoke UI in this release.

---

## API Endpoints

### Modified: `GET /api/users`

Existing auth. **No role required.** Response adds `roles: string[]` (`[]` when the user has no `UserRole` rows). All existing fields unchanged.

### New: Ask (not under `/api/admin`)

| Method | Path | Auth | Role | Notes |
|--------|------|------|------|--------|
| POST | `/api/asks` | JWT | none | Body `{ type, message }`. 429 when over cap. |
| POST | `/api/asks/email-change-notices/{token}` | none | none | `token` is a GUID. Public. |

`POST /api/asks` uses `[CustomAuthorization]` only. Do not put `[AdminAuthorization]` on it.

### New: Admin (`[AdminAuthorization]` on the controller)

| Method | Path | Response |
|--------|------|----------|
| GET | `/api/admin/asks` | `AskListItemModel[]` newest first, **unbounded** |
| GET | `/api/admin/signups` | `{ count, users }` last 30 days, **unbounded**, newest first |
| GET | `/api/admin/users?q=` | `AdminUserSearchResultModel[]` **all matches**, or `[]` if `q` length < 2 |
| PUT | `/api/admin/users/{userId}/email` | `ChangeEmailResultModel` |

Status codes:

| Case | Status |
|------|--------|
| Not authenticated | 401 |
| Authenticated, not admin | 403 |
| Validation (message, type, same email, invalid email, expired token) | 400 |
| Target user not found | 404 |
| Duplicate email | 409 |
| Ask rate limit | 429 |

Existing `POST /api/contacts` and `giveFeedback` are **unchanged**.

---

## Backend Design

This codebase uses `BaseService` + `StreamContext` (not a separate repository layer). New services follow that pattern.

### `TooManyRequestsException`

**File:** `Domain/Exceptions/TooManyRequestsException.cs`

```csharp
public class TooManyRequestsException : BaseException
{
    public TooManyRequestsException(string message) : base(message)
    {
        Status = 429;
    }
}
```

Global `CustomErrorHandler` already maps `BaseException.Status`.

### `AdminAuthorizationAttribute`

**File:** `Memento/Libs/AdminAuthorizationAttribute.cs`

`IAsyncAuthorizationFilter` (role lookup is async). One attribute so new admin actions cannot forget the gate.

1. No `HttpContext.Items["UserId"]` → 401 JSON `{ message: "Unauthorized" }` (same shape as `CustomAuthorization`).
2. `UserService.HasRoleAsync(userId, RoleNames.Admin)` is false → 403 `{ message: "Forbidden" }`.
3. True → continue.

Do **not** apply this attribute to existing controllers or to `AskController`. Resolve `UserService` from `RequestServices` (same pattern as `CustomAuthorization` resolving `AiServiceSettings`).

### `UserService` (modify)

```csharp
public async Task<bool> HasRoleAsync(int userId, string role)
{
    return await Context.UserRoles
        .AnyAsync(r => r.UserId == userId && r.Role == role);
}

public async Task<List<string>> GetRolesAsync(int userId)
{
    return await Context.UserRoles
        .Where(r => r.UserId == userId)
        .Select(r => r.Role)
        .ToListAsync();
}
```

`GetUser` sets `userModel.Roles = await GetRolesAsync(currentUserId);`. Users with zero rows get `[]`.

### `AskService` (new)

Extends `BaseService`. Depends on `SendEmailService`, `IBackgroundJobQueue`, `ILogger<AskService>`.

```csharp
Task<int> CreateAsync(int userId, string type, string message, string source)
Task FileEmailChangeDisputeAsync(Guid token)
```

Validation (factory-style, not a type switch for persistence):

```csharp
private static readonly HashSet<string> ValidTypes =
    new(StringComparer.OrdinalIgnoreCase) { AskTypes.Ask, AskTypes.Bug };

private static string NormalizeType(string type)
{
    var key = type?.Trim().ToLowerInvariant();
    if (key == null || !ValidTypes.Contains(key))
        throw new BadRequestException("Type must be ask or bug.");
    return key;
}
```

Rate limit only when `source == AskSources.Account`:

```csharp
var windowStart = DateTime.UtcNow.AddHours(-AskLimits.WindowHours);
var count = await Context.Asks.CountAsync(a =>
    a.UserId == userId
    && a.Source == AskSources.Account
    && a.Created >= windowStart);
if (count >= AskLimits.MaxPerUserPerWindow)
    throw new TooManyRequestsException("Please wait before sending another");
```

Do not wrap the count + insert in a serializable transaction to close the TOCTOU race (two concurrent requests can both pass). Accept that the cap is best-effort.

Notify admins after successful persist:

```csharp
var admins = await Context.UserRoles
    .Where(r => r.Role == RoleNames.Admin)
    .Join(Context.UserProfiles,
        r => r.UserId, u => u.UserId,
        (r, u) => u)
    .ToListAsync();
```

Skip missing/invalid emails (`TextFormatter.IsValidEmail`). Enqueue `EmailJob` per remaining admin (`EmailTypes.AdminAsk`). If the queue is null, call `SendEmailService.SendAsync` in a per-address try/catch (same fallback as `ContactService`). If the admin list is empty, log a warning and still return success to the user.

HtmlEncode `Message` (and name/email) in the email model so the existing Razor templates cannot render user HTML.

### `AdminService` (new)

Extends `BaseService`. Depends on `SendEmailService`, `ILogger<AdminService>`.

**GetAsksAsync** — no `Take`/`Skip`:

```csharp
return await Context.Asks
    .Join(Context.UserProfiles, a => a.UserId, u => u.UserId, (a, u) => new { a, u })
    .OrderByDescending(x => x.a.Created)
    .Select(x => new AskListItemModel { /* map; Name may be null */ })
    .ToListAsync();
```

**GetSignupsAsync** — `Created >= UtcNow.AddDays(-30)`, `OrderByDescending(Created)`, no `Take`. `Count = users.Count`.

**SearchUsersAsync(q)**:

```csharp
var term = q?.Trim() ?? "";
if (term.Length < 2)
    return new List<AdminUserSearchResultModel>();

var lowered = term.ToLower();
return await Context.UserProfiles
    .Where(u =>
        (u.Email != null && u.Email.ToLower().Contains(lowered))
        || (u.Name != null && u.Name.ToLower().Contains(lowered))
        || (u.UserName != null && u.UserName.ToLower().Contains(lowered)))
    .OrderByDescending(u => u.Created)
    .Select(u => new AdminUserSearchResultModel { /* */ })
    .ToListAsync();
```

No `Take`. No extra "narrowing" when the result set is large.

**ChangeEmailAsync** — steps in Data Flow. Google constant matches `GoogleAuthService` (`"Google"`). Duplicate check excludes `targetUserId`. Create the audit row **before** sending mail so the dispute token exists for the old-email body.

Dispute expiry: `DateTime.UtcNow.AddDays(7)`. Token: `Guid.NewGuid()`.

Send notices **synchronously** (only two emails) so the response can set `OldEmailSent` / `NewEmailSent`. Catch per address; never throw after the write. `SendPostmarkEmail` currently swallows Postmark failures — the warning covers exceptions (template/render/network). Document that Postmark `Status != Success` is a pre-existing pipeline gap, not in scope to rewrite.

### Email templates

Add to `EmailTypes` (next values 30–32):

```
AdminAsk = 30,
EmailChangeNew = 31,
EmailChangeOld = 32,
```

Do **not** add these to `TokenAddedEmails` (that would inject a magic-link login token).

| Type | Subject | Body must include |
|------|---------|-------------------|
| AdminAsk | `Fyli @Model.TypeLabel from @Model.Name` | type, message, name, email, user id, time, link to `{HostUrl}/admin`. No support@ CTA. |
| EmailChangeNew | `Your Fyli login email was changed` | login is now `{new}`; use it for magic-link; if you did not ask, sign in and file an Ask from Account. **No support address.** |
| EmailChangeOld | `Your Fyli login email was changed` | changed to `{new}`; ignore if you asked; **I didn't request this** button → `{HostUrl}/email-change-notice/{token}`. **No support address.** |

Use `Constants.HostUrl` for frontend links (not `BaseUrl`).

If name is empty, fall back to email in subjects/greetings.

### `SendAsync` virtual

Make `SendEmailService.SendAsync` `virtual` and `TestSendEmailService.SendAsync` `override` so tests that inject `SendEmailService` actually record mail. Today's `new` hide does not.

### DI

`Startup.ConfigureServices`:

```csharp
services.AddScoped<AskService, AskService>();
services.AddScoped<AdminService, AdminService>();
```

No new rate-limiter policy. The ask cap is in `AskService`.

---

## Frontend Components

Style: Bootstrap 5 + `var(--fyli-*)` only. No hardcoded hex. See Design Decisions below.

### Auth / types

```typescript
export interface User {
  // existing fields...
  roles: string[]
}
```

`createUser()` in `src/test/fixtures.ts` **must** default `roles: []` (`noUncheckedIndexedAccess` / `vue-tsc`).

`useAuthStore`:

```typescript
const hasAdmin = computed(
  () => user.value?.roles?.includes("admin") === true,
)
```

Return `hasAdmin` from the store (same list as `isAuthenticated`). Drawer and the router guard read `auth.hasAdmin`, not a raw `roles.includes` in three places.

### Router

```typescript
{
  path: "/admin",
  name: "admin",
  component: () => import("@/views/admin/AdminView.vue"),
  meta: { auth: true, role: "admin", layout: "app" },
},
{
  path: "/email-change-notice/:token",
  name: "email-change-notice",
  component: () => import("@/views/account/EmailChangeNoticeView.vue"),
  meta: { layout: "public" },
},
```

Only `/admin` uses `meta.role`. Guard (after the existing user fetch):

```typescript
if (to.meta.role === "admin" && !auth.hasAdmin) {
  return { path: "/" }
}
```

Signed-out `/admin` already hits `meta.auth` → login. Signed-in non-admin → Memories. Do not render an "Admin exists" error page.

Add `/admin` and `/email-change-notice/00000000-0000-0000-0000-000000000000` to `emailRoutes.test.ts`.

### `AppDrawer`

Keep the current five items. **Append** Admin as the last item only when `auth.hasAdmin`:

- label: Admin
- to: `/admin`
- icons: `mdi-shield-account-outline` / `mdi-shield-account`
- `matchPaths: ["/admin"]`

Rewrite `AppDrawer.test.ts` to use a real Pinia `useAuthStore` (AccountView pattern) instead of a static `vi.mock("@/stores/auth")`, so tests can set `roles`.

Non-admin: drawer markup matches today (no Admin node).

### Account Help (`AccountView`)

New **Help** card **below Plan, above Logout**. Visible to every signed-in user.

- Heading: Help
- Prompt: "Ask a question or tell us something is broken."
- Required type: radio (`form-check`) Ask / Bug. `name="ask-type"`. Touch target ≥ 44px.
- Required message: `textarea.form-control`, min 10 / max 2000
- Submit: `btn btn-primary w-100`, disabled while invalid or in flight; spinner when in flight
- Success: `alert alert-success` `role="alert"` — "We got it. We'll take a look." Clear message; leave type selected
- Error: `alert alert-danger` `role="alert"`
- 429: `alert alert-warning` `role="alert"` — use `getErrorMessage` so the server text shows ("Please wait before sending another")

No title, screenshot, or email field.

### `AdminView` (`/admin`)

Page title: **Admin** (`h1.h4`, same as Account). Three stacked cards, mobile-first, inside existing `AppLayout` (max-width 600px).

1. **Asks & bugs** (first — actionable)
2. **Joined last 30 days**
3. **Change user email**

On mount, load asks + signups in parallel. Any **403** → `router.replace("/")`. Other failures → existing `ErrorState` with retry.

**Asks:** newest first, already sorted by API. Each row: `badge rounded-pill` (Ask: `text-bg-primary`, Bug: `text-bg-danger`) plus the words Ask/Bug (color is not the only signal). Message wraps (`text-break`, `white-space: pre-wrap`). Name, email, user id, time. Empty name → show email. Empty: `EmptyState` "No asks or bugs yet". **Render the full array. No client-side cap, slice, or pager.**

**Signups:** headline "N people joined in the last 30 days". List name, email, join date (user-local, `toLocaleDateString`). Empty name → email. Count 0: "No one joined in the last 30 days" — not a blank table. **Full list, no cap.**

**Email change:** search `form-control`, search after 2 characters (debounce ~300ms). Results: name, email, user id, join date. Empty: "No users match". Select a result → current email + new email field + Change. Change disabled while in flight or invalid. `ConfirmModal` before write (`confirmClass="btn btn-primary"`, `confirmLabel="Change email"`, message shows old → new). Success: update selected email + `alert alert-success`. Duplicate: `alert alert-danger` with server message. If `oldEmailSent` or `newEmailSent` is false: `alert alert-warning` "Email was changed, but we could not notify {address}". Refresh the selected row (and search results that still show the old email).

**No virtual scroll** in this release. Unbounded render is an explicit v1.2 product choice (no caps, no paging). Do not add a windowed list, infinite scroll, or "showing first N" truncation. Expected volume is operator-scale.

### `EmailChangeNoticeView`

**File:** `fyli-fe-v2/src/views/account/EmailChangeNoticeView.vue`  
Lives next to Account, **not** under `views/admin/`. This is a public, signed-out page. It must not share Admin chrome, admin API clients, or an "admin" folder that implies operator UI.

`PublicLayout`. On mount, POST the token. Success or already-used: "We got it. We'll take a look." Expired/missing: "This link has expired." No login requirement.

### API services

```typescript
// askApi.ts
createAsk(type: "ask" | "bug", message: string)
fileEmailChangeNotice(token: string)

// adminApi.ts
getAsks()
getSignups()
searchUsers(q: string)
changeUserEmail(userId: number, email: string)
```

Paths must match the backend (`/asks`, `/admin/asks`, …) relative to `/api`.

---

## Design Decisions

Reviewed against `docs/FRONTEND_STYLE_GUIDE.md`.

| Surface | Choice | Why |
|---------|--------|-----|
| Account Help | Same `card mb-3` as Name/Email/Plan | Account already uses stacked cards; Help must feel native, not a new visual language |
| Type control | `form-check` radios, not a dropdown | Two values; radios make the required choice visible; 44px targets |
| Submit | `btn btn-primary w-100` | Primary CTA, mobile full-width |
| Alerts | Bootstrap `alert-*` + `role="alert"` | Existing Account/app pattern; success / danger / warning |
| Drawer Admin | Last item, `mdi-shield-account-outline` | PRD: last, operator-like, already in MDI |
| Ask vs Bug | `text-bg-primary` vs `text-bg-danger` + text label | Semantic Bootstrap colors; primary is brand `#56c596`; never color-only |
| Admin sections | Three `card`s, asks first | Actionable work above metrics above a dangerous write |
| Confirm | Existing `ConfirmModal` with **primary** confirm (not default danger) | Email change is privileged but not a delete |
| Empty | Existing `EmptyState` | Centered muted copy |
| Errors | Existing `ErrorState` | Retry |
| Public notice | `views/account/EmailChangeNoticeView.vue` + `PublicLayout` | Signed-out help path. Must not live under `views/admin/` or look like operator UI |
| Dates | `toLocaleDateString` / `toLocaleString` | User-local, no new date library |
| Lists | Stacked rows, not a wide table | `AppLayout` is 600px; tables overflow on a phone |

**Accessibility:** labels above inputs; radios associated with labels; submit disabled reason is implicit (invalid form); focus rings from Bootstrap primary; drawer Admin has text + icon.

**Not in this release:** character counter, virtual scroll (unbounded lists are a v1.2 product choice), admin sub-nav, Help in the drawer.

---

## Testing Plan

TDD: failing tests first. Coverage target 70% on new code. Services use `CreateTestContext()` (no transaction), `DetachAllEntities`, `CreateVerificationContext`. See `docs/TESTING_BEST_PRACTICES.md`.

**No controller / API-host test project.** This repo tests backend through `DomainTest` service tests (`AskServiceTest`, `AdminServiceTest`, `UserServiceTest`). Do not add a new Memento Web test project. Auth (401/403) is covered by `HasRoleAsync` plus the frontend router/AdminView 403 tests. HTTP status mapping for `TooManyRequestsException` / `ConflictException` is already global via `CustomErrorHandler` + `BaseException.Status`.

### Backend (`DomainTest`)

**UserServiceTest**

- `GetUser_WithNoRoles_ShouldReturnEmptyRolesList` — existing users stay `[]`
- `GetUser_WithAdminRole_ShouldIncludeAdmin`
- `HasRoleAsync_WhenMissing_ShouldReturnFalse`
- `HasRoleAsync_WhenAdmin_ShouldReturnTrue`

**AskServiceTest**

- `CreateAsync_ValidAsk_ShouldPersistAndReturnId`
- `CreateAsync_ValidBug_ShouldPersistTypeBug`
- `CreateAsync_MessageTooShort_ShouldThrowBadRequestException`
- `CreateAsync_MessageTooLong_ShouldThrowBadRequestException`
- `CreateAsync_InvalidType_ShouldThrowBadRequestException`
- `CreateAsync_SixthIn24Hours_ShouldThrowTooManyRequestsException` — persist 5, sixth fails, sixth not written
- `CreateAsync_AfterWindow_ShouldAllow` — 5 rows with `Created` 25 hours ago, sixth succeeds
- `CreateAsync_DoesNotAcceptOtherUserId` — (implicit: method only takes current user id)
- `CreateAsync_ZeroAdmins_ShouldStillPersist`
- `CreateAsync_ShouldEmailEachAdmin` — two admin users, `TestSendEmailService` records two `AdminAsk` mails; skip admin with empty email
- `FileEmailChangeDisputeAsync_ValidToken_ShouldCreateBugAndMarkUsed`
- `FileEmailChangeDisputeAsync_AlreadyUsed_ShouldBeIdempotent`
- `FileEmailChangeDisputeAsync_Expired_ShouldThrowBadRequestException`
- `FileEmailChangeDisputeAsync_DoesNotCountAgainstRateLimit` — user already at 5 account asks; dispute still persists

**AdminServiceTest**

- `GetAsksAsync_ShouldReturnNewestFirst_AllRows` — insert 3, assert order and count 3 (no cap)
- `GetSignupsAsync_ShouldIncludeOnlyLast30Days_AllRows`
- `GetSignupsAsync_OlderThan30Days_ShouldExclude`
- `SearchUsersAsync_MatchesEmailNameAndUserName`
- `SearchUsersAsync_ShortQuery_ShouldReturnEmpty` — 1 char → `[]`, not all users
- `SearchUsersAsync_ShouldReturnAllMatches_NoTake` — more than 50 matches still all returned
- `ChangeEmailAsync_Success_ShouldUpdateProfileAndAuditAndGoogleEmail`
- `ChangeEmailAsync_ShouldNotChangeAlternateUserEmails`
- `ChangeEmailAsync_Duplicate_ShouldThrowConflictException`
- `ChangeEmailAsync_SameEmail_ShouldThrowBadRequestException`
- `ChangeEmailAsync_InvalidEmail_ShouldThrowBadRequestException`
- `ChangeEmailAsync_MissingUser_ShouldThrowNotFoundException`
- `ChangeEmailAsync_ShouldNotInvalidateAnythingOnUserTokenField` — `UserProfile.Token` unchanged

**TestServiceFactory** — `CreateAskService`, `CreateAdminService`; grant helper to insert `UserRole`.

### Frontend (Vitest)

**fixtures / auth**

- `createUser` includes `roles: []`
- `hasAdmin` true only when `roles` contains `"admin"`
- `fetchUser` stores `roles` from the API

**askApi / adminApi** — method, path, body; mock `api`.

**AppDrawer**

- non-admin: no "Admin" text; five items ending in Account
- admin: Admin is last; active on `/admin`

**Router**

- `/admin` and `/email-change-notice/:token` resolve
- guard: authenticated non-admin navigating to admin → `/` (unit-test the condition via store + a small extracted helper, or mount router with a stub component)

**AccountView**

- Help section below Plan, above Logout
- submit disabled without type / short message
- success path: calls `createAsk`, shows "We got it. We'll take a look.", clears message
- 429: warning text
- persist error: danger, no success claim
- visible for non-admin users

**AdminView**

- three section headings
- asks empty state
- renders every ask in the fixture (e.g. 3 items, no pager)
- signups count + rows; zero-join copy
- search: no call under 2 chars; lists all returned matches
- confirm modal before change
- 409 shows duplicate message
- 403 redirects to `/`
- send-failure warning when `oldEmailSent` is false

**EmailChangeNoticeView** (`views/account/EmailChangeNoticeView.test.ts`)

- POSTs token on mount
- success copy
- expired copy
- does not import `adminApi` or render Admin chrome

Run: `cd fyli-fe-v2 && npx vue-tsc --noEmit` after adding `roles`.

---

## Implementation Order

### Phase 1: Role + seed + Admin shell + signup metrics

1. `UserRole` entity, StreamContext, EF migration, `docs/migrations/AddUserRole.sql`
2. `GrantAdminKibbeyj.sql`
3. `RoleNames`, `HasRoleAsync`, `GetUser.Roles`
4. `TooManyRequestsException` can wait for Phase 2; `AdminAuthorizationAttribute` now
5. `AdminService.GetSignupsAsync` + `GET /api/admin/signups`
6. DI
7. Frontend: `User.roles`, fixture, `hasAdmin`, router + guard, drawer item, `AdminView` with signups section only (asks/email cards can be empty placeholders or omitted until later phases — prefer real empty asks card so layout is final)
8. Tests for this phase
9. Append `UserRole` to the entity summary in `docs/DATABASE_GUIDE.md`

### Phase 2: Ask / file a bug

1. `Ask` entity, migration, SQL
2. `AskService` + rate limit + admin emails + templates
3. `AskController`
4. `GET /api/admin/asks` + Asks section on AdminView (first card)
5. Account Help form + `askApi`
6. Tests
7. Append `Ask` to `docs/DATABASE_GUIDE.md` entity summary

### Phase 3: Search, email change, notices, audit

1. `AdminAudit` entity, migration, SQL
2. Search + change-email in `AdminService` / `AdminController`
3. Notices + dispute token + public page at `views/account/EmailChangeNoticeView.vue` (not under `views/admin/`)
4. Google `ExternalLogin.Email` sync
5. Admin UI for search/change + ConfirmModal
6. Tests
7. Append `AdminAudit` to `docs/DATABASE_GUIDE.md` entity summary
8. Update `docs/release_note.md` for the shipped feature (Admin page, Account Help, email change)

After all three phases are built and reviewed, move `docs/prd/PRD_ADMIN_PAGE.md` to `docs/prd/archive/` and this TDD to `docs/tdd/archive/`.

---

## Backwards Compatibility

- Existing users have no `UserRole` rows → `roles: []`, no drawer Admin, no `/admin`
- JWT still `{ id }`
- `GetUser` fields unchanged aside from additive `roles`
- No role checks on existing controllers
- `POST /api/asks` is new and ungated by role
- Drops, sharing, and access rules untouched
- `UserProfile` columns unchanged
- `POST /api/contacts` and `giveFeedback` unchanged
- Magic-link still reads `UserProfile.Email`; Google still matches `Provider` + `ProviderUserId` first

---

## Security

- Server is the source of truth for admin (filter + DB), not the JWT
- Ask create does not take a `userId`
- Dispute token is a GUID, unique, single-use, 7-day expiry, bound to one `AdminAudit`
- Do not log full email-change payloads in client-visible errors
- Search, signup list, and ask list are admin-only (other users' PII)
- Signups endpoint does not accept an arbitrary `days` window
- Email uniqueness is application-level and case-insensitive; no merge
- Rate limit is per authenticated user, not IP (IP limiter would punish shared NAT and miss a user rotating IPs)

---

## Out of Scope (matches PRD)

Self-service email change; in-product role grant; extra roles; Admin in bottom nav; Help in the drawer; ask status/replies/history; screenshots; public help form except the dispute link; analytics beyond 30-day joins; account merge; relinking Google; editing `UserEmail`; audit UI; JWT invalidation; unique DB index on email; rewriting contacts/feedback.
