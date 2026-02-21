# Database Guide

## Overview

- **Database:** SQL Server (via Docker, `localhost:1433`)
- **ORM:** EF Core 9.0.8 (Code-First)
- **Target Framework:** .NET 9.0
- **Context:** `StreamContext` in `cimplur-core/Memento/Domain/Entities/StreamContext.cs`

## SQL Server Syntax

All raw SQL must use SQL Server syntax (not PostgreSQL):

| Type | SQL Server | NOT |
|------|-----------|-----|
| Auto-increment | `INT IDENTITY(1,1)` | `SERIAL` |
| Timestamps | `DATETIME2` | `TIMESTAMPTZ` |
| Booleans | `BIT` | `BOOLEAN` |
| GUIDs | `UNIQUEIDENTIFIER` | `UUID` |
| Unicode strings | `NVARCHAR` | `TEXT` |
| Identifiers | `[TableName]` | `"TableName"` |

## Generating Raw SQL for Migrations

Production does **not** use EF migrations directly. Raw SQL scripts are generated from migrations and applied manually.

**Always use the EF Core tooling to generate SQL — never hand-write migration scripts.**

```bash
cd cimplur-core/Memento

# Generate idempotent SQL for all migrations after a given migration:
dotnet ef migrations script <from_migration_name> --idempotent --project Domain --startup-project Memento

# Example: generate SQL for everything after transcode_update:
dotnet ef migrations script 20251207185045_transcode_update --idempotent --project Domain --startup-project Memento
```

The `--idempotent` flag wraps each step in `IF NOT EXISTS` checks against `__EFMigrationsHistory`, making scripts safe to re-run.

Save generated SQL to `docs/migrations/` and update the relevant TDD post creation.

## Creating Schema Changes (EF Core Code-First)

Never write raw SQL for schema changes. Always use the Code-First workflow:

1. Create or update the POCO entity in `cimplur-core/Memento/Domain/Entities/`
2. Add `DbSet<T>` property to `StreamContext.cs`
3. Configure FKs, indexes, and constraints in `StreamContext.OnModelCreating`
4. Generate the migration:
   ```bash
   cd cimplur-core/Memento && dotnet ef migrations add <Name> --project Domain --startup-project Memento
   ```
5. Generate the raw SQL (see above) and save to the TDD

Migrations are auto-generated in `cimplur-core/Memento/Domain/Migrations/`.

## Connection Configuration

- **Design-time** (migrations): reads `DatabaseConnection` from `cimplur-core/Memento/Domain/appsettings.json` via `DesignTimeDbContextFactory`
- **Runtime** (services): reads `DatabaseConnection` from environment variable (loaded from `.env`)

## Service Data Access Pattern

Services extend `BaseService`, which lazy-creates its own `StreamContext`:

```csharp
public class BaseService : IDisposable
{
    private StreamContext context;
    protected StreamContext Context
    {
        get
        {
            if (context == null)
            {
                var builder = new DbContextOptionsBuilder<StreamContext>();
                builder.EnableDetailedErrors(true);
                builder.UseSqlServer(Environment.GetEnvironmentVariable("DatabaseConnection"));
                context = new StreamContext(builder.Options);
            }
            return context;
        }
    }
}
```

Each service instance creates its own context. This means:
- Services read **committed** data only — they do not share a test transaction
- Tests that call service methods must commit data first (see test patterns in `MEMORY.md`)

## OnModelCreating Conventions

### Delete Behaviors
- **`DeleteBehavior.Restrict`** — default for most FKs (MemoryShareLinks, ExternalLogins, QuestionRequests, etc.)
- **`DeleteBehavior.NoAction`** — used when circular dependencies exist
- **`DeleteBehavior.Cascade`** — parent-child hierarchies only (Questions → QuestionSet, QuestionRequestRecipients → QuestionRequest)

### Composite Keys
Used for many-to-many join tables:
- `AlbumDrop` → `(AlbumId, DropId)`
- `TagViewer` → `(UserTagId, UserId)`
- `TimelineDrop` → `(TimelineId, DropId)`
- `SharingSuggestion` → `(OwnerUserId, SuggestedUserId)`

### Unique Indexes
- `MemoryShareLink.Token` (UNIQUEIDENTIFIER)
- `TimelineShareLink.Token` (UNIQUEIDENTIFIER)
- `QuestionRequestRecipient.Token` (UNIQUEIDENTIFIER)
- `ExternalLogin` → `(Provider, ProviderUserId)`
- `QuestionResponse` → `(QuestionRequestRecipientId, QuestionId)`
- `UserPrompt` → `(PromptId, UserId)`
- `UserRelationship` → `(UserId, Relationship)`
- `TimelineUser` → `(UserId, TimelineId)`
- `UserTag` → `(UserId, Name)` with filter `WHERE [Name] IS NOT NULL`

### JSON Columns
Some `UserProfile` fields store serialized JSON in large varchar columns:
- `CurrentNotifications` (varchar 8000)
- `CurrentTagIds` (varchar 4000)
- `CurrentPeople` (varchar 8000)

### Soft Deletes
Several entities use an `Archived` (BIT) flag rather than hard deletes:
- `Drop`, `UserTag`, `Album`, `QuestionSet`

## Entity Summary

The `StreamContext` defines 40+ DbSets. The core domain model is user-centric:

- **UserProfile** — central entity connecting everything
- **Drop** — primary content unit (memories)
- **UserUser / ShareRequest / MemoryShareLink** — sharing layer
- **Timeline / TimelineUser / TimelineDrop** — collections of drops
- **UserTag (Network) / TagViewer / TagDrop** — categorization
- **Prompt / UserPrompt / PromptTimeline** — drop creation workflows
- **QuestionSet / Question / QuestionRequest / QuestionRequestRecipient / QuestionResponse** — survey system
- **ExternalLogin** — OAuth providers (Google)
- **PremiumPlan / SharedPlan / Transaction** — subscriptions and billing

## Migration History

| Migration | Description |
|-----------|-------------|
| 20210502004355 | Initial schema |
| 20251207185045 | Transcode update |
| 20260201014219 | AddMemoryShareLinks |
| 20260206032422 | QuestionRequests (5 tables) |
| 20260209005943 | AddExternalLogin |
| 20260210222732 | AddTimelineShareLinks |
| 20260219192308 | AddCacheEntry (AI suggestion rate limiting) |
